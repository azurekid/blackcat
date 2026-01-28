function Get-BlackCatCacheStats {
    <#
    .SYNOPSIS
        Displays comprehensive statistics about the BlackCat cache systems with advanced analytics and insights.

    .DESCRIPTION
        This function provides detailed information about the current cache state for BlackCat cache systems,
        including total entries, valid/expired entries, memory usage, hit rates, performance metrics,
        cache efficiency analysis, detailed cache key listings with advanced filtering capabilities,
        trend analysis, memory optimization recommendations, and export capabilities.

    .PARAMETER CacheType
        Specifies which cache type to display statistics for. Valid values are 'MSGraph', 'AzBatch', or 'All'.
        Default is 'All' which shows statistics for all cache types.

    .PARAMETER ShowDetails
        When specified, displays detailed information including individual cache entries and their metadata.

    .PARAMETER ShowPerformance
        When specified, displays performance metrics including hit rates, average response times, and efficiency statistics.

    .PARAMETER ShowTrends
        When specified, displays trend analysis including cache growth patterns and usage trends over time.

    .PARAMETER ShowRecommendations
        When specified, displays detailed optimization recommendations based on cache usage patterns.

    .PARAMETER FilterExpired
        When specified, shows only expired cache entries.

    .PARAMETER FilterValid
        When specified, shows only valid (non-expired) cache entries.

    .PARAMETER FilterCompressed
        When specified, shows only compressed cache entries.

    .PARAMETER FilterLarge
        When specified, shows only cache entries larger than 1MB.

    .PARAMETER MinSize
        Filters cache entries to show only those larger than the specified size in KB.

    .PARAMETER MaxAge
        Filters cache entries to show only those newer than the specified age in hours.

    .PARAMETER SortBy
        Specifies how to sort cache entries. Valid values are 'Timestamp', 'Size', 'Key', 'ExpirationTime', 'Age', 'TTL'.
        Default is 'Timestamp'.

    .PARAMETER OutputFormat
        Specifies the output format. Valid values are 'Table', 'List', 'JSON', 'Summary', 'CSV', 'XML'.
        Default is 'Summary'.

    .PARAMETER Top
        Limits the number of cache entries to display. Default shows all entries.

    .PARAMETER ExportPath
        When specified, exports the cache statistics to the specified file path.

    .PARAMETER IncludeHistogram
        When specified, displays size and age histograms for cache entries.

    .PARAMETER Quiet
        When specified, suppresses console output and only returns data objects.

    .EXAMPLE
        Get-BlackCatCacheStats

        This example displays a comprehensive summary of cache statistics for all cache types.

    .EXAMPLE
        Get-BlackCatCacheStats -CacheType MSGraph -ShowDetails -ShowTrends

        This example displays detailed statistics and trend analysis for Microsoft Graph API cache.

    .EXAMPLE
        Get-BlackCatCacheStats -ShowPerformance -ShowRecommendations -OutputFormat Table

        This example displays performance metrics and optimization recommendations in table format.

    .EXAMPLE
        Get-BlackCatCacheStats -FilterLarge -MinSize 512 -SortBy Size -Top 5

        This example shows the top 5 largest cache entries over 512KB sorted by size.

    .EXAMPLE
        Get-BlackCatCacheStats -OutputFormat JSON -ExportPath "cache-stats.json" -Quiet

        This example exports cache statistics to a JSON file without console output.

    .EXAMPLE
        Get-BlackCatCacheStats -IncludeHistogram -MaxAge 24 -ShowTrends

        This example shows cache statistics with histograms for entries newer than 24 hours and trend analysis.

    .NOTES
        This function provides comprehensive cache analytics to help optimize cache performance and usage.
        Expired entries are automatically identified but not removed unless accessed through normal cache operations.
        Advanced features include trend analysis, optimization recommendations, and multiple export formats.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateSet('MSGraph', 'AzBatch', 'All')]
        [string]$CacheType = 'All',

        [Parameter(Mandatory = $false)]
        [switch]$ShowDetails,

        [Parameter(Mandatory = $false)]
        [switch]$ShowPerformance,

        [Parameter(Mandatory = $false)]
        [switch]$ShowTrends,

        [Parameter(Mandatory = $false)]
        [switch]$ShowRecommendations,

        [Parameter(Mandatory = $false)]
        [switch]$FilterExpired,

        [Parameter(Mandatory = $false)]
        [switch]$FilterValid,

        [Parameter(Mandatory = $false)]
        [switch]$FilterCompressed,

        [Parameter(Mandatory = $false)]
        [switch]$FilterLarge,

        [Parameter(Mandatory = $false)]
        [int]$MinSize = 0,

        [Parameter(Mandatory = $false)]
        [int]$MaxAge = 0,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Timestamp', 'Size', 'Key', 'ExpirationTime', 'Age', 'TTL')]
        [string]$SortBy = 'Timestamp',

        [Parameter(Mandatory = $false)]
        [ValidateSet('Table', 'List', 'JSON', 'Summary', 'CSV', 'XML')]
        [string]$OutputFormat = 'Summary',

        [Parameter(Mandatory = $false)]
        [int]$Top = 0,

        [Parameter(Mandatory = $false)]
        [string]$ExportPath,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeHistogram,

        [Parameter(Mandatory = $false)]
        [switch]$Quiet
    )

    begin {
        $startTime = Get-Date
        $cacheTypes = if ($CacheType -eq 'All') { @('MSGraph', 'AzBatch') } else { @($CacheType) }
        $allCacheData = @()
        $performanceData = @{}
        $trendData = @{}
        $histogramData = @{}
        
        # Helper function for creating histograms
        function New-Histogram {
            param($Data, $Property, $BucketCount = 10)
            
            if (-not $Data -or $Data.Count -eq 0) { return @() }
            
            $values = $Data | ForEach-Object { $_.$Property }
            $min = ($values | Measure-Object -Minimum).Minimum
            $max = ($values | Measure-Object -Maximum).Maximum
            
            if ($min -eq $max) { 
                return @([PSCustomObject]@{ Range = "$min"; Count = $Data.Count; Percentage = 100 })
            }
            
            $bucketSize = ($max - $min) / $BucketCount
            $buckets = @{}
            
            foreach ($value in $values) {
                $bucketIndex = [math]::Floor(($value - $min) / $bucketSize)
                if ($bucketIndex -eq $BucketCount) { $bucketIndex = $BucketCount - 1 }
                
                $bucketStart = $min + ($bucketIndex * $bucketSize)
                $bucketEnd = $bucketStart + $bucketSize
                $bucketKey = "$([math]::Round($bucketStart, 2))-$([math]::Round($bucketEnd, 2))"
                
                if (-not $buckets.ContainsKey($bucketKey)) {
                    $buckets[$bucketKey] = 0
                }
                $buckets[$bucketKey]++
            }
            
            $total = $Data.Count
            return $buckets.GetEnumerator() | ForEach-Object {
                [PSCustomObject]@{
                    Range = $_.Key
                    Count = $_.Value
                    Percentage = [math]::Round(($_.Value / $total) * 100, 1)
                }
            } | Sort-Object Range
        }
        
        # Helper function for trend analysis
        function Get-TrendAnalysis {
            param($Entries, $CacheType)
            
            if (-not $Entries -or $Entries.Count -eq 0) {
                return @{
                    GrowthRate = 0
                    PeakUsageHour = "N/A"
                    AverageAge = 0
                    TurnoverRate = 0
                    Prediction = "Insufficient data"
                }
            }
            
            $now = Get-Date
            $hoursData = @{}
            $ageStats = $Entries | ForEach-Object { $_.Age.TotalHours }
            
            # Group entries by hour for trend analysis
            foreach ($entry in $Entries) {
                $hour = $entry.Timestamp.Hour
                if (-not $hoursData.ContainsKey($hour)) {
                    $hoursData[$hour] = 0
                }
                $hoursData[$hour]++
            }
            
            $peakHour = if ($hoursData.Count -gt 0) {
                ($hoursData.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
            } else { "N/A" }
            
            $avgAge = if ($ageStats) { ($ageStats | Measure-Object -Average).Average } else { 0 }
            $validEntries = $Entries | Where-Object { -not $_.IsExpired }
            $turnoverRate = if ($Entries.Count -gt 0) { 
                (($Entries.Count - $validEntries.Count) / $Entries.Count) * 100 
            } else { 0 }
            
            # Simple growth prediction
            $recentEntries = $Entries | Where-Object { $_.Age.TotalHours -lt 24 }
            $growthRate = if ($Entries.Count -gt 0) {
                ($recentEntries.Count / $Entries.Count) * 100
            } else { 0 }
            
            $prediction = if ($growthRate -gt 50) {
                "High growth - consider memory optimization"
            } elseif ($growthRate -gt 20) {
                "Moderate growth - monitor usage"
            } elseif ($turnoverRate -gt 60) {
                "High turnover - consider longer expiration"
            } else {
                "Stable usage pattern"
            }
            
            return @{
                GrowthRate = [math]::Round($growthRate, 2)
                PeakUsageHour = $peakHour
                AverageAge = [math]::Round($avgAge, 2)
                TurnoverRate = [math]::Round($turnoverRate, 2)
                Prediction = $prediction
                HourlyDistribution = $hoursData
            }
        }
    }

    process {
        # Collect comprehensive cache data
        foreach ($type in $cacheTypes) {
            $cacheStore = Get-CacheStore -CacheType $type
            
            if (-not $cacheStore -or -not $cacheStore.Value -or $cacheStore.Value.Count -eq 0) {
                $performanceData[$type] = @{
                    Type = $type
                    Status = 'Uninitialized'
                    TotalEntries = 0
                    ValidEntries = 0
                    ExpiredEntries = 0
                    TotalSizeMB = 0
                    AverageEntrySize = 0
                    OldestEntry = $null
                    NewestEntry = $null
                    HitRate = 0
                    MemoryEfficiency = 0
                }
                continue
            }

            $entries = @()
            $totalSize = 0
            $validCount = 0
            $expiredCount = 0
            $compressedCount = 0
            $timestamps = @()

            foreach ($key in $cacheStore.Value.Keys) {
                $entry = $cacheStore.Value[$key]
                $isExpired = Test-CacheEntryExpired -CacheEntry $entry
                $entrySize = if ($entry.Size) { $entry.Size } else { 
                    ($entry.Data | ConvertTo-Json -Depth 10 -Compress | Measure-Object -Character).Characters 
                }
                
                $entryInfo = [PSCustomObject]@{
                    CacheType = $type
                    Key = $key
                    Timestamp = $entry.Timestamp
                    ExpirationTime = $entry.Timestamp.AddMinutes($entry.ExpirationMinutes)
                    Age = ((Get-Date) - $entry.Timestamp)
                    TTL = ($entry.Timestamp.AddMinutes($entry.ExpirationMinutes) - (Get-Date))
                    IsExpired = $isExpired
                    IsCompressed = if ($entry.PSObject.Properties['IsCompressed']) { $entry.IsCompressed } else { $false }
                    Size = $entrySize
                    SizeMB = [math]::Round($entrySize / 1MB, 3)
                    ExpirationMinutes = $entry.ExpirationMinutes
                    Status = if ($isExpired) { 'Expired' } else { 'Valid' }
                }

                $entries += $entryInfo
                $totalSize += $entrySize
                $timestamps += $entry.Timestamp

                if ($isExpired) { 
                    $expiredCount++ 
                } else { 
                    $validCount++ 
                }

                if ($entryInfo.IsCompressed) {
                    $compressedCount++
                }
            }

            # Calculate performance metrics
            $totalEntries = $entries.Count
            $averageSize = if ($totalEntries -gt 0) { $totalSize / $totalEntries } else { 0 }
            $oldestEntry = if ($timestamps) { ($timestamps | Sort-Object)[0] } else { $null }
            $newestEntry = if ($timestamps) { ($timestamps | Sort-Object -Descending)[0] } else { $null }
            $memoryEfficiency = if ($totalSize -gt 0 -and $compressedCount -gt 0) { 
                [math]::Round(($compressedCount / $totalEntries) * 100, 2) 
            } else { 0 }

            # Enhanced performance metrics
            $hitRate = if ($totalEntries -gt 0) { 
                [math]::Round((($validCount / $totalEntries) * 100), 2) 
            } else { 0 }
            
            $compressionRatio = if ($compressedCount -gt 0 -and $totalEntries -gt 0) {
                [math]::Round(($compressedCount / $totalEntries) * 100, 2)
            } else { 0 }
            
            $memoryDensity = if ($totalEntries -gt 0) {
                [math]::Round($totalSize / $totalEntries, 0)
            } else { 0 }

            $performanceData[$type] = @{
                Type = $type
                Status = 'Active'
                TotalEntries = $totalEntries
                ValidEntries = $validCount
                ExpiredEntries = $expiredCount
                CompressedEntries = $compressedCount
                TotalSizeBytes = $totalSize
                TotalSizeMB = [math]::Round($totalSize / 1MB, 3)
                AverageEntrySize = [math]::Round($averageSize, 0)
                AverageEntrySizeKB = [math]::Round($averageSize / 1KB, 2)
                OldestEntry = $oldestEntry
                NewestEntry = $newestEntry
                CacheSpan = if ($oldestEntry -and $newestEntry) { $newestEntry - $oldestEntry } else { $null }
                MemoryEfficiency = $memoryEfficiency
                ExpirationRate = if ($totalEntries -gt 0) { [math]::Round(($expiredCount / $totalEntries) * 100, 2) } else { 0 }
                HitRate = $hitRate
                CompressionRatio = $compressionRatio
                MemoryDensity = $memoryDensity
                CacheUtilization = if ($totalEntries -gt 0) { [math]::Round(($validCount / $totalEntries) * 100, 2) } else { 0 }
            }

            # Generate trend analysis if requested
            if ($ShowTrends -and $entries.Count -gt 0) {
                $trendData[$type] = Get-TrendAnalysis -Entries $entries -CacheType $type
            }

            # Generate histogram data if requested
            if ($IncludeHistogram -and $entries.Count -gt 0) {
                $histogramData[$type] = @{
                    SizeHistogram = New-Histogram -Data $entries -Property "SizeMB" -BucketCount 8
                    AgeHistogram = New-Histogram -Data ($entries | ForEach-Object { [PSCustomObject]@{ AgeHours = $_.Age.TotalHours } }) -Property "AgeHours" -BucketCount 6
                }
            }

            $allCacheData += $entries
        }

        # Apply advanced filters
        if ($FilterExpired) {
            $allCacheData = $allCacheData | Where-Object { $_.IsExpired -eq $true }
        }
        if ($FilterValid) {
            $allCacheData = $allCacheData | Where-Object { $_.IsExpired -eq $false }
        }
        if ($FilterCompressed) {
            $allCacheData = $allCacheData | Where-Object { $_.IsCompressed -eq $true }
        }
        if ($FilterLarge) {
            $allCacheData = $allCacheData | Where-Object { $_.SizeMB -gt 1 }
        }
        if ($MinSize -gt 0) {
            $allCacheData = $allCacheData | Where-Object { ($_.Size / 1KB) -gt $MinSize }
        }
        if ($MaxAge -gt 0) {
            $allCacheData = $allCacheData | Where-Object { $_.Age.TotalHours -lt $MaxAge }
        }

        # Apply enhanced sorting
        switch ($SortBy) {
            'Size' { $allCacheData = $allCacheData | Sort-Object Size -Descending }
            'Key' { $allCacheData = $allCacheData | Sort-Object Key }
            'ExpirationTime' { $allCacheData = $allCacheData | Sort-Object ExpirationTime }
            'Age' { $allCacheData = $allCacheData | Sort-Object Age -Descending }
            'TTL' { $allCacheData = $allCacheData | Sort-Object TTL -Descending }
            default { $allCacheData = $allCacheData | Sort-Object Timestamp -Descending }
        }

        # Apply top limit
        if ($Top -gt 0 -and $allCacheData.Count -gt $Top) {
            $allCacheData = $allCacheData | Select-Object -First $Top
        }

        # Generate comprehensive output data
        $outputData = @{
            GeneratedAt = Get-Date
            CacheTypes = $cacheTypes
            Performance = $performanceData
            Trends = $trendData
            Histograms = $histogramData
            Entries = if ($ShowDetails) { $allCacheData } else { $null }
            Filters = @{
                CacheType = $CacheType
                FilterExpired = $FilterExpired.IsPresent
                FilterValid = $FilterValid.IsPresent
                FilterCompressed = $FilterCompressed.IsPresent
                FilterLarge = $FilterLarge.IsPresent
                MinSize = $MinSize
                MaxAge = $MaxAge
                SortBy = $SortBy
                Top = $Top
            }
            Summary = @{
                TotalCaches = $cacheTypes.Count
                ActiveCaches = ($performanceData.Values | Where-Object { $_.Status -eq 'Active' }).Count
                TotalEntries = ($performanceData.Values | Measure-Object -Property TotalEntries -Sum).Sum
                TotalSizeMB = ($performanceData.Values | Measure-Object -Property TotalSizeMB -Sum).Sum
                OverallHitRate = if (($performanceData.Values | Measure-Object -Property TotalEntries -Sum).Sum -gt 0) {
                    [math]::Round((($performanceData.Values | Measure-Object -Property ValidEntries -Sum).Sum / ($performanceData.Values | Measure-Object -Property TotalEntries -Sum).Sum) * 100, 2)
                } else { 0 }
            }
        }

        # Handle export if specified
        if ($ExportPath) {
            try {
                switch -Regex ($ExportPath) {
                    '\.json$' { 
                        $outputData | ConvertTo-Json -Depth 10 | Out-File -FilePath $ExportPath -Encoding UTF8
                        if (-not $Quiet) { Write-Host " Cache statistics exported to: $ExportPath" -ForegroundColor Green }
                    }
                    '\.xml$' { 
                        $outputData | ConvertTo-Xml -Depth 10 | Out-File -FilePath $ExportPath -Encoding UTF8
                        if (-not $Quiet) { Write-Host " Cache statistics exported to: $ExportPath" -ForegroundColor Green }
                    }
                    '\.csv$' { 
                        if ($allCacheData.Count -gt 0) {
                            $allCacheData | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
                            if (-not $Quiet) { Write-Host " Cache entries exported to: $ExportPath" -ForegroundColor Green }
                        } else {
                            if (-not $Quiet) { Write-Host "  No cache entries to export" -ForegroundColor Yellow }
                        }
                    }
                    default { 
                        $outputData | ConvertTo-Json -Depth 10 | Out-File -FilePath $ExportPath -Encoding UTF8
                        if (-not $Quiet) { Write-Host " Cache statistics exported to: $ExportPath (JSON format)" -ForegroundColor Green }
                    }
                }
            }
            catch {
                if (-not $Quiet) { Write-Host " Export failed: $($_.Exception.Message)" -ForegroundColor Red }
            }
        }

        # Return early if Quiet mode and data was exported
        if ($Quiet) {
            return $outputData
        }

        # Generate output based on format
        switch ($OutputFormat) {
            'JSON' {
                return ($outputData | ConvertTo-Json -Depth 8)
            }
            'XML' {
                return ($outputData | ConvertTo-Xml -Depth 8)
            }
            'CSV' {
                if ($allCacheData.Count -gt 0) {
                    return ($allCacheData | ConvertTo-Csv -NoTypeInformation)
                } else {
                    Write-Host "  No cache entries available for CSV format" -ForegroundColor Yellow
                    return ""
                }
            }
            'List' {
                Write-Host "=== BlackCat Cache Statistics (List Format) ===" -ForegroundColor Cyan
                Write-Host ""
                
                foreach ($type in $cacheTypes) {
                    $perf = $performanceData[$type]
                    Write-Host "Cache Type: $($perf.Type)" -ForegroundColor Yellow
                    Write-Host "  Status: $($perf.Status)" -ForegroundColor $(if ($perf.Status -eq 'Active') { 'Green' } else { 'Gray' })
                    Write-Host "  Total Entries: $($perf.TotalEntries)" -ForegroundColor White
                    Write-Host "  Valid Entries: $($perf.ValidEntries)" -ForegroundColor Green
                    Write-Host "  Expired Entries: $($perf.ExpiredEntries)" -ForegroundColor Red
                    Write-Host "  Compressed Entries: $($perf.CompressedEntries)" -ForegroundColor Cyan
                    Write-Host "  Total Size: $($perf.TotalSizeMB) MB" -ForegroundColor White
                    Write-Host "  Average Entry Size: $($perf.AverageEntrySizeKB) KB" -ForegroundColor White
                    Write-Host "  Memory Efficiency: $($perf.MemoryEfficiency)%" -ForegroundColor $(if ($perf.MemoryEfficiency -gt 50) { 'Green' } else { 'Yellow' })
                    Write-Host "  Expiration Rate: $($perf.ExpirationRate)%" -ForegroundColor $(if ($perf.ExpirationRate -lt 20) { 'Green' } elseif ($perf.ExpirationRate -lt 50) { 'Yellow' } else { 'Red' })
                    if ($perf.OldestEntry) {
                        Write-Host "  Cache Age: $([math]::Round(((Get-Date) - $perf.OldestEntry).TotalHours, 2)) hours" -ForegroundColor White
                    }
                    Write-Host ""
                }
                return
            }
            'Table' {
                Write-Host "=== BlackCat Cache Statistics (Table Format) ===" -ForegroundColor Cyan
                Write-Host ""
                
                $tableData = foreach ($type in $cacheTypes) {
                    $perf = $performanceData[$type]
                    [PSCustomObject]@{
                        CacheType = $perf.Type
                        Status = $perf.Status
                        Total = $perf.TotalEntries
                        Valid = $perf.ValidEntries
                        Expired = $perf.ExpiredEntries
                        Compressed = $perf.CompressedEntries
                        'Size(MB)' = $perf.TotalSizeMB
                        'Avg(KB)' = $perf.AverageEntrySizeKB
                        'Efficiency%' = $perf.MemoryEfficiency
                        'Expiration%' = $perf.ExpirationRate
                    }
                }
                $tableData | Format-Table -AutoSize
                return
            }
            default {
                # Enhanced Summary format with advanced analytics
                Write-Host "╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
                Write-Host "║                    BlackCat Cache Analytics Dashboard                ║" -ForegroundColor Cyan
                Write-Host "╚══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
                Write-Host ""

                # Overall statistics with enhanced metrics
                $summary = $outputData.Summary
                Write-Host " GLOBAL OVERVIEW" -ForegroundColor Green
                Write-Host "├─ Active Cache Types: $($summary.ActiveCaches)/$($summary.TotalCaches)" -ForegroundColor White
                Write-Host "├─ Total Cache Entries: $($summary.TotalEntries)" -ForegroundColor White
                Write-Host "├─ Overall Hit Rate: $($summary.OverallHitRate)%" -ForegroundColor $(if ($summary.OverallHitRate -gt 80) { 'Green' } elseif ($summary.OverallHitRate -gt 60) { 'Yellow' } else { 'Red' })
                Write-Host "├─ Total Memory Usage: $([math]::Round($summary.TotalSizeMB, 2)) MB" -ForegroundColor White
                
                # Add filter information if filters are applied
                $activeFilters = @()
                if ($FilterExpired) { $activeFilters += "Expired" }
                if ($FilterValid) { $activeFilters += "Valid" }
                if ($FilterCompressed) { $activeFilters += "Compressed" }
                if ($FilterLarge) { $activeFilters += "Large (>1MB)" }
                if ($MinSize -gt 0) { $activeFilters += "MinSize: ${MinSize}KB" }
                if ($MaxAge -gt 0) { $activeFilters += "MaxAge: ${MaxAge}h" }
                
                if ($activeFilters.Count -gt 0) {
                    Write-Host "├─ Active Filters: $($activeFilters -join ', ')" -ForegroundColor Magenta
                }
                
                if ($Top -gt 0) {
                    Write-Host "├─ Display Limit: Top $Top entries" -ForegroundColor Magenta
                }
                
                Write-Host "└─ Sorted By: $SortBy" -ForegroundColor Gray
                Write-Host ""

                # Individual cache type analysis with enhanced metrics
                foreach ($type in $cacheTypes) {
                    $perf = $performanceData[$type]
                    
                    if ($perf.Status -eq 'Uninitialized') {
                        Write-Host " $($perf.Type.ToUpper()) CACHE" -ForegroundColor Gray
                        Write-Host "└─ Status: Not initialized" -ForegroundColor Gray
                        Write-Host ""
                        continue
                    }

                    Write-Host " $($perf.Type.ToUpper()) CACHE ANALYTICS" -ForegroundColor Yellow
                    Write-Host "├─ Status: $($perf.Status)" -ForegroundColor Green
                    Write-Host "├─ Entries: Total: $($perf.TotalEntries) | Valid: $($perf.ValidEntries) | Expired: $($perf.ExpiredEntries)" -ForegroundColor White
                    Write-Host "├─ Compression: $($perf.CompressedEntries) entries ($($perf.CompressionRatio)%)" -ForegroundColor Cyan
                    Write-Host "├─ Memory: Usage: $($perf.TotalSizeMB) MB | Avg: $($perf.AverageEntrySizeKB) KB/entry" -ForegroundColor White
                    Write-Host "├─ Performance: Hit Rate: $($perf.HitRate)% | Utilization: $($perf.CacheUtilization)%" -ForegroundColor $(if ($perf.HitRate -gt 80) { 'Green' } elseif ($perf.HitRate -gt 60) { 'Yellow' } else { 'Red' })
                    Write-Host "├─ Efficiency: Memory: $($perf.MemoryEfficiency)% | Expiration Rate: $($perf.ExpirationRate)%" -ForegroundColor $(if ($perf.MemoryEfficiency -gt 50 -and $perf.ExpirationRate -lt 20) { 'Green' } elseif ($perf.ExpirationRate -lt 50) { 'Yellow' } else { 'Red' })
                    
                    if ($perf.OldestEntry) {
                        $cacheAge = [math]::Round(((Get-Date) - $perf.OldestEntry).TotalHours, 2)
                        Write-Host "└─ Age: Cache Span: $cacheAge hours | Density: $([math]::Round($perf.MemoryDensity / 1KB, 1)) KB/entry" -ForegroundColor White
                    } else {
                        Write-Host "└─ Age: N/A" -ForegroundColor Gray
                    }
                    Write-Host ""
                }

                # Trend analysis if requested
                if ($ShowTrends -and $trendData.Count -gt 0) {
                    Write-Host " TREND ANALYSIS" -ForegroundColor Blue
                    foreach ($type in $cacheTypes) {
                        if ($trendData.ContainsKey($type)) {
                            $trend = $trendData[$type]
                            Write-Host "  $($type.ToUpper()):" -ForegroundColor Yellow
                            Write-Host "    ├─ Growth Rate: $($trend.GrowthRate)% (last 24h)" -ForegroundColor White
                            Write-Host "    ├─ Peak Usage Hour: $($trend.PeakUsageHour)" -ForegroundColor White
                            Write-Host "    ├─ Average Entry Age: $($trend.AverageAge) hours" -ForegroundColor White
                            Write-Host "    ├─ Turnover Rate: $($trend.TurnoverRate)%" -ForegroundColor $(if ($trend.TurnoverRate -lt 30) { 'Green' } elseif ($trend.TurnoverRate -lt 60) { 'Yellow' } else { 'Red' })
                            Write-Host "    └─ Prediction: $($trend.Prediction)" -ForegroundColor Magenta
                        }
                    }
                    Write-Host ""
                }

                # Histogram display if requested
                if ($IncludeHistogram -and $histogramData.Count -gt 0) {
                    Write-Host " DISTRIBUTION HISTOGRAMS" -ForegroundColor Blue
                    foreach ($type in $cacheTypes) {
                        if ($histogramData.ContainsKey($type)) {
                            $histData = $histogramData[$type]
                            Write-Host "  $($type.ToUpper()) - Size Distribution (MB):" -ForegroundColor Yellow
                            foreach ($bucket in $histData.SizeHistogram) {
                                $bar = "█" * [math]::Min([math]::Floor($bucket.Percentage / 5), 20)
                                Write-Host "    $($bucket.Range.PadRight(12)) │$bar $($bucket.Count) ($($bucket.Percentage)%)" -ForegroundColor Cyan
                            }
                            Write-Host ""
                            Write-Host "  $($type.ToUpper()) - Age Distribution (Hours):" -ForegroundColor Yellow
                            foreach ($bucket in $histData.AgeHistogram) {
                                $bar = "█" * [math]::Min([math]::Floor($bucket.Percentage / 5), 20)
                                Write-Host "    $($bucket.Range.PadRight(12)) │$bar $($bucket.Count) ($($bucket.Percentage)%)" -ForegroundColor Cyan
                            }
                            Write-Host ""
                        }
                    }
                }

                # Enhanced performance recommendations
                Write-Host " PERFORMANCE INSIGHTS" -ForegroundColor Magenta
                $recommendations = @()
                
                foreach ($type in $cacheTypes) {
                    $perf = $performanceData[$type]
                    if ($perf.Status -eq 'Uninitialized') { continue }
                    
                    # Enhanced recommendation logic
                    if ($perf.HitRate -lt 60) {
                        $recommendations += "  Low hit rate in $type cache ($($perf.HitRate)%) - consider increasing expiration time or reviewing cache strategy"
                    }
                    if ($perf.ExpirationRate -gt 50) {
                        $recommendations += " High expiration rate in $type cache ($($perf.ExpirationRate)%) - consider longer TTL or usage pattern analysis"
                    }
                    if ($perf.TotalSizeMB -gt 100) {
                        $recommendations += "� Large memory usage in $type cache ($($perf.TotalSizeMB) MB) - consider enabling compression or implementing LRU eviction"
                    }
                    if ($perf.TotalEntries -gt 100 -and $perf.CompressionRatio -eq 0) {
                        $recommendations += "  $type cache has $($perf.TotalEntries) entries with no compression - could reduce memory by up to 70%"
                    }
                    if ($perf.ValidEntries -eq 0 -and $perf.TotalEntries -gt 0) {
                        $recommendations += " All entries in $type cache are expired - run cache cleanup or implement automatic cleanup"
                    }
                    if ($perf.TotalEntries -gt 500) {
                        $recommendations += " Large cache size in $type ($($perf.TotalEntries) entries) - consider implementing size limits or LRU eviction"
                    }
                    if ($perf.MemoryDensity -gt 1048576) { # > 1MB per entry
                        $recommendations += " Large average entry size in $type cache ($([math]::Round($perf.MemoryDensity / 1MB, 1)) MB/entry) - compression highly recommended"
                    }
                    
                    # Trend-based recommendations
                    if ($ShowTrends -and $trendData.ContainsKey($type)) {
                        $trend = $trendData[$type]
                        if ($trend.GrowthRate -gt 75) {
                            $recommendations += " Rapid growth detected in $type cache ($($trend.GrowthRate)% in 24h) - monitor memory usage closely"
                        }
                        if ($trend.TurnoverRate -gt 80) {
                            $recommendations += " High turnover rate in $type cache ($($trend.TurnoverRate)%) - cache effectiveness may be compromised"
                        }
                    }
                }

                if ($recommendations.Count -eq 0) {
                    Write-Host " Cache performance is optimal! All metrics within recommended ranges." -ForegroundColor Green
                } else {
                    foreach ($rec in $recommendations) {
                        Write-Host $rec -ForegroundColor Yellow
                    }
                }
                Write-Host ""

                # Show detailed entries if requested
                if ($ShowDetails -and $allCacheData.Count -gt 0) {
                    Write-Host " DETAILED CACHE ENTRIES" -ForegroundColor Blue
                    $detailTable = $allCacheData | Select-Object -First (if ($Top -gt 0) { $Top } else { $allCacheData.Count }) |
                        Select-Object CacheType, 
                                      @{Name='Key'; Expression={if ($_.Key.Length -gt 30) { $_.Key.Substring(0,27) + "..." } else { $_.Key }}},
                                      @{Name='Age'; Expression={"$([math]::Round($_.Age.TotalHours, 1))h"}},
                                      @{Name='TTL'; Expression={if ($_.TTL.TotalSeconds -gt 0) { "$([math]::Round($_.TTL.TotalHours, 1))h" } else { "Expired" }}},
                                      Status,
                                      @{Name='Size'; Expression={"$($_.SizeMB) MB"}},
                                      @{Name='Compressed'; Expression={if ($_.IsCompressed) { "Yes" } else { "No" }}}
                    
                    $detailTable | Format-Table -AutoSize
                    
                    if ($allCacheData.Count -gt ($detailTable | Measure-Object).Count) {
                        Write-Host "... and $($allCacheData.Count - ($detailTable | Measure-Object).Count) more entries" -ForegroundColor Gray
                    }
                }

                # Enhanced performance metrics if requested
                if ($ShowPerformance) {
                    Write-Host " ADVANCED PERFORMANCE METRICS" -ForegroundColor Blue
                    $perfTable = foreach ($type in $cacheTypes) {
                        $perf = $performanceData[$type]
                        if ($perf.Status -eq 'Active') {
                            [PSCustomObject]@{
                                Cache = $perf.Type
                                'Entries' = $perf.TotalEntries
                                'Hit Rate' = "$($perf.HitRate)%"
                                'Utilization' = "$($perf.CacheUtilization)%"
                                'Avg Size' = "$($perf.AverageEntrySizeKB) KB"
                                'Compression' = "$($perf.CompressionRatio)%"
                                'Memory' = "$($perf.TotalSizeMB) MB"
                                'Density' = "$([math]::Round($perf.MemoryDensity / 1KB, 1)) KB/entry"
                                'Efficiency' = if ($perf.HitRate -gt 80 -and $perf.ExpirationRate -lt 20) { "High" } 
                                             elseif ($perf.HitRate -gt 60 -and $perf.ExpirationRate -lt 40) { "Medium" } 
                                             else { "Low" }
                            }
                        }
                    }
                    if ($perfTable) {
                        $perfTable | Format-Table -AutoSize
                    }
                }

                $executionTime = ((Get-Date) - $startTime).TotalMilliseconds
                Write-Host " Advanced analysis completed in $([math]::Round($executionTime, 2)) ms" -ForegroundColor Gray
                
                # Return data object for programmatic use
                return $outputData
            }
        }
    }
}
