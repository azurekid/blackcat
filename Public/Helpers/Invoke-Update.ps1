function Invoke-Update {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$Repository = 'https://raw.githubusercontent.com/azurekid/blackcat/refs/heads/main/support-files/'
    )

    begin {

        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"

        $filesArray = @(
            'permutations.txt',
            'userAgents.json',
            'ServiceTags.json',
            'appRoleIds.csv',
            'EntraRoles.csv',
            'AzureRoles.csv',
            'subdomains.json'
        )
    }

    process {
        Write-Verbose "Creating helper directory"
        Test-Path -Path $helperPath -ErrorAction SilentlyContinue | New-Item -ItemType Directory -Path $helperPath -Force

        try {
            Write-Verbose "Downloading support files"

            foreach ($file in $filesArray) {
                $fileUri = "$Repository$file"
                $destinationPath = "$helperPath/$file"
                Write-Verbose "Downloading $file from $fileUri to $destinationPath"
                Invoke-WebRequest -Uri $fileUri -OutFile $destinationPath -ErrorAction Stop
                Update-AzureServiceTag -Region 'Azure Public'
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
        The Invoke-Update function downloads a set of predefined helper files from a specified repository URL and saves them to a local directory. This function is useful for keeping local helper files up-to-date with the latest versions available in the repository.

    .PARAMETER Repository
        Specifies the base URL of the repository from which to download the helper files. The default value is 'https://raw.githubusercontent.com/azurekid/blackcat/refs/heads/main/src/Helpers/'.

    .EXAMPLE
        Invoke-Update
        Downloads the helper files from the default repository URL and saves them to the local directory.

    .EXAMPLE
        Invoke-Update -Repository 'https://example.com/helpers/'
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