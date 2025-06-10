function Test-DnsTwistDomain {
    <#
    .SYNOPSIS
        Checks for DNS typosquatting domain variations that may be used for malicious purposes.
    
    .DESCRIPTION
        This function generates various typosquatting domain variations based on a legitimate domain name,
        checks if these domains are registered, and calculates a risk score for each registered domain.
        This helps identify potential phishing or malicious domains targeting users of the legitimate site.
    
    .PARAMETER Domain
        The legitimate domain name to check for typosquatting variations.
    
    .PARAMETER MaxResults
        The maximum number of results to return. Default is 100.
    
    .PARAMETER IncludeAvailable
        Include domains that are available for registration in the results. Default is to only show registered domains.
    
    .PARAMETER RegistrationCheckMethod
        Specifies the method to check domain registration status: "rdap", "whois", "dns", or "all".
        Default is "all" which tries various methods in order of reliability.
    
    .EXAMPLE
        Test-DnsTwistDomain -Domain "google.com"
        
        Checks for typosquatting variations of google.com that are registered and returns them with risk scores.
    
    .EXAMPLE
        Test-DnsTwistDomain -Domain "microsoft.com" -MaxResults 50 -IncludeAvailable $true
        
        Checks for typosquatting variations of microsoft.com, including available domains, and returns up to 50 results.
    
    .NOTES
        This function relies on Get-DnsTwistDomains to generate domain variations and Test-DomainRegistration to check registration status.
        Risk scoring is based on multiple factors including domain similarity, registration information, and common phishing indicators.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [string]$Domain,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxResults = 100,
        
        [Parameter(Mandatory = $false)]
        [bool]$IncludeAvailable = $false,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("rdap", "whois", "dns", "all")]
        [string]$RegistrationCheckMethod = "all"
    )

    begin {
        # Validate the domain format
        if (-not ($Domain -match '^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)+$')) {
            Write-Error "Invalid domain format: $Domain"
            return
        }

        # Risk scoring factors and weights (0-100)
        $riskFactors = @{
            # Identity and visual confusion factors
            HasHomoglyphs = 30              # Homoglyphs are very high risk (visually identical)
            HasCharacterSwap = 18           # Swapped characters can be hard to notice
            HasMissingChar = 15             # Missing character (shorter domain)
            HasExtraChar = 10               # Extra character (longer domain)
            HasKeyboardTypo = 12            # Keyboard adjacency typos
            
            # Domain attribute factors
            IsTldVariation = 25             # TLD variation (.com vs .org) is very common in phishing
            HasHyphen = 8                   # Domains with hyphens can appear more legitimate
            
            # Temporal factors
            IsRecentlyRegistered = 25       # Recently registered domains are higher risk
            
            # Registration factors
            HasPrivacyProtection = 15       # Privacy-protected WHOIS can indicate hiding identity
            HasSuspiciousNameServer = 20    # Suspicious nameservers often indicate malicious intent
            
            # Severity multipliers
            SuspiciousTLDMultiplier = 1.2   # Multiplier for suspicious TLDs (.xyz, .info, etc.)
        }

        # Date threshold for recently registered domains (6 months)
        $recentRegistrationThreshold = (Get-Date).AddMonths(-6)

        Write-Verbose "Generating typosquatting variations for domain: $Domain"
    }

    process {
        try {
            # Generate domain twist variations
            $twistDomains = Get-DnsTwistDomains -Domain $Domain
            
            if ($null -eq $twistDomains -or $twistDomains.Count -eq 0) {
                Write-Warning "No domain variations were generated for: $Domain"
                return
            }
            
            Write-Verbose "Generated $($twistDomains.Count) domain variations"
            
            # Initialize results collection
            $results = [System.Collections.Generic.List[PSObject]]::new()
            $processedCount = 0
            
            # Process each domain variation
            foreach ($twistedDomain in $twistDomains) {
                # Check if we've reached the max results limit
                if ($processedCount -ge $MaxResults) {
                    Write-Verbose "Reached maximum results limit: $MaxResults"
                    break
                }
                
                Write-Verbose "Checking registration for: $twistedDomain"
                $registrationInfo = Test-DomainRegistration -Domain $twistedDomain -Method $RegistrationCheckMethod
                
                # Skip unregistered domains if not including available domains
                if ($registrationInfo.Status -eq "Available" -and -not $IncludeAvailable) {
                    continue
                }
                
                # Calculate risk score for registered domains
                $riskScore = 0
                $riskFactorsFound = @()
                
                if ($registrationInfo.Status -eq "Registered") {
                    # Extract main domain parts for comparison
                    $domainParts = $Domain -split "\."
                    $twistDomainParts = $twistedDomain -split "\."
                    $originalMainDomain = $domainParts[0]
                    $twistedMainDomain = $twistDomainParts[0]
                    $originalTld = ($domainParts | Select-Object -Skip 1) -join "."
                    $twistedTld = ($twistDomainParts | Select-Object -Skip 1) -join "."
                    
                    # 1. Check for homoglyphs (visually similar characters)
                    $homoglyphMap = @{
                        'a' = @('á', 'à', 'â', 'ã', 'ä', 'å', 'ą', 'а', '4')
                        'b' = @('d', 'lb', 'ib', 'б', '6', '8')
                        'c' = @('е', 'с', '(')
                        'e' = @('é', 'è', 'ê', 'ë', 'ё', 'е', '3')
                        'g' = @('q', '9')
                        'i' = @('1', 'l', 'í', 'ì', 'î', 'ï', 'ι', 'і', '|', '!')
                        'l' = @('1', 'i', '|')
                        'm' = @('rn', 'rгn', 'nn')
                        'n' = @('м', 'п') 
                        'o' = @('0', 'ο', 'о', 'ö', 'ó', 'ò', 'ô', 'õ')
                        'p' = @('р')
                        'r' = @('г')
                        's' = @('$', '5')
                        'w' = @('vv', 'ѡ')
                        'x' = @('х')
                        'y' = @('у')
                        '0' = @('o', 'О', 'Ο')
                        '1' = @('l', 'i', '|')
                        '5' = @('s')
                        '8' = @('B')
                    }
                    
                    $hasHomoglyphs = $false
                    foreach ($key in $homoglyphMap.Keys) {
                        if ($originalMainDomain.Contains($key)) {
                            foreach ($homoglyph in $homoglyphMap[$key]) {
                                if ($twistedMainDomain.Contains($homoglyph) -and -not $originalMainDomain.Contains($homoglyph)) {
                                    $hasHomoglyphs = $true
                                    $riskScore += $riskFactors.HasHomoglyphs
                                    $riskFactorsFound += "Contains homoglyphs"
                                    break
                                }
                            }
                            if ($hasHomoglyphs) { break }
                        }
                    }
                    
                    # Also check for numeric substitutions (e.g., "3" for "e")
                    if (-not $hasHomoglyphs) {
                        $numericSubstitutions = @{
                            '0' = 'o'
                            '1' = 'i' 
                            '2' = 'z'
                            '3' = 'e'
                            '4' = 'a'
                            '5' = 's'
                            '7' = 't'
                            '8' = 'b'
                            '9' = 'g'
                        }
                        foreach ($num in $numericSubstitutions.Keys) {
                            if ($twistedMainDomain.Contains($num) -and (-not $originalMainDomain.Contains($num))) {
                                $hasHomoglyphs = $true
                                $riskScore += $riskFactors.HasHomoglyphs
                                $riskFactorsFound += "Contains numeric homoglyphs"
                                break
                            }
                        }
                    }
                    
                    # 2. Check for character swaps (transposition)
                    for ($i = 0; $i -lt $originalMainDomain.Length - 1; $i++) {
                        $swappedString = $originalMainDomain.Substring(0, $i) + 
                                         $originalMainDomain[$i+1] + 
                                         $originalMainDomain[$i] + 
                                         $originalMainDomain.Substring($i+2)
                        if ($twistedMainDomain -eq $swappedString) {
                            $riskScore += $riskFactors.HasCharacterSwap
                            $riskFactorsFound += "Character swapping"
                            break
                        }
                    }
                    
                    # 3. Check for missing characters
                    if ($twistedMainDomain.Length -eq ($originalMainDomain.Length - 1)) {
                        # Test if removing one character from the original domain can produce the twisted domain
                        $isMissingChar = $false
                        for ($i = 0; $i -lt $originalMainDomain.Length; $i++) {
                            $shortened = $originalMainDomain.Remove($i, 1)
                            if ($twistedMainDomain -eq $shortened) {
                                $isMissingChar = $true
                                break
                            }
                        }
                        
                        if ($isMissingChar) {
                            $riskScore += $riskFactors.HasMissingChar
                            $riskFactorsFound += "Missing character"
                        }
                    }
                    
                    # 4. Check for extra characters
                    if ($twistedMainDomain.Length -eq ($originalMainDomain.Length + 1)) {
                        # Try to determine if it's an extra character rather than a completely different domain
                        for ($i = 0; $i -lt $twistedMainDomain.Length; $i++) {
                            $shortened = $twistedMainDomain.Remove($i, 1)
                            if ($shortened -eq $originalMainDomain) {
                                $riskScore += $riskFactors.HasExtraChar
                                $riskFactorsFound += "Extra character"
                                break
                            }
                        }
                    }
                    
                    # 5. Check for keyboard typos (adjacent keys)
                    if ($twistedMainDomain.Length -eq $originalMainDomain.Length) {
                        $keyboard = @{
                            'a' = @('q', 'w', 's', 'z')
                            'b' = @('v', 'g', 'h', 'n')
                            'c' = @('x', 'd', 'f', 'v')
                            'd' = @('s', 'e', 'r', 'f', 'c', 'x')
                            'e' = @('w', 's', 'd', 'r')
                            'f' = @('d', 'r', 't', 'g', 'v', 'c')
                            'g' = @('f', 't', 'y', 'h', 'b', 'v')
                            'h' = @('g', 'y', 'u', 'j', 'n', 'b')
                            'i' = @('u', 'j', 'k', 'o')
                            'j' = @('h', 'u', 'i', 'k', 'm', 'n')
                            'k' = @('j', 'i', 'o', 'l', 'm')
                            'l' = @('k', 'o', 'p', 'm')
                            'm' = @('n', 'j', 'k', 'l')
                            'n' = @('b', 'h', 'j', 'm')
                            'o' = @('i', 'k', 'l', 'p')
                            'p' = @('o', 'l')
                            'q' = @('w', 'a')
                            'r' = @('e', 'd', 'f', 't')
                            's' = @('a', 'w', 'e', 'd', 'x', 'z')
                            't' = @('r', 'f', 'g', 'y')
                            'u' = @('y', 'h', 'j', 'i')
                            'v' = @('c', 'f', 'g', 'b')
                            'w' = @('q', 'a', 's', 'e')
                            'x' = @('z', 's', 'd', 'c')
                            'y' = @('t', 'g', 'h', 'u')
                            'z' = @('a', 's', 'x')
                        }
                        
                        for ($i = 0; $i -lt $originalMainDomain.Length; $i++) {
                            $char = $originalMainDomain[$i].ToString().ToLower()
                            if ($keyboard.ContainsKey($char) -and $i -lt $twistedMainDomain.Length) {
                                if ($keyboard[$char] -contains $twistedMainDomain[$i].ToString().ToLower()) {
                                    $riskScore += $riskFactors.HasKeyboardTypo
                                    $riskFactorsFound += "Keyboard adjacency typo"
                                    break
                                }
                            }
                        }
                    }
                    
                    # 6. Check for TLD variation
                    if ($originalTld -ne $twistedTld) {
                        $riskScore += $riskFactors.IsTldVariation
                        $riskFactorsFound += "TLD variation"
                        
                        # Add extra risk for suspicious TLDs often used for phishing
                        $suspiciousTlds = @('.xyz', '.info', '.cc', '.tk', '.pw', '.ml', '.ga')
                        foreach ($susptld in $suspiciousTlds) {
                            if ($twistedTld.EndsWith($susptld)) {
                                $riskScore = [Math]::Round($riskScore * $riskFactors.SuspiciousTLDMultiplier)
                                $riskFactorsFound += "Suspicious TLD"
                                break
                            }
                        }
                    }
                    
                    # 7. Check for hyphens
                    if ($twistedMainDomain.Contains('-') -and -not $originalMainDomain.Contains('-')) {
                        $riskScore += $riskFactors.HasHyphen
                        $riskFactorsFound += "Added hyphen"
                    }

                    # 8. Check registration date if available
                    if ($registrationInfo.Created) {
                        try {
                            $creationDate = [DateTime]::Parse($registrationInfo.Created)
                            if ($creationDate -gt $recentRegistrationThreshold) {
                                $riskScore += $riskFactors.IsRecentlyRegistered
                                $riskFactorsFound += "Recently registered"
                                
                                # Add graduated risk - newer domains are riskier
                                $daysSinceCreation = (Get-Date) - $creationDate
                                if ($daysSinceCreation.TotalDays -lt 30) {
                                    $riskScore += 10  # Very recent registration (additional risk)
                                    $riskFactorsFound[-1] = "Very recently registered (<30 days)"
                                }
                            }
                        } 
                        catch {
                            Write-Verbose "Could not parse creation date: $($registrationInfo.Created)"
                        }
                    }
                    
                    # 9. Check for privacy protection/missing WHOIS data
                    if ($registrationInfo.Registrar -match "privacy|protect|guard|redact|anonymous|private" -or 
                        $registrationInfo.Registrar -eq "Unknown Registrar" -or 
                        $registrationInfo.Registrar -eq "Unknown (Parser Error)") {
                        $riskScore += $riskFactors.HasPrivacyProtection
                        $riskFactorsFound += "Privacy protected/Limited WHOIS"
                    }
                    
                    # 10. Check for suspicious name servers
                    if ($registrationInfo.NameServers) {
                        $suspiciousNameServerPatterns = @(
                            'park', 'ondisplay', 'suspended', 'hostinger', 'namecheap.com',
                            'dynamicdns', 'afraid.org', 'noip.com', 'ddns', 'strangled.net'
                        )
                        
                        foreach ($pattern in $suspiciousNameServerPatterns) {
                            if ($registrationInfo.NameServers -match $pattern) {
                                $riskScore += $riskFactors.HasSuspiciousNameServer
                                $riskFactorsFound += "Suspicious nameservers"
                                break
                            }
                        }
                    }
                }
                
                # Normalize risk score to 0-100 range
                if ($riskScore -gt 100) { $riskScore = 100 }
                
                # Determine risk level text
                $riskLevel = switch ($riskScore) {
                    {$_ -ge 80} { "Very High" }
                    {$_ -ge 60} { "High" }
                    {$_ -ge 40} { "Medium" }
                    {$_ -ge 20} { "Low" }
                    default { "Very Low" }
                }

                # Create result object with risk information
                $result = [PSCustomObject]@{
                    Domain = $twistedDomain
                    Status = $registrationInfo.Status
                    RiskScore = $riskScore
                    RiskLevel = $riskLevel
                    RiskFactors = $riskFactorsFound -join ", "
                }
                
                # Add registration info properties if available
                if ($registrationInfo.Status -eq "Registered") {
                    Add-Member -InputObject $result -MemberType NoteProperty -Name "Registrar" -Value $registrationInfo.Registrar
                    if ($registrationInfo.Created) {
                        Add-Member -InputObject $result -MemberType NoteProperty -Name "Created" -Value $registrationInfo.Created
                    }
                    if ($registrationInfo.Expires) {
                        Add-Member -InputObject $result -MemberType NoteProperty -Name "Expires" -Value $registrationInfo.Expires
                    }
                    if ($registrationInfo.NameServers) {
                        Add-Member -InputObject $result -MemberType NoteProperty -Name "NameServers" -Value $registrationInfo.NameServers
                    }
                } else {
                    if ($registrationInfo.Message) {
                        Add-Member -InputObject $result -MemberType NoteProperty -Name "Message" -Value $registrationInfo.Message
                    }
                }
                
                $results.Add($result)
                $processedCount++
            }
            
            # Sort results by risk score (descending)
            return $results | Sort-Object -Property RiskScore -Descending
        }
        catch {
            Write-Error "Error in Test-DnsTwistDomain: $($_.Exception.Message)"
        }
    }

    end {
        Write-Verbose "Test-DnsTwistDomain completed"
    }
}
