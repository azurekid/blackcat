function Invoke-EnumSubDomains {
    [CmdletBinding()]
    [OutputType([System.Collections.ArrayList])]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, ValueFromPipeline = $true)]
        [Alias('domain-name')]
        [ValidatePattern('^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$',
            ErrorMessage = 'Domain name must be in valid format (e.g., example.com)')]
        [string[]]$DomainName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet('all', 'common', 'development', 'marketing', 'ecommerce', 'corporate', 'infrastructure', 'education', 'security', 'media', 'networking', 'cloud')]
        [string]$Category = 'common',

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias('word-list')]
        [string]$WordList,

        [Parameter(Mandatory = $false)]
        [Alias('throttle-limit')]
        [int]$ThrottleLimit = 100,

        [Parameter(Mandatory = $false)]
        [switch]$DeepSearch
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"

        $result = [System.Collections.ArrayList]::new()
        $type = if ($DeepSearch) { 'deep' } else { 'default' }
        if ($type -eq 'deep') {
            Write-Message  -FunctionName $($MyInvocation.MyCommand.Name) "Deep search $($type -eq 'deep' ? 'enabled' : 'disabled')" -Severity Information
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
                    foreach ($sd in $SessionVariables.subdomains[$type].$cat) {
                        [void]$subdomains.Add($sd)
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
                    $result = $using:result
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
                            if ($subdomains[$type].$catLookup -contains $subdomain) {
                                $foundCategory = $catLookup
                                Write-Verbose "Found category '$catLookup' for subdomain '$_'"
                                break
                            }
                        }

                        $resultObject = [PSCustomObject]@{
                            Domain     = $domain
                            Category   = $foundCategory
                            Url        = $uri
                            HostName   = $hostName
                            IpAddress  = $ipAddress
                        }

                        [void]$result.Add($resultObject)
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
        if (-not $result -or $result.Count -eq 0) {
            Write-Information "No public resources found" -InformationAction Continue
        }
        else {
            Write-Information "Found $($result.Count) public resources" -InformationAction Continue
            return $result | Sort-Object Domain, Category, Url | Format-Table -AutoSize
        }
    }
<#
.SYNOPSIS
    Enumerates subdomains for specified domain names.

.DESCRIPTION
    The Invoke-EnumSubDomains function performs subdomain enumeration for one or more domain names
    by checking the DNS resolution of common subdomain prefixes. It can use built-in subdomain lists
    categorized by purpose or a custom word list provided by the user.

.PARAMETER DomainName
    One or more domain names to enumerate subdomains for. The domains must be in a valid format (e.g., example.com).

.PARAMETER Category
    The category of subdomains to check. Available options:
    - all: Use all subdomain categories
    - common: Common subdomains (default)
    - development: Development-related subdomains
    - marketing: Marketing-related subdomains
    - ecommerce: E-commerce related subdomains
    - corporate: Corporate-related subdomains
    - infrastructure: Infrastructure-related subdomains
    - education: Education-related subdomains
    - security: Security-related subdomains
    - media: Media-related subdomains
    - networking: Networking-related subdomains
    - cloud: Cloud-related subdomains

.PARAMETER WordList
    Path to a custom wordlist file containing subdomain prefixes, one per line.

.PARAMETER ThrottleLimit
    Maximum number of concurrent DNS resolution operations. Default is 100.

.PARAMETER DeepSearch
    Switch to enable deep search mode, which uses an extended list of subdomain prefixes.

.EXAMPLE
    Invoke-EnumSubDomains -DomainName example.com

    Enumerates common subdomains for example.com.

.EXAMPLE
    Invoke-EnumSubDomains -DomainName example.com -Category development

    Enumerates development-related subdomains for example.com.

.EXAMPLE
    Invoke-EnumSubDomains -DomainName example.com -WordList .\subdomains.txt

    Enumerates subdomains for example.com using a custom wordlist.

.EXAMPLE
    Invoke-EnumSubDomains -DomainName example.com -DeepSearch

    Performs a deep subdomain enumeration for example.com using an extended list of subdomain prefixes.

.EXAMPLE
    "example.com", "example.org" | Invoke-EnumSubDomains

    Enumerates common subdomains for multiple domains provided via pipeline.

.OUTPUTS
    System.Collections.ArrayList
    Returns a collection of discovered subdomains with their associated information.

.NOTES
    The function requires network connectivity to perform DNS resolution.
    Deep search mode will take considerably longer to complete due to the extended subdomain list.

.LINK
    https://github.com/azurekid/blackcat
#>
}
