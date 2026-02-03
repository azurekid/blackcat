function Get-BlackCatCacheMemoryStats {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateSet('MSGraph', 'AzBatch', 'All')]
        [string]$CacheType = 'All'
    )

    $memoryUsage = @()
    $cacheTypes = if ($CacheType -eq 'All') { @('MSGraph', 'AzBatch') } else { @($CacheType) }
    
    foreach ($type in $cacheTypes) {
        $store = Get-CacheStore -CacheType $type
        if ($store -and $store.Count -gt 0) {
            $typeMemoryMB = [math]::Round(([System.GC]::GetTotalMemory($false) / 1MB), 2)
            $memoryUsage += [PSCustomObject]@{
                CacheType = $type
                EntryCount = $store.Count
                MemoryUsageMB = $typeMemoryMB / $cacheTypes.Count  # Rough estimate
            }
        }
    }
    
    if ($memoryUsage) {
        Write-Host "=== BlackCat Cache Memory Usage ===" -ForegroundColor Cyan
        Write-Host ""
        
        $totalMemoryMB = ($memoryUsage | Measure-Object -Property MemoryUsageMB -Sum).Sum
        $totalEntries = ($memoryUsage | Measure-Object -Property EntryCount -Sum).Sum
        
        $memoryUsage | Format-Table -AutoSize
        
        Write-Host "Summary:" -ForegroundColor Yellow
        Write-Host "  Total Memory Usage: $([math]::Round($totalMemoryMB, 2)) MB" -ForegroundColor White
        Write-Host "  Total Cache Entries: $totalEntries" -ForegroundColor White
        
        if ($totalMemoryMB -gt 250) {
            Write-Host "  High memory usage detected!" -ForegroundColor Red
            Write-Host "   Consider using -CompressCache or reducing -MaxCacheSize" -ForegroundColor Yellow
        }
        elseif ($totalMemoryMB -gt 20) {
            Write-Host " Moderate memory usage" -ForegroundColor Yellow
            Write-Host "   Monitor usage and consider compression for large datasets" -ForegroundColor White
        }
        else {
            Write-Host " Memory usage is within acceptable limits" -ForegroundColor Green
        }
    }
    else {
        Write-Host "No cache data available" -ForegroundColor Yellow
    }
     <#
    .SYNOPSIS
        Displays detailed memory usage statistics for BlackCat cache systems.

    .DESCRIPTION
        This function shows comprehensive memory usage information for the cache systems,
        including total memory usage, average entry sizes, compression statistics, and
        provides recommendations for memory optimization.

    .PARAMETER CacheType
        Specifies which cache type to display memory statistics for. Valid values are 'MSGraph', 'AzBatch', or 'All'.
        Default is 'All' which shows statistics for all cache types.

    .EXAMPLE
        Get-BlackCatCacheMemoryStats

        This example displays memory usage statistics for all cache types.

    .EXAMPLE
        Get-BlackCatCacheMemoryStats -CacheType MSGraph

        This example displays memory usage statistics only for Microsoft Graph API cache.

    .NOTES
        This is a utility/support function and does not directly map to MITRE ATT&CK tactics.
        Use this function to monitor memory usage and identify opportunities for optimization.
        Large cache sizes may impact PowerShell session performance.
    #>
}
