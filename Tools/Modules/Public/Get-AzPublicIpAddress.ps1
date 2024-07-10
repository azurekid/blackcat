
using namespace System.Management.Automation

# used for auto-generating the valid values for the ServiceName parameter
class ServiceNames : IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        return ($script:SessionVariables.serviceTags.properties.systemService | Sort-Object -Unique -Descending) #| Where-Object name -notlike '*.*').Name
    }
}

class RegionNames : IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        return ($script:SessionVariables.serviceTags.properties.region | Sort-Object -Unique -Descending)
    }
}

function Get-AzPublicIpAddress {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$AddressPrefix = '*',

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet( [ServiceNames] )]
        [string]$ServiceName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet( [RegionNames] )]
        [string]$Region
    )

    begin {
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
        if (-not $SessionVariables.serviceTags) {
            Update-ServiceTags
        }
    }

    process {

        try {
            $result = $SessionVariables.serviceTags | Where-Object { `
                    $_.properties.addressPrefixes -like "*$AddressPrefix*" `
                    -and $_.properties.region -like "*$Region*" `
                    -and $_.properties.systemService -like "*$ServiceName*"
            }
        }
        catch {
            # Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
            Write-Error $($MyInvocation.MyCommand.Name)
        }
    }
    end {
        return $result.properties
    }
<#
    .SYNOPSIS
        Retrieves public IP addresses based on specified criteria.

    .DESCRIPTION
        The Get-PublicIpAddress function retrieves public IP addresses based on the specified criteria, such as address prefix, service name, and region.

    .PARAMETER AddressPrefix
        Specifies the address prefix to filter the IP addresses. The default value is '*'.

    .PARAMETER ServiceName
        Specifies the service name to filter the IP addresses. The valid values are generated dynamically using the ServiceNames class.

    .PARAMETER Region
        Specifies the region to filter the IP addresses. The valid values are generated dynamically using the RegionNames class.

    .EXAMPLE
        Get-PublicIpAddress -ServiceName 'AzureAppService' -Region 'westus'
        Retrieves public IP addresses with the service name 'AzureAppService', and region 'West US'.
#>
}


# $LocationURI = ((Invoke-WebRequest -uri "https://www.microsoft.com/en-us/download/confirmation.aspx?id=56519").links | Where-Object {$_.href -like "*ServiceTags*"}).href
# $uri = ((Invoke-WebRequest -uri "https://www.microsoft.com/en-us/download/confirmation.aspx?id=56519").links | Where-Object outerHTML -like "*click here to download manually*").href
# $uri = 'https://download.microsoft.com/download/7/1/D/71D86715-5596-4529-9B13-DA13A5DE5B63/ServiceTags_Public_20240701.json'