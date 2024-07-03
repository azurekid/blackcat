function New-JWTToken {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Issuer,

        [Parameter(Mandatory = $true)]
        [string]$Subject,

        [Parameter(Mandatory = $true)]
        [string]$Audience,

        [Parameter(Mandatory = $true)]
        [string]$Secret,

        [Parameter(Mandatory = $true)]
        [int]$ExpirationMinutes
    )

    $header = @{
        "alg" = "HS256"
        "typ" = "JWT"
    }

    $payload = @{
        "iss" = $Issuer
        "sub" = $Subject
        "aud" = $Audience
        "exp" = Get-Date  -Date (Get-Date).AddMinutes($ExpirationMinutes).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        "iat" =  Get-Date -Date (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        "nbf" = Get-Date  -Date (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    $headerBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($header | ConvertTo-Json -Compress)))
    $payloadBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Compress)))

    $signature = [System.Convert]::ToBase64String([System.Security.Cryptography.HMACSHA256]::new([System.Text.Encoding]::UTF8.GetBytes($Secret)).ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$headerBase64.$payloadBase64")))

    $jwtToken = "$headerBase64.$payloadBase64.$signature"

    return $jwtToken
}