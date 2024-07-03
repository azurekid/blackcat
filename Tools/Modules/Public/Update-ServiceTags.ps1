function Update-ServiceTags {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Region = 'Azure Cloud'
    )

    begin {
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {

        try {

            Write-Verbose "Getting lastest IP Ranges"
            $uri = ((Invoke-WebRequest -uri "https://www.microsoft.com/en-us/download/confirmation.aspx?id=56519").links | Where-Object outerHTML -like "*click here to download manually*").href
            (Invoke-RestMethod -uri $uri).values | ConvertTo-Json -Depth 100 | Out-File $helperPath\ServiceTags.json -Force

            Write-Verbose "Updating Service Tags"
            $sessionVariables:serviceTags = (Get-Content $helperPath\ServiceTags.json | ConvertFrom-Json)
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
<#
    .SYNOPSIS
    Updates the service tags by retrieving the latest IP ranges from Microsoft.

    .DESCRIPTION
    The Update-ServiceTags function retrieves the latest IP ranges from Microsoft's website and updates the service tags accordingly. It downloads the IP ranges JSON file and converts it to a PowerShell object for further processing.

    .PARAMETER Region
    Specifies the region for which the service tags should be updated. The default value is 'Azure Cloud'.

    .EXAMPLE
    Update-ServiceTags -Region 'West US'

    This example updates the service tags for the 'West US' region.

    .INPUTS
    None. You cannot pipe input to this function.

    .OUTPUTS
    None. The function does not generate any output.

    .NOTES
    Author: Your Name
    Date: Today's Date
#>
}