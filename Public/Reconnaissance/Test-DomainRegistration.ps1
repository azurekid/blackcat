function Test-DomainRegistration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Domain,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("rdap", "whois", "dns", "all")]
        [string]$Method = "all"
    )
    
    # Add some verification to ensure the domain is a valid format
    if (-not $Domain -or -not ($Domain -match '^[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}$')) {
        Write-Warning " Invalid domain format: $Domain"
        return [PSCustomObject]@{
            Status  = "Invalid"
            Domain  = $Domain
            Message = " Invalid domain format"
        }
    }
    
    # Helper function to check via DNS
    function Test-DomainViaDNS {
        param([string]$DomainName)
        
        try {
            $result = Resolve-DnsName -Name $DomainName -ErrorAction Stop
            if ($result) {
                return [PSCustomObject]@{
                    Status    = "Registered"
                    Domain    = $DomainName
                    Registrar = "Unknown (DNS lookup only)"
                    Message   = " Domain resolves in DNS"
                }
            }
        }
        catch {
            return [PSCustomObject]@{
                Status  = "Available"
                Domain  = $DomainName
                Message = "🆓 Domain does not resolve in DNS"
            }
        }
    }
    
    # If method is "dns" or we're rate limited and trying alternative methods
    if ($Method -eq "dns" -or $Method -eq "all") {
        $dnsResult = Test-DomainViaDNS -DomainName $Domain
        # If we're only using DNS or we get a successful DNS result when using "all" method
        if ($Method -eq "dns" -or ($Method -eq "all" -and $dnsResult.Status -eq "Registered")) {
            return $dnsResult
        }
    }
    
    # If we're not using RDAP, skip this section
    if ($Method -eq "dns") {
        # We've already returned the DNS result if it was the requested method
        return $dnsResult
    }
    
    try {
        # Add retry logic for rate limiting
        $maxRetries = 2
        $retryCount = 0
        $retryDelayMs = 1500  # Start with 1.5 second delay
        $success = $false
        $response = $null
        
        # Try multiple RDAP services if the primary fails
        $rdapServices = @(
            "https://rdap.org/domain/$Domain",
            "https://www.rdap.net/domain/$Domain"
        )
        
        foreach ($rdapService in $rdapServices) {
            $retryCount = 0
            while (-not $success -and $retryCount -lt $maxRetries) {
                try {
                    Write-Verbose "Trying RDAP service: $rdapService"
                    $response = Invoke-RestMethod -Uri $rdapService -ErrorAction Stop -TimeoutSec 10
                    $success = $true
                    break  # Exit the retry loop if successful
                }
                catch {
                    if ($_.Exception.Response.StatusCode.value__ -eq 429) {
                        # Rate limited - implement exponential backoff
                        $retryCount++
                        if ($retryCount -lt $maxRetries) {
                            # Calculate retry delay with exponential backoff and jitter
                            $jitter = Get-Random -Minimum 100 -Maximum 500
                            $retryDelayMs = $retryDelayMs * 2 + $jitter
                            Write-Verbose " Rate limited for domain $Domain, retry $retryCount after $($retryDelayMs)ms"
                            Start-Sleep -Milliseconds $retryDelayMs
                        }
                        else {
                            # Try the next service or fail if this was the last one
                            Write-Verbose " Rate limit exceeded for $rdapService, trying next service"
                            break
                        }
                    }
                    else {
                        # For other errors, try the next service
                        Write-Verbose " Error with $rdapService $($_.Exception.Message)"
                        break
                    }
                }
            }
            
            # If we got a successful response, no need to try additional services
            if ($success) {
                break
            }
        }
        
        # If we've exhausted all RDAP options, try DNS as last resort
        if (-not $success -and $Method -eq "all") {
            Write-Verbose " All RDAP services failed, falling back to DNS check for $Domain"
            return Test-DomainViaDNS -DomainName $Domain
        }
        
        # If we still haven't succeeded and we're not in "all" mode, throw to be caught by the catch block
        if (-not $success -and $Method -ne "all") {
            throw [System.Net.WebException]::new("All RDAP services failed for domain $Domain")
        }
        
        # If no valid response, stop here
        if (-not $response) {
            throw [System.Net.WebException]::new("No valid response from RDAP services for $Domain")
        }
        
        # Domain is registered
        if ($response.objectClassName -eq "domain") {
            try {
                # Extract important dates
                $creationDate = ($response.events | Where-Object { $_.eventAction -eq "registration" }).eventDate
                $expiryDate = ($response.events | Where-Object { $_.eventAction -eq "expiration" }).eventDate
                $lastUpdateDate = ($response.events | Where-Object { $_.eventAction -like "*last update*" }).eventDate
                
                # Extract name servers
                $nameServers = $response.nameservers | ForEach-Object { $_.ldhName }
                
                # Extract registrar information
                $registrarName = "Unknown Registrar"
                $registrarEntity = $response.entities | Where-Object { $_.roles -contains "registrar" }
                
                if ($registrarEntity) {
                    $vcardFn = $registrarEntity.vcardArray[1] | Where-Object { $_[0] -eq "fn" }
                    if ($vcardFn) {
                        $registrarName = $vcardFn[3]
                    }
                }
                
                # Create user-friendly output object
                return [PSCustomObject]@{
                    Status      = "Registered"
                    Domain      = $Domain
                    Registrar   = $registrarName
                    Created     = $creationDate
                    Expires     = $expiryDate
                    LastUpdated = $lastUpdateDate
                    NameServers = $nameServers -join ", "
                    Message     = " Domain is registered"
                }
            }
            catch {
                # If we got a response, but couldn't parse it correctly
                return [PSCustomObject]@{
                    Status      = "Registered"
                    Domain      = $Domain
                    Registrar   = "Unknown (Parser Error)"
                    Message     = " Error parsing domain data: $($_.Exception.Message)"
                }
            }
        }
        else {
            # Got a response, but it wasn't a domain
            return [PSCustomObject]@{
                Status   = "Unknown"
                Domain   = $Domain
                Message  = " Unexpected response format"
            }
        }
    }
    catch {
        # Handle specific error cases
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
            # 404 means domain is available
            return [PSCustomObject]@{
                Status  = "Available"
                Domain  = $Domain
                Message = "🆓 Domain appears to be available for registration"
            }
        }
        elseif ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 429) {
            # Rate limiting
            return [PSCustomObject]@{
                Status  = "RateLimited"
                Domain  = $Domain
                Message = " Rate limited by API service when checking domain"
            }
        }
        elseif ($_.Exception.Message -match "timed out|timeout") {
            # Timeout errors
            return [PSCustomObject]@{
                Status  = "Timeout"
                Domain  = $Domain
                Message = " Request timed out when checking domain registration"
            }
        }
        else {
            # General errors
            return [PSCustomObject]@{
                Status  = "Error"
                Domain  = $Domain
                Message = " Error checking domain: $($_.Exception.Message)"
            }
        }
    }

    <#
    .SYNOPSIS
        Tests whether a domain is registered or available for registration.

    .DESCRIPTION
        The Test-DomainRegistration function checks domain registration status using RDAP, WHOIS, 
        or DNS lookups. This can be used to identify potential domain takeover opportunities.

    .PARAMETER Domain
        The domain name to check for registration status.

    .PARAMETER Method
        The method to use for checking domain registration. Valid values are:
        - rdap: Use RDAP protocol
        - whois: Use WHOIS lookup
        - dns: Use DNS resolution
        - all: Try all methods (default)

    .EXAMPLE
        Test-DomainRegistration -Domain "example.com"

        Checks if example.com is registered using all available methods.

    .EXAMPLE
        Test-DomainRegistration -Domain "potential-subdomain.azurewebsites.net" -Method dns

        Checks if the subdomain resolves in DNS (useful for subdomain takeover checks).

    .NOTES
        Author: Rogier Dijkman
        This function is useful for identifying dangling DNS records and subdomain takeover opportunities.

    .LINK
        MITRE ATT&CK Tactic: TA0043 - Reconnaissance
        https://attack.mitre.org/tactics/TA0043/

    .LINK
        MITRE ATT&CK Technique: T1593.002 - Search Open Websites/Domains: Search Engines
        https://attack.mitre.org/techniques/T1593/002/
    #>
}
