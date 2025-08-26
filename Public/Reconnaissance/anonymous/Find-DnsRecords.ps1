using namespace System.Management.Automation

class SubdomainCategories : IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        $categories = @('all')
        if ($script:SessionVariables -and $script:SessionVariables.subdomains -and $script:SessionVariables.subdomains.default) {
            $categories += $script:SessionVariables.subdomains.default.Keys
        }
        return $categories
    }
}

function Find-DnsRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias("d", "domain")]
        [string[]]$Domains,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 300)]
        [Alias("delay-min", "min-delay")]
        [int]$MinDelay = 1,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 600)]
        [Alias("delay-max", "max-delay")]
        [int]$MaxDelay = 3,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [Alias("log-path", "l", "log")]
        [string]$LogPath = ".\recon_results.log",

        [Parameter(Mandatory = $false)]
        [ValidateSet("A", "AAAA", "CNAME", "MX", "NS", "TXT", "SOA", "PTR")]
        [Alias("record-types", "types", "r")]
        [string[]]$RecordTypes = @("A", "AAAA", "CNAME", "MX", "TXT"),

        [Parameter(Mandatory = $false)]
        [Alias("fast", "f")]
        [switch]$FastMode,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Minimal", "Standard", "Detailed")]
        [Alias("info-level", "level")]
        [string]$DNSInfoLevel = "Standard",

        [Parameter(Mandatory = $false)]
        [ValidateSet("Object", "JSON", "CSV", "Table")]
        [Alias("output", "o")]
        [string]$OutputFormat = "Table",
        
        [Parameter(Mandatory = $false)]
        [Alias("no-cache", "bypass-cache")]
        [switch]$SkipCache,

        [Parameter(Mandatory = $false)]
        [Alias("cache-expiration", "expiration")]
        [int]$CacheExpirationMinutes = 30,

        [Parameter(Mandatory = $false)]
        [Alias("max-cache")]
        [int]$MaxCacheSize = 100,

        [Parameter(Mandatory = $false)]
        [Alias("compress")]
        [switch]$CompressCache,

        [Parameter(Mandatory = $false)]
        [Alias("enum-subdomains", "subdomains", "s")]
        [switch]$EnumerateSubdomains,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 200)]
        [Alias("subdomain-throttle", "throttle-limit", "t")]
        [int]$SubdomainThrottleLimit = 50,

        [Parameter(Mandatory = $false)]
        [ValidateSet([SubdomainCategories])]
        [Alias("subdomain-cat", "cat", "c")]
        [string]$SubdomainCategory = "common",

        [Parameter(Mandatory = $false)]
        [Alias("deep-search", "deep", "ds")]
        [switch]$DeepSubdomainSearch
    )

    begin {
        Write-Verbose "Starting DNS reconnaissance with enhanced provider support"

        if ($MinDelay -gt $MaxDelay) {
            throw "MinDelay cannot be greater than MaxDelay"
        }
        
        if ($EnumerateSubdomains -and $SubdomainThrottleLimit -gt 200) {
            Write-Warning "High subdomain throttle limit may cause rate limiting. Consider reducing to 100 or less."
        }
        
        if ($DeepSubdomainSearch -and -not $EnumerateSubdomains) {
            Write-Warning "DeepSubdomainSearch requires EnumerateSubdomains to be enabled. Enabling subdomain enumeration."
            $EnumerateSubdomains = $true
        }

        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'DnsRecon'

        $DNSProviders = @{
            "Cloudflare" = @{ URL = "https://cloudflare-dns.com/dns-query"; Region = "Global"; Type = "Commercial"; Reliability = 99.9 }
            "Google" = @{ URL = "https://dns.google/resolve"; Region = "Global"; Type = "Commercial"; Reliability = 99.8 }
            "NextDNS" = @{ URL = "https://dns.nextdns.io"; Region = "Global"; Type = "Privacy"; Reliability = 99.5 }
            "DNS.SB" = @{ URL = "https://doh.dns.sb/dns-query"; Region = "Global"; Type = "Privacy"; Reliability = 99.3 }
            "DNSPod" = @{ URL = "https://dns.pub/dns-query"; Region = "China/Global"; Type = "Commercial"; Reliability = 99.0 }
        }

        # User agents - integrate with BlackCat module if available (replaces UseRandomUserAgent parameter)
        if ($BlackCatAvailable -and $script:SessionVariables -and $script:SessionVariables.userAgents) {
            Write-Verbose "Using BlackCat module user agents from session variables"
            $UserAgents = $script:SessionVariables.userAgents.agents | ForEach-Object { $_.value }
        } else {
            Write-Verbose "Using built-in user agents (anonymous mode)"
            $UserAgents = @(
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.5938.132 Safari/537.36",
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_5_2) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.5938.132 Safari/537.36",
                "Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/119.0"
            )
        }



        # Initialize results and configuration
        $Results = [System.Collections.ArrayList]::new()
        $Stats = @{ TotalQueries = 0; SuccessfulQueries = 0; FailedQueries = 0; StartTime = Get-Date }
        $Config = @{
            MinDelay = if ($FastMode) { 0.5 } else { $MinDelay }
            MaxDelay = if ($FastMode) { 1 } else { $MaxDelay }
            Timeout = if ($FastMode) { 2 } else { 10 }
        }
    }

    process {
        foreach ($Domain in $Domains) {
            # Generate a cache key for the current domain and parameters
            $cacheParams = @{
                Domain = $Domain
                RecordTypes = ($RecordTypes -join ",")
                EnumerateSubdomains = $EnumerateSubdomains.IsPresent
                DeepSubdomainSearch = $DeepSubdomainSearch.IsPresent
                SubdomainCategory = $SubdomainCategory
            }
            $cacheKey = ConvertTo-CacheKey -BaseIdentifier "Find-DnsRecords" -Parameters $cacheParams

            # Try to get cached results if not skipping cache
            if (-not $SkipCache) {
                try {
                    $cachedResult = Get-BlackCatCache -Key $cacheKey -CacheType 'General'
                    if ($null -ne $cachedResult) {
                        Write-Verbose "Retrieved DNS results from cache for domain: $Domain"
                        
                        # Merge cached results into Results collection
                        foreach ($entry in $cachedResult) {
                            [void]$Results.Add($entry)
                        }
                        
                        # Skip processing this domain since we have cached results
                        continue
                    }
                }
                catch {
                    Write-Verbose "Error retrieving from cache: $($_.Exception.Message). Proceeding with fresh DNS queries."
                }
            }
        
            Write-Host "🎯 Analyzing domain: $Domain" -ForegroundColor Green
            
            # Rotate through providers for load balancing
            $ProviderNames = $DNSProviders.Keys | Sort-Object { Get-Random }
            
            # Build list of domains to query (root domain + subdomains if enabled)
            $DomainsToQuery = @($Domain)
            
            # Add subdomain enumeration for CNAME discovery
            if ($EnumerateSubdomains -and $RecordTypes -contains "CNAME") {
                Write-Host "  🔍 Enumerating subdomains for CNAME discovery..." -ForegroundColor Cyan
                
                # Determine subdomain type based on DeepSubdomainSearch parameter
                $SubdomainType = if ($DeepSubdomainSearch) { 'deep' } else { 'default' }
                
                # Get subdomain list from session variables (same logic as Find-SubDomain)
                $SubdomainList = if ($script:SessionVariables -and $script:SessionVariables.subdomains) {
                    Write-Verbose "Using session variable subdomain list (type: $SubdomainType, category: $SubdomainCategory)"
                    
                    $subdomains = [System.Collections.Generic.HashSet[string]]::new()
                    
                    if ($SubdomainCategory -eq 'all') {
                        foreach ($cat in $script:SessionVariables.subdomains[$SubdomainType].Keys) {
                            # Skip the 'common' category when 'all' is selected for improved performance
                            if ($cat -ne 'common') {
                                foreach ($sd in $script:SessionVariables.subdomains[$SubdomainType].$cat) {
                                    [void]$subdomains.Add($sd)
                                }
                            }
                        }
                    } else {
                        if ($script:SessionVariables.subdomains[$SubdomainType].ContainsKey($SubdomainCategory)) {
                            foreach ($sd in $script:SessionVariables.subdomains[$SubdomainType].$SubdomainCategory) {
                                [void]$subdomains.Add($sd)
                            }
                        } else {
                            Write-Warning "Category '$SubdomainCategory' not found in session variables. Available categories: $($script:SessionVariables.subdomains[$SubdomainType].Keys -join ', ')"
                            $subdomains = $null
                        }
                    }
                    
                    if ($subdomains) { [array]$subdomains } else { $null }
                } else {
                    Write-Warning "Session variables not available. Cannot enumerate subdomains without BlackCat framework."
                    $null
                }
                
                if (-not $SubdomainList) {
                    Write-Host "    ⚠️ Subdomain enumeration skipped - no subdomain data available" -ForegroundColor Yellow
                    continue
                }
                
                # Generate subdomain candidates
                $SubdomainCandidates = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                foreach ($subdomain in $SubdomainList) {
                    [void]$SubdomainCandidates.Add("$subdomain.$Domain")
                }
                
                $SearchTypeMsg = if ($DeepSubdomainSearch) { "deep search" } else { "standard search" }
                Write-Host "    🎯 Testing $($SubdomainCandidates.Count) subdomain candidates ($SearchTypeMsg, category: $SubdomainCategory)..." -ForegroundColor Yellow
                
                # Test subdomains in parallel for existence first (faster DNS resolution check)
                $ValidSubdomains = $SubdomainCandidates | ForEach-Object -Parallel {
                    try {
                        $null = [System.Net.Dns]::GetHostEntry($_)
                        return $_
                    }
                    catch {
                        # Subdomain doesn't resolve, skip it
                        return $null
                    }
                } -ThrottleLimit $SubdomainThrottleLimit | Where-Object { $_ -ne $null }
                
                $DomainsToQuery += $ValidSubdomains
                Write-Host "    ✅ Found $($ValidSubdomains.Count) valid subdomains" -ForegroundColor Green
            }
            
            foreach ($RecordType in $RecordTypes) {
                Write-Host "  🔍 Querying $RecordType records..." -ForegroundColor Yellow
                
                # Query each domain (root + valid subdomains)
                foreach ($QueryDomain in $DomainsToQuery) {
                    # Skip subdomain enumeration for non-CNAME record types on subdomains
                    if ($QueryDomain -ne $Domain -and $RecordType -ne "CNAME") {
                        continue
                    }
                    
                    if ($DNSInfoLevel -eq "Detailed" -and $QueryDomain -ne $Domain) {
                        Write-Host "    🔍 Querying $RecordType for subdomain: $QueryDomain" -ForegroundColor Gray
                    }
                    
                    foreach ($ProviderName in $ProviderNames) {
                        $Provider = $DNSProviders[$ProviderName]
                        
                        if ($DNSInfoLevel -eq "Detailed") {
                            Write-Host "    📡 Using $ProviderName ($($Provider.Reliability)%)" -ForegroundColor Cyan
                        }
                        
                        try {
                            $Stats.TotalQueries++
                            
                            # JSON DNS query
                            $QueryUrl = "$($Provider.URL)?name=$QueryDomain&type=$RecordType"
                            $Headers = @{ 
                                "Accept" = "application/dns-json"
                                "User-Agent" = ($UserAgents | Get-Random)
                            }
                            
                            $Response = Invoke-RestMethod -Uri $QueryUrl -Headers $Headers -TimeoutSec $Config.Timeout -ErrorAction Stop
                            
                            # Debug output for CNAME queries
                            if ($DNSInfoLevel -eq "Detailed" -and $RecordType -eq "CNAME") {
                                Write-Host "      🔍 Query URL: $QueryUrl" -ForegroundColor Gray
                                Write-Host "      🔍 Response has $($Response.Answer.Count) answers" -ForegroundColor Gray
                            }
                            
                            # ... existing code for processing Response.Answer ...
                            
                            # For CNAME queries, also try with DO (DNSSEC OK) bit to get unfiltered responses
                            if ($RecordType -eq "CNAME" -and -not $Response.Answer) {
                                try {
                                    $DnssecQueryUrl = "$($Provider.URL)?name=$QueryDomain&type=$RecordType&do=true"
                                    $DnssecResponse = Invoke-RestMethod -Uri $DnssecQueryUrl -Headers $Headers -TimeoutSec $Config.Timeout -ErrorAction Stop
                                    
                                    if ($DnssecResponse.Answer) {
                                        $Response = $DnssecResponse
                                        if ($DNSInfoLevel -eq "Detailed") {
                                            Write-Host "      🔍 DNSSEC query returned $($Response.Answer.Count) answers" -ForegroundColor Gray
                                        }
                                    }
                                } catch {
                                    # DNSSEC query failed, continue with original response
                                    if ($DNSInfoLevel -eq "Detailed") {
                                        Write-Host "      🔍 DNSSEC query failed: $($_.Exception.Message)" -ForegroundColor Gray
                                    }
                                }
                                
                                # If still no CNAME found, try querying for A records to detect proxied CNAMEs
                                if (-not $Response.Answer) {
                                    try {
                                        $AQueryUrl = "$($Provider.URL)?name=$QueryDomain&type=A"
                                        $AResponse = Invoke-RestMethod -Uri $AQueryUrl -Headers $Headers -TimeoutSec $Config.Timeout -ErrorAction Stop
                                        
                                        if ($AResponse.Answer) {
                                            # Check if the A records point to CDN IPs (indicating CNAME flattening/proxying)
                                            $CDNRecords = $AResponse.Answer | Where-Object { 
                                                $_.type -eq 1 -and (
                                                    # Cloudflare IP ranges (more comprehensive)
                                                    ($_.data -match '^(104\.1[6-9]|104\.2[0-7]|104\.21|104\.22|104\.23|104\.24|104\.25|104\.26|104\.27|104\.28|104\.29|104\.30|104\.31|108\.162|141\.101|162\.15[8-9]|172\.6[4-7]|172\.64|172\.65|172\.66|172\.67|172\.68|172\.69|172\.70|172\.71|173\.245|188\.114|190\.93|197\.234|198\.41|131\.0|203\.28)\.') -or
                                                    # AWS CloudFront
                                                    ($_.data -match '^(13\.32|13\.35|52\.8[4-5]|54\.23[0-9]|99\.8[4-6]|143\.204|205\.251)\.') -or
                                                    # Fastly
                                                    ($_.data -match '^(23\.235|151\.101)\.') -or
                                                    # KeyCDN  
                                                    ($_.data -match '^(95\.85|104\.16)\.') -or
                                                    # MaxCDN/StackPath
                                                    ($_.data -match '^(66\.254|68\.232)\.')
                                                )
                                            }
                                            
                                            if ($CDNRecords) {
                                                $Response = $AResponse
                                                if ($DNSInfoLevel -eq "Detailed") {
                                                    Write-Host "      🔍 A record query returned $($CDNRecords.Count) CDN records (likely flattened CNAME)" -ForegroundColor Gray
                                                }
                                            }
                                        }
                                    } catch {
                                        if ($DNSInfoLevel -eq "Detailed") {
                                            Write-Host "      🔍 A record fallback query failed: $($_.Exception.Message)" -ForegroundColor Gray
                                        }
                                    }
                                }
                            }
                            
                            if ($Response.Answer) {
                                $FoundRecord = $false
                                
                                foreach ($Answer in $Response.Answer) {
                                    # More flexible record type matching - check both by type number and handle edge cases
                                    $ExpectedType = (@{"A"=1;"AAAA"=28;"CNAME"=5;"MX"=15;"NS"=2;"TXT"=16;"SOA"=6;"PTR"=12}[$RecordType])
                                    
                                    # Debug output for CNAME queries when in detailed mode
                                    if ($DNSInfoLevel -eq "Detailed" -and $RecordType -eq "CNAME") {
                                        Write-Host "      🔍 Answer type: $($Answer.type), Expected: $ExpectedType, Data: $($Answer.data)" -ForegroundColor Gray
                                    }
                                    
                                    # For CNAME queries, check if this is actually a CNAME record
                                    if ($RecordType -eq "CNAME" -and $Answer.type -eq 5) {
                                        $null = $Results.Add([PSCustomObject]@{
                                            Domain = $QueryDomain
                                            RecordType = $RecordType
                                            Data = $Answer.data
                                            TTL = $Answer.TTL
                                            DNSProvider = $ProviderName
                                            ProviderType = $Provider.Type
                                            ProviderRegion = $Provider.Region
                                            Reliability = $Provider.Reliability
                                            Timestamp = Get-Date
                                            QueryMethod = "DoH-JSON"
                                            IsSubdomain = ($QueryDomain -ne $Domain)
                                        })
                                        
                                        $Stats.SuccessfulQueries++
                                        $DisplayDomain = if ($QueryDomain -ne $Domain) { $QueryDomain } else { $QueryDomain }
                                        Write-Host "      ✅ $DisplayDomain -> $($Answer.data) (TTL: $($Answer.TTL))" -ForegroundColor Green
                                        $FoundRecord = $true
                                    }
                                    # For non-CNAME queries or exact type matches
                                    elseif ($Answer.type -eq $ExpectedType) {
                                        $null = $Results.Add([PSCustomObject]@{
                                            Domain = $QueryDomain
                                            RecordType = $RecordType
                                            Data = $Answer.data
                                            TTL = $Answer.TTL
                                            DNSProvider = $ProviderName
                                            ProviderType = $Provider.Type
                                            ProviderRegion = $Provider.Region
                                            Reliability = $Provider.Reliability
                                            Timestamp = Get-Date
                                            QueryMethod = "DoH-JSON"
                                            IsSubdomain = ($QueryDomain -ne $Domain)
                                        })
                                        
                                        $Stats.SuccessfulQueries++
                                        $DisplayDomain = if ($QueryDomain -ne $Domain) { $QueryDomain } else { $QueryDomain }
                                        Write-Host "      ✅ $DisplayDomain -> $($Answer.data) (TTL: $($Answer.TTL))" -ForegroundColor Green
                                        $FoundRecord = $true
                                    }
                                }
                                
                                # Special handling for CNAME queries that might be resolved to final A/AAAA records
                                if ($RecordType -eq "CNAME" -and -not $FoundRecord) {
                                    # Check if we got A or AAAA records when querying for CNAME (indicates proxied/resolved CNAME)
                                    $ProxiedRecords = $Response.Answer | Where-Object { $_.type -eq 1 -or $_.type -eq 28 }
                                    if ($ProxiedRecords) {
                                        foreach ($ProxiedRecord in $ProxiedRecords) {
                                            # Try to detect if this is likely a proxied CNAME by checking common CDN patterns
                                            $IsLikelyProxied = $false
                                            $ProxyService = "Unknown"
                                            
                                            # Comprehensive Cloudflare IP ranges
                                            if ($ProxiedRecord.data -match '^(104\.1[6-9]|104\.2[0-7]|104\.21|104\.22|104\.23|104\.24|104\.25|104\.26|104\.27|104\.28|104\.29|104\.30|104\.31|108\.162|141\.101|162\.15[8-9]|172\.6[4-7]|172\.64|172\.65|172\.66|172\.67|172\.68|172\.69|172\.70|172\.71|173\.245|188\.114|190\.93|197\.234|198\.41|131\.0|203\.28)\.') {
                                                $IsLikelyProxied = $true
                                                $ProxyService = "Cloudflare"
                                            }
                                            # AWS CloudFront patterns
                                            elseif ($ProxiedRecord.data -match '^(13\.32|13\.35|52\.8[4-5]|54\.23[0-9]|99\.8[4-6]|143\.204|205\.251)\.') {
                                                $IsLikelyProxied = $true
                                                $ProxyService = "AWS CloudFront"
                                            }
                                            # Fastly CDN
                                            elseif ($ProxiedRecord.data -match '^(23\.235|151\.101)\.') {
                                                $IsLikelyProxied = $true
                                                $ProxyService = "Fastly"
                                            }
                                            # Common other CDN patterns can be added here
                                            
                                            if ($IsLikelyProxied) {
                                                $null = $Results.Add([PSCustomObject]@{
                                                    Domain = $QueryDomain
                                                    RecordType = "CNAME (Flattened)"
                                                    Data = "$($ProxiedRecord.data) [$ProxyService Flattened/Proxied]"
                                                    TTL = $ProxiedRecord.TTL
                                                    DNSProvider = $ProviderName
                                                    ProviderType = $Provider.Type
                                                    ProviderRegion = $Provider.Region
                                                    Reliability = $Provider.Reliability
                                                    Timestamp = Get-Date
                                                    QueryMethod = "DoH-JSON"
                                                    IsSubdomain = ($QueryDomain -ne $Domain)
                                                })
                                                
                                                $Stats.SuccessfulQueries++
                                                $DisplayDomain = if ($QueryDomain -ne $Domain) { $QueryDomain } else { $QueryDomain }
                                                Write-Host "      🔶 $DisplayDomain -> $($ProxiedRecord.data) [$ProxyService Flattened CNAME] (TTL: $($ProxiedRecord.TTL))" -ForegroundColor DarkYellow
                                                $FoundRecord = $true
                                            }
                                        }
                                    }
                                }
                            } else {
                                # Handle case where no records are found
                                if ($DNSInfoLevel -ne "Minimal" -and $QueryDomain -eq $Domain) {
                                        Write-Host "      ℹ️ No $RecordType records found" -ForegroundColor Gray
                                }
                            }
                            
                            # Add delay between requests
                            if ($Config.MaxDelay -gt 0) {
                                $Delay = Get-Random -Minimum $Config.MinDelay -Maximum $Config.MaxDelay
                                Start-Sleep -Seconds $Delay
                            }
                            
                            # Break after successful response (whether records found or authoritative no-records)
                            # Only continue to next provider on actual HTTP/network failures
                            break  # Success - got authoritative response from DNS provider
                        }
                        catch {
                            $Stats.FailedQueries++
                            
                            if ($DNSInfoLevel -eq "Detailed") {
                                Write-Host "      ❌ Query failed: $($_.Exception.Message)" -ForegroundColor Red
                            }
                        }
                    }
                }
            }
            
            # Store domain-specific results in cache
            if (-not $SkipCache) {
                try {
                    # Get only results for this domain
                    $domainResults = $Results | Where-Object { $_.Domain -eq $Domain -or ($_.Domain -like "*.$Domain" -and $_.IsSubdomain -eq $true) }
                    
                    # Cache results if we have any
                    if ($domainResults -and $domainResults.Count -gt 0) {
                        Set-BlackCatCache -Key $cacheKey -Data $domainResults -ExpirationMinutes $CacheExpirationMinutes `
                            -CacheType 'General' -MaxCacheSize $MaxCacheSize -CompressData:$CompressCache
                        Write-Verbose "Cached DNS results for domain: $Domain (expires in $CacheExpirationMinutes minutes)"
                    }
                }
                catch {
                    Write-Verbose "Failed to cache results for domain $Domain`: $($_.Exception.Message)"
                }
            }
        }
    }

    end {
        $Duration = (Get-Date) - $Stats.StartTime
        
        Write-Host "`n📊 Reconnaissance Summary:" -ForegroundColor Magenta
        Write-Host "   Total Queries: $($Stats.TotalQueries)" -ForegroundColor White
        Write-Host "   Successful: $($Stats.SuccessfulQueries)" -ForegroundColor Green
        Write-Host "   Failed: $($Stats.FailedQueries)" -ForegroundColor Red
        Write-Host "   Duration: $($Duration.TotalSeconds.ToString('F2')) seconds" -ForegroundColor White
        Write-Host "   Records Found: $($Results.Count)" -ForegroundColor Yellow
        if ($EnumerateSubdomains) {
            $SubdomainResults = $Results | Where-Object { $_.IsSubdomain -eq $true }
            Write-Host "   Subdomain Records: $($SubdomainResults.Count)" -ForegroundColor Cyan
        }

        # Format and return results using Format-BlackCatOutput if available
        $formatParam = @{
            Data = $Results
            OutputFormat = $OutputFormat
            FunctionName = $MyInvocation.MyCommand.Name
            FilePrefix = 'DNSRecon'
        }
        
        return Format-BlackCatOutput @formatParam
    }
<#
.SYNOPSIS
    Performs comprehensive DNS reconnaissance on target domains with enhanced provider support and subdomain enumeration capabilities.

.DESCRIPTION
    Find-DnsRecords is an advanced DNS reconnaissance tool that queries multiple DNS-over-HTTPS providers to gather DNS records
    for specified domains. It supports various record types, subdomain enumeration with CNAME discovery, and can detect
    flattened/proxied CNAMEs used by CDN services like Cloudflare. The function provides load balancing across multiple
    DNS providers, customizable delays for stealth, and integrates with the BlackCat framework for enhanced subdomain lists
    and user agent rotation.

.PARAMETER Domains
    One or more target domains to perform DNS reconnaissance on.
    Accepts pipeline input.

.PARAMETER MinDelay
    Minimum delay in seconds between DNS queries (1-300).
    Default: 1 second. Helps avoid rate limiting.

.PARAMETER MaxDelay
    Maximum delay in seconds between DNS queries (1-600).
    Default: 3 seconds. Random delay between MinDelay and MaxDelay is used.

.PARAMETER LogPath
    Path to save reconnaissance results log file.
    Default: ".\recon_results.log"

.PARAMETER RecordTypes
    Array of DNS record types to query.
    Valid values: "A", "AAAA", "CNAME", "MX", "NS", "TXT", "SOA", "PTR"
    Default: @("A", "AAAA", "CNAME", "MX", "TXT")

.PARAMETER FastMode
    Switch to enable fast mode with reduced delays and timeouts.
    Overrides MinDelay/MaxDelay settings.

.PARAMETER DNSInfoLevel
    Level of detail in output messages.
    Valid values: "Minimal", "Standard", "Detailed"
    Default: "Standard"

.PARAMETER OutputFormat
    Format for the returned results.
    Valid values: "Object", "JSON", "CSV", "Table"
    Default: "Table"

.PARAMETER SkipCache
    Switch to bypass using cached results and force a fresh DNS query.
    Default: False (cache is used if available)

.PARAMETER CacheExpirationMinutes
    Number of minutes to store results in cache before they expire.
    Default: 30 minutes

.PARAMETER MaxCacheSize
    Maximum number of entries to keep in the cache (uses LRU eviction).
    Default: 100 entries

.PARAMETER CompressCache
    Switch to enable compression of cached data to reduce memory usage.
    Default: False (no compression)

.PARAMETER EnumerateSubdomains
    Switch to enable subdomain enumeration for CNAME discovery.
    Requires BlackCat framework session variables for subdomain lists.

.PARAMETER SubdomainThrottleLimit
    Maximum number of parallel threads for subdomain testing (1-200).
    Default: 50. Higher values may cause rate limiting.

.PARAMETER SubdomainCategory
    Category of subdomains to enumerate from session variables.
    Valid values depend on loaded subdomain lists (e.g., "common", "cloud", "all").
    Default: "common"

.PARAMETER DeepSubdomainSearch
    Switch to enable deep subdomain search using extended wordlists.
    Automatically enables EnumerateSubdomains if not already set.

.EXAMPLE
    Find-DnsRecords -Domains "example.com" -RecordTypes "A","CNAME"

    Performs basic DNS reconnaissance for A and CNAME records on example.com.

.EXAMPLE
    Find-DnsRecords -Domains "example.com","test.com" -EnumerateSubdomains -SubdomainCategory "cloud" -OutputFormat JSON

    Enumerates cloud-related subdomains for multiple domains and returns results in JSON format.

.EXAMPLE
    @("domain1.com", "domain2.com") | Find-DnsRecords -FastMode -RecordTypes "A","AAAA","CNAME" -DNSInfoLevel Detailed

    Performs fast reconnaissance with detailed output for multiple domains via pipeline.

.EXAMPLE
    Find-DnsRecords -Domains "target.com" -EnumerateSubdomains -DeepSubdomainSearch -SubdomainThrottleLimit 100
    
    Performs deep subdomain enumeration with increased parallelization for comprehensive CNAME discovery.
    
.EXAMPLE
    Find-DnsRecords -Domains "example.com" -OutputFormat JSON -OutputFile "example-dns-scan"
    
    Performs DNS reconnaissance and exports the results to "example-dns-scan.json" using Format-BlackCatOutput.
    
.EXAMPLE
    Find-DnsRecords -Domains "example.com" -CacheExpirationMinutes 60 -CompressCache
    
    Performs DNS reconnaissance and caches the results for 60 minutes with compression enabled.
    
.EXAMPLE
    Find-DnsRecords -Domains "example.com" -SkipCache
    
    Forces a fresh DNS lookup, bypassing any cached results for the domain.

.NOTES
    Author: BlackCat Security Framework
    Version: 2.0.0

    This function integrates with the BlackCat framework when available, providing:
    - Enhanced subdomain wordlists from session variables
    - Randomized user agent rotation
    - Category-based subdomain enumeration
    - CNAME flattening detection

.INPUTS
    System.String[]
    Accepts domain names from pipeline.

.OUTPUTS
    System.Object[] | System.String
    Returns DNS record objects in specified format (Object, JSON, CSV, or Table).

.LINK
    https://github.com/blackcat/reconnaissance
#>
}