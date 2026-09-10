function Get-EntraCertificateToken {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Alias('client-id', 'client_id')]
        [string]$AppId,

        [Parameter(Mandatory = $true)]
        [Alias('tenant', 'tenant_id')]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [Alias('cert-path', 'pfx')]
        [string]$CertificatePath,

        [Parameter(Mandatory = $false)]
        [Alias('pwd')]
        [string]$CertificatePassword,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Azure', 'MSGraph', 'KeyVault', 'Storage')]
        [string]$EndpointType = 'MSGraph',

        [Parameter(Mandatory = $false)]
        [switch]$Decode
    )

    $endpoints = @{
        Azure    = 'https://management.azure.com'
        MSGraph  = 'https://graph.microsoft.com'
        KeyVault = 'https://vault.azure.net'
        Storage  = 'https://storage.azure.com'
    }
    $resourceUrl = $endpoints[$EndpointType]
    $scope       = "$resourceUrl/.default"

    # 1. Load Certificate and Extract RSA Private Key
    Write-Host "[*] Loading certificate from $CertificatePath..." -ForegroundColor Cyan
    $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $CertificatePath,
        $CertificatePassword,
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
    )

    if (-not $cert.HasPrivateKey) {
        throw "The provided certificate does not contain a private key."
    }

    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)

    # 2. Build Base64URL-encoded SHA-1 Thumbprint (x5t header)
    $thumbprintBytes = [System.Convert]::FromHexString($cert.Thumbprint)
    $x5t = [System.Convert]::ToBase64String($thumbprintBytes) -replace '\+', '-' -replace '/', '_' -replace '=+$', ''

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $tokenUri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

    # 3. Construct JWT Header and Payload
    $header = @{
        alg = 'RS256'
        typ = 'JWT'
        x5t = $x5t
    }

    $payload = @{
        aud = $tokenUri
        iss = $AppId
        sub = $AppId
        jti = [guid]::NewGuid().ToString()
        nbf = $now
        iat = $now
        exp = $now + 600 # 10 minutes
    }

    # 4. Sign JWT using RSA-SHA256
    $headerEncoded  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($header | ConvertTo-Json -Compress))) -replace '\+', '-' -replace '/', '_' -replace '=+$', ''
    $payloadEncoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Compress))) -replace '\+', '-' -replace '/', '_' -replace '=+$', ''
    $signInputBytes = [Text.Encoding]::UTF8.GetBytes("$headerEncoded.$payloadEncoded")

    $signatureBytes = $rsa.SignData(
        $signInputBytes,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    )
    $signatureEncoded = [Convert]::ToBase64String($signatureBytes) -replace '\+', '-' -replace '/', '_' -replace '=+$', ''
    $clientAssertion  = "$headerEncoded.$payloadEncoded.$signatureEncoded"

    # 5. Exchange Client Assertion for Entra Access Token
    Write-Host "[*] Exchanging signed assertion at Entra token endpoint..." -ForegroundColor Cyan
    $body = @{
        client_id             = $AppId
        grant_type            = 'client_credentials'
        client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
        client_assertion      = $clientAssertion
        scope                 = $scope
    }

    try {
        $response = Invoke-RestMethod -Uri $tokenUri -Method POST -Body $body -ContentType 'application/x-www-form-urlencoded'
        Write-Host "[+] Token acquired successfully for $AppId" -ForegroundColor Green

        $tokenResult = [PSCustomObject]@{
            AppId        = $AppId
            TenantId     = $TenantId
            EndpointType = $EndpointType
            Resource     = $resourceUrl
            TokenType    = $response.token_type
            AccessToken  = $response.access_token
            ExpiresIn    = $response.expires_in
            ExpiresOn    = (Get-Date).AddSeconds($response.expires_in).ToString('yyyy-MM-dd HH:mm:ss')
        }

        if ($Decode) {
            $tokenParts = $response.access_token -split '\.'
            $padLength  = 4 - ($tokenParts[1].Length % 4)
            if ($padLength -lt 4) { $tokenParts[1] += ('=' * $padLength) }
            $decodedJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($tokenParts[1].Replace('-', '+').Replace('_', '/')))
            $tokenResult | Add-Member -NotePropertyName 'DecodedToken' -NotePropertyValue ($decodedJson | ConvertFrom-Json)
        }

        return $tokenResult
    }
    catch {
        Write-Error "Token exchange failed: $($_.Exception.Message)"
        if ($_.ErrorDetails.Message) {
            Write-Host $_.ErrorDetails.Message -ForegroundColor Red
        }
    }
    finally {
        if ($rsa) { $rsa.Dispose() }
        if ($cert) { $cert.Dispose() }
    }
}