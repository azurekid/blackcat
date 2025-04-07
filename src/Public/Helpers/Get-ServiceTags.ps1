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

function Get-ServiceTags {
    [cmdletbinding()]
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
                $SessionVariables.serviceTags | foreach {
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
        Retrieves the Azure service tag associated with a given IP address.

    .DESCRIPTION
        The Invoke-AzServiceTags function retrieves the Azure service tag that corresponds to a specified IP address. It checks if the IP address matches any of the service tag prefixes and returns the corresponding service tag name.

    .PARAMETER IpAddress
        Specifies the IP address for which to retrieve the Azure service tag.

    .EXAMPLE
        Invoke-AzServiceTags -IpAddress "192.168.1.10"
        Retrieves the Azure service tag associated with the IP address "192.168.1.10".

    .NOTES
        This function requires the 'Update-ServiceTags' function to be run before use in order to load the service tags.

    .LINK
        Update-ServiceTags
    #>
}