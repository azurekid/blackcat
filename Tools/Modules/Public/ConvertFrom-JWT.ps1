function ConvertFrom-JWT {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0)]
        $Base64JWT
    )

    Begin {
    }
    Process {
        $Spl = $Base64JWT.Split(".")
        $token = [PSCustomObject] @{
            Header  = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String((Invoke-SplitJWT $Spl[0]))) | ConvertFrom-Json
            Payload = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String((Invoke-SplitJWT $Spl[1]))) | ConvertFrom-Json
        }

        $jwtroles = @()
        foreach ($Role in $token.Payload.wids) {
            $jwtRoles += ($SessionVariables.Roles | Where-Object { $_.ID -eq $Role }).displayName
        }
    }
    End {
        $result = [PSCustomObject]@{
            Audience         = $token.Payload.aud
            Issuer           = $token.Payload.iss
            IssuedAt         = [System.DateTimeOffset]::FromUnixTimeSeconds($token.Payload.iat)
            Expires          = [System.DateTimeOffset]::FromUnixTimeSeconds($token.Payload.exp)
            NotBefore        = [System.DateTimeOffset]::FromUnixTimeSeconds($token.Payload.nbf)
            UPN              = $token.Payload.upn
            FirstName        = $token.Payload.given_name
            LastName         = $token.Payload.family_name
            "User Object ID" = $token.Payload.oid
            "Auth. Method"   = $token.Payload.amr
            "IP Address"     = $token.Payload.ipaddr
            "Tenant ID"      = $token.Payload.tid
            Scope            = $token.Payload.scp
            Roles            = $jwtRoles
        }

        return $result
    }
}
