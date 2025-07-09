function Write-CacheTypeStats {
    <#
    .SYNOPSIS
        Helper function to display statistics for a specific cache type.
    
    .DESCRIPTION
        This internal helper reduces duplication in cache statistics display logic.
        Uses Write-Host to output formatted cache statistics information.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$CacheTypeName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('MSGraph', 'AzBatch', 'General')]
        [string]$CacheType
    )
    
    Write-Host "$CacheTypeName Cache:" -ForegroundColor Yellow
    $stats = Get-BlackCatCacheStatsInternal -CacheType $CacheType
    if ($stats) {
        $stats | Format-Table -AutoSize
    }
    else {
        Write-Host "  No cache data available" -ForegroundColor Gray
    }
}
