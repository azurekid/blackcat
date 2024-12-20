function Invoke-UpdateHelpers {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet("Azure Public", "Azure China", "Azure Germany", "Azure US Government")]
        [string]$Region = 'Azure Public',

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet("Azure Public", "Azure China", "Azure Germany", "Azure US Government")]
        [string]$Repository = 'https://raw.githubusercontent.com/azurekid/blackcat/refs/heads/main/src/Helpers/'
    )

    begin {
        # $MyInvocation.MyCommand.Name | Invoke-BlackCat
        switch ($Region) {
            "Azure Public" { $uri = "https://www.microsoft.com/en-us/download/confirmation.aspx?id=56519" }
            "Azure China" { $uri = "https://www.microsoft.com/en-us/download/confirmation.aspx?id=57062" }
            "Azure Germany" { $uri = "https://www.microsoft.com/en-us/download/confirmation.aspx?id=57064" }
            "Azure US Government" { $uri = "https://www.microsoft.com/en-us/download/confirmation.aspx?id=57063" }
        }

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

            # $uri = ((Invoke-WebRequest -uri $uri).links | Where-Object outerHTML -like "*click here to download manually*").href
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
        Updates the service tags for Azure regions.

    .DESCRIPTION
        The Update-ServiceTags function is used to update the service tags for Azure regions. It retrieves the latest IP ranges for the specified region and updates the service tags accordingly.

    .PARAMETER Region
        Specifies the Azure region for which to update the service tags. The available options are:
        - Azure Public
        - Azure China
        - Azure Germany
        - Azure US Government
        The default value is 'Azure Public'.

    .EXAMPLE
        Update-ServiceTags -Region "Azure Public"
        Updates the service tags for the Azure Public region.

    .EXAMPLE
        Update-ServiceTags -Region "Azure China"
        Updates the service tags for the Azure China region.

    .INPUTS
        None. You cannot pipe objects to this function.

    .OUTPUTS
        None. The function does not generate any output.

    .NOTES
        Author: Your Name
        Date: Today's Date
#>
}
