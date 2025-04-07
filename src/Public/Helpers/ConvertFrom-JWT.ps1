function ConvertFrom-JWT {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0)]
            # [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9-]+[A-Za-z0-9]$', ErrorMessage = "It does not match a valid JWT Token")]
        $Base64JWT
    )

    Begin {
        if ($Base64JWT -like "Bearer *") {
            $Base64JWT = $Base64JWT -replace "Bearer ", ""
        }
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
            "ObjectId"       = $token.Payload.oid
            "Auth. Method"   = $token.Payload.amr
            "IP Address"     = $token.Payload.ipaddr
            "Tenant ID"      = $token.Payload.tid
            Scope            = $token.Payload.scp
            Roles            = $jwtRoles
        }

        return $result
    }
<#
.SYNOPSIS
Converts a JSON Web Token (JWT) from Base64 encoding to a PowerShell object.

.DESCRIPTION
The ConvertFrom-JWT function takes a Base64-encoded JWT as input and converts it into a PowerShell object. It splits the JWT into its header and payload parts, decodes them from Base64, and converts them into JSON objects. It also extracts specific properties from the payload and returns them as properties of the resulting object.

.PARAMETER Base64JWT
The Base64-encoded JWT to convert.

.OUTPUTS
The function returns a PowerShell object with the following properties:
- Audience: The audience of the JWT.
- Issuer: The issuer of the JWT.
- IssuedAt: The timestamp when the JWT was issued.
- Expires: The timestamp when the JWT expires.
- NotBefore: The timestamp when the JWT becomes valid.
- UPN: The user principal name associated with the JWT.
- FirstName: The first name of the user associated with the JWT.
- LastName: The last name of the user associated with the JWT.
- User Object ID: The object ID of the user associated with the JWT.
- Auth. Method: The authentication method used for the JWT.
- IP Address: The IP address associated with the JWT.
- Tenant ID: The ID of the tenant associated with the JWT.
- Scope: The scope of the JWT.
- Roles: An array of roles associated with the JWT.

.EXAMPLE
$jwt = "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJCbGFja0NhdCIsImlhdCI6MTcyMDAzNzg4MCwiZXhwIjoxNzM1Njc2MjgwLCJhdWQiOiJodHRwOi8vZ2l0aHViLmNvbS9henVyZWtpZC9ibGFja2NhdCIsInN1YiI6Impyb2NrZXRAZXhhbXBsZS5jb20iLCJnaXZlbl9uYW1lIjoiSGFybGFuZCIsImZhbWlseV9uYW1lIjoiU2FuZGVycyIsInVwbiI6Imguc2FuZGVyc0BibGFja2NhdC5pbyIsIm9pZCI6IjkyYmUzMGQ4LTNiYzctNDZjNy05ZDJjLWQ5MGY2MTlmOWNkNCIsImFtciI6Ik1GQSIsImlwYWRkciI6IjEyNy4wLjEuMSIsInNjcCI6IkxhYnMiLCJ3aWRzIjoiNjJlOTAzOTQtNjlmNS00MjM3LTkxOTAtMDEyMTc3MTQ1ZTEwIiwidGlkIjoiNmNhZWM2YWEtMDYzYS00ZGMyLTg2MjUtMGQzN2YwM2ViMWNhIn0.ui-Axc5b6EhazRwYtRYLdMFJpESiwykP8l-4rJgnduQ"
$result = ConvertFrom-JWT -Base64JWT $jwt
$result

This example demonstrates how to use the ConvertFrom-JWT function to convert a Base64-encoded JWT into a PowerShell object. The resulting object is then assigned to the $result variable and displayed.

#>
}