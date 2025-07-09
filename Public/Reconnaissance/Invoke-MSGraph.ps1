function Invoke-MsGraph {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $false)]
        [string]$relativeUrl,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [switch]$NoBatch,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [int]$MaxRetries = 3,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [int]$RetryDelaySeconds = 5, # Initial delay in seconds

        [Parameter(Mandatory = $false)]
        [ValidateSet("Object", "JSON", "CSV", "Table")]
        [Alias("output", "o")]
        [string]$OutputFormat = "Object",

        [Parameter(Mandatory = $false)]
        [switch]$SkipCache,

        [Parameter(Mandatory = $false)]
        [int]$CacheExpirationMinutes = 30,

        [Parameter(Mandatory = $false)]
        [int]$MaxCacheSize = 100,

        [Parameter(Mandatory = $false)]
        [switch]$CompressCache
    )

    begin {
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
    }

    process {
        # Generate cache key for this request
        $cacheParams = @{
            NoBatch = $NoBatch.IsPresent
            OutputFormat = $OutputFormat
        }
        $cacheKey = ConvertTo-CacheKey -BaseIdentifier $relativeUrl -Parameters $cacheParams
        
        # Check cache first (unless skipping cache)
        if (-not $SkipCache) {
            try {
                $cachedResult = Get-BlackCatCache -Key $cacheKey -CacheType 'MSGraph'
                if ($null -ne $cachedResult) {
                    Write-Verbose "Retrieved result from cache for: $relativeUrl"
                    
                    # Apply output formatting to cached result
                    try {
                        switch ($OutputFormat) {
                            "JSON" {
                                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                                $jsonOutput = $cachedResult | ConvertTo-Json -Depth 3
                                $jsonFilePath = "MSGraphResult_$timestamp.json"
                                $jsonOutput | Out-File -FilePath $jsonFilePath -Encoding UTF8
                                Write-Host "💾 JSON output saved to: $jsonFilePath (from cache)" -ForegroundColor Green
                                return
                            }
                            "CSV" {
                                if ($cachedResult -is [array] -and $cachedResult.Count -gt 0) {
                                    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                                    $csvOutput = $cachedResult | ConvertTo-Csv -NoTypeInformation
                                    $csvFilePath = "MSGraphResult_$timestamp.csv"
                                    $csvOutput | Out-File -FilePath $csvFilePath -Encoding UTF8
                                    Write-Host "📊 CSV output saved to: $csvFilePath (from cache)" -ForegroundColor Green
                                } else {
                                    Write-Warning "Cannot export cached data to CSV: No data or single object returned"
                                    return $cachedResult
                                }
                                return
                            }
                            "Object" { return $cachedResult }
                            "Table" { 
                                if ($cachedResult -is [array] -and $cachedResult.Count -gt 0) {
                                    return $cachedResult | Format-Table -AutoSize 
                                } else {
                                    return $cachedResult
                                }
                            }
                        }
                    }
                    catch {
                        Write-Verbose "Error formatting cached result: $($_.Exception.Message). Proceeding with fresh API call."
                        # Continue to make fresh API call if cache formatting fails
                    }
                }
            }
            catch {
                Write-Verbose "Error retrieving from cache: $($_.Exception.Message). Proceeding with fresh API call."
                # Continue to make fresh API call if cache retrieval fails
            }
        }

        $retries = 0
        do {
            try {
                if ($NoBatch) {
                    $uri = "$($sessionVariables.graphUri)/$relativeUrl" -replace 'applications/\(', 'applications('
                    Write-Verbose "Invoking Microsoft Graph API: $uri"
                    $requestParam = @{
                        Headers       = $script:graphHeader
                        Uri           = $uri
                        Method        = 'GET'
                        UserAgent     = $($sessionVariables.userAgent)
                        ErrorVariable = 'Err'
                    }
                }
                else {

                    $payload = @{
                        requests = @(
                            @{
                                id     = "List"
                                method = 'GET'
                                url    = '/{0}' -f "$relativeUrl"
                            }
                        )
                    }

                    $requestParam = @{
                        Headers       = $script:graphHeader
                        Uri           = '{0}/$batch' -f $sessionVariables.graphUri
                        Method        = 'POST'
                        ContentType   = 'application/json'
                        Body          = $payload | ConvertTo-Json -Depth 10
                        UserAgent     = $($sessionVariables.userAgent)
                        ErrorVariable = 'Err'
                    }
                }

                try {
                    $initialResponse = (Invoke-RestMethod @requestParam)
                } catch {
                    if ($Err) {
                        $ErrorMessage = ($Err.Message | ConvertFrom-Json).error.message
                        Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "$($ErrorMessage)" -Severity 'Error'
                    }
                    return $null
                }

                # Handle empty or null response
                if ($null -eq $initialResponse) {
                    Write-Verbose "No data returned from API call to: $relativeUrl"
                    return $null
                }

                try {
                    if ($NoBatch) {
                        $result = $initialResponse
                    } else {
                        # Check for throttling headers
                        if ($initialResponse.Headers."Retry-After") {
                            $retryAfter = [int]$initialResponse.Headers."Retry-After"
                            Write-Warning "Throttled!  Waiting $($retryAfter) seconds before retrying."
                            Start-Sleep -Seconds $retryAfter
                            $retries++ # Increment retries, important to track
                            continue  # Skip the rest of the loop and retry
                        }

                        $allItems = Get-AllPages -ProcessLink $initialResponse
                        $result = $allItems
                    }

                    # Handle empty result
                    if ($null -eq $result -or ($result -is [array] -and $result.Count -eq 0)) {
                        Write-Verbose "No data found for: $relativeUrl"
                        return $null
                    }
                }
                catch {
                    Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Error processing response: $($_.Exception.Message)" -Severity 'Error'
                    return $null
                }

                # Cache the result before formatting (unless skipping cache or result is null)
                if (-not $SkipCache -and $null -ne $result) {
                    try {
                        Set-BlackCatCache -Key $cacheKey -Data $result -ExpirationMinutes $CacheExpirationMinutes -CacheType 'MSGraph' -MaxCacheSize $MaxCacheSize -CompressData:$CompressCache
                        Write-Verbose "Cached result for: $relativeUrl (expires in $CacheExpirationMinutes minutes)"
                    }
                    catch {
                        Write-Verbose "Failed to cache result for: $relativeUrl - $($_.Exception.Message)"
                    }
                }

                # Handle null result before formatting
                if ($null -eq $result) {
                    Write-Verbose "No data to format for: $relativeUrl"
                    return $null
                }

                # Apply output formatting
                try {
                    switch ($OutputFormat) {
                        "JSON" {
                            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                            $jsonOutput = $result | ConvertTo-Json -Depth 3
                            $jsonFilePath = "MSGraphResult_$timestamp.json"
                            $jsonOutput | Out-File -FilePath $jsonFilePath -Encoding UTF8
                            Write-Host "💾 JSON output saved to: $jsonFilePath" -ForegroundColor Green
                            return
                        }
                        "CSV" {
                            if ($result -is [array] -and $result.Count -gt 0) {
                                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                                $csvOutput = $result | ConvertTo-Csv -NoTypeInformation
                                $csvFilePath = "MSGraphResult_$timestamp.csv"
                                $csvOutput | Out-File -FilePath $csvFilePath -Encoding UTF8
                                Write-Host "📊 CSV output saved to: $csvFilePath" -ForegroundColor Green
                            } else {
                                Write-Warning "Cannot export to CSV: No data or single object returned"
                                return $result
                            }
                            return
                        }
                        "Object" { return $result }
                        "Table" { 
                            if ($result -is [array] -and $result.Count -gt 0) {
                                return $result | Format-Table -AutoSize 
                            } else {
                                return $result
                            }
                        }
                    }
                }
                catch {
                    Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Error formatting output: $($_.Exception.Message)" -Severity 'Warning'
                    return $result
                }

                return $result

            }
            catch {
                if ($_.Exception.Message -contains "*429*") { # Check for specific throttling error
                    $retries++
                    $retryAfter = $RetryDelaySeconds * ($retries) # Exponential backoff
                    Write-Warning "Throttled!  Retry $($retries) of $($MaxRetries). Waiting $($retryAfter) seconds before retrying."
                    Start-Sleep -Seconds $retryAfter
                }
                elseif ($_.Exception.Message -contains "*401") {
                    Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Unauthorized access to the Graph API." -Severity 'Error'
                    break # No point in retrying if unauthorized
                }
                else {
                    Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
                    break # Break out of the retry loop for other errors
                }
            }
        } while ($retries -lt $MaxRetries)

        if ($retries -ge $MaxRetries) {
            Write-Error "Max retries reached.  Failed to execute request after $($MaxRetries) attempts."
        }
    }
    <#
    .SYNOPSIS
        Invokes a request to the Microsoft Graph API.

    .DESCRIPTION
        This function sends a request to the Microsoft Graph API using the specified parameters.
        It handles authentication and constructs the appropriate headers for the request.
        The function supports various output formats and includes retry logic for handling throttling.

    .PARAMETER relativeUrl
        The relative URL for the Microsoft Graph API endpoint to call.

    .PARAMETER NoBatch
        When specified, sends individual requests instead of using batch requests.

    .PARAMETER MaxRetries
        The maximum number of retries when encountering throttling or transient errors. Default is 3.

    .PARAMETER RetryDelaySeconds
        The initial delay in seconds between retries, with exponential backoff. Default is 5 seconds.

    .PARAMETER OutputFormat
        Specifies the output format for results. Valid values are:
        - Object: Returns PowerShell objects (default)
        - JSON: Saves results to a JSON file with timestamp
        - CSV: Saves results to a CSV file with timestamp
        - Table: Returns results in formatted table
        Aliases: output, o

    .PARAMETER SkipCache
        When specified, bypasses the cache and forces a fresh API call.

    .PARAMETER CacheExpirationMinutes
        Sets the cache expiration time in minutes. Default is 30 minutes.
        This parameter controls how long the cached results remain valid.

    .PARAMETER MaxCacheSize
        Maximum number of entries to store in the cache. Default is 100.
        When this limit is reached, least recently used entries are removed.

    .PARAMETER CompressCache
        When specified, compresses cache data to reduce memory usage.
        Recommended for large datasets or memory-constrained environments.

    .EXAMPLE
        Invoke-MSGraph -relativeUrl "applications"

        This example sends a GET request to the Microsoft Graph API to retrieve information about the applications.

    .EXAMPLE
        Invoke-MSGraph -relativeUrl "users" -OutputFormat JSON

        This example retrieves users from Microsoft Graph and saves the results to a JSON file.

    .EXAMPLE
        Invoke-MSGraph -relativeUrl "groups" -OutputFormat Table

        This example retrieves groups from Microsoft Graph and displays the results in a formatted table.

    .EXAMPLE
        Invoke-MSGraph -relativeUrl "applications" -SkipCache

        This example forces a fresh API call to retrieve applications, bypassing any cached results.

    .EXAMPLE
        Invoke-MSGraph -relativeUrl "users" -CacheExpirationMinutes 60

        This example retrieves users and caches the results for 60 minutes instead of the default 30 minutes.

    .EXAMPLE
        Invoke-MSGraph -relativeUrl "applications" -MaxCacheSize 50 -CompressCache

        This example retrieves applications with a smaller cache size and enables compression to save memory.

    .EXAMPLE
        Invoke-MSGraph -relativeUrl "groups" -CompressCache

        This example retrieves groups and compresses the cached data to reduce memory usage in large environments.
#>
}