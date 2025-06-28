<#
.SYNOPSIS
    Performs stealth DNS reconnaissance using multiple DNS providers.

.DESCRIPTION
    This function performs DNS reconnaissance using DNS-over-HTTPS (DoH) providers
    to gather DNS records while maintaining stealth and avoiding detection.

    Enhanced with 5 DNS providers for improved reliability and geographic diversity:
    - Cloudflare (99.9% reliability, Global, Commercial)
    - Google (99.8% reliability, Global, Commercial)  
    - NextDNS (99.5% reliability, Global, Privacy-focused)
    - DNS.SB (99.3% reliability, Global, Privacy-focused)
    - DNSPod (99% reliability, China/Global, Commercial)

    Features automatic provider rotation, load balancing, and comprehensive error handling.

.PARAMETER Domains
    Array of domain names to perform reconnaissance on.

.PARAMETER MinDelay
    Minimum delay between requests in seconds (1-300).

.PARAMETER MaxDelay
    Maximum delay between requests in seconds (1-600).

.PARAMETER LogPath
    Path to the log file for storing reconnaissance results.

.PARAMETER RecordTypes
    Array of DNS record types to query (A, AAAA, CNAME, MX, NS, TXT, SOA, PTR).

.PARAMETER UseRandomUserAgent
    Whether to use random User-Agent strings for requests.

.PARAMETER FastMode
    Enable fast mode with reduced delays and timeouts.

.PARAMETER DNSInfoLevel
    Level of DNS information to display (Minimal, Standard, Detailed).

.PARAMETER OutputFormat
    Format for output results (Object, JSON, Table).

.EXAMPLE
    Invoke-StealthDNSRecon -Domains @("example.com", "test.com")

.NOTES
    Requires internet connectivity and access to DNS-over-HTTPS providers.
#>

# Helper function for logging
function Write-DNSLog {
    param([string]$Message, [string]$Level = "INFO", [string]$LogPath)
    $LogEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Write-Verbose $LogEntry
    try {
        if ($LogPath) { Add-Content -Path $LogPath -Value $LogEntry -ErrorAction SilentlyContinue }
    } catch { }
}

function Invoke-StealthDNSRecon {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Domains,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 300)]
        [int]$MinDelay = 1,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 600)]
        [int]$MaxDelay = 3,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$LogPath = ".\recon_results.log",

        [Parameter(Mandatory = $false)]
        [ValidateSet("A", "AAAA", "CNAME", "MX", "NS", "TXT", "SOA", "PTR")]
        [string[]]$RecordTypes = @("A", "AAAA", "MX", "TXT"),

        [Parameter(Mandatory = $false)]
        [switch]$UseRandomUserAgent,

        [Parameter(Mandatory = $false)]
        [switch]$FastMode,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Minimal", "Standard", "Detailed")]
        [string]$DNSInfoLevel = "Standard",

        [Parameter(Mandatory = $false)]
        [ValidateSet("Object", "JSON", "Table")]
        [string]$OutputFormat = "Object"
    )

    begin {
        Write-Verbose "Starting DNS reconnaissance with enhanced provider support"

        # Initialize BlackCat framework (optional for anonymous operation)
        $BlackCatAvailable = $false
        try {
            if (Get-Command "Invoke-BlackCat" -ErrorAction SilentlyContinue) {
                $MyInvocation.MyCommand.Name | Invoke-BlackCat
                $BlackCatAvailable = $true
                Write-Verbose "BlackCat framework integrated successfully"
            }
        }
        catch {
            Write-Verbose "BlackCat framework integration failed: $($_.Exception.Message). Operating in anonymous mode."
        }

        # Enhanced DNS provider pool (5 providers - JSON format only)
        $DNSProviders = @{
            "Cloudflare" = @{ URL = "https://cloudflare-dns.com/dns-query"; Region = "Global"; Type = "Commercial"; Reliability = 99.9 }
            "Google" = @{ URL = "https://dns.google/resolve"; Region = "Global"; Type = "Commercial"; Reliability = 99.8 }
            "NextDNS" = @{ URL = "https://dns.nextdns.io"; Region = "Global"; Type = "Privacy"; Reliability = 99.5 }
            "DNS.SB" = @{ URL = "https://doh.dns.sb/dns-query"; Region = "Global"; Type = "Privacy"; Reliability = 99.3 }
            "DNSPod" = @{ URL = "https://dns.pub/dns-query"; Region = "China/Global"; Type = "Commercial"; Reliability = 99.0 }
        }

        # User agents - integrate with BlackCat module if available
        if ($BlackCatAvailable -and $script:SessionVariables -and $script:SessionVariables.userAgents) {
            Write-Verbose "Using BlackCat module user agents"
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
            Timeout = if ($FastMode) { 5 } else { 10 }
        }

        Write-DNSLog "🚀 Starting stealth DNS reconnaissance" "INFO" $LogPath
    }

    process {
        foreach ($Domain in $Domains) {
            Write-Host "🎯 Analyzing domain: $Domain" -ForegroundColor Green
            
            # Rotate through providers for load balancing
            $ProviderNames = $DNSProviders.Keys | Sort-Object { Get-Random }
            
            foreach ($RecordType in $RecordTypes) {
                Write-Host "  🔍 Querying $RecordType records..." -ForegroundColor Yellow
                
                foreach ($ProviderName in $ProviderNames) {
                    $Provider = $DNSProviders[$ProviderName]
                    
                    if ($DNSInfoLevel -eq "Detailed") {
                        Write-Host "    📡 Using $ProviderName ($($Provider.Reliability)%)" -ForegroundColor Cyan
                    }
                    
                    try {
                        $Stats.TotalQueries++
                        
                        # JSON DNS query
                        $QueryUrl = "$($Provider.URL)?name=$Domain&type=$RecordType"
                        $Headers = @{ "Accept" = "application/dns-json" }
                        if ($UseRandomUserAgent) { $Headers["User-Agent"] = $UserAgents | Get-Random }
                        
                        $Response = Invoke-RestMethod -Uri $QueryUrl -Headers $Headers -TimeoutSec $Config.Timeout -ErrorAction Stop
                        
                        if ($Response.Answer) {
                            foreach ($Answer in $Response.Answer) {
                                if ($Answer.type -eq (@{"A"=1;"AAAA"=28;"CNAME"=5;"MX"=15;"NS"=2;"TXT"=16;"SOA"=6;"PTR"=12}[$RecordType])) {
                                    $null = $Results.Add([PSCustomObject]@{
                                        Domain = $Domain
                                        RecordType = $RecordType
                                        Data = $Answer.data
                                        TTL = $Answer.TTL
                                        DNSProvider = $ProviderName
                                        ProviderType = $Provider.Type
                                        ProviderRegion = $Provider.Region
                                        Reliability = $Provider.Reliability
                                        Timestamp = Get-Date
                                        QueryMethod = "DoH-JSON"
                                    })
                                    
                                    $Stats.SuccessfulQueries++
                                    Write-Host "      ✅ $($Answer.data) (TTL: $($Answer.TTL))" -ForegroundColor Green
                                    Write-DNSLog "✅ Found $RecordType record: $($Answer.data) [TTL: $($Answer.TTL)] via $ProviderName" "INFO" $LogPath
                                }
                            }
                        }
                        
                        # Add delay between requests
                        if ($Config.MaxDelay -gt 0) {
                            $Delay = Get-Random -Minimum $Config.MinDelay -Maximum $Config.MaxDelay
                            Start-Sleep -Seconds $Delay
                        }
                        
                        break  # Success, move to next record type
                    }
                    catch {
                        $Stats.FailedQueries++
                        Write-DNSLog "❌ Query failed for $Domain ($RecordType) via $ProviderName : $($_.Exception.Message)" "ERROR" $LogPath
                        
                        if ($DNSInfoLevel -eq "Detailed") {
                            Write-Host "      ❌ Query failed: $($_.Exception.Message)" -ForegroundColor Red
                        }
                        # Continue to next provider
                    }
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
        
        Write-DNSLog "📊 Reconnaissance completed: $($Results.Count) records found in $($Duration.TotalSeconds.ToString('F2'))s" "INFO" $LogPath
        
        # Return results in requested format
        switch ($OutputFormat) {
            "JSON" { return $Results | ConvertTo-Json -Depth 3 }
            "Table" { return $Results | Format-Table -AutoSize }
            default { return $Results }
        }
    }
}