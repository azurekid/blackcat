function Invoke-StealthOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Random", "Progressive", "BusinessHours", "Exponential")]
        [string]$DelayType = "Random",

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 600)]
        [int]$MinDelay = 1,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 3600)]
        [int]$MaxDelay = 5,

        [Parameter(Mandatory = $false)]
        [switch]$Silent,

        [Parameter(Mandatory = $false)]
        [ValidateSet("US", "UK", "EU", "JP", "AU", "ES", "IT", "FR", "MX", "CN", "BR", "IN", "KR")]
        [string]$Country = "EU",

        [Parameter(Mandatory = $false)]
        [string]$TimeZone = $null,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0.0, 1.0)]
        [double]$Jitter = 0.2
    )

    begin {
        Write-Verbose " Starting stealth pipeline with $DelayType timing"
        $itemCount = 0
        
        # Business hours mapping for different countries with cultural patterns
        $businessHours = @{
            "US" = @{ Start = 9; End = 17; TimeZone = "Eastern Standard Time"; LunchBreak = $false }
            "UK" = @{ Start = 9; End = 17; TimeZone = "GMT Standard Time"; LunchBreak = $false }
            "EU" = @{ Start = 9; End = 17; TimeZone = "W. Europe Standard Time"; LunchBreak = $false }
            "JP" = @{ Start = 9; End = 18; TimeZone = "Tokyo Standard Time"; LunchBreak = $false }
            "AU" = @{ Start = 9; End = 17; TimeZone = "AUS Eastern Standard Time"; LunchBreak = $false }
            "ES" = @{ Start = 9; End = 14; End2 = 17; End2Close = 20; TimeZone = "Romance Standard Time"; LunchBreak = $true; LunchStart = 14; LunchEnd = 17; SiestaPattern = $true }
            "IT" = @{ Start = 9; End = 13; End2 = 14; End2Close = 18; TimeZone = "W. Europe Standard Time"; LunchBreak = $true; LunchStart = 13; LunchEnd = 14; SiestaPattern = $true }
            "FR" = @{ Start = 9; End = 12; End2 = 14; End2Close = 17; TimeZone = "Romance Standard Time"; LunchBreak = $true; LunchStart = 12; LunchEnd = 14; WorkWeekHours = 35 }
            "MX" = @{ Start = 9; End = 14; End2 = 16; End2Close = 19; TimeZone = "Central Standard Time (Mexico)"; LunchBreak = $true; LunchStart = 14; LunchEnd = 16; SiestaPattern = $true }
            "CN" = @{ Start = 9; End = 12; End2 = 14; End2Close = 18; TimeZone = "China Standard Time"; LunchBreak = $true; LunchStart = 12; LunchEnd = 14; NoonNap = $true }
            "BR" = @{ Start = 8; End = 12; End2 = 13; End2Close = 17; TimeZone = "E. South America Standard Time"; LunchBreak = $true; LunchStart = 12; LunchEnd = 13 }
            "IN" = @{ Start = 9; End = 18; TimeZone = "India Standard Time"; LunchBreak = $false; ExtendedHours = $true }
            "KR" = @{ Start = 9; End = 18; TimeZone = "Korea Standard Time"; LunchBreak = $false; LongWorkCulture = $true }
        }
    }

    process {
        # Calculate stealth delay based on type
        $calculatedDelay = 0
        $businessConfigDescription = $null  # Store for delay message
        
        switch ($DelayType) {
            "Random" {
                $calculatedDelay = Get-Random -Minimum $MinDelay -Maximum $MaxDelay
            }
            
            "Progressive" {
                $step = $itemCount + 1
                $calculatedDelay = $MinDelay + ($step * 0.5)
                if ($calculatedDelay -gt $MaxDelay) {
                    $calculatedDelay = $MaxDelay
                }
            }
            
            "BusinessHours" {
                # Determine timezone and business hours configuration
                $targetTimeZone = $null
                $businessConfig = $null
                
                if ($TimeZone) {
                    # When TimeZone is specified, use generic business hours pattern
                    $businessConfig = @{ 
                        Start = 9; 
                        End = 17; 
                        LunchBreak = $false;
                        Description = "Generic"
                    }
                    
                    # Check if TimeZone is UTC offset format (+2, -5, +5.5, etc.)
                    if ($TimeZone -match '^[+-]\d+(?:\.\d+)?$') {
                        try {
                            $offsetHours = [double]$TimeZone
                            $offsetTimeSpan = [TimeSpan]::FromHours($offsetHours)
                            $targetTimeZone = [System.TimeZoneInfo]::CreateCustomTimeZone(
                                "Custom_UTC$TimeZone",
                                $offsetTimeSpan,
                                "Custom UTC$TimeZone",
                                "Custom UTC$TimeZone"
                            )
                            $businessConfig.Description = "UTC$TimeZone"
                            $businessConfigDescription = $businessConfig.Description
                            Write-Verbose " Using custom UTC offset: $TimeZone with generic business hours"
                        }
                        catch {
                            Write-Warning " Invalid UTC offset format '$TimeZone'. Using country default."
                            $businessConfig = $businessHours[$Country]
                            if (-not $businessConfig) { 
                                $businessConfig = $businessHours["US"]
                                $businessConfigDescription = "US"
                            } else {
                                $businessConfigDescription = $Country
                            }
                            $targetTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById($businessConfig.TimeZone)
                        }
                    }
                    else {
                        # Try to use as timezone name
                        try {
                            $targetTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById($TimeZone)
                            $businessConfig.Description = $TimeZone
                            $businessConfigDescription = $businessConfig.Description
                            Write-Verbose " Using specified timezone: $TimeZone with generic business hours"
                        }
                        catch {
                            Write-Warning " Timezone '$TimeZone' not found. Using country default."
                            $businessConfig = $businessHours[$Country]
                            if (-not $businessConfig) { 
                                $businessConfig = $businessHours["US"]
                                $businessConfigDescription = "US"
                            } else {
                                $businessConfigDescription = $Country
                            }
                            $targetTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById($businessConfig.TimeZone)
                        }
                    }
                }
                else {
                    # Use country-specific business hours and timezone
                    $businessConfig = $businessHours[$Country]
                    if (-not $businessConfig) {
                        $businessConfig = $businessHours["US"]  # Default fallback
                        $businessConfigDescription = "US"
                    } else {
                        $businessConfigDescription = $Country
                    }
                    $targetTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById($businessConfig.TimeZone)
                    Write-Verbose " Using country-specific configuration: $Country"
                }
                try {
                    $localTime = [System.TimeZoneInfo]::ConvertTimeFromUtc((Get-Date).ToUniversalTime(), $targetTimeZone)
                }
                catch {
                    $localTime = Get-Date  # Fallback to system time
                }
                
                $currentHour = $localTime.Hour
                $isWeekday = $localTime.DayOfWeek -notin @([DayOfWeek]::Saturday, [DayOfWeek]::Sunday)
                
                # Determine if currently in business hours based on configuration
                $isBusinessHours = $false
                
                if ($businessConfig.LunchBreak) {
                    # Countries with lunch break/siesta patterns (ES, IT, FR, MX, CN, BR)
                    $morningHours = $currentHour -ge $businessConfig.Start -and $currentHour -lt $businessConfig.End
                    
                    if ($businessConfig.End2 -and $businessConfig.End2Close) {
                        $afternoonHours = $currentHour -ge $businessConfig.End2 -and $currentHour -lt $businessConfig.End2Close
                        $isBusinessHours = $morningHours -or $afternoonHours
                    } else {
                        $isBusinessHours = $morningHours
                    }
                    
                    # Check if currently in lunch/siesta break
                    $isLunchBreak = $currentHour -ge $businessConfig.LunchStart -and $currentHour -lt $businessConfig.LunchEnd
                } else {
                    # Standard business hours (US, UK, DE, JP, AU, IN, KR, or generic)
                    $isBusinessHours = $currentHour -ge $businessConfig.Start -and $currentHour -lt $businessConfig.End
                }
                
                # Check if we need to wait for business hours (default behavior for BusinessHours timing)
                if (-not $isBusinessHours -or -not $isWeekday) {
                    $waitSeconds = 0
                    
                    if (-not $isWeekday) {
                        # Calculate time until next Monday
                        $daysUntilMonday = (8 - [int]$localTime.DayOfWeek) % 7
                        if ($daysUntilMonday -eq 0) { $daysUntilMonday = 1 } # If it's Sunday, wait until Monday
                        
                        $nextBusinessDay = $localTime.Date.AddDays($daysUntilMonday).AddHours($businessConfig.Start)
                        $waitSeconds = ($nextBusinessDay - $localTime).TotalSeconds
                    }
                    elseif ($businessConfig.LunchBreak -and $isLunchBreak) {
                        # Currently in lunch break - wait until afternoon session
                        if ($businessConfig.End2) {
                            $afternoonStart = $localTime.Date.AddHours($businessConfig.End2)
                            $waitSeconds = ($afternoonStart - $localTime).TotalSeconds
                        }
                    }
                    elseif ($currentHour -lt $businessConfig.Start) {
                        # Wait until business hours start today
                        $businessStart = $localTime.Date.AddHours($businessConfig.Start)
                        $waitSeconds = ($businessStart - $localTime).TotalSeconds
                    }
                    elseif ($businessConfig.LunchBreak -and $businessConfig.End2Close -and $currentHour -ge $businessConfig.End2Close) {
                        # After business hours for lunch break countries
                        $nextDay = $localTime.Date.AddDays(1)
                        if ($nextDay.DayOfWeek -eq [DayOfWeek]::Saturday) {
                            $nextDay = $nextDay.AddDays(2) # Skip to Monday
                        }
                        elseif ($nextDay.DayOfWeek -eq [DayOfWeek]::Sunday) {
                            $nextDay = $nextDay.AddDays(1) # Skip to Monday
                        }
                        
                        $nextBusinessStart = $nextDay.AddHours($businessConfig.Start)
                        $waitSeconds = ($nextBusinessStart - $localTime).TotalSeconds
                    }
                    elseif (-not $businessConfig.LunchBreak -and $currentHour -ge $businessConfig.End) {
                        # After standard business hours
                        $nextDay = $localTime.Date.AddDays(1)
                        if ($nextDay.DayOfWeek -eq [DayOfWeek]::Saturday) {
                            $nextDay = $nextDay.AddDays(2) # Skip to Monday
                        }
                        elseif ($nextDay.DayOfWeek -eq [DayOfWeek]::Sunday) {
                            $nextDay = $nextDay.AddDays(1) # Skip to Monday
                        }
                        
                        $nextBusinessStart = $nextDay.AddHours($businessConfig.Start)
                        $waitSeconds = ($nextBusinessStart - $localTime).TotalSeconds
                    }
                    
                    if ($waitSeconds -gt 0) {
                        $waitHours = [Math]::Floor($waitSeconds / 3600)
                        $waitMinutes = [Math]::Floor(($waitSeconds % 3600) / 60)
                        
                        if (-not $Silent) {
                            $configDescription = if ($TimeZone) { $businessConfig.Description } else { $Country }
                            $waitMessage = if ($isLunchBreak -and $businessConfig.SiestaPattern) {
                                if ($waitHours -gt 0) {
                                    " Waiting {0}h {1}m until {2} siesta/lunch break ends..." -f $waitHours, $waitMinutes, $configDescription
                                } else {
                                    " Waiting {0}m until {1} siesta/lunch break ends..." -f $waitMinutes, $configDescription
                                }
                            } elseif ($waitHours -gt 0) {
                                " Waiting {0}h {1}m until {2} business hours begin..." -f $waitHours, $waitMinutes, $configDescription
                            } else {
                                " Waiting {0}m until {1} business hours begin..." -f $waitMinutes, $configDescription
                            }
                            Write-Host "  $waitMessage" -ForegroundColor Magenta
                        }
                        
                        Start-Sleep -Seconds $waitSeconds
                        
                        # Recalculate current time after waiting using the same timezone logic
                        $localTime = [System.TimeZoneInfo]::ConvertTimeFromUtc((Get-Date).ToUniversalTime(), $targetTimeZone)
                        $currentHour = $localTime.Hour
                        $isWeekday = $localTime.DayOfWeek -notin @([DayOfWeek]::Saturday, [DayOfWeek]::Sunday)
                        
                        # Recalculate business hours status
                        if ($businessConfig.LunchBreak) {
                            $morningHours = $currentHour -ge $businessConfig.Start -and $currentHour -lt $businessConfig.End
                            if ($businessConfig.End2 -and $businessConfig.End2Close) {
                                $afternoonHours = $currentHour -ge $businessConfig.End2 -and $currentHour -lt $businessConfig.End2Close
                                $isBusinessHours = $morningHours -or $afternoonHours
                            } else {
                                $isBusinessHours = $morningHours
                            }
                        } else {
                            $isBusinessHours = $currentHour -ge $businessConfig.Start -and $currentHour -lt $businessConfig.End
                        }
                    }
                }
                
                # Apply appropriate delays based on activity level
                if ($isBusinessHours -and $isWeekday) {
                    # Active business hours - shorter delays
                    $calculatedDelay = Get-Random -Minimum $MinDelay -Maximum ([Math]::Min($MaxDelay, $MinDelay + 3))
                }
                elseif ($businessConfig.LunchBreak -and $isLunchBreak -and $isWeekday) {
                    # Lunch/siesta time - moderate delays (some reduced activity)
                    $lunchMin = [Math]::Max($MinDelay, 5)
                    $lunchMax = [Math]::Max([Math]::Min($MaxDelay, 15), $lunchMin + 1)
                    $calculatedDelay = Get-Random -Minimum $lunchMin -Maximum $lunchMax
                }
                else {
                    # Outside business hours - longer delays to simulate reduced activity
                    $outsideHoursMin = [Math]::Max($MinDelay, 10)
                    $outsideHoursMax = [Math]::Max($MaxDelay, $outsideHoursMin + 1)
                    $calculatedDelay = Get-Random -Minimum $outsideHoursMin -Maximum $outsideHoursMax
                }
            }
            
            "Exponential" {
                $retryCount = $itemCount + 1
                $baseDelay = [Math]::Max($MinDelay, 1)
                $calculatedDelay = $baseDelay * [Math]::Pow(2, [Math]::Min($retryCount - 1, 6))  # Cap at 2^6
                if ($calculatedDelay -gt $MaxDelay) {
                    $calculatedDelay = $MaxDelay
                }
            }
        }
        
        # Apply jitter to prevent pattern detection
        if ($Jitter -gt 0) {
            $jitterAmount = $calculatedDelay * $Jitter * (Get-Random -Minimum -1.0 -Maximum 1.0)
            $calculatedDelay = [Math]::Max(0, $calculatedDelay + $jitterAmount)
        }
        
        # Round to reasonable precision
        $calculatedDelay = [Math]::Round($calculatedDelay, 1)
        
        # Apply the delay
        if ($calculatedDelay -gt 0) {
            if (-not $Silent) {
                $delayMessage = switch ($DelayType) {
                    "BusinessHours" {
                        $timeInfo = " ($businessConfigDescription)"
                        # Context-aware emoji based on configuration
                        $emoji = if ($TimeZone) { "" } else { "" }
                        "$emoji Stealth delay: {0}s (BusinessHours{1})" -f $calculatedDelay, $timeInfo
                    }
                    "Progressive" {
                        " Stealth delay: {0}s (Progressive - Step {1})" -f $calculatedDelay, ($itemCount + 1)
                    }
                    "Exponential" {
                        " Stealth delay: {0}s (Exponential - Level {1})" -f $calculatedDelay, ($itemCount + 1)
                    }
                    default {
                        " Stealth delay: {0}s ({1})" -f $calculatedDelay, $DelayType
                    }
                }
                Write-Host "  $delayMessage" -ForegroundColor DarkYellow
            }
            
            Start-Sleep -Seconds $calculatedDelay
        }

        # Pass through the input object
        if ($PSBoundParameters.ContainsKey('InputObject')) {
            Write-Output $InputObject
        }

        $itemCount++
    }

    end {
        Write-Verbose " Stealth pipeline completed for $itemCount items"
    }
<#
    .SYNOPSIS
        Executes operations with configurable stealth timing delays.

    .DESCRIPTION
        Invoke-StealthOperation processes input objects through a pipeline while applying
        intelligent timing delays to avoid detection patterns. The function supports multiple
        delay strategies including random intervals, progressive timing, business hours
        simulation, and exponential backoff patterns.

        Ideal for scenarios requiring rate limiting, anti-detection measures, or simulating
        human-like interaction patterns in automated operations.

    .PARAMETER InputObject
        Objects to process through the stealth pipeline. Accepts pipeline input.

    .PARAMETER DelayType
        Specifies the delay pattern strategy:
        - Random: Random delays between min and max values
        - Progressive: Incrementally increasing delays per item
        - BusinessHours: Simulates activity during business hours (automatically waits for business hours)
        - Exponential: Exponential backoff pattern for each item
        Default: Random

    .PARAMETER MinDelay
        Minimum delay duration in seconds (0-600). Default: 1

    .PARAMETER MaxDelay
        Maximum delay duration in seconds (1-3600). Default: 5

    .PARAMETER Silent
        Suppresses delay notification messages when specified.

    .PARAMETER Country
        Two-letter country code for business hours timing. Valid values:
        US, UK, EU, JP, AU, ES, IT, FR, MX, CN, BR, IN, KR.
        Only used when DelayType is BusinessHours. Default: "US"

    .PARAMETER TimeZone
        Override timezone for business hours calculation. Supports timezone names
        (e.g., "Pacific Standard Time") or UTC offset notation (e.g., "+2", "-5", "+5.5").
        Only used when DelayType is BusinessHours.

    .PARAMETER Jitter
        Random jitter percentage to add to delays (0.0-1.0).
        Adds randomness to prevent pattern detection. Default: 0.2

    .EXAMPLE
        Invoke-StealthOperation | Find-PublicStorageContainer -StorageAccountName "test"        Executes storage discovery with default random stealth timing.

    .EXAMPLE
        "example.com", "test.com" | Invoke-StealthOperation -DelayType BusinessHours -Country "UK" | ForEach-Object {
            Find-DnsRecords -Domain $_
        }

        Processes domains with UK business hours timing simulation.

    .EXAMPLE
        Get-Content domains.txt | Invoke-StealthOperation -MinDelay 30 -MaxDelay 180 -Silent | ForEach-Object {
            Find-SubDomain -Domain $_
        }

        Performs subdomain enumeration with extended delays (30-180 seconds) without status messages.

    .EXAMPLE
        1..10 | Invoke-StealthOperation -DelayType Exponential | ForEach-Object {
            Test-Connection -Count 1 -ComputerName "server$_"
        }

        Tests multiple servers with exponentially increasing delays between operations.

    .EXAMPLE
        "target.com" | Invoke-StealthOperation -DelayType BusinessHours -Country "UK" | ForEach-Object {
            Find-DnsRecords -Domain $_
        }

        Automatically waits until UK business hours before executing DNS reconnaissance.

    .EXAMPLE
        "target.com" | Invoke-StealthOperation -DelayType BusinessHours -Country "EU" -TimeZone "+2" | ForEach-Object {
            Find-DnsRecords -Domain $_
        }

        Uses German business culture with UTC+2 timezone offset for precise timing.

    .NOTES
        Built-in stealth delay implementation eliminates dependency on external functions.
        Consider network policies and rate limits when configuring delay parameters.

    .LINK
        MITRE ATT&CK Tactic: TA0005 - Defense Evasion
        https://attack.mitre.org/tactics/TA0005/

    .LINK
        MITRE ATT&CK Technique: T1562.003 - Impair Defenses: Impair Command History Logging
        https://attack.mitre.org/techniques/T1562/003/

    #>
}
