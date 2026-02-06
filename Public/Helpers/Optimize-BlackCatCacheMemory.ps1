function Optimize-BlackCatCacheMemory {
    <#
    .SYNOPSIS
        Optimizes cache memory usage by cleaning expired entries and applying compression.

    .DESCRIPTION
        Optimizes cache memory by removing expired entries, LRU cleanup, and optional compression.

    .PARAMETER CacheType
        Specifies which cache type to optimize. Valid values are 'MSGraph', 'AzBatch', or 'All'.
        Default is 'All' which optimizes all cache types.

    .PARAMETER MaxSize
        Maximum number of entries to keep in each cache. Default is 100.

    .PARAMETER CompressLargeEntries
        When specified, compresses cache entries larger than 1KB to save memory.

    .PARAMETER Force
        Forces optimization even if cache is below the size limit.

    .EXAMPLE
        Optimize-BlackCatCacheMemory

        This example optimizes all cache types using default settings.

    .EXAMPLE
        Optimize-BlackCatCacheMemory -CacheType MSGraph -MaxSize 50 -CompressLargeEntries

        This example optimizes only the MSGraph cache, limiting it to 50 entries and compressing large entries.

    .NOTES
        This is a utility/support function and does not directly map to MITRE ATT&CK tactics.
        This function helps manage memory usage in large environments with extensive cache data.
        Run regularly in long-running sessions or scripts processing large datasets.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateSet('MSGraph', 'AzBatch', 'All')]
        [string]$CacheType = 'All',

        [Parameter(Mandatory = $false)]
        [int]$MaxSize = 100,

        [Parameter(Mandatory = $false)]
        [switch]$CompressLargeEntries,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    $cacheTypes = if ($CacheType -eq 'All') { @('MSGraph', 'AzBatch') } else { @($CacheType) }
    $totalOptimized = 0

    Write-Host "Starting cache memory optimization..." -ForegroundColor Cyan

    foreach ($type in $cacheTypes) {
        Write-Host "Optimizing $type cache..." -ForegroundColor Yellow
        
        # Get current stats
        $beforeStats = Get-BlackCatCacheStatsInternal -CacheType $type
        if (-not $beforeStats) {
            Write-Host "  No $type cache found, skipping..." -ForegroundColor Gray
            continue
        }

        $sizeBefore = $beforeStats.MemoryUsageMB
        
        # Optimize cache size
        if ($Force -or $beforeStats.TotalEntries -gt $MaxSize) {
            Optimize-BlackCatCache -CacheType $type -MaxSize $MaxSize
        }

        # Compress large entries if requested
        if ($CompressLargeEntries) {
            $currentCache = Get-Variable -Name "${type}Cache" -Scope Script -ErrorAction SilentlyContinue
            if ($currentCache -and $currentCache.Value) {
                $compressed = 0
                foreach ($key in @($currentCache.Value.Keys)) {
                    $entry = $currentCache.Value[$key]
                    if (-not $entry.IsCompressed -and $entry.Size -gt 1KB) {
                        try {
                            $compressedData = Compress-CacheData -Data $entry.Data
                            $entry.Data = $compressedData
                            $entry.IsCompressed = $true
                            $compressed++
                        }
                        catch {
                            Write-Verbose "Failed to compress cache entry: $key"
                        }
                    }
                }
                if ($compressed -gt 0) {
                    Write-Host "  Compressed $compressed large cache entries" -ForegroundColor Green
                }
            }
        }

        # Get after stats
        $afterStats = Get-BlackCatCacheStatsInternal -CacheType $type
        $sizeAfter = if ($afterStats) { $afterStats.MemoryUsageMB } else { 0 }
        $savings = $sizeBefore - $sizeAfter
        $afterEntries = if ($afterStats) { $afterStats.TotalEntries } else { 0 }

        Write-Host "  $type cache: $($beforeStats.TotalEntries) → $afterEntries entries" -ForegroundColor White
        Write-Host "  Memory usage: $([math]::Round($sizeBefore, 2)) → $([math]::Round($sizeAfter, 2)) MB" -ForegroundColor White
        if ($savings -gt 0) {
            Write-Host "   Saved $([math]::Round($savings, 2)) MB" -ForegroundColor Green
        }

        $totalOptimized++
    }

    Write-Host ""
    Write-Host "Cache optimization complete! Optimized $totalOptimized cache type(s)." -ForegroundColor Cyan
}
