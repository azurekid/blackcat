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
    The `Invoke-SplitJWT` function takes a JWT string as input and pads it with '=' characters to ensure its length is a multiple of 4. This is useful for base64 decoding, as base64 encoded strings must have a length that is a multiple of 4.

    .PARAMETER String
    The JWT string to be padded.

    .EXAMPLES
    # Example 1
    PS C:\> "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" | Invoke-SplitJWT
    eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9====

    # Example 2
    PS C:\> $jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
    PS C:\> Invoke-SplitJWT -String $jwt
    eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9====

    .NOTES
    This function is useful for preparing JWT strings for base64 decoding.
#>
}