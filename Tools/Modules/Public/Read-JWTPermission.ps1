function Read-JWT {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true,
        ValueFromPipeline = $true,
        Position = 0)]
        $Base64JWT
    )

    Begin {
        $Roles = Get-Content -Path ./roles.csv | ConvertFrom-Csv
    }
    Process {
        $tokenValues = (ConvertFrom-JWT -Base64JWT $Base64JWT)

        $jwtroles = @()
        foreach ($Role in $tokenValues.Payload.wids) {
            $jwtRoles += ($Roles | Where-Object { $_.ID -eq $Role }).displayName
        }

        return $jwtRoles
    }
    End {
    }
}