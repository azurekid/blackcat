function ConvertTo-Base64Url {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0)]
        [byte[]]$Bytes
    )

    Process {
        [System.Convert]::ToBase64String($Bytes).
            TrimEnd('=').
            Replace('+', '-').
            Replace('/', '_')
    }

    <#
    .SYNOPSIS
        Converts a byte array to a Base64URL-encoded string.

    .DESCRIPTION
        Encodes a byte array using standard Base64 and then
        applies URL-safe transformations per RFC 4648 section 5:
        padding removed, '+' replaced with '-', '/' with '_'.
        Used for JWT header/payload encoding and JWKS key
        parameters.

    .PARAMETER Bytes
        The byte array to encode.

    .EXAMPLE
        $encoded = ConvertTo-Base64Url -Bytes ([byte[]]@(1,2,3))

        Converts bytes to a Base64URL string.

    .EXAMPLE
        [Text.Encoding]::UTF8.GetBytes('hello') |
            ConvertTo-Base64Url

        Encodes a UTF-8 string as Base64URL via pipeline.

    .NOTES
        Private helper function used by New-JWT and
        Setup-FederatedTokenExchange for JWKS generation.
    #>
}
