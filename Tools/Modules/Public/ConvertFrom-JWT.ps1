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
        [PSCustomObject] @{
            Header  = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String((Invoke-SplitJWT $Spl[0]))) | ConvertFrom-Json
            Payload = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String((Invoke-SplitJWT $Spl[1]))) | ConvertFrom-Json
        }

    }
    End {
    }
}