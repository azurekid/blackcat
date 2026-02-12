# Setup script for Invoke-FederatedTokenExchange OIDC infrastructure
# Pure PowerShell - no external dependencies (az CLI or OpenSSL)
# Run this once to set up the storage account and upload OIDC metadata

param (
    [Parameter(Mandatory = $false)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "rg-blackcat-oidc",
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "westus",
    
    [Parameter(Mandatory = $false)]
    [string]$KeyPath = "./blackcat-oidc.pem"
)

Write-Host "Setting up OIDC infrastructure for Invoke-FederatedTokenExchange..." -ForegroundColor Green
Write-Host "(Pure PowerShell - no az CLI or OpenSSL required)" -ForegroundColor Gray

# Get Azure context from Az.Accounts
try {
    $azContext = Get-AzContext -ErrorAction Stop
    if (-not $azContext) {
        Write-Host "`nERROR: Not authenticated to Azure. Run:" -ForegroundColor Red
        Write-Host "  Connect-AzAccount" -ForegroundColor Yellow
        exit 1
    }
    
    $tenantId = $azContext.Tenant.Id
    $subscriptionId = $azContext.Subscription.Id
    $armUri = 'https://management.azure.com'
    
    Write-Host "  ✓ Authenticated to tenant: $tenantId" -ForegroundColor Green
    Write-Host "  ✓ Subscription: $subscriptionId" -ForegroundColor Green
    
    # Get ARM access token (convert from SecureString)
    $token = Get-AzAccessToken -ResourceUrl 'https://management.azure.com' -ErrorAction Stop
    $plainToken = ConvertFrom-SecureString -SecureString $token.Token -AsPlainText
    $authHeader = @{
        'Authorization' = "Bearer $plainToken"
        'Content-Type'  = 'application/json'
    }
}
catch {
    Write-Host "`nERROR: Failed to get Azure context: $_" -ForegroundColor Red
    Write-Host "Make sure Az.Accounts module is installed and you're authenticated." -ForegroundColor Yellow
    exit 1
}

# ── Step 1: Generate RSA key if needed ────────────────────────────────────────
if (-not (Test-Path $KeyPath)) {
    Write-Host "`n[1/5] Generating RSA-2048 key pair..." -ForegroundColor Cyan
    
    try {
        # Generate RSA key using .NET
        $rsa = [System.Security.Cryptography.RSA]::Create(2048)
        
        # Export as PKCS8 PEM (standard format)
        $keyBytes = $rsa.ExportPkcs8PrivateKey()
        $keyB64 = [System.Convert]::ToBase64String($keyBytes)
        
        # Format as PEM with line breaks every 64 chars
        $pemLines = @('-----BEGIN PRIVATE KEY-----')
        for ($i = 0; $i -lt $keyB64.Length; $i += 64) {
            $len = [Math]::Min(64, $keyB64.Length - $i)
            $pemLines += $keyB64.Substring($i, $len)
        }
        $pemLines += '-----END PRIVATE KEY-----'
        
        $pemLines -join "`n" | Set-Content -Path $KeyPath -NoNewline
        $rsa.Dispose()
        
        Write-Host "  Private key saved: $KeyPath" -ForegroundColor Green
    }
    catch {
        Write-Host "  ERROR: Failed to generate RSA key: $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "`n[1/5] Using existing key: $KeyPath" -ForegroundColor Cyan
}

# ── Step 2: Load key and generate JWKS ────────────────────────────────────────
Write-Host "`n[2/5] Generating JWKS from private key..." -ForegroundColor Cyan

$pemContent = Get-Content -Path $KeyPath -Raw
$pemClean = $pemContent `
    -replace '-----BEGIN.*-----', '' `
    -replace '-----END.*-----', '' `
    -replace '\s', ''
$keyBytes = [System.Convert]::FromBase64String($pemClean)

$rsa = [System.Security.Cryptography.RSA]::Create()
try {
    if ($pemContent -match 'BEGIN RSA PRIVATE KEY') {
        $rsa.ImportRSAPrivateKey($keyBytes, [ref]$null)
    } else {
        $rsa.ImportPkcs8PrivateKey($keyBytes, [ref]$null)
    }
    
    $params = $rsa.ExportParameters($false)
    
    function ConvertTo-Base64Url {
        param ([byte[]]$Bytes)
        [System.Convert]::ToBase64String($Bytes).
            TrimEnd('=').
            Replace('+', '-').
            Replace('/', '_')
    }
    
    $modulus = ConvertTo-Base64Url -Bytes $params.Modulus
    $exponent = ConvertTo-Base64Url -Bytes $params.Exponent
    $keyId = [guid]::NewGuid().ToString()
    
    $jwks = @{
        keys = @(
            @{
                kty = 'RSA'
                use = 'sig'
                alg = 'RS256'
                kid = $keyId
                n   = $modulus
                e   = $exponent
            }
        )
    } | ConvertTo-Json -Depth 5 -Compress
    
    $jwks | Out-File -FilePath "./jwks.json" -Encoding utf8 -NoNewline
    Write-Host "  JWKS saved: ./jwks.json" -ForegroundColor Green
    Write-Host "  Key ID: $keyId" -ForegroundColor White
}
finally {
    $rsa.Dispose()
}

# ── Step 3: Create storage account ────────────────────────────────────────────
Write-Host "`n[3/5] Creating Azure Storage account..." -ForegroundColor Cyan

if (-not $StorageAccountName) {
    $suffix = -join ((97..122) + (48..57) | Get-Random -Count 8 | ForEach-Object { [char]$_ })
    $StorageAccountName = "bcoidc$suffix"
}

Write-Host "  Storage account name: $StorageAccountName" -ForegroundColor White

# Create resource group
$rgUri = '{0}/subscriptions/{1}/resourceGroups/{2}?api-version=2021-04-01' -f `
    $armUri, $subscriptionId, $ResourceGroupName

Write-Host "  Checking resource group: $ResourceGroupName" -ForegroundColor Yellow

try {
    $rgCheck = Invoke-RestMethod `
        -Uri $rgUri `
        -Headers $authHeader `
        -Method GET `
        -ErrorAction SilentlyContinue
    Write-Host "    Resource group exists" -ForegroundColor Green
}
catch {
    if ($_.Exception.Response.StatusCode -eq 404) {
        Write-Host "    Creating resource group..." -ForegroundColor Yellow
        $rgBody = @{
            location = $Location
        } | ConvertTo-Json
        
        $null = Invoke-RestMethod `
            -Uri $rgUri `
            -Headers $authHeader `
            -Method PUT `
            -Body $rgBody `
            -ContentType 'application/json'
        Write-Host "    Resource group created" -ForegroundColor Green
    }
    else {
        Write-Host "  ERROR: Failed to check resource group: $_" -ForegroundColor Red
        exit 1
    }
}

# Create storage account
$storageApiVersion = '2023-05-01'
$storageUri = '{0}/subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.Storage/storageAccounts/{3}?api-version={4}' -f `
    $armUri, $subscriptionId, $ResourceGroupName, $StorageAccountName, $storageApiVersion

Write-Host "  Creating storage account..." -ForegroundColor Yellow

$storageBody = @{
    kind       = 'StorageV2'
    location   = $Location
    sku        = @{ name = 'Standard_LRS' }
    properties = @{
        allowBlobPublicAccess = $true
        minimumTlsVersion     = 'TLS1_2'
        supportsHttpsTrafficOnly = $true
    }
} | ConvertTo-Json -Depth 5

try {
    $null = Invoke-RestMethod `
        -Uri $storageUri `
        -Headers $authHeader `
        -Method PUT `
        -Body $storageBody `
        -ContentType 'application/json'
    
    # Wait for provisioning
    Write-Host "  Waiting for storage account provisioning..." -ForegroundColor Yellow
    $maxWait = 30
    for ($i = 1; $i -le $maxWait; $i++) {
        Start-Sleep -Seconds 2
        $storageStatus = Invoke-RestMethod `
            -Uri $storageUri `
            -Headers $authHeader `
            -Method GET
        
        if ($storageStatus.properties.provisioningState -eq 'Succeeded') {
            Write-Host "    Storage account ready" -ForegroundColor Green
            break
        }
        
        if ($i -eq $maxWait) {
            Write-Host "  ERROR: Storage account provisioning timeout" -ForegroundColor Red
            exit 1
        }
    }
}
catch {
    Write-Host "  ERROR: Failed to create storage account: $_" -ForegroundColor Red
    Write-Host "    Response: $($_.ErrorDetails.Message)" -ForegroundColor Gray
    exit 1
}

# Get storage account keys for blob operations
$keysUri = '{0}/subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.Storage/storageAccounts/{3}/listKeys?api-version={4}' -f `
    $armUri, $subscriptionId, $ResourceGroupName, $StorageAccountName, $storageApiVersion

try {
    $keys = Invoke-RestMethod `
        -Uri $keysUri `
        -Headers $authHeader `
        -Method POST
    $accountKey = $keys.keys[0].value
}
catch {
    Write-Host "  ERROR: Failed to get storage account keys: $_" -ForegroundColor Red
    exit 1
}

# Create blob container with public access using data plane API
$blobBase = 'https://{0}.blob.core.windows.net' -f $StorageAccountName
$containerUri = '{0}/oidc?restype=container' -f $blobBase

Write-Host "  Creating blob container: oidc (public access)" -ForegroundColor Yellow

$date = [DateTime]::UtcNow.ToString('R')
$stringToSign = "PUT`n`n`n`n`n`n`n`n`n`n`n`nx-ms-blob-public-access:blob`nx-ms-date:$date`nx-ms-version:2021-06-08`n/$StorageAccountName/oidc`nrestype:container"
$hmac = [System.Security.Cryptography.HMACSHA256]::new([Convert]::FromBase64String($accountKey))
$signature = [Convert]::ToBase64String($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($stringToSign)))

try {
    $null = Invoke-RestMethod `
        -Uri $containerUri `
        -Method PUT `
        -Headers @{
            'x-ms-date'                = $date
            'x-ms-version'             = '2021-06-08'
            'x-ms-blob-public-access'  = 'blob'
            'Authorization'            = "SharedKey ${StorageAccountName}:$signature"
        }
    Write-Host "    Container created" -ForegroundColor Green
}
catch {
    # Container might already exist
    if ($_.Exception.Response.StatusCode -ne 409) {
        Write-Host "  WARNING: Container creation returned: $($_.Exception.Response.StatusCode)" -ForegroundColor Yellow
    } else {
        Write-Host "    Container already exists" -ForegroundColor Green
    }
}

$issuerUrl = "https://${StorageAccountName}.blob.core.windows.net/oidc"
Write-Host "  Issuer URL: $issuerUrl" -ForegroundColor Green

# ── Step 4: Create OIDC discovery document ────────────────────────────────────
Write-Host "`n[4/5] Creating OIDC discovery document..." -ForegroundColor Cyan

$discovery = @{
    issuer = $issuerUrl
    jwks_uri = "${issuerUrl}/jwks"
    response_types_supported = @('id_token')
    subject_types_supported = @('public')
    id_token_signing_alg_values_supported = @('RS256')
} | ConvertTo-Json -Compress

$discovery | Out-File -FilePath "./openid-configuration" -Encoding utf8 -NoNewline
Write-Host "  Discovery document saved: ./openid-configuration" -ForegroundColor Green

# ── Step 5: Upload files to blob storage ──────────────────────────────────────
Write-Host "`n[5/5] Uploading OIDC metadata to blob storage..." -ForegroundColor Cyan

# Helper function to upload blob with SharedKey auth
function Upload-Blob {
    param (
        [string]$BlobName,
        [string]$Content,
        [string]$ContentType = 'application/json'
    )
    
    $blobUri = '{0}/oidc/{1}' -f $blobBase, $BlobName
    $contentBytes = [Text.Encoding]::UTF8.GetBytes($Content)
    $contentLength = $contentBytes.Length
    $date = [DateTime]::UtcNow.ToString('R')
    
    # Build canonical headers and string to sign for SharedKey
    $canonicalHeaders = "x-ms-blob-type:BlockBlob`nx-ms-date:$date`nx-ms-version:2021-06-08"
    $canonicalResource = "/$StorageAccountName/oidc/$BlobName"
    $stringToSign = "PUT`n`n`n$contentLength`n`n$ContentType`n`n`n`n`n`n`n$canonicalHeaders`n$canonicalResource"
    
    $hmac = [System.Security.Cryptography.HMACSHA256]::new([Convert]::FromBase64String($accountKey))
    $signature = [Convert]::ToBase64String($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($stringToSign)))
    
    try {
        $null = Invoke-RestMethod `
            -Uri $blobUri `
            -Method PUT `
            -Headers @{
                'x-ms-date'       = $date
                'x-ms-version'    = '2021-06-08'
                'x-ms-blob-type'  = 'BlockBlob'
                'Content-Type'    = $ContentType
                'Content-Length'  = $contentLength
                'Authorization'   = "SharedKey ${StorageAccountName}:$signature"
            } `
            -Body $contentBytes
        return $true
    }
    catch {
        Write-Host "    ERROR uploading $BlobName`: $_" -ForegroundColor Red
        return $false
    }
}

# Upload JWKS
Write-Host "  Uploading jwks..." -ForegroundColor Yellow
$jwksContent = Get-Content -Path ./jwks.json -Raw
if (Upload-Blob -BlobName 'jwks' -Content $jwksContent) {
    Write-Host "    ✓ jwks uploaded" -ForegroundColor Green
}

# Upload discovery document
Write-Host "  Uploading .well-known/openid-configuration..." -ForegroundColor Yellow
$discoveryContent = Get-Content -Path ./openid-configuration -Raw
if (Upload-Blob -BlobName '.well-known/openid-configuration' -Content $discoveryContent) {
    Write-Host "    ✓ Discovery document uploaded" -ForegroundColor Green
}

# ── Verify setup ───────────────────────────────────────────────────────────────
Write-Host "`n✓ Setup complete!" -ForegroundColor Green
Write-Host "`nVerifying anonymous access..." -ForegroundColor Cyan

try {
    $jwksTest = Invoke-RestMethod -Uri "${issuerUrl}/jwks" -Method GET -ErrorAction Stop
    Write-Host "  ✓ JWKS accessible (kid: $($jwksTest.keys[0].kid))" -ForegroundColor Green
    
    $discoveryTest = Invoke-RestMethod -Uri "${issuerUrl}/.well-known/openid-configuration" -Method GET -ErrorAction Stop
    Write-Host "  ✓ Discovery document accessible" -ForegroundColor Green
    Write-Host "    Issuer: $($discoveryTest.issuer)" -ForegroundColor Gray
    Write-Host "    JWKS URI: $($discoveryTest.jwks_uri)" -ForegroundColor Gray
}
catch {
    Write-Host "  ⚠ Warning: Anonymous access verification failed" -ForegroundColor Yellow
    Write-Host "    Error: $_" -ForegroundColor Gray
    Write-Host "    Wait 30s for propagation, then verify manually:" -ForegroundColor Yellow
    Write-Host "    Invoke-RestMethod '${issuerUrl}/jwks'" -ForegroundColor White
}

# ── Usage instructions ─────────────────────────────────────────────────────────
Write-Host "`n" + ("─" * 70) -ForegroundColor Gray
Write-Host "Usage Example:" -ForegroundColor Cyan
Write-Host @"

Invoke-FederatedTokenExchange ``
    -Name "your-uami-name" ``
    -ResourceGroupName "your-resource-group" ``
    -IssuerUrl "$issuerUrl" ``
    -PrivateKeyPath "$KeyPath" ``
    -Cleanup

"@ -ForegroundColor White

Write-Host "Local Files:" -ForegroundColor Cyan
Write-Host "  - Private key:     $KeyPath (KEEP SECURE!)" -ForegroundColor White
Write-Host "  - JWKS:            ./jwks.json" -ForegroundColor White
Write-Host "  - Discovery doc:   ./openid-configuration" -ForegroundColor White
Write-Host "`nAzure Resources:" -ForegroundColor Cyan
Write-Host "  - Subscription:    $subscriptionId" -ForegroundColor White
Write-Host "  - Resource Group:  $ResourceGroupName" -ForegroundColor White
Write-Host "  - Storage Account: $StorageAccountName" -ForegroundColor White
Write-Host "  - Container:       oidc (public blob access)" -ForegroundColor White
Write-Host "  - Issuer URL:      $issuerUrl" -ForegroundColor White
Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "  1. Keep $KeyPath secure (backup to Key Vault recommended)" -ForegroundColor White
Write-Host "  2. Use Invoke-FederatedTokenExchange to extract UAMI tokens" -ForegroundColor White
Write-Host "  3. Clean up with -Cleanup flag to remove FICs after extraction" -ForegroundColor White
Write-Host ("─" * 70) -ForegroundColor Gray
