function New-JWT {
    [CmdletBinding()]
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