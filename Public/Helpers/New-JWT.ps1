function New-JWT {
    [CmdletBinding(
        SupportsShouldProcess = $true,
        DefaultParameterSetName = 'HMAC'
    )]
    [OutputType([string])]
    Param
    (
        [Parameter(Mandatory = $true)]
        [string]$Audience,

        [Parameter(Mandatory = $true)]
        [string]$Issuer,

        [Parameter(Mandatory = $true)]
        [string]$Subject,

        [Parameter(Mandatory = $true)]
        [int]$ExpirationMinutes,

        [Parameter(
            Mandatory = $true,
            ParameterSetName = 'HMAC'
        )]
        [string]$SigningKey,

        [Parameter(
            Mandatory = $true,
            ParameterSetName = 'RSA'
        )]
        [System.Security.Cryptography.RSA]$RSAKey,

        [Parameter(
            Mandatory = $false,
            ParameterSetName = 'RSA'
        )]
        [string]$KeyId,

        [Parameter(Mandatory = $false)]
        [hashtable]$AdditionalClaims
    )

    if ($PSCmdlet.ShouldProcess(
        "Creating a new JWT token"
    )) {
        $isRSA = $PSCmdlet.ParameterSetName -eq 'RSA'

        $header = @{
            alg = if ($isRSA) { 'RS256' } else { 'HS256' }
            typ = 'JWT'
        }
        if ($KeyId) { $header.kid = $KeyId }

        $now = [math]::Floor(
            [System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        )
        $exp = [math]::Floor(
            ([System.DateTimeOffset]::UtcNow.AddMinutes(
                $ExpirationMinutes
            )).ToUnixTimeSeconds()
        )

        $payload = @{
            aud = $Audience
            iss = $Issuer
            iat = $now
            nbf = $now
            exp = $exp
            sub = $Subject
        }

        if ($AdditionalClaims) {
            foreach ($key in $AdditionalClaims.Keys) {
                $payload[$key] = $AdditionalClaims[$key]
            }
        }

        $headerJson = $header | ConvertTo-Json -Compress
        $payloadJson = $payload | ConvertTo-Json -Compress

        if ($isRSA) {
            $headerB64 = ConvertTo-Base64Url -Bytes (
                [System.Text.Encoding]::UTF8.GetBytes(
                    $headerJson
                )
            )
            $payloadB64 = ConvertTo-Base64Url -Bytes (
                [System.Text.Encoding]::UTF8.GetBytes(
                    $payloadJson
                )
            )

            $sigInput = '{0}.{1}' -f $headerB64, $payloadB64
            $sigBytes = $RSAKey.SignData(
                [System.Text.Encoding]::UTF8.GetBytes(
                    $sigInput
                ),
                [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
            )
            $signature = ConvertTo-Base64Url -Bytes $sigBytes

            return '{0}.{1}.{2}' -f `
                $headerB64, $payloadB64, $signature
        }
        else {
            $headerBase64 = [System.Convert]::ToBase64String(
                [System.Text.Encoding]::UTF8.GetBytes(
                    $headerJson
                )
            )
            $payloadBase64 = [System.Convert]::ToBase64String(
                [System.Text.Encoding]::UTF8.GetBytes(
                    $payloadJson
                )
            )

            $signature = [System.Convert]::ToBase64String(
                [System.Security.Cryptography.HMACSHA256]::new(
                    [System.Text.Encoding]::UTF8.GetBytes(
                        $SigningKey
                    )
                ).ComputeHash(
                    [System.Text.Encoding]::UTF8.GetBytes(
                        "$headerBase64.$payloadBase64"
                    )
                )
            )

            $jwt = "$headerBase64.$payloadBase64.$signature"
            return $jwt
        }
    }
<#
.SYNOPSIS
Generates a new JWT with HS256 or RS256 signing.

.DESCRIPTION
Creates a new JWT token using HS256 (HMAC-SHA256) or RS256
(RSA-SHA256) algorithm. Supports custom claims via the
AdditionalClaims parameter. RS256 mode uses proper Base64URL
encoding as required by RFC 7515 and the Entra token endpoint.

.PARAMETER Audience
The audience (aud) claim. Typically the intended recipient.

.PARAMETER Issuer
The issuer (iss) claim. The entity that issued the token.

.PARAMETER Subject
The subject (sub) claim. The principal of the token.

.PARAMETER ExpirationMinutes
Expiration time in minutes from now.

.PARAMETER SigningKey
Secret key for HS256 signing. Required for HMAC parameter set.

.PARAMETER RSAKey
RSA key object for RS256 signing. Required for RSA parameter
set. Generate with [System.Security.Cryptography.RSA]::Create().

.PARAMETER KeyId
Optional key identifier (kid) added to the JWT header.
Required when the JWKS contains multiple keys.

.PARAMETER AdditionalClaims
Hashtable of extra claims to include in the payload.
Example: @{ jti = [guid]::NewGuid().ToString() }

.EXAMPLE
New-JWT -Audience "example.com" -Issuer "my-app" `
    -Subject "user123" -ExpirationMinutes 60 `
    -SigningKey "my-secret-key"

Generates an HS256-signed JWT token.

.EXAMPLE
$rsa = [System.Security.Cryptography.RSA]::Create(2048)
New-JWT -Audience "api://AzureADTokenExchange" `
    -Issuer "https://myissuer.example.com" `
    -Subject "workload-identity" `
    -ExpirationMinutes 10 `
    -RSAKey $rsa -KeyId "key-1" `
    -AdditionalClaims @{ jti = [guid]::NewGuid().ToString() }

Generates an RS256-signed JWT for Entra ID federated
identity credential token exchange.

.NOTES
    RS256 tokens use Base64URL encoding (RFC 7515).
    HS256 tokens preserve legacy Base64 encoding for
    backward compatibility.

.LINK
    MITRE ATT&CK Tactic: TA0006 - Credential Access
    https://attack.mitre.org/tactics/TA0006/

.LINK
    MITRE ATT&CK Technique: T1606.002 - Forge Web Credentials
    https://attack.mitre.org/techniques/T1606/002/
#>
}