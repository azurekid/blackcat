
using namespace System.Management.Automation

class ValidServiceNames : IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        $Values = (Invoke-RestMethod -uri 'https://download.microsoft.com/download/7/1/D/71D86715-5596-4529-9B13-DA13A5DE5B63/ServiceTags_Public_20240701.json').values | where name -notlike '*.*'
        return $Values.Name
    }
}

function Get-PublicIpAddress {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^(?:\d{1,3}\.){3}\d{1,3}(?:\/\d{1,2})?$|^([0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}(?:\/\d{1,3})?$', ErrorMessage = "IP CIDR does not match expected pattern '{1}'")]
        [string]$AddressPrefix = '*',

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet( [ValidServiceNames] )]
        [string]$ServiceName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Region = '*'
    )

    begin {
        # $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {

        try {

            Write-Verbose "Information Dialog"
            $uri = "https://download.microsoft.com/download/7/1/D/71D86715-5596-4529-9B13-DA13A5DE5B63/ServiceTags_Public_20240701.json"

            $requestParam = @{
                Uri     = $uri
                Method  = 'GET'
            }

            $apiResponse = (Invoke-RestMethod @requestParam).values

                $result = $apiResponse | Where-Object { `
                    $_.properties.addressPrefixes -like "*$AddressPrefix*" `
                    -and $_.properties.region -like "*$Region*" `
                    -and $_.name -like "*$ServiceName*"
                }

            return $result.properties

        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
    end {
        return $result
    }
<#
.SYNOPSIS
    Retrieves public IP addresses based on specified criteria.

.DESCRIPTION
    The Get-PublicIpAddress function retrieves public IP addresses based on the specified criteria such as address prefix, service name, and region.

.PARAMETER AddressPrefix
    Specifies the address prefix to filter the IP addresses.

.PARAMETER ServiceName
    Specifies the service name to filter the IP addresses.

.PARAMETER Region
    Specifies the region to filter the IP addresses.

.EXAMPLE
    Get-PublicIpAddress -AddressPrefix '192.168.0.0/24' -ServiceName 'WebApp' -Region 'West US'
    Retrieves public IP addresses with the address prefix '192.168.0.0/24', service name 'WebApp', and region 'West US'.

.EXAMPLE
    Get-PublicIpAddress -AddressPrefix '10.0.0.0/8'
    Retrieves all public IP addresses with the address prefix '10.0.0.0/8'.

.EXAMPLE
    Get-PublicIpAddress -ServiceName 'WebApp'
    Retrieves all public IP addresses with the service name 'WebApp'.

.EXAMPLE
    Get-PublicIpAddress -Region 'West US'

.INPUTS
    None. You cannot pipe input to this function.

.OUTPUTS
    System.Object
    Returns an object representing the retrieved public IP addresses.

.NOTES
    Author: Your Name
    Date:   Current Date
#>
}