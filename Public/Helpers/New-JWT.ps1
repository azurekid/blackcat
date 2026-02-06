function New-JWT {
    [CmdletBinding(SupportsShouldProcess = $true)]
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

        [Parameter(Mandatory = $true)]
        [string]$SigningKey
    )

    if ($PSCmdlet.ShouldProcess("Creating a new JWT token")) {
        $header = @{
            alg = "HS256"
            typ = "JWT"
        }

        $payload = @{
            aud         = $Audience
            iss         = $Issuer
            iat         = [math]::Floor([System.DateTimeOffset]::Now.ToUnixTimeSeconds())
            nbf         = [math]::Floor([System.DateTimeOffset]::Now.ToUnixTimeSeconds())
            exp         = [math]::Floor(([System.DateTimeOffset]::Now.AddMinutes($ExpirationMinutes)).ToUnixTimeSeconds())
            sub         = $Subject
        }

        $headerJson = $header | ConvertTo-Json -Compress
        $payloadJson = $payload | ConvertTo-Json -Compress

        $headerBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($headerJson))
        $payloadBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($payloadJson))

        $signature = [System.Convert]::ToBase64String([System.Security.Cryptography.HMACSHA256]::new([System.Text.Encoding]::UTF8.GetBytes($SigningKey)).ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$headerBase64.$payloadBase64")))

        $jwt = "$headerBase64.$payloadBase64.$signature"
        return $jwt
    }
<#
.SYNOPSIS
Generates a new JSON Web Token (JWT) with the specified parameters.

.DESCRIPTION
Creates a new JWT token using HS256 algorithm with specified audience, issuer, and expiration. Supports custom claims and signing keys for token generation. Useful for testing authentication mechanisms and creating test tokens for Azure services.

.PARAMETER Audience
Specifies the audience (aud) claim for the JWT. This is typically the intended recipient of the token.

.PARAMETER Issuer
Specifies the issuer (iss) claim for the JWT. This is typically the entity that issued the token.

.PARAMETER Subject
Specifies the subject (sub) claim for the JWT. This is typically the principal that is the subject of the token.

.PARAMETER ExpirationMinutes
Specifies the expiration time (exp) claim for the JWT in minutes. This determines how long the token is valid.

.PARAMETER SigningKey
Specifies the secret key used to sign the JWT. This key is used to generate the signature for the token.

.EXAMPLE
PS> New-JWT -Audience "example.com" -Issuer "my-app" -Subject "user123" -ExpirationMinutes 60 -SigningKey "my-secret-key"
Generates a JWT token for the specified audience, issuer, subject, and expiration time using the provided signing key.

.NOTES
    This function can be used to forge JWT tokens for testing or attack scenarios.

.LINK
    MITRE ATT&CK Tactic: TA0006 - Credential Access
    https://attack.mitre.org/tactics/TA0006/

.LINK
    MITRE ATT&CK Technique: T1606.002 - Forge Web Credentials: SAML Tokens
    https://attack.mitre.org/techniques/T1606/002/
#>
}