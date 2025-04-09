using namespace System.Management.Automation

# used for auto-generating the valid values for the ServiceName parameter
class ServiceNames : IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        return ($script:SessionVariables.serviceTags.properties.systemService | Sort-Object -Unique -Descending)
    }
}

class RegionNames : IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        return ($script:SessionVariables.serviceTags.properties.region | Sort-Object -Unique -Descending)
    }
}

function Get-ServiceTag {
    [cmdletbinding()]
    [OutputType([PSCustomObject], [string])]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$IpAddress,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet( [ServiceNames] )]
        [string]$ServiceName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet( [RegionNames] )]
        [string]$Region
    )

    begin {
        # Check if service tags are loaded
        if (($script:SessionVariables.serviceTags).count -le 1) {
            Write-Output "Service tags not loaded. Please run the 'Update-ServiceTags' function."
            break
        }

        # Create filter for the CIDR to improve performance
        if ($ipAddress -match '^([0-9A-Fa-f]{1,4}):([0-9A-Fa-f]{1,4}):') {
            Write-Output 'Processing IPv6'
            $firstTwoSegments = $ipAddress.split(':')[0..1] -join ':'
        }
        else {
            $firstTwoSegments = $ipAddress.split('.')[0..1] -join '.'
        }
    }

    process {
        try {
            if ($IpAddress) {
                $SessionVariables.serviceTags | ForEach-Object {
                    # Check if the IP address matches any of the service tag prefixes within the CIDR range
                    Write-Verbose "Checking service tag: $($_.Name)"
                    foreach ($prefix in $_.properties.addressPrefixes) {
                        if ($IpAddress.Contains("*")) {
                            if ($prefix -match "^$firstTwoSegments") {
                                $addresses = @(Get-CidrAddresses -CidrRange $prefix)
                                if ($addresses -match "$($ipAddress)") {
                                    $result = [PSCustomObject]@{
                                        changeNumber    = $_.properties.changeNumber
                                        region          = ($_.Name.split('.'))[1]
                                        regionId        = $_.properties.regionId
                                        platform        = $_.properties.platform
                                        systemService   = $_.properties.systemService
                                        addressPrefixes = $prefix
                                        networkFeatures = $_.properties.networkFeatures
                                    }
                                    return $result
                                }
                                else {
                                    continue
                                }
                            }
                        }
                        elseif ($prefix -match "^$firstTwoSegments") {
                            $ip = [System.Net.IPAddress]::Parse($IpAddress)
                            $network = [System.Net.IPNetwork]::Parse($prefix)

                            if ($network.Contains($ip)) {
                                $result = [PSCustomObject]@{
                                    changeNumber    = $_.properties.changeNumber
                                    region          = ($_.Name.split('.'))[1]
                                    regionId        = $_.properties.regionId
                                    platform        = $_.properties.platform
                                    systemService   = $_.properties.systemService
                                    addressPrefixes = $prefix
                                    networkFeatures = $_.properties.networkFeatures
                                }
                                return $result
                            }
                            else {
                                continue
                            }
                        }
                        else {
                            continue
                        }
                    }
                }
                if (-not($result)) {
                    return "No matching service tag found for the given IP address."
                }
            }
            else {
                $result = $SessionVariables.serviceTags | Where-Object { `
                        $_.properties.region -like "*$Region*" `
                        -and $_.properties.systemService -like "*$ServiceName*"
                }
                return $result.properties
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
<#
.SYNOPSIS
Retrieves service tag information based on IP address, service name, or region.

.DESCRIPTION
The Get-ServiceTag function retrieves service tag details from a predefined set of service tags.
It can filter results based on an IP address, service name, or region. The function supports both
IPv4 and IPv6 addresses and checks if the provided IP address falls within the CIDR ranges of the
service tags. If no IP address is provided, it filters service tags based on the specified service
name and region.

.PARAMETER IpAddress
The IP address to check against the service tag CIDR ranges. Supports both IPv4 and IPv6 formats.

.PARAMETER ServiceName
The name of the service to filter the service tags. Must be one of the predefined service names.

.PARAMETER Region
The region to filter the service tags. Must be one of the predefined region names.

.OUTPUTS
[PSCustomObject]
Returns a custom object containing details about the matching service tag, including:
- changeNumber
- region
- regionId
- platform
- systemService
- addressPrefixes
- networkFeatures

[string]
Returns a string message if no matching service tag is found for the given IP address.

.NOTES
- Ensure that the 'Update-ServiceTags' function is run to load the service tags into the session
    before using this function.
- The function uses session variables to access the service tags.

.EXAMPLE
# Example 1: Retrieve service tag information for a specific IP address
Get-ServiceTag -IpAddress "192.168.1.1"

# Example 2: Retrieve service tag information for a specific service name and region
Get-ServiceTag -ServiceName "Storage" -Region "EastUS"

# Example 3: Retrieve service tag information for an IPv6 address
Get-ServiceTag -IpAddress "2001:0db8:85a3:0000:0000:8a2e:0370:7334"

# Example 4: Retrieve all service tags for a specific region
Get-ServiceTag -Region "WestEurope"

#>
}