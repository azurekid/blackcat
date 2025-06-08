using namespace System.Management.Automation

# Dynamic validation classes for auto-generating valid values
class AzureServiceNames : IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        if ($script:SessionVariables.serviceTags) {
            return ($script:SessionVariables.serviceTags.properties.systemService | Sort-Object -Unique)
        }
        return @()
    }
}

class AzureRegionNames : IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        if ($script:SessionVariables.serviceTags) {
            return ($script:SessionVariables.serviceTags.properties.region | Sort-Object -Unique)
        }
        return @()
    }
}

function Find-AzureServiceTag {
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
        Write-Verbose "Starting Azure Service Tag lookup"
        
        # Validate that service tags are loaded
        if (-not $script:SessionVariables -or -not $script:SessionVariables.serviceTags -or $script:SessionVariables.serviceTags.Count -le 1) {
            $errorMsg = "Azure service tags not loaded. Please run 'Update-ServiceTag' function first."
            Write-Error $errorMsg -ErrorAction Stop
        }

        Write-Verbose "Service tags loaded: $($script:SessionVariables.serviceTags.Count) entries"
        $results = @()
    }

    process {
        try {
            # Handle IP address lookup
            if ($PSCmdlet.ParameterSetName -eq 'ByIP') {
                foreach ($currentIP in $IPAddress) {
                    Write-Verbose "Processing IP address: $currentIP"
                    
                    # Optimize search by filtering CIDR ranges
                    $firstTwoSegments = if ($currentIP -match '^([0-9A-Fa-f]{1,4}):([0-9A-Fa-f]{1,4}):') {
                        Write-Verbose 'Processing IPv6 address'
                        $currentIP.Split(':')[0..1] -join ':'
                    } else {
                        $currentIP.Split('.')[0..1] -join '.'
                    }

                    $found = $false
                    foreach ($serviceTag in $script:SessionVariables.serviceTags) {
                        Write-Verbose "Checking service tag: $($serviceTag.Name)"
                        
                        foreach ($prefix in $serviceTag.properties.addressPrefixes) {
                            # Performance optimization: skip if prefix doesn't match first segments
                            if ($prefix -notmatch "^$([regex]::Escape($firstTwoSegments))") {
                                continue
                            }

                            try {
                                if ($currentIP.Contains("*")) {
                                    # Handle wildcard IP addresses
                                    $addresses = @(Get-CidrAddresses -CidrRange $prefix)
                                    if ($addresses -match [regex]::Escape($currentIP.Replace('*', '.*'))) {
                                        $results += New-ServiceTagResult -ServiceTag $serviceTag -Prefix $prefix
                                        $found = $true
                                    }
                                } else {
                                    # Handle standard IP lookup
                                    $ip = [System.Net.IPAddress]::Parse($currentIP)
                                    $network = [System.Net.IPNetwork]::Parse($prefix)
                                    
                                    if ($network.Contains($ip)) {
                                        $results += New-ServiceTagResult -ServiceTag $serviceTag -Prefix $prefix
                                        $found = $true
                                    }
                                }
                            }
                            catch {
                                Write-Verbose "Error processing prefix $prefix : $($_.Exception.Message)"
                                continue
                            }
                        }
                    }
                    
                    if (-not $found) {
                        Write-Warning "No matching Azure service tag found for IP address: $currentIP"
                    }
                }
            }
            # Handle filtering by service name and/or region
            else {
                Write-Verbose "Filtering service tags by: Service='$ServiceName', Region='$Region'"
                
                $filteredTags = $script:SessionVariables.serviceTags | Where-Object {
                    $matchesService = if ($ServiceName) { 
                        $_.properties.systemService -like "*$ServiceName*" 
                    } else { 
                        $true 
                    }
                    
                    $matchesRegion = if ($Region) { 
                        $_.properties.region -like "*$Region*" 
                    } else { 
                        $true 
                    }
                    
                    return ($matchesService -and $matchesRegion)
                }
                
                foreach ($tag in $filteredTags) {
                    $results += New-ServiceTagResult -ServiceTag $tag
                }
                
                if ($filteredTags.Count -eq 0) {
                    Write-Warning "No service tags found matching the specified criteria."
                }
            }
        }
        catch {
            Write-Error "Error processing service tag lookup: $($_.Exception.Message)" -ErrorAction Continue
        }
    }

    end {
        # Output results based on requested format
        if ($results.Count -gt 0) {
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
        else {
            Write-Verbose "No results found."
        }
    }
}

# Helper function to create consistent service tag result objects
function New-ServiceTagResult {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ServiceTag,
        
        [Parameter(Mandatory = $false)]
        [string]$Prefix
    )
    
    return [PSCustomObject]@{
        PSTypeName      = 'AzureServiceTag'
        ServiceTagName  = $ServiceTag.Name
        SystemService   = $ServiceTag.properties.systemService
        Region          = ($ServiceTag.Name.Split('.'))[1]
        RegionId        = $ServiceTag.properties.regionId
        Platform        = $ServiceTag.properties.platform
        ChangeNumber    = $ServiceTag.properties.changeNumber
        AddressPrefix   = if ($Prefix) { $Prefix } else { $ServiceTag.properties.addressPrefixes -join ', ' }
        NetworkFeatures = $ServiceTag.properties.networkFeatures -join ', '
        RequiredFqdns   = if ($ServiceTag.properties.requiredFqdns) { $ServiceTag.properties.requiredFqdns -join ', ' } else { $null }
    }
}

<#
.SYNOPSIS
Finds Azure service tag information based on IP address, service name, or region.

.DESCRIPTION
The Find-AzureServiceTag function retrieves Azure service tag details from loaded service tag data.
It supports multiple search modes:
- IP address lookup: Checks if IP addresses fall within Azure service CIDR ranges
- Service filtering: Filters by Azure service name (Storage, Compute, etc.)
- Region filtering: Filters by Azure region (EastUS, WestEurope, etc.)

The function supports both IPv4 and IPv6 addresses and provides multiple output formats.
It also includes Linux-friendly parameter aliases for cross-platform compatibility.

.PARAMETER IPAddress
One or more IP addresses to lookup in Azure service tags. Supports IPv4, IPv6, and wildcard patterns.
Aliases: ip, address, host

.PARAMETER ServiceName  
Azure service name to filter by (e.g., Storage, Compute, SQL). Uses dynamic validation.
Aliases: service, svc, service-name

.PARAMETER Region
Azure region to filter by (e.g., EastUS, WestEurope). Uses dynamic validation.
Aliases: location, region-name, loc

.PARAMETER AsJson
Returns results in JSON format.
Aliases: json, raw

.PARAMETER Detailed
Returns results in detailed table format.
Aliases: table, list

.OUTPUTS
[PSCustomObject[]]
Returns custom objects with Azure service tag information including:
- ServiceTagName: Full service tag name
- SystemService: Azure service type
- Region: Azure region
- RegionId: Numeric region identifier
- Platform: Platform type (Azure, etc.)
- ChangeNumber: Service tag version
- AddressPrefix: CIDR ranges or specific prefix
- NetworkFeatures: Supported network features
- RequiredFqdns: Required fully qualified domain names

.NOTES
- Requires service tags to be loaded via 'Update-ServiceTag' function first
- Function name changed from Get-ServiceTag for better clarity
- Added Linux-friendly aliases for cross-platform use
- Supports pipeline input for processing multiple IP addresses
- Optimized performance with CIDR prefix filtering

.EXAMPLE
# Find service tag for a specific IP
Find-AzureServiceTag -IPAddress "52.239.152.0"

# Linux-style usage with aliases
azure-service-tag --ip "52.239.152.0" --json

# Filter by service name
Find-AzureServiceTag -ServiceName "Storage" -Region "EastUS"

# Multiple IP addresses via pipeline
@("52.239.152.0", "40.77.226.0") | Find-AzureServiceTag

# Get all service tags for a region in detailed format
Find-AzureServiceTag -Region "WestEurope" -Detailed

.LINK
https://docs.microsoft.com/en-us/azure/virtual-network/service-tags-overview

#>