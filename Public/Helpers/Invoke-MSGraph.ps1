function Invoke-MsGraph {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $false, ParameterSetName = 'Standard')]
        [string]$relativeUrl,

        [Parameter(Mandatory = $true, ParameterSetName = 'BatchRequest')]
        [ValidateNotNull()]
        [System.Collections.Generic.List[hashtable]]$BatchRequests,

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
        # Handle batch requests differently
        if ($PSCmdlet.ParameterSetName -eq 'BatchRequest') {
            Write-Verbose "Processing batch request with $($BatchRequests.Count) items"

            # The Graph API batch endpoint can handle up to 20 requests per batch
            $maxBatchSize = 20
            $batchResults = @{}
            $retries = 0

            do {
                try {
                    # Process requests in batches of 20
                    for ($i = 0; $i -lt $BatchRequests.Count; $i += $maxBatchSize) {
                        $currentBatchRequests = $BatchRequests | Select-Object -Skip $i -First $maxBatchSize

                        Write-Verbose "Processing batch $($i / $maxBatchSize + 1) with $($currentBatchRequests.Count) requests"

                        # Create the batch request payload
                        $payload = @{
                            requests = $currentBatchRequests
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

                        # Execute the batch request
                        try {
                            $response = Invoke-RestMethod @requestParam

                            # Process the responses and add to the results dictionary
                            foreach ($responseItem in $response.responses) {
                                $requestId = $responseItem.id
                                if ($responseItem.status -eq 200) {
                                    $batchResults[$requestId] = @{
                                        Success = $true
                                        Data = $responseItem.body
                                        Status = $responseItem.status
                                    }
                                }
                                else {
                                    $batchResults[$requestId] = @{
                                        Success = $false
                                        Error = $responseItem.body.error
                                        Status = $responseItem.status
                                    }

                                    # Handle 404 errors with verbose message instead of warning
                                    if ($responseItem.status -eq 404 -or
                                        ($responseItem.body.error -and (
                                            $responseItem.body.error.code -eq "Request_ResourceNotFound" -or
                                            $responseItem.body.error.code -eq "ResourceNotFound" -or
                                            $responseItem.body.error.message -match "not found" -or
                                            $responseItem.body.error.message -match "Invalid object identifier"
                                        ))
                                    ) {
                                        # Extract resource ID from the URL if possible
                                        $resourceIdMatch = $null
                                        if ($responseItem.body.error.message -match "'([^']+)'") {
                                            $resourceIdMatch = $matches[1]
                                        }
                                        $resourceId = $resourceIdMatch ?? "resource"

                                        Write-Verbose "Batch request $($requestId): Resource '$($resourceId)' not found or inaccessible (status $($responseItem.status))"
                                    }
                                    else {
                                        Write-Verbose "Request $requestId failed with status $($responseItem.status): $($responseItem.body.error.message)"
                                    }
                                }
                            }
                        }
                        catch {
                            Write-Warning "Error in batch request: $($_.Exception.Message)"
                            # Increment retry counter and continue to the next batch
                            $retries++
                            if ($retries -lt $MaxRetries) {
                                Start-Sleep -Seconds ($RetryDelaySeconds * $retries)
                                continue
                            }
                            else {
                                Write-Error "Max retries reached for batch request."
                                return $null
                            }
                        }
                    }

                    # Return the batch results
                    return $batchResults
                }
                catch {
                    Write-Warning "Error processing batch requests: $($_.Exception.Message)"
                    $retries++
                    if ($retries -lt $MaxRetries) {
                        Start-Sleep -Seconds ($RetryDelaySeconds * $retries)
                        continue
                    }
                    else {
                        Write-Error "Max retries reached for batch request."
                        return $null
                    }
                }
            } while ($retries -lt $MaxRetries)
            
            return $null
        }
        else {
            # Standard single request processing
            $cacheParams = @{
                NoBatch = $NoBatch.IsPresent
            }
            $cacheKey = ConvertTo-CacheKey -BaseIdentifier $relativeUrl -Parameters $cacheParams
            
            if (-not $SkipCache) {
                try {
                    $cachedResult = Get-BlackCatCache -Key $cacheKey -CacheType 'MSGraph'
                    if ($null -ne $cachedResult) {
                        Write-Verbose "Retrieved result from cache for: $relativeUrl"
                        
                        $formatParam = @{
                            Data         = $cachedResult
                            OutputFormat = $OutputFormat
                            FunctionName = $MyInvocation.MyCommand.Name
                            FilePrefix   = 'MSGraph'
                        }
                        return Format-BlackCatOutput @formatParam
                    }
                }
                catch {
                    Write-Verbose "Error retrieving from cache: $($_.Exception.Message). Proceeding with fresh API call."
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
                    }
                    catch {
                        if ($Err) {
                            $ErrorMessage = $null
                            try {
                                $ErrorMessage = ($Err.Message | ConvertFrom-Json).error.message
                            }
                            catch {
                                $ErrorMessage = $Err.Message
                            }
                            
                            # Check if this is a resource not found or invalid ID error
                            if ($ErrorMessage -match "not exist|not found|Invalid object identifier") {
                                # For resource not found errors, just log verbose and return null without error
                                $resourceId = "unknown"
                                if ($ErrorMessage -match "'([^']+)'") {
                                    $resourceId = $matches[1]
                                }
                                Write-Verbose "Resource '$resourceId' not found or invalid identifier (non-fatal error)"
                                return $null
                            }
                            else {
                                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "$($ErrorMessage)" -Severity 'Error'
                            }
                        }
                        return $null
                    }

                    if ($null -eq $initialResponse) {
                        Write-Verbose "No data returned from API call to: $relativeUrl"
                        return $null
                    }

                    try {
                        if ($NoBatch) {
                            $result = $initialResponse
                        }
                        else {
                            if ($initialResponse.Headers."Retry-After") {
                                $retryAfter = [int]$initialResponse.Headers."Retry-After"
                                Write-Warning "Throttled!  Waiting $($retryAfter) seconds before retrying."
                                Start-Sleep -Seconds $retryAfter
                                $retries++ # Increment retries, important to track
                                continue   # Skip the rest of the loop and retry
                            }

                            $allItems = Get-AllPages -ProcessLink $initialResponse
                            $result = $allItems
                        }

                        # Check for batch request that returned no results
                        if ($null -eq $result -or ($result -is [array] -and $result.Count -eq 0)) {
                            Write-Verbose "No data found for: $relativeUrl"
                            return $null
                        }
                    }
                    catch {
                        Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Error processing response: $($_.Exception.Message)" -Severity 'Error'
                        return $null
                    }

                    if (-not $SkipCache -and $null -ne $result) {
                        try {
                            Set-BlackCatCache -Key $cacheKey -Data $result -ExpirationMinutes $CacheExpirationMinutes -CacheType 'MSGraph' -MaxCacheSize $MaxCacheSize -CompressData:$CompressCache
                            Write-Verbose "Cached result for: $relativeUrl (expires in $CacheExpirationMinutes minutes)"
                        }
                        catch {
                            Write-Verbose "Failed to cache result for: $relativeUrl - $($_.Exception.Message)"
                        }
                    }

                    if ($null -eq $result) {
                        Write-Verbose "No data to format for: $relativeUrl"
                        return $null
                    }

                    $formatParam = @{
                        Data         = $result
                        OutputFormat = $OutputFormat
                        FunctionName = $MyInvocation.MyCommand.Name
                        FilePrefix   = 'MSGraph'
                    }
                    return Format-BlackCatOutput @formatParam
                }
                catch {
                    # Handle throttling errors
                    if ($_.Exception.Response.StatusCode -eq 429 ||
                        $_.Exception.Message -match "429" ||
                        $_.Exception.Message -match "too many requests") {
                        
                        $retryAfter = $RetryDelaySeconds * ($retries + 1) # Exponential backoff

                        # Try to get the retry-after header if available
                        if ($_.Exception.Response -and $_.Exception.Response.Headers -and $_.Exception.Response.Headers."Retry-After") {
                            $retryAfter = [int]$_.Exception.Response.Headers."Retry-After"
                        }

                        $retries++
                        Write-Warning "Throttled! Retry $($retries) of $($MaxRetries). Waiting $($retryAfter) seconds before retrying."
                        Start-Sleep -Seconds $retryAfter
                    }
                    # Handle authentication errors
                    elseif ($_.Exception.Response.StatusCode -eq 401 ||
                           $_.Exception.Message -match "401" ||
                           $_.Exception.Message -match "unauthorized" -or
                           $_.Exception.Message -match "access.*denied") {

                        Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Unauthorized access to the Graph API. Your token might be expired or invalid." -Severity 'Error'
                        break
                    }
                    # Handle not found errors with verbose logging instead of errors
                    elseif ($_.Exception.Response.StatusCode -eq 404 ||
                           $_.Exception.Message -match "404" ||
                           $_.Exception.Message -match "not found" ||
                           $_.Exception.Message -match "Invalid object identifier" ||
                           $_.Exception.Message -match "does not exist") {

                        $resourceId = $relativeUrl -replace '.*/([^/]+)$', '$1'
                        Write-Verbose "Resource not found: $resourceId - it may have been deleted or you may not have access"
                        return $null
                    }
                    else {
                        Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'

                        if ($retries -lt $MaxRetries) {
                            $retries++
                            $retryAfter = $RetryDelaySeconds * $retries # Exponential backoff
                            Write-Warning "Error occurred. Retry $retries of $MaxRetries. Waiting $retryAfter seconds before retrying."
                            Start-Sleep -Seconds $retryAfter
                        }
                        else {
                            break
                        }
                    }
                }
            } while ($retries -lt $MaxRetries)

            if ($retries -ge $MaxRetries) {
                Write-Error "Max retries reached. Failed to execute request after $($MaxRetries) attempts."
            }

            return $null
        }
    }

    end {
        # Empty end block to complete the function structure
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
        Used in the standard parameter set for single requests.

    .PARAMETER BatchRequests
        An array of request objects for batch processing. Each request should be a hashtable with:
        - id: A unique identifier for the request
        - method: HTTP method (typically "GET")
        - url: The relative URL for the request (starting with "/")
        Used in the BatchRequest parameter set for efficiently processing multiple requests at once.

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

    .NOTES
        This function requires appropriate Microsoft Graph permissions for the requested resource.

    .LINK
        MITRE ATT&CK Tactic: TA0007 - Discovery
        https://attack.mitre.org/tactics/TA0007/

    .LINK
        MITRE ATT&CK Technique: T1526 - Cloud Service Discovery
        https://attack.mitre.org/techniques/T1526/
    #>
}