function Invoke-AzBatch {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^Microsoft\.[A-Za-z]+(/[A-Za-z]+)+$|^$')]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceTypeCompleterAttribute()]
        [Alias('resource-type')]
        [string]$ResourceType,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias('resource-name', 'ResourceName')]
        [string]$Name,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [switch]$Silent,

        [Parameter(Mandatory = $false)]
        [string]$filter,

        [Parameter(Mandatory = $false)]
        [switch]$SkipCache,

        [Parameter(Mandatory = $false)]
        [int]$CacheExpirationMinutes = 30,

        [Parameter(Mandatory = $false)]
        [int]$MaxCacheSize = 100,

        [Parameter(Mandatory = $false)]
        [switch]$CompressCache,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Object', 'JSON', 'CSV', 'Table')]
        [Alias('output', 'o')]
        [string]$OutputFormat = 'Object'
    )

    begin {

        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {
        $cacheParams = @{
            ResourceType = $ResourceType
            Name = $Name
            Filter = $filter
            Silent = $Silent.IsPresent
        }
        $baseIdentifier = "azbatch"
        $cacheKey = ConvertTo-CacheKey -BaseIdentifier $baseIdentifier -Parameters $cacheParams

        if (-not $SkipCache) {
            try {
                $cachedResult = Get-BlackCatCache -Key $cacheKey -CacheType 'AzBatch'
                if ($null -ne $cachedResult) {
                    Write-Verbose "Retrieved result from cache for Azure Batch query"
                    return $cachedResult
                }
            }
            catch {
                Write-Verbose "Error retrieving from cache: $($_.Exception.Message). Proceeding with fresh API call."
            }
        }

        try {
            $allResources = @()
            $skipToken = $null
            $pageCount = 0

            do {
                $pageCount++
                Write-Verbose "Retrieving page $pageCount of resources"

                $payload = @{
                    requests = @(
                        @{
                            httpMethod = 'POST'
                            url        = $($sessionVariables.resourceGraphUri)
                            content    = @{
                                query = "resources"
                            }
                        }
                    )
                }

                if (![string]::IsNullOrEmpty($ResourceType)) {
                    $payload.requests[0].content.query = "resources | where type == '$($ResourceType.ToLower())'"
                }

                if (![string]::IsNullOrEmpty($Name)) {
                    $payload.requests[0].content.query += " | where name == '$($Name)'"
                    Write-Output "Filtering resources by name: $Name"
                }

                if (![string]::IsNullOrEmpty($filter)) {
                    $payload.requests[0].content.query += "$filter"
                    Write-Output "Filtering resources with: $($payload.requests[0].content.query)"
                }

                # Add skipToken to the request if available
                if ($skipToken) {
                    if (!$payload.requests[0].content.options) {
                        $payload.requests[0].content.options = @{}
                    }
                    $payload.requests[0].content.options.'$skipToken' = $skipToken
                    Write-Verbose "Using skipToken for pagination: $skipToken"
                }

                $requestParam = @{
                    Headers     = $script:authHeader
                    Uri         = $sessionVariables.batchUri
                    Method      = 'POST'
                    ContentType = 'application/json'
                    Body        = $payload | ConvertTo-Json -Depth 10
                    UserAgent   = $($sessionVariables.userAgent)
                }

                Write-Verbose "Making API request using User-Agent: $($sessionVariables.userAgent)"
                $response = Invoke-RestMethod @requestParam
                $pageData = $response.responses.content.data

                if ($pageData) {
                    $allResources += $pageData
                    Write-Verbose "Retrieved $($pageData.Count) resources on page $pageCount. Total count: $($allResources.Count)"
                }

                # Get skipToken for next page if it exists
                $skipToken = $response.responses.content.'$skipToken'

            } while ($skipToken)

            if ($allResources.Count -eq 0) {
                if (-not $Silent) {
                    Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "No resources found" -Severity 'Information'
                }
                return $null
            }

            if (-not $SkipCache -and $null -ne $allResources) {
                try {
                    Set-BlackCatCache -Key $cacheKey -Data $allResources -ExpirationMinutes $CacheExpirationMinutes -CacheType 'AzBatch' -MaxCacheSize $MaxCacheSize -CompressData:$CompressCache
                    Write-Verbose "Cached Azure Batch result (expires in $CacheExpirationMinutes minutes)"
                }
                catch {
                    Write-Verbose "Failed to cache Azure Batch result - $($_.Exception.Message)"
                }
            }

            $formatParam = @{
                Data          = $allResources
                OutputFormat  = $OutputFormat
                FunctionName  = $MyInvocation.MyCommand.Name
                FilePrefix    = 'AzBatch'
                Silent        = $Silent.IsPresent
            }
            return Format-BlackCatOutput @formatParam
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
    <#
    .SYNOPSIS
        Invokes Azure Resource Graph queries using batch requests with caching support.

    .DESCRIPTION
        This function sends batch requests to Azure Resource Graph API to query Azure resources.
        It supports filtering by resource type, name, and custom filters. The function includes
        automatic pagination, caching for improved performance, and comprehensive error handling.

    .PARAMETER ResourceType
        The Azure resource type to filter by (e.g., 'Microsoft.Storage/storageAccounts').
        Must follow the format 'Microsoft.Provider/resourceType'.

    .PARAMETER Name
        The specific resource name to filter by. When specified, only resources with this exact name will be returned.

    .PARAMETER Silent
        When specified, suppresses informational messages about no resources found.

    .PARAMETER filter
        Additional KQL (Kusto Query Language) filter to apply to the resource query.
        This is appended to the base query for advanced filtering.

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
        Recommended for large environments with many resources.

    .PARAMETER OutputFormat
        Specifies the output format for the results. Valid values are:
        - Object: Returns PowerShell objects (default)
        - JSON: Exports results to a timestamped JSON file and displays file path
        - CSV: Exports results to a timestamped CSV file and displays file path
        - Table: Displays results in a formatted table and returns objects
        Default is 'Object'. Supports aliases 'output' and 'o'.

    .EXAMPLE
        Invoke-AzBatch -ResourceType "Microsoft.Storage/storageAccounts"

        This example retrieves all storage accounts in the current subscription context.

    .EXAMPLE
        Invoke-AzBatch -ResourceType "Microsoft.Compute/virtualMachines" -Name "myVM"

        This example retrieves a specific virtual machine named "myVM".

    .EXAMPLE
        Invoke-AzBatch -ResourceType "Microsoft.KeyVault/vaults" -SkipCache

        This example forces a fresh API call to retrieve key vaults, bypassing any cached results.

    .EXAMPLE
        Invoke-AzBatch -ResourceType "Microsoft.Storage/storageAccounts" -filter "| where location == 'eastus'"

        This example retrieves storage accounts in the East US region using a custom filter.

    .EXAMPLE
        Invoke-AzBatch -ResourceType "Microsoft.Compute/virtualMachines" -CacheExpirationMinutes 60

        This example retrieves virtual machines and caches the results for 60 minutes instead of the default 30 minutes.

    .EXAMPLE
        Invoke-AzBatch -ResourceType "Microsoft.Storage/storageAccounts" -MaxCacheSize 50 -CompressCache

        This example retrieves storage accounts with a smaller cache size and enables compression for large environments.

    .EXAMPLE
        Invoke-AzBatch -ResourceType "Microsoft.Network/virtualNetworks" -CompressCache

        This example retrieves virtual networks and compresses the cached data to reduce memory usage.

    .NOTES
        - This function requires appropriate Azure permissions to query resources
        - Results are automatically cached to improve performance for repeated queries
        - Use Get-BlackCatCacheStats to monitor cache usage
        - The function handles pagination automatically for large result sets

    .LINK
        MITRE ATT&CK Tactic: TA0007 - Discovery
        https://attack.mitre.org/tactics/TA0007/

    .LINK
        MITRE ATT&CK Technique: T1526 - Cloud Service Discovery
        https://attack.mitre.org/techniques/T1526/
    #>
}