
# Domain Permutation Configuration
# This file contains configuration data for domain permutation generation

$DomainPermutationConfig = @{
    # Common phishing TLDs (frequently used by attackers)
    PhishingTLDs = @(
        "com", "net", "org", "info", "biz", "co", "io", "me", "tv", "cc",
        "tk", "ml", "ga", "cf", "click", "online", "site", "website", 
        "top", "xyz", "club", "store", "shop", "live", "tech", "app",
        "link", "download", "stream", "news", "today", "world", "global"
    )
    
    # Common subdomain patterns used in phishing
    PhishingSubdomains = @(
        "www", "secure", "login", "auth", "account", "support", "help",
        "admin", "portal", "app", "api", "mail", "email", "webmail",
        "signin", "signup", "verify", "update", "confirm", "activate",
        "reset", "recovery", "security", "protection", "service",
        "customer", "billing", "payment", "invoice", "statement"
    )
    
    # High-value targets for domain monitoring
    CorporateKeywords = @(
        "microsoft", "google", "amazon", "apple", "facebook", "meta",
        "paypal", "netflix", "adobe", "salesforce", "zoom", "slack",
        "github", "linkedin", "twitter", "instagram", "youtube",
        "dropbox", "spotify", "steam", "epic", "origin"
    )
    
    # Banking and financial keywords (high priority)
    FinancialKeywords = @(
        "bank", "banking", "credit", "debit", "card", "payment", "pay",
        "wallet", "crypto", "bitcoin", "coinbase", "binance", "kraken",
        "visa", "mastercard", "amex", "discover", "finance", "loan",
        "mortgage", "investment", "trading", "forex", "stock"
    )
    
    # Common word insertions for phishing domains
    CommonInsertions = @(
        "secure", "auth", "login", "account", "service", "support",
        "help", "update", "verify", "confirm", "new", "my", "portal",
        "admin", "user", "client", "customer", "official", "real"
    )
    
    # Character substitution patterns for advanced typosquatting
    AdvancedSubstitutions = @{
        "microsoft" = @("microsft", "microsooft", "micrsoft", "micr0soft", "micr0s0ft")
        "google" = @("googIe", "goog1e", "g00gle", "googel", "gooogle")
        "amazon" = @("amaz0n", "amazom", "amazone", "amazonn", "amaozn")
        "paypal" = @("paypaI", "payp4l", "paypa1", "paypayl", "paypall")
        "facebook" = @("faceb00k", "facebbok", "facebo0k", "faceebook", "facebook")
        "apple" = @("appIe", "app1e", "appl3", "applle", "aple")
    }
    
    # Risk scoring weights
    RiskWeights = @{
        "Homograph" = 10      # Highest risk - visually deceptive
        "Typo" = 8           # High risk - common user errors
        "Insertion" = 6      # Medium-high risk
        "TLD" = 5            # Medium risk
        "Subdomain" = 4      # Medium-low risk
        "Hyphen" = 3         # Lower risk
        "Replacement" = 7    # High risk
        "Transposition" = 6  # Medium-high risk
        "Omission" = 5       # Medium risk
    }
    
    # Domain age thresholds (days) for additional risk assessment
    DomainAgeRisk = @{
        "VeryNew" = 7        # Registered within last week
        "New" = 30           # Registered within last month
        "Recent" = 90        # Registered within last 3 months
        "Established" = 365  # Older than 1 year
    }
    
    # Common patterns that increase suspicion
    SuspiciousPatterns = @(
        "update", "verify", "confirm", "secure", "urgent", "suspend",
        "expire", "renew", "validate", "activate", "unlock", "restore",
        "alert", "notice", "warning", "important", "critical", "action"
    )
    
    # Whitelist patterns (legitimate variations to ignore)
    WhitelistPatterns = @(
        "*.microsoft.com",
        "*.google.com", 
        "*.amazon.com",
        "*.amazonaws.com",
        "*.cloudfront.net",
        "*.azure.com",
        "*.azurewebsites.net"
    )
}

function Get-DomainPermutationConfig {
    <#
    .SYNOPSIS
    Returns the domain permutation configuration
    
    .DESCRIPTION
    Provides access to the domain permutation configuration data
    
    .PARAMETER Section
    Specific section of configuration to return
    #>
    
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet("PhishingTLDs", "PhishingSubdomains", "CorporateKeywords", 
                     "FinancialKeywords", "CommonInsertions", "AdvancedSubstitutions",
                     "RiskWeights", "DomainAgeRisk", "SuspiciousPatterns", "WhitelistPatterns")]
        [string]$Section
    )
    
    if ($Section) {
        return $DomainPermutationConfig[$Section]
    }
    
    return $DomainPermutationConfig
}

function Test-DomainWhitelist {
    <#
    .SYNOPSIS
    Checks if a domain matches whitelist patterns
    
    .PARAMETER Domain
    Domain to check against whitelist
    #>
    
    param(
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )
    
    $whitelistPatterns = Get-DomainPermutationConfig -Section "WhitelistPatterns"
    
    foreach ($pattern in $whitelistPatterns) {
        if ($Domain -like $pattern) {
            return $true
        }
    }
    
    return $false
}

function Get-DomainRiskScore {
    <#
    .SYNOPSIS
    Calculates a risk score for a domain permutation
    
    .PARAMETER Domain
    The permuted domain
    
    .PARAMETER PermutationType
    Type of permutation
    
    .PARAMETER OriginalDomain
    The original domain being permuted
    
    .PARAMETER RegistrationDate
    When the domain was registered (if known)
    #>
    
    param(
        [Parameter(Mandatory = $true)]
        [string]$Domain,
        
        [Parameter(Mandatory = $true)]
        [string]$PermutationType,
        
        [Parameter(Mandatory = $true)]
        [string]$OriginalDomain,
        
        [Parameter(Mandatory = $false)]
        [datetime]$RegistrationDate
    )
    
    $config = Get-DomainPermutationConfig
    
    # Base risk score from permutation type
    $riskScore = $config.RiskWeights[$PermutationType]
    if (-not $riskScore) { $riskScore = 5 }
    
    # Increase risk for financial/corporate keywords
    $domainLower = $Domain.ToLower()
    $originalLower = $OriginalDomain.ToLower()
    
    foreach ($keyword in $config.FinancialKeywords) {
        if ($originalLower.Contains($keyword.ToLower())) {
            $riskScore += 5
            break
        }
    }
    
    foreach ($keyword in $config.CorporateKeywords) {
        if ($originalLower.Contains($keyword.ToLower())) {
            $riskScore += 3
            break
        }
    }
    
    # Increase risk for suspicious patterns
    foreach ($pattern in $config.SuspiciousPatterns) {
        if ($domainLower.Contains($pattern.ToLower())) {
            $riskScore += 2
        }
    }
    
    # Adjust for domain age
    if ($RegistrationDate) {
        $daysSinceRegistration = (Get-Date) - $RegistrationDate
        
        if ($daysSinceRegistration.Days -le $config.DomainAgeRisk.VeryNew) {
            $riskScore += 5
        }
        elseif ($daysSinceRegistration.Days -le $config.DomainAgeRisk.New) {
            $riskScore += 3
        }
        elseif ($daysSinceRegistration.Days -le $config.DomainAgeRisk.Recent) {
            $riskScore += 2
        }
    }
    
    # Normalize score to 1-10 scale
    $normalizedScore = [Math]::Min([Math]::Max($riskScore, 1), 10)
    
    return [PSCustomObject]@{
        RiskScore = $normalizedScore
        RiskLevel = switch ($normalizedScore) {
            {$_ -ge 8} { "Critical" }
            {$_ -ge 6} { "High" }
            {$_ -ge 4} { "Medium" }
            {$_ -ge 2} { "Low" }
            default { "Minimal" }
        }
    }
}

# Export configuration for use by other scripts
Export-ModuleMember -Function Get-DomainPermutationConfig, Test-DomainWhitelist, Get-DomainRiskScore -Variable DomainPermutationConfig
