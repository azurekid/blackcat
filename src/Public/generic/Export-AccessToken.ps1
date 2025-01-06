function Export-AccessToken {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [array]$audiences = @("https://graph.microsoft.com/.default", "https://management.azure.com/.default", "https://vault.azure.net/.default"),

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputFile = "AccessTokens.txt"
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
    }

    process {
        try {
            Write-Verbose "Requesting access tokens for specified audiences"
            $tokens = @()

            foreach ($audience in $audiences) {
                $accessToken = Get-AzAccessToken -Audience $audience
                $tokenObject = [PSCustomObject]@{
                    Audience = $audience
                    Token    = $accessToken
                }
                $tokens += $tokenObject
            }

            Write-Verbose "Exporting tokens to file $OutputFile"
            $tokens | Out-File -FilePath $OutputFile
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }

    <#
    .SYNOPSIS
        This function exports access tokens for specified audiences to a text file.

    .DESCRIPTION
        The Export-AccessToken function requests access tokens for the specified audiences and exports them to a text file. It handles errors and logs messages accordingly.

    .PARAMETER audiences
        The audiences parameter is an optional array of strings that specifies the audiences for which to request access tokens.

    .PARAMETER OutputFile
        The OutputFile parameter is an optional string that specifies the path to the file where the tokens will be exported.

    .EXAMPLE
        ```powershell
        Export-AccessToken -audiences @("https://graph.microsoft.com/.default") -OutputFile "AccessTokens.txt"
        ```
        This example calls the Export-AccessToken function with a specified audience and output file.

    .EXAMPLE
        ```powershell
        Export-AccessToken -OutputFile "AccessTokens.txt"
        ```
        This example calls the Export-AccessToken function with the default audiences and a specified output file.

    .LINK
        For more information, see the related documentation or contact support.
    #>
}