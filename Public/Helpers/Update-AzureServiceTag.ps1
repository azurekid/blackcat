function Update-AzureServiceTag {
    <#
    .SYNOPSIS
        Updates the local cache of Azure Service Tags from Microsoft.

    .DESCRIPTION
        Downloads the latest Azure IP ranges and Service Tags from Microsoft's download center.
        The service tag data is stored locally and used by Find-AzureServiceTag for IP lookups.
        Supports Azure Public, Azure China, Azure Germany, and Azure US Government clouds.

    .PARAMETER Region
        The Azure cloud region to download service tags for.
        Valid values: "Azure Public", "Azure China", "Azure Germany", "Azure US Government".
        Default: "Azure Public".

    .EXAMPLE
        Update-AzureServiceTag

        Downloads and updates the service tags for Azure Public cloud.

    .EXAMPLE
        Update-AzureServiceTag -Region "Azure US Government"

        Downloads and updates the service tags for Azure US Government cloud.

    .NOTES
        This function must be run before using Find-AzureServiceTag.
        The downloaded data is saved to ServiceTags.json in the helper path.

    .LINK
        MITRE ATT&CK Tactic: TA0007 - Discovery
        https://attack.mitre.org/tactics/TA0007/

    .LINK
        MITRE ATT&CK Technique: T1526 - Cloud Service Discovery
        https://attack.mitre.org/techniques/T1526/

    #>
    [cmdletbinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet("Azure Public", "Azure China", "Azure Germany", "Azure US Government")]
        [string]$Region = 'Azure Public'
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
    }

    process {
        try {
            switch ($Region) {
                "Azure Public" { $uri = "https://www.microsoft.com/download/details.aspx?id=56519" }
                "Azure China" { $uri = "https://www.microsoft.com/download/details.aspx?id=57062" }
                "Azure Germany" { $uri = "https://www.microsoft.com/download/details.aspx?id=57064" }
                "Azure US Government" { $uri = "https://www.microsoft.com/download/details.aspx?id=57063" }
            }

            if ($PSCmdlet.ShouldProcess("Service Tags for $Region", "Update")) {
                Write-Verbose "Getting latest IP Ranges"

                $uri = ((Invoke-WebRequest -uri $uri).links | Where-Object outerHTML -like "*Azure IP Ranges*").href

                Write-Verbose "Downloading Service Tags from $uri"
                $serviceTagData = Invoke-RestMethod -uri $uri
                
                # Extract the values array from the service tag data if it exists
                $serviceTagValues = if ($serviceTagData.PSObject.Properties.Name -contains 'values') {
                    $serviceTagData.values
                } else {
                    $serviceTagData
                }
                
                # Save to file
                $serviceTagValues | ConvertTo-Json -Depth 100 | Out-File $helperPath/ServiceTags.json -Force

                Write-Verbose "Updating Service Tags for $Region"
                # Initialize session variables if they don't exist
                if (-not $script:SessionVariables) { $script:SessionVariables = @{} }
                
                # Store service tags in script scope
                $script:SessionVariables.serviceTags = $serviceTagValues
                
                Write-Verbose "Successfully updated service tags with $($serviceTagValues.Count) entries"
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
}
