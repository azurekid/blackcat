using namespace System.Management.Automation

# used for auto-generating the valid values for the ServiceName parameter
class AzureServiceNames : IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        try {
            # Check if serviceTags is loaded and contains items
            if ($null -eq $script:SessionVariables -or $null -eq $script:SessionVariables.serviceTags) {
                Write-Warning "Service tags not loaded. Run Update-ServiceTag first."
                return @('LoadServiceTagsFirst')
            }
            
            # Extract all unique system services from the service tags array
            return ($script:SessionVariables.serviceTags | 
                   Where-Object { $_.properties.systemService } |
                   ForEach-Object { $_.properties.systemService } | 
                   Sort-Object -Unique)
        }
        catch {
            Write-Warning "Error retrieving service names: $_"
            return @('ErrorLoadingServiceNames')
        }
    }
}

class AzureRegionNames : IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        try {
            # Check if serviceTags is loaded and contains items
            if ($null -eq $script:SessionVariables -or $null -eq $script:SessionVariables.serviceTags) {
                Write-Warning "Service tags not loaded. Run Update-ServiceTag first."
                return @('LoadServiceTagsFirst')
            }
            
            # Extract all unique regions from the service tags array
            return ($script:SessionVariables.serviceTags | 
                   Where-Object { $_.properties.region } |
                   ForEach-Object { $_.properties.region } | 
                   Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                   Sort-Object -Unique)
        }
        catch {
            Write-Warning "Error retrieving region names: $_"
            return @('ErrorLoadingRegionNames')
        }
    }
}

function Find-AzureServiceTag {
    <#
    .SYNOPSIS
        Searches Azure Service Tags to find IP ranges and service information.

    .DESCRIPTION
        This function searches through Azure Service Tags to identify which Azure services
        are associated with specific IP addresses or to filter service tags by service name
        and region. Useful for network security analysis and firewall configuration.

    .PARAMETER IPAddress
        The IP address to lookup in Azure service tags (IPv4 or IPv6).

    .PARAMETER ServiceName
        The Azure service name to filter by.

    .PARAMETER Region
        The Azure region to filter by.

    .PARAMETER AsJson
        Returns results in JSON format.

    .PARAMETER Detailed
        Returns detailed results with all properties.

    .EXAMPLE
        Find-AzureServiceTag -IPAddress "20.38.98.100"

        Searches for which Azure service tag contains the specified IP address.

    .EXAMPLE
        Find-AzureServiceTag -ServiceName "AzureStorage" -Region "westeurope"

        Returns all service tags for Azure Storage in West Europe.

    .NOTES
        Requires running Update-AzureServiceTag first to load the service tag data.

    .LINK
        MITRE ATT&CK Tactic: TA0043 - Reconnaissance
        https://attack.mitre.org/tactics/TA0043/

    .LINK
        MITRE ATT&CK Technique: T1590.005 - Gather Victim Network Information: IP Addresses
        https://attack.mitre.org/techniques/T1590/005/

    #>
    [CmdletBinding(DefaultParameterSetName = 'ByFilters')]
    [Alias('Get-ServiceTag', 'Find-ServiceTag', 'azure-service-tag', 'find-service-tag')]
    [OutputType([PSCustomObject[]])]
    param (
        [Parameter(
            Mandatory = $false, 
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'ByIP',
            HelpMessage = "IP address to lookup in Azure service tags (IPv4 or IPv6)"
        )]
        [Alias('ip', 'address', 'host')]
        [ValidateScript({
            if ($_ -match '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$|^(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$|^::1$|^\*\.') {
                return $true
            }
            throw "Invalid IP address format. Please provide a valid IPv4 or IPv6 address."
        })]
        [string[]]$IPAddress,

        [Parameter(
            Mandatory = $false, 
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'ByFilters',
            HelpMessage = "Azure service name to filter by"
        )]
        [ValidateSet([AzureServiceNames])]
        [Alias('service', 'svc', 'service-name')]
        [string]$ServiceName,

        [Parameter(
            Mandatory = $false, 
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'ByFilters',
            HelpMessage = "Azure region to filter by"
        )]
        [ValidateSet([AzureRegionNames])]
        [Alias('location', 'region-name', 'loc')]
        [string]$Region,

        [Parameter(Mandatory = $false)]
        [Alias('json', 'raw')]
        [switch]$AsJson,

        [Parameter(Mandatory = $false)]
        [Alias('table', 'list')]
        [switch]$Detailed
    )

    begin {
        # Check if service tags are loaded
        if ($null -eq $script:SessionVariables -or $null -eq $script:SessionVariables.serviceTags -or ($script:SessionVariables.serviceTags).count -le 1) {
            $errorMsg = "Service tags not loaded. Please run the 'Update-ServiceTag' function."
            Write-Error $errorMsg -ErrorAction Stop
        }
        
        $results = @()
        
        # Create filter for the CIDR to improve performance if IP address is provided
        if ($IPAddress) {
            foreach ($ip in $IPAddress) {
                if ($ip -match '^([0-9A-Fa-f]{1,4}):([0-9A-Fa-f]{1,4}):') {
                    Write-Verbose "Processing IPv6 address: $ip"
                    $firstTwoSegments = $ip.Split(':')[0..1] -join ':'
                }
                else {
                    Write-Verbose "Processing IPv4 address: $ip"
                    $firstTwoSegments = $ip.Split('.')[0..1] -join '.'
                }
            }
        }
    }

    process {
        try {
            if ($IpAddress) {
                $results = @()
                $SessionVariables.serviceTags | ForEach-Object {
                    # Check if the IP address matches any of the service tag prefixes within the CIDR range
                    Write-Verbose "Checking service tag: $($_.Name)"
                    foreach ($prefix in $_.properties.addressPrefixes) {
                        if ($IpAddress.Contains("*")) {
                            if ($prefix -match "^$firstTwoSegments") {
                                $addresses = @(Get-CidrAddresses -CidrRange $prefix)
                                if ($addresses -match "$($ipAddress)") {
                                    $result = [PSCustomObject]@{
                                        ServiceTagName   = $_.Name
                                        changeNumber     = $_.properties.changeNumber
                                        region           = ($_.Name.split('.'))[1]
                                        regionId         = $_.properties.regionId
                                        platform         = $_.properties.platform
                                        systemService    = $_.properties.systemService
                                        addressPrefixes  = $prefix
                                        networkFeatures  = $_.properties.networkFeatures
                                    }
                                    $results += $result
                                }
                            }
                        }
                        elseif ($prefix -match "^$firstTwoSegments") {
                            $ip = [System.Net.IPAddress]::Parse($IpAddress)
                            $network = [System.Net.IPNetwork]::Parse($prefix)

                            if ($network.Contains($ip)) {
                                $result = [PSCustomObject]@{
                                    ServiceTagName   = $_.Name
                                    changeNumber     = $_.properties.changeNumber
                                    region           = ($_.Name.split('.'))[1]
                                    regionId         = $_.properties.regionId
                                    platform         = $_.properties.platform
                                    systemService    = $_.properties.systemService
                                    addressPrefixes  = $prefix
                                    networkFeatures  = $_.properties.networkFeatures
                                }
                                $results += $result
                            }
                        }
                    }
                }

                if ($results.Count -eq 0) {
                    $results = "No matching service tag found for the given IP address."
                }
            }
            else {
                $filteredTags = $SessionVariables.serviceTags | Where-Object {
                    $_.properties.region -like "*$Region*" -and
                    $_.properties.systemService -like "*$ServiceName*"
                }

                # Create detailed results if needed
                $results = @()
                foreach ($tag in $filteredTags) {

                        foreach ($prefix in $tag.properties.addressPrefixes) {
                            if ($Detailed) {
                                $results += [PSCustomObject]@{
                                    ServiceTagName   = $tag.Name
                                    SystemService    = $tag.properties.systemService
                                    Region           = $tag.properties.region
                                    RegionId         = $tag.properties.regionId
                                    Platform         = $tag.properties.platform
                                    ChangeNumber     = $tag.properties.changeNumber
                                    AddressPrefix    = $prefix
                                    NetworkFeatures  = $tag.properties.networkFeatures -join ','
                                }
                            } else {
                                $results += [PSCustomObject]@{
                                    SystemService    = $tag.properties.systemService
                                    Region           = $tag.properties.region
                                    AddressPrefix    = $prefix
                                }
                            }
                        }
                    }
                }
            # Format the output based on switches
            if ($AsJson) {
                return ($results | ConvertTo-Json -Depth 4)
            }
            elseif ($Detailed) {
                return ($results | Format-Table -AutoSize)
            }
            else {
                return $results
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
}
