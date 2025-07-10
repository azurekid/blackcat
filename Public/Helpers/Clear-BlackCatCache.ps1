function Clear-BlackCatCache {
    <#
    .SYNOPSIS
        Clears the cache used by BlackCat functions.

    .DESCRIPTION
        This function allows you to clear cached API results from Microsoft Graph API and Azure Batch calls.
        You can clear specific cache entries by key, clear all cached data, or clear specific cache types.

    .PARAMETER Key
        The specific cache key to clear. If not specified, use -All to clear everything.
        Auto-completion is provided for available cache keys based on the selected CacheType.

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

    .EXAMPLE
        Clear-BlackCatCache -Key <TAB>

        This example demonstrates autocompletion. Press TAB after typing -Key to see available cache keys.
        The autocompletion will show keys based on the selected CacheType.

    .NOTES
        Use Get-BlackCatCacheStats to see current cache statistics before clearing.
        Tab completion is available for the -Key parameter to show available cache keys.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            
            # Get the CacheType parameter value from the command
            $cacheType = $fakeBoundParameters['CacheType']
            if (-not $cacheType) {
                $cacheType = 'All'
            }
            
            try {
                # Get available cache keys for autocompletion by leveraging Get-BlackCatCacheStats
                $availableKeys = @()
                $cacheTypes = if ($cacheType -eq 'All') { @('MSGraph', 'AzBatch') } else { @($cacheType) }
                
                foreach ($type in $cacheTypes) {
                    try {
                        # Use Get-BlackCatCacheStats with ShowDetails to get cache entries with keys
                        $stats = Get-BlackCatCacheStats -CacheType $type -ShowDetails -Quiet
                        
                        if ($stats -and $stats.Entries -and $stats.Entries.Count -gt 0) {
                            $availableKeys += $stats.Entries | ForEach-Object { $_.Key }
                        }
                    }
                    catch {
                        # Silently continue if cache access fails
                        continue
                    }
                }
                
                # Filter keys based on what user has typed and return them
                $filteredKeys = $availableKeys | Where-Object { $_ -like "$wordToComplete*" } | Sort-Object
                
                # Quote the key if it contains special characters
                $filteredKeys | ForEach-Object {
                    if ($_ -match '[\s\|]') {
                        "'$_'"
                    } else {
                        $_
                    }
                }
            }
            catch {
                # If anything fails, return empty array
                @()
            }
        })]
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

function Get-BlackCatCacheKeys {
    <#
    .SYNOPSIS
        Helper function to get available cache keys for autocompletion.
    
    .DESCRIPTION
        This function retrieves all available cache keys from the specified cache type(s)
        for use in parameter autocompletion.
    
    .PARAMETER CacheType
        Specifies which cache type to get keys from. Valid values are 'MSGraph', 'AzBatch', or 'All'.
        Default is 'All' which gets keys from all cache types.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateSet('MSGraph', 'AzBatch', 'All')]
        [string]$CacheType = 'All'
    )
    
    $allKeys = @()
    $cacheTypes = if ($CacheType -eq 'All') { @('MSGraph', 'AzBatch') } else { @($CacheType) }
    
    foreach ($type in $cacheTypes) {
        try {
            # Use Get-BlackCatCacheStats with ShowDetails to get cache entries with keys
            $stats = Get-BlackCatCacheStats -CacheType $type -ShowDetails -Quiet
            
            if ($stats -and $stats.Entries -and $stats.Entries.Count -gt 0) {
                $allKeys += $stats.Entries | ForEach-Object { $_.Key }
            }
        }
        catch {
            # Silently continue if cache access fails
            continue
        }
    }
    
    return $allKeys | Sort-Object
}
