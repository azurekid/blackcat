using namespace System.Management.Automation

# Used for auto-generating the valid values for the Category parameter
class SubdomainCategories : IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        # Get all category keys and add 'all' as an option
        $categories = @('all')
        $categories += $script:SessionVariables.subdomains.default.Keys
        return $categories
    }
}

function Find-SubDomain {
    [CmdletBinding()]
    [OutputType([System.Collections.ArrayList])]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, ValueFromPipeline = $true)]
        [Alias('domain-name', 'domain')]
        [ValidatePattern('^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$',
            ErrorMessage = 'Domain name must be in valid format (e.g., example.com)')]
        [string[]]$DomainName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias('cat', 'c')]
        [ValidateSet([SubdomainCategories])]
        [string]$Category = 'all',

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias('word-list', 'w')]
        [string]$WordList,

        [Parameter(Mandatory = $false)]
        [Alias('throttle-limit', 'threads', 't')]
        [int]$ThrottleLimit = 100,

        [Parameter(Mandatory = $false)]
        [Alias('deep', 'd')]
        [switch]$DeepSearch,

        [Parameter(Mandatory = $false)]
        [Alias('json', 'raw')]
        [switch]$AsJson,

        [Parameter(Mandatory = $false)]
        [Alias('table', 'list')]
        [switch]$Detailed
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"

        $results = [System.Collections.ArrayList]::new()
        $type = if ($DeepSearch) { 'deep' } else { 'default' }
        if ($type -eq 'deep') {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) "Deep search enabled" -Severity Information
        }
    }

    process {
        try {
            # Get subdomain list
            $subdomains = [System.Collections.Generic.HashSet[string]]::new()
            if ($WordList) {
                (Get-Content -Path $WordList) | ForEach-Object { [void]$subdomains.Add($_) }
                Write-Information "$($MyInvocation.MyCommand.Name): Loaded $($subdomains.Count) subdomains from '$WordList'" -InformationAction Continue
            }

            if ($Category -eq 'all') {
                foreach ($cat in $SessionVariables.subdomains[$type].Keys) {
                    # Skip the 'common' category when 'all' is selected for improved performance
                    if ($cat -ne 'common') {
                        foreach ($sd in $SessionVariables.subdomains[$type].$cat) {
                            [void]$subdomains.Add($sd)
                        }
                    }
                }
            }
            else {
                foreach ($sd in $SessionVariables.subdomains[$type].$Category) {
                    [void]$subdomains.Add($sd)
                }
            }

            Write-Verbose "$($MyInvocation.MyCommand.Name): Loaded $($subdomains.Count) subdomains from session"

            # Process each domain in the array
            foreach ($domain in $DomainName) {
                Write-Verbose "$($MyInvocation.MyCommand.Name): Processing domain: $domain"

                $dnsNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                foreach ($sd in $subdomains) {
                    [void]$dnsNames.Add("$sd.$domain")
                }

                $totalDns = $dnsNames.Count
                Write-Verbose "$($MyInvocation.MyCommand.Name): Starting DNS resolution for $totalDns names for domain $domain..."

                $dnsNames | ForEach-Object -Parallel {
                    $results = $using:results
                    $type = $using:type
                    $domain = $using:domain
                    $subdomains = $using:SessionVariables.subdomains
                    try {
                        Write-Verbose "$($MyInvocation.MyCommand.Name): Resolving DNS for '$_'"
                        $dnsInfo = [System.Net.Dns]::GetHostEntry($_)
                        $ipAddress = $dnsInfo.AddressList.IpAddressToString
                        $subdomain = $_.Split('.')[0]
                        $uri = "https://$_"
                        $hostName = $dnsInfo.HostName

                        $foundCategory = $null
                        foreach ($catLookup in $subdomains[$type].Keys) {
                            # Skip the 'common' category when 'all' is selected
                            if ($using:Category -eq 'all' -and $catLookup -eq 'common') {
                                continue
                            }

                            if ($subdomains[$type].$catLookup -contains $subdomain) {
                                $foundCategory = $catLookup
                                Write-Verbose "Found category '$catLookup' for subdomain '$_'"
                                break
                            }
                        }

                        $resultObject = [PSCustomObject]@{
                            Domain    = $domain
                            Category  = $foundCategory
                            Url       = $uri
                            HostName  = $hostName
                            IpAddress = $ipAddress
                        }

                        [void]$results.Add($resultObject)
                    }
                    catch [System.Net.Sockets.SocketException] {
                        Write-Verbose "$($MyInvocation.MyCommand.Name): DNS resolution failed for '$_' - $($_.Exception.Message)"
                    }
                } -ThrottleLimit $ThrottleLimit
            }
        }
        catch {
            Write-Error $_.Exception.Message -ErrorAction Continue
        }
    }

    end {
         Write-Verbose "Function $($MyInvocation.MyCommand.Name) completed"
        if ($results.Count -gt 0) {
            if ($AsJson) {
                return ($results | ConvertTo-Json -Depth 4)
            }
            elseif ($Detailed) {
                return ($results | Format-Table -AutoSize)
            }
            else {
                return $results | Select-Object Domain, Category, Url
            }
        }
        else {
            Write-Information "No public resources found" -InformationAction Continue
        }
    }
    <#
.SYNOPSIS
    Discovers active subdomains for specified domain names through DNS resolution.

.DESCRIPTION
    Enumerates subdomains via DNS resolution using common prefixes or custom wordlists. Supports multiple subdomain categories and parallel processing for efficient discovery. Essential for external reconnaissance and attack surface identification.

.PARAMETER DomainName
    One or more domain names to enumerate subdomains for (e.g., example.com).
    Must be in valid domain format (e.g., example.com).

.PARAMETER Category
    The category of subdomains to check. Available options include 'all' and any categories
    defined in the session variables. Default is 'common'.

.PARAMETER WordList
    Path to a custom file containing subdomain prefixes to check, one per line.
    When specified, these prefixes will be used in addition to any from the selected category.

.PARAMETER ThrottleLimit
    Maximum number of concurrent DNS resolutions to perform. Default is 100.
    Adjust based on available system resources.

.PARAMETER DeepSearch
    When specified, uses an expanded list of subdomains for more thorough enumeration.
    This significantly increases the number of DNS lookups performed.

.PARAMETER AsJson
Returns results in JSON format.
Aliases: json, raw

.PARAMETER Detailed
Returns results in detailed table format.
Aliases: table, list

.EXAMPLE
    Find-SubDomain -DomainName example.com

    Checks for common subdomains of example.com.

.EXAMPLE
    Find-SubDomain -DomainName example.com -Category dev

    Checks for development-related subdomains of example.com.

.EXAMPLE
    Find-SubDomain -DomainName example.com,sample.org -DeepSearch

    Performs a deep search for subdomains on both example.com and sample.org.

.EXAMPLE
    Find-SubDomain -DomainName example.com -WordList .\my-subdomains.txt -ThrottleLimit 50

    Checks subdomains from a custom list against example.com with 50 concurrent threads.

.OUTPUTS
    System.Collections.ArrayList
    Returns a collection of PSCustomObjects containing Domain, Category, Url, HostName, and IpAddress properties.

.NOTES
    This function performs unauthenticated DNS enumeration and does not require Azure credentials.

.LINK
    MITRE ATT&CK Tactic: TA0043 - Reconnaissance
    https://attack.mitre.org/tactics/TA0043/

.LINK
    MITRE ATT&CK Technique: T1596.001 - Search Open Technical Databases: DNS/Passive DNS
    https://attack.mitre.org/techniques/T1596/001/

#>
}