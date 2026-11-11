function Invoke-SplitJWT {
    Param
    (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0)]
        $String
    )

    Process {
        $Length = $String.Length
        if ($String.Length % 4 -ne 0) {
            $Length += 4 - ($String.Length % 4)
        }
        return $String.PadRight($Length, "=")
    }
<#
    .SYNOPSIS
    Pads a JWT string with '=' characters to make its length a multiple of 4.

    .DESCRIPTION
    Pads a JWT string with '=' characters so its length is a multiple of 4, required for base64 decoding.

    .PARAMETER String
    The JWT string to pad.

    .EXAMPLE
    PS C:\> "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" | Invoke-SplitJWT
    eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9====

    .NOTES
    Prepares JWT strings for base64 decoding.
#>
}