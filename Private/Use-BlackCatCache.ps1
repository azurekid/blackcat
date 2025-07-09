using namespace System.IO.Compression

function Set-BlackCatCache {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Key,
        
        [Parameter(Mandatory = $true)]
        [object]$Data,
        
        [Parameter(Mandatory = $false)]
        [int]$ExpirationMinutes = 30,

        [Parameter(Mandatory = $false)]
        [ValidateSet('MSGraph', 'AzBatch', 'General')]
        [string]$CacheType = 'General',

        [Parameter(Mandatory = $false)]
        [int]$MaxCacheSize = 100,

        [Parameter(Mandatory = $false)]
        [switch]$CompressData
    )
    
    # Initialize cache if it doesn't exist
    $currentCache = Initialize-CacheStore -CacheType $CacheType
    
    # Apply cache size limit (LRU eviction)
    if ($currentCache.Value.Count -ge $MaxCacheSize) {
        # Remove oldest entries until we're under the limit
        $sortedEntries = $currentCache.Value.GetEnumerator() | Sort-Object { $_.Value.Timestamp }
        $entriesToRemove = $sortedEntries | Select-Object -First ($currentCache.Value.Count - $MaxCacheSize + 1)
        
        foreach ($entry in $entriesToRemove) {
            $currentCache.Value.Remove($entry.Key)
            Write-Verbose "Removed old cache entry: $($entry.Key) from $CacheType cache (LRU cleanup)"
        }
    }
    
    # Prepare data for caching
    $dataToCache = $Data
    $isCompressed = $false
    
    # Apply compression if requested
    if ($CompressData -and $Data) {
        try {
            # Simple compression using .NET compression
            $jsonData = $Data | ConvertTo-Json -Depth 10 -Compress
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonData)
            
            if ($bytes.Length -gt 1KB) {  # Only compress if data is larger than 1KB
                $memoryStream = New-Object System.IO.MemoryStream
                $gzipStream = New-Object System.IO.Compression.GzipStream($memoryStream, [System.IO.Compression.CompressionMode]::Compress)
                $gzipStream.Write($bytes, 0, $bytes.Length)
                $gzipStream.Close()
                
                $compressedBytes = $memoryStream.ToArray()
                $memoryStream.Close()
                
                if ($compressedBytes.Length -lt $bytes.Length) {
                    $dataToCache = [Convert]::ToBase64String($compressedBytes)
                    $isCompressed = $true
                    Write-Verbose "Compressed cache data: $($bytes.Length) → $($compressedBytes.Length) bytes"
                }
            }
        }
        catch {
            Write-Verbose "Compression failed, storing uncompressed: $($_.Exception.Message)"
        }
    }
    
    $cacheEntry = @{
        Data = $dataToCache
        Timestamp = Get-Date
        ExpirationMinutes = $ExpirationMinutes
        IsCompressed = $isCompressed
        Size = if ($isCompressed) { [Convert]::FromBase64String($dataToCache).Length } else { 
            ($Data | ConvertTo-Json -Depth 10 -Compress | Measure-Object -Character).Characters 
        }
    }
    
    $currentCache.Value[$Key] = $cacheEntry
    $compressionNote = if ($isCompressed) { " (compressed)" } else { "" }
    Write-Verbose "Cached data for key: $Key in $CacheType cache (expires in $ExpirationMinutes minutes)$compressionNote"
}

function Get-BlackCatCache {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $false)]
        [ValidateSet('MSGraph', 'AzBatch', 'General')]
        [string]$CacheType = 'General'
    )
    
    # Get cache variable
    $currentCache = Get-CacheStore -CacheType $CacheType
    
    # Return null if cache doesn't exist
    if (-not $currentCache -or -not $currentCache.Value) {
        return $null
    }
    
    # Return null if key doesn't exist
    if (-not $currentCache.Value.ContainsKey($Key)) {
        return $null
    }
    
    $cacheEntry = $currentCache.Value[$Key]
    
    # Check if cache entry has expired
    if (Test-CacheEntryExpired -CacheEntry $cacheEntry) {
        $age = (Get-Date) - $cacheEntry.Timestamp
        Write-Verbose "Cache entry for key '$Key' in $CacheType cache has expired (age: $($age.TotalMinutes) minutes)"
        $currentCache.Value.Remove($Key)
        return $null
    }
    
    # Decompress data if it was compressed
    $resultData = $cacheEntry.Data
    if ($cacheEntry.IsCompressed) {
        try {
            $compressedBytes = [Convert]::FromBase64String($cacheEntry.Data)
            $memoryStream = New-Object System.IO.MemoryStream(,$compressedBytes)
            $gzipStream = New-Object System.IO.Compression.GzipStream($memoryStream, [System.IO.Compression.CompressionMode]::Decompress)
            $streamReader = New-Object System.IO.StreamReader($gzipStream)
            $jsonData = $streamReader.ReadToEnd()
            $streamReader.Close()
            $gzipStream.Close()
            $memoryStream.Close()
            
            $resultData = $jsonData | ConvertFrom-Json
            Write-Verbose "Decompressed cache data for key: $Key"
        }
        catch {
            Write-Verbose "Failed to decompress cache data for key: $Key - $($_.Exception.Message)"
            $currentCache.Value.Remove($Key)
            return $null
        }
    }
    
    $age = (Get-Date) - $cacheEntry.Timestamp
    Write-Verbose "Retrieved cached data for key: $Key from $CacheType cache (age: $($age.TotalMinutes) minutes)"
    return $resultData
}

function Clear-BlackCatCacheInternal {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Key,
        
        [Parameter(Mandatory = $false)]
        [switch]$All,

        [Parameter(Mandatory = $false)]
        [ValidateSet('MSGraph', 'AzBatch', 'General')]
        [string]$CacheType = 'General'
    )
    
    # Get cache variable
    $currentCache = Get-CacheStore -CacheType $CacheType
    
    if (-not $currentCache -or -not $currentCache.Value) {
        Write-Verbose "No $CacheType cache to clear"
        return
    }
    
    if ($All) {
        $currentCache.Value.Clear()
        Write-Verbose "Cleared all $CacheType cache entries"
    }
    elseif ($Key) {
        if ($currentCache.Value.ContainsKey($Key)) {
            $currentCache.Value.Remove($Key)
            Write-Verbose "Cleared $CacheType cache entry for key: $Key"
        }
        else {
            Write-Verbose "$CacheType cache key '$Key' not found"
        }
    }
    else {
        Write-Warning "Specify either -Key or -All parameter"
    }
}

function Get-BlackCatCacheStatsInternal {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateSet('MSGraph', 'AzBatch', 'General')]
        [string]$CacheType = 'General'
    )
    
    # Get cache variable
    $currentCache = Get-CacheStore -CacheType $CacheType
    
    if (-not $currentCache -or -not $currentCache.Value) {
        Write-Host "No $CacheType cache initialized" -ForegroundColor Yellow
        return
    }
    
    $totalEntries = $currentCache.Value.Count
    $expiredEntries = 0
    $validEntries = 0
    
    foreach ($key in $currentCache.Value.Keys) {
        $cacheEntry = $currentCache.Value[$key]
        
        if (Test-CacheEntryExpired -CacheEntry $cacheEntry) {
            $expiredEntries++
        }
        else {
            $validEntries++
        }
    }
    
    $stats = [PSCustomObject]@{
        CacheType = $CacheType
        TotalEntries = $totalEntries
        ValidEntries = $validEntries
        ExpiredEntries = $expiredEntries
        CacheKeys = $currentCache.Value.Keys | Sort-Object
    }
    
    return $stats
}

function ConvertTo-CacheKey {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$BaseIdentifier,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Parameters = @{}
    )
    
    # Create a consistent cache key from the base identifier and parameters
    $keyParts = @($BaseIdentifier)
    
    # Add sorted parameters to ensure consistent key generation
    if ($Parameters.Count -gt 0) {
        $sortedParams = $Parameters.GetEnumerator() | Sort-Object Name
        foreach ($param in $sortedParams) {
            $keyParts += "$($param.Name)=$($param.Value)"
        }
    }
    
    $cacheKey = ($keyParts -join "|").ToLower()
    return $cacheKey
}

function Invoke-CacheableOperation {
    <#
    .SYNOPSIS
        Executes a cacheable operation with unified cache handling logic.
    
    .DESCRIPTION
        This helper function encapsulates the common pattern of cache retrieval,
        operation execution, and cache storage used by both MSGraph and AzBatch functions.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$CacheKey,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('MSGraph', 'AzBatch', 'General')]
        [string]$CacheType,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$Operation,
        
        [Parameter(Mandatory = $false)]
        [bool]$SkipCache = $false,
        
        [Parameter(Mandatory = $false)]
        [int]$CacheExpirationMinutes = 30,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxCacheSize = 100,
        
        [Parameter(Mandatory = $false)]
        [bool]$CompressCache = $false,
        
        [Parameter(Mandatory = $false)]
        [string]$OperationName = "operation"
    )
    
    # Check cache first (unless skipping cache)
    if (-not $SkipCache) {
        try {
            $cachedResult = Get-BlackCatCache -Key $CacheKey -CacheType $CacheType
            if ($null -ne $cachedResult) {
                Write-Verbose "Retrieved result from cache for $OperationName"
                return $cachedResult
            }
        }
        catch {
            Write-Verbose "Error retrieving from cache: $($_.Exception.Message). Proceeding with fresh $OperationName."
        }
    }
    
    # Execute the operation
    try {
        $result = & $Operation
        
        # Cache the result (unless skipping cache or result is null)
        if (-not $SkipCache -and $null -ne $result) {
            try {
                Set-BlackCatCache -Key $CacheKey -Data $result -ExpirationMinutes $CacheExpirationMinutes -CacheType $CacheType -MaxCacheSize $MaxCacheSize -CompressData:$CompressCache
                Write-Verbose "Cached result for $OperationName (expires in $CacheExpirationMinutes minutes)"
            }
            catch {
                Write-Verbose "Failed to cache result for $OperationName - $($_.Exception.Message)"
            }
        }
        
        return $result
    }
    catch {
        Write-Verbose "Error executing $OperationName : $($_.Exception.Message)"
        throw
    }
}

function Initialize-CacheStore {
    <#
    .SYNOPSIS
        Initializes a cache store if it doesn't exist.
    
    .DESCRIPTION
        This helper function consolidates the cache initialization logic
        used across multiple cache functions.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('MSGraph', 'AzBatch', 'General')]
        [string]$CacheType
    )
    
    $currentCache = Get-Variable -Name "${CacheType}Cache" -Scope Script -ErrorAction SilentlyContinue
    
    if (-not $currentCache) {
        New-Variable -Name "${CacheType}Cache" -Value @{} -Scope Script -Force
        $currentCache = Get-Variable -Name "${CacheType}Cache" -Scope Script
    }
    
    return $currentCache
}

function Get-CacheStore {
    <#
    .SYNOPSIS
        Gets a cache store for the specified cache type.
    
    .DESCRIPTION
        This helper function consolidates the cache store retrieval logic
        used across multiple cache functions.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('MSGraph', 'AzBatch', 'General')]
        [string]$CacheType
    )
    
    return Get-Variable -Name "${CacheType}Cache" -Scope Script -ErrorAction SilentlyContinue
}

function Get-CacheParameters {
    <#
    .SYNOPSIS
        Extracts and validates cache parameters from function calls.
    
    .DESCRIPTION
        This helper function standardizes cache parameter extraction
        for use with the Invoke-CacheableOperation function.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [bool]$SkipCache = $false,
        
        [Parameter(Mandatory = $false)]
        [int]$CacheExpirationMinutes = 30,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxCacheSize = 100,
        
        [Parameter(Mandatory = $false)]
        [bool]$CompressCache = $false
    )
    
    return @{
        SkipCache = $SkipCache
        CacheExpirationMinutes = $CacheExpirationMinutes
        MaxCacheSize = $MaxCacheSize
        CompressCache = $CompressCache
    }
}

function Test-CacheEntryExpired {
    <#
    .SYNOPSIS
        Tests if a cache entry has expired.
    
    .DESCRIPTION
        This helper function consolidates cache expiration logic
        used across multiple cache functions.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$CacheEntry
    )
    
    $age = (Get-Date) - $CacheEntry.Timestamp
    return ($age.TotalMinutes -gt $CacheEntry.ExpirationMinutes)
}