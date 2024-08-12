function Update-ServiceTags {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet("Azure Public", "Azure China", "Azure Germany", "Azure US Government")]
        [string]$Region = 'Azure Public'
    )

    begin {
        # $MyInvocation.MyCommand.Name | Invoke-BlackCat
        switch ($Region) {
            "Azure Public" { $uri = "https://www.microsoft.com/en-us/download/confirmation.aspx?id=56519" }
            "Azure China" { $uri = "https://www.microsoft.com/en-us/download/confirmation.aspx?id=57062" }
            "Azure Germany" { $uri = "https://www.microsoft.com/en-us/download/confirmation.aspx?id=57064" }
            "Azure US Government" { $uri = "https://www.microsoft.com/en-us/download/confirmation.aspx?id=57063" }
        }
    }

    process {
        try {
            Write-Verbose "Getting lastest IP Ranges"

            $uri = ((Invoke-WebRequest -uri $uri).links | Where-Object outerHTML -like "*click here to download manually*").href
            (Invoke-RestMethod -uri $uri).values | ConvertTo-Json -Depth 100 | Out-File $helperPath/ServiceTags.json -Force

            Write-Verbose "Updating Service Tags for $Region"
            $sessionVariables.serviceTags = (Get-Content $helperPath/ServiceTags.json | ConvertFrom-Json)
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
