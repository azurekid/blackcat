function Clear-BlackCatCache {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            
            $cacheType = $fakeBoundParameters['CacheType']
            if (-not $cacheType) {
                $cacheType = 'All'
            }
            
            try {
                $availableKeys = @()
                $cacheTypes = if ($cacheType -eq 'All') { @('MSGraph', 'AzBatch', 'General') } else { @($cacheType) }
                
                foreach ($type in $cacheTypes) {
                    try {
                        $stats = Get-BlackCatCacheStats -CacheType $type -ShowDetails -Quiet
                        
                        if ($stats -and $stats.Entries -and $stats.Entries.Count -gt 0) {
                            $availableKeys += $stats.Entries | ForEach-Object { $_.Key }
                        }
                    }
                    catch {
                        continue
                    }
                }
                
                $filteredKeys = $availableKeys | Where-Object { $_ -like "$wordToComplete*" } | Sort-Object
                
                $filteredKeys | ForEach-Object {
                    if ($_ -match '[\s\|]') {
                        "'$_'"
                    } else {
                        $_
                    }
                }
            }
            catch {
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
        Clear-BlackCatCacheInternal -Key $Key -All:$All -CacheType 'MSGraph'
        Clear-BlackCatCacheInternal -Key $Key -All:$All -CacheType 'AzBatch'
        Clear-BlackCatCacheInternal -Key $Key -All:$All -CacheType 'General'
    }
    else {
        Clear-BlackCatCacheInternal -Key $Key -All:$All -CacheType $CacheType
    }
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
}