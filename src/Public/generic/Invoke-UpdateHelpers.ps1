function Invoke-UpdateHelpers {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$Repository = 'https://raw.githubusercontent.com/azurekid/blackcat/refs/heads/main/src/Helpers/'
    )

    begin {

        $filesArray = @(
            'permutations.txt',
            'userAgents.json',
            'ServiceTags.json',
            'appRoleIds.csv',
            'wordlist.txt',
            'EntraRoles.csv'

        )
    }

    process {
        try {
            Write-Verbose "Downloading support files"

            foreach ($file in $filesArray) {
                $fileUri = "$Repository$file"
                $destinationPath = "$helperPath/$file"
                Write-Verbose "Downloading $file from $fileUri to $destinationPath"
                Invoke-WebRequest -Uri $fileUri -OutFile $destinationPath -ErrorAction Stop
            }

        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
<#
    .SYNOPSIS
        Downloads and updates helper files from a specified repository.

    .DESCRIPTION
        The Invoke-UpdateHelpers function downloads a set of predefined helper files from a specified repository URL and saves them to a local directory. This function is useful for keeping local helper files up-to-date with the latest versions available in the repository.

    .PARAMETER Repository
        Specifies the base URL of the repository from which to download the helper files. The default value is 'https://raw.githubusercontent.com/azurekid/blackcat/refs/heads/main/src/Helpers/'.

    .EXAMPLE
        Invoke-UpdateHelpers
        Downloads the helper files from the default repository URL and saves them to the local directory.

    .EXAMPLE
        Invoke-UpdateHelpers -Repository 'https://example.com/helpers/'
        Downloads the helper files from the specified repository URL and saves them to the local directory.

    .INPUTS
        None. You cannot pipe objects to this function.

    .OUTPUTS
        None. The function does not generate any output.

    .NOTES
        Author: Your Name
        Date: Today's Date
#>
}