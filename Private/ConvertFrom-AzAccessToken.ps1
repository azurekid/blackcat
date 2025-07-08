function ConvertFrom-AzAccessToken {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        $Token
    )

    try {
        # Handle string tokens (older Az.Accounts versions)
        if ($Token -is [string]) {
            return $Token
        }
        # Handle SecureString tokens (newer Az.Accounts versions)
        elseif ($Token.GetType().Name -eq 'SecureString') {
            $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token)
            try {
                return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
            }
            finally {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
            }
        }
        # Fallback for other token types
        else {
            return $Token.ToString()
        }
    }
    catch {
        Write-Warning "Failed to convert access token: $($_.Exception.Message)"
        return $null
    }

    <#
    .SYNOPSIS
        Converts Azure access tokens from different Az.Accounts module versions to a string.

    .DESCRIPTION
        The ConvertFrom-AzAccessToken function safely converts access tokens returned by Get-AzAccessToken
        from both older versions (string tokens) and newer versions (SecureString tokens) of the Az.Accounts module.
        This ensures backwards compatibility across different module versions.

    .PARAMETER Token
        The token object returned by Get-AzAccessToken. Can be a string (older versions) or SecureString (newer versions).

    .EXAMPLE
        $token = Get-AzAccessToken -ResourceTypeName 'MSGraph'
        $tokenString = ConvertFrom-AzAccessToken -Token $token.Token

    .EXAMPLE
        $token = Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com'
        $tokenString = ConvertFrom-AzAccessToken -Token $token.Token

    .NOTES
        Author: Rogier Dijkman
        This function provides backwards compatibility for the Az.Accounts module token format changes.
        Properly handles memory cleanup for SecureString tokens to prevent memory leaks.
    #>
}
