function Clear-BlackCatCache {
    <#
    .SYNOPSIS
        Clears the cache used by BlackCat functions.

    .DESCRIPTION
        This function allows you to clear cached API results from Microsoft Graph API and Azure Batch calls.
        You can clear specific cache entries by key, clear all cached data, or clear specific cache types.

    .PARAMETER Key
        The specific cache key to clear. If not specified, use -All to clear everything.

    .PARAMETER All
        Clears all cached entries from all cache types.

    .PARAMETER CacheType
        Specifies which cache type to clear. Valid values are 'MSGraph', 'AzBatch', or 'All'.
        Default is 'All' which clears all cache types.

    .EXAMPLE
        Clear-BlackCatCache -All

        This example clears all cached API results from all cache types.

    .EXAMPLE
        Clear-BlackCatCache -CacheType MSGraph -All

        This example clears all cached Microsoft Graph API results only.

    .EXAMPLE
        Clear-BlackCatCache -Key "users|nobatch=false|outputformat=object" -CacheType MSGraph

        This example clears the cache entry for a specific Microsoft Graph API call.

    .NOTES
        Use Get-BlackCatCacheStats to see current cache statistics before clearing.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Key,
        
        [Parameter(Mandatory = $false)]
        [switch]$All,

        [Parameter(Mandatory = $false)]
        [ValidateSet('MSGraph', 'AzBatch', 'All')]
        [string]$CacheType = 'All'
    )

    if ($CacheType -eq 'All') {
        # Clear all cache types
        Clear-BlackCatCacheInternal -Key $Key -All:$All -CacheType 'MSGraph'
        Clear-BlackCatCacheInternal -Key $Key -All:$All -CacheType 'AzBatch'
    }
    else {
        Clear-BlackCatCacheInternal -Key $Key -All:$All -CacheType $CacheType
    }
}
