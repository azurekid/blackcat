function Find-AzurePublicResource {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9-]+[A-Za-z0-9]$', ErrorMessage = "It does not match expected pattern '{1}'")]
        [string]$Name,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias("word-list", "w")]
        [string]$WordList,

        [Parameter(Mandatory = $false)]
        [Alias("throttle-limit", 't', 'threads')]
        [int]$ThrottleLimit = 50,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Object", "JSON", "CSV", "Table")]
        [Alias("output", "o")]
        [string]$OutputFormat,

        [Parameter(Mandatory = $false)]
        [Alias("no-cache", "bypass-cache")]
        [switch]$SkipCache,

        [Parameter(Mandatory = $false)]
        [Alias("cache-expiration", "expiration")]
        [int]$CacheExpirationMinutes = 30,

        [Parameter(Mandatory = $false)]
        [Alias("max-cache")]
        [int]$MaxCacheSize = 100,

        [Parameter(Mandatory = $false)]
        [Alias("compress")]
        [switch]$CompressCache,

        [Parameter(Mandatory = $false)]
        [Alias("private-links", "private-link")]
        [switch]$PrivateLinkOnly,

        [Parameter(Mandatory = $false)]
        [Alias("fast", "quick")]
        [switch]$FastMode
    )

    begin {
        $validDnsNames  = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
        $results        = [System.Collections.Concurrent.ConcurrentBag[psobject]]::new()
        $foundResources = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
    }

    process {
        $searchScope = if ($PrivateLinkOnly) {
            'Azure Private Link resources'
        }
        else {
            'Azure public resources'
        }

        Write-Host " Analyzing $searchScope for: $Name" -ForegroundColor Green

        # Generate cache key and check for cached results
        $cacheParams = @{
            Name            = $Name
            FastMode        = $FastMode.IsPresent
            PrivateLinkOnly = $PrivateLinkOnly.IsPresent
        }
        $cacheKey = ConvertTo-CacheKey `
            -BaseIdentifier "Find-AzurePublicResource" `
            -Parameters $cacheParams

        if (-not $SkipCache) {
            try {
                $cachedResult = Get-BlackCatCache -Key $cacheKey -CacheType 'General'
                if ($null -ne $cachedResult) {
                    Write-Verbose "Retrieved Azure resource results from cache for: $Name"
                    foreach ($item in $cachedResult) { $results.Add($item) }
                    return
                }
            }
            catch {
                Write-Verbose "Error retrieving from cache: $($_.Exception.Message). Proceeding with fresh queries."
            }
        }

        try {
            if ($WordList) {
                Write-Host "   Loading permutations from word list..." -ForegroundColor Cyan
                $permutations = [System.Collections.Generic.HashSet[string]](Get-Content $WordList)
                Write-Host "     Loaded $($permutations.Count) permutations from '$WordList'" -ForegroundColor Green
            } else {
                $permutations = [System.Collections.Generic.HashSet[string]]::new()
            }

            if ($sessionVariables.permutations) {
                Write-Host "   Loading session permutations..." -ForegroundColor Cyan
                foreach ($item in $sessionVariables.permutations) { [void]$permutations.Add($item) }
                Write-Host "     Loaded total of $($permutations.Count) permutations" -ForegroundColor Green
            }

            # Always include the base name without any suffix
            if (-not $permutations.Contains('')) { [void]$permutations.Add('') }

            # Add CAF resource abbreviations (https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations)
            $resourceAbbreviations = @(
                'st', 'sa', 'kv', 'acr', 'app', 'func', 'web', 'api', 'apim', 'sql', 'sqlmi', 'sqlsrv', 'mysql', 'psql', 'cosmos', 'mongo', 'redis', 'sb', 'evh', 'cdn', 'edge', 'ai', 'ml', 'syn', 'synw', 'synp', 'vh', 'aks', 'aksnode', 'vm', 'vmss', 'vnet', 'subnet', 'nsg', 'fw', 'appgw', 'bastion', 'dns', 'pip'
            )
            $resourceAbbreviations | ForEach-Object { [void]$permutations.Add("-$_") ; [void]$permutations.Add("$_") }

            Write-Host "   Generating Azure service DNS names..." -ForegroundColor Yellow
            if ($FastMode) {
                Write-Host "   Fast mode enabled: using high-signal Azure endpoint suffixes only..." -ForegroundColor Cyan
            }

            $dnsNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

            $publicDomains = @(
                # Storage
                'blob.core.windows.net',
                'file.core.windows.net',
                'table.core.windows.net',
                'queue.core.windows.net',
                'dfs.core.windows.net',

                # Databases
                'database.windows.net',
                'documents.azure.com',
                'redis.cache.windows.net',
                'mysql.database.azure.com',
                'postgres.database.azure.com',
                'mariadb.database.azure.com',

                # Security
                'vault.azure.net',

                # Compute & Containers
                'azurecr.io',
                'azurewebsites.net',
                'scm.azurewebsites.net',

                # AI/ML
                'cognitiveservices.azure.com',
                'openai.azure.com',
                'search.windows.net',
                'azureml.net',

                # Integration
                'servicebus.windows.net',
                'azure-api.net',
                'service.signalr.net',
                'webpubsub.azure.com',

                # Other
                'azureedge.net',
                'azure-devices.net',
                'eventgrid.azure.net',
                'azuremicroservices.io',
                'azuresynapse.net',
                'batch.azure.com'
            )

            $privateLinkDomains = @(
                # Storage
                'privatelink.blob.core.windows.net',
                'privatelink.file.core.windows.net',
                'privatelink.table.core.windows.net',
                'privatelink.queue.core.windows.net',
                'privatelink.dfs.core.windows.net',

                # Databases
                'privatelink.database.windows.net',
                'privatelink.documents.azure.com',
                'privatelink.redis.cache.windows.net',
                'privatelink.mysql.database.azure.com',
                'privatelink.postgres.database.azure.com',
                'privatelink.mariadb.database.azure.com',

                # Security
                'privatelink.vaultcore.azure.net',

                # Compute & Containers
                'privatelink.azurecr.io',
                'privatelink.azurewebsites.net',
                'privatelink.scm.azurewebsites.net',

                # AI/ML
                'privatelink.cognitiveservices.azure.com',
                'privatelink.search.windows.net',
                'privatelink.azureml.net',

                # Integration
                'privatelink.servicebus.windows.net',
                'privatelink.azure-api.net',
                'privatelink.service.signalr.net',
                'privatelink.webpubsub.azure.com',

                # Other
                'privatelink.eventgrid.azure.net',
                'privatelink.azuremicroservices.io',
                'privatelink.azuresynapse.net'
            )

            $fastPublicDomains = @(
                'blob.core.windows.net',
                'vault.azure.net',
                'azurewebsites.net',
                'scm.azurewebsites.net',
                'azurecr.io',
                'openai.azure.com',
                'search.windows.net',
                'servicebus.windows.net',
                'azure-api.net',
                'azureedge.net'
            )

            $fastPrivateLinkDomains = @(
                'privatelink.blob.core.windows.net',
                'privatelink.vaultcore.azure.net',
                'privatelink.azurewebsites.net',
                'privatelink.scm.azurewebsites.net',
                'privatelink.azurecr.io',
                'privatelink.search.windows.net',
                'privatelink.servicebus.windows.net',
                'privatelink.azure-api.net'
            )

            $domains = if ($PrivateLinkOnly) {
                if ($FastMode) {
                    $fastPrivateLinkDomains
                }
                else {
                    $privateLinkDomains
                }
            }
            else {
                if ($FastMode) {
                    $fastPublicDomains
                }
                else {
                    $publicDomains
                }
            }

            foreach ($domain in $domains) {
                # Add the base candidate once per domain instead of
                # re-adding it for every permutation.
                [void]$dnsNames.Add(('{0}.{1}' -f $Name, $domain))

                foreach ($permutation in $permutations) {
                    if ([string]::IsNullOrEmpty($permutation)) {
                        continue
                    }

                    [void]$dnsNames.Add(
                        ('{0}{1}.{2}' -f $Name, $permutation, $domain)
                    )
                    [void]$dnsNames.Add(
                        ('{1}{0}.{2}' -f $Name, $permutation, $domain)
                    )
                }
            }

            $totalDns = $dnsNames.Count
            Write-Host "     Testing $totalDns DNS name candidates..." -ForegroundColor Yellow
            Write-Host "   Starting DNS resolution with $ThrottleLimit concurrent threads..." -ForegroundColor Cyan

            $dnsNames | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
                try {
                    $validDnsNames = $using:validDnsNames
                    $results = $using:results
                    $foundResources = $using:foundResources
                    $recordTypes = [System.Collections.Generic.HashSet[string]]::new()
                    $cnameTarget = $null
                    $dnsResult = $null

                    try {
                        $dnsResult = [System.Net.Dns]::GetHostEntry($_)
                        if ($dnsResult -and $dnsResult.AddressList.Count -gt 0) {
                            [void]$recordTypes.Add('A')
                        }

                        if (
                            $dnsResult -and
                            $dnsResult.HostName -and
                            $dnsResult.HostName.TrimEnd('.') -ne $_.TrimEnd('.')
                        ) {
                            $cnameTarget = $dnsResult.HostName.TrimEnd('.')
                            [void]$recordTypes.Add('CNAME')
                        }
                    }
                    catch [System.Net.Sockets.SocketException] {
                    }

                    if ($recordTypes.Count -gt 0) {
                        $resourceTypeBase = switch -Regex ($_) {
                            # Storage
                            '\.blob\.core\.windows\.net$' { 'StorageBlob'; break }
                            '\.file\.core\.windows\.net$' { 'StorageFile'; break }
                            '\.table\.core\.windows\.net$' { 'StorageTable'; break }
                            '\.queue\.core\.windows\.net$' { 'StorageQueue'; break }
                            '\.dfs\.core\.windows\.net$' { 'DataLakeStorage'; break }
                            '\.privatelink\.blob\.core\.windows\.net$' { 'StorageBlob'; break }
                            '\.privatelink\.file\.core\.windows\.net$' { 'StorageFile'; break }
                            '\.privatelink\.table\.core\.windows\.net$' { 'StorageTable'; break }
                            '\.privatelink\.queue\.core\.windows\.net$' { 'StorageQueue'; break }
                            '\.privatelink\.dfs\.core\.windows\.net$' { 'DataLakeStorage'; break }

                            # Databases
                            '\.database\.windows\.net$' { 'SqlDatabase'; break }
                            '\.documents\.azure\.com$' { 'CosmosDB'; break }
                            '\.redis\.cache\.windows\.net$' { 'RedisCache'; break }
                            '\.mysql\.database\.azure\.com$' { 'MySQL'; break }
                            '\.postgres\.database\.azure\.com$' { 'PostgreSQL'; break }
                            '\.mariadb\.database\.azure\.com$' { 'MariaDB'; break }
                            '\.privatelink\.database\.windows\.net$' { 'SqlDatabase'; break }
                            '\.privatelink\.documents\.azure\.com$' { 'CosmosDB'; break }
                            '\.privatelink\.redis\.cache\.windows\.net$' { 'RedisCache'; break }
                            '\.privatelink\.mysql\.database\.azure\.com$' { 'MySQL'; break }
                            '\.privatelink\.postgres\.database\.azure\.com$' { 'PostgreSQL'; break }
                            '\.privatelink\.mariadb\.database\.azure\.com$' { 'MariaDB'; break }

                            # Security
                            '\.vault\.azure\.net$' { 'KeyVault'; break }
                            '\.vaultcore\.azure\.net$' { 'KeyVault'; break }
                            '\.privatelink\.vaultcore\.azure\.net$' { 'KeyVault'; break }

                            # Compute & Containers
                            '\.azurecr\.io$' { 'ContainerRegistry'; break }
                            '\.azurewebsites\.net$' { 'AppService'; break }
                            '\.scm\.azurewebsites\.net$' { 'AppServiceKudu'; break }
                            '\.privatelink\.azurecr\.io$' { 'ContainerRegistry'; break }
                            '\.privatelink\.azurewebsites\.net$' { 'AppService'; break }
                            '\.privatelink\.scm\.azurewebsites\.net$' { 'AppServiceKudu'; break }

                            # AI/ML
                            '\.cognitiveservices\.azure\.com$' { 'CognitiveServices'; break }
                            '\.openai\.azure\.com$' { 'AzureOpenAI'; break }
                            '\.search\.windows\.net$' { 'AzureSearch'; break }
                            '\.azureml\.net$' { 'MachineLearning'; break }
                            '\.privatelink\.cognitiveservices\.azure\.com$' { 'CognitiveServices'; break }
                            '\.privatelink\.search\.windows\.net$' { 'AzureSearch'; break }
                            '\.privatelink\.azureml\.net$' { 'MachineLearning'; break }

                            # Integration
                            '\.servicebus\.windows\.net$' { 'ServiceBus'; break }
                            '\.azure-api\.net$' { 'APIManagement'; break }
                            '\.service\.signalr\.net$' { 'SignalR'; break }
                            '\.webpubsub\.azure\.com$' { 'WebPubSub'; break }
                            '\.privatelink\.servicebus\.windows\.net$' { 'ServiceBus'; break }
                            '\.privatelink\.azure-api\.net$' { 'APIManagement'; break }
                            '\.privatelink\.service\.signalr\.net$' { 'SignalR'; break }
                            '\.privatelink\.webpubsub\.azure\.com$' { 'WebPubSub'; break }

                            # Other
                            '\.azureedge\.net$' { 'CDN'; break }
                            '\.azure-devices\.net$' { 'IoTHub'; break }
                            '\.eventgrid\.azure\.net$' { 'EventGrid'; break }
                            '\.azuremicroservices\.io$' { 'SpringApps'; break }
                            '\.azuresynapse\.net$' { 'SynapseAnalytics'; break }
                            '\.batch\.azure\.com$' { 'AzureBatch'; break }
                            '\.privatelink\.eventgrid\.azure\.net$' { 'EventGrid'; break }
                            '\.privatelink\.azuremicroservices\.io$' { 'SpringApps'; break }
                            '\.privatelink\.azuresynapse\.net$' { 'SynapseAnalytics'; break }
                            default { 'Unknown' }
                        }
                        $isPrivateLink = $_ -match '\.privatelink\.'
                        $resourceName = $_.Split('.')[0]

                        $ipAddresses = if ($dnsResult) {
                            $dnsResult.AddressList.IPAddressToString -join ", "
                        }

                        $endpointType = if ($isPrivateLink) { 'PrivateLink' } else { 'Public' }
                        $resourceType = if ($isPrivateLink) {
                            "$resourceTypeBase-PrivateLink"
                        }
                        else { $resourceTypeBase }

                        $obj = [PSCustomObject]@{
                            Domain         = $_
                            RecordType     = ($recordTypes -join ',')
                            Data           = $ipAddresses
                            TTL            = $null
                            DNSProvider    = "System.Net.Dns"
                            ProviderType   = "System"
                            ProviderRegion = "Local"
                            Reliability    = $null
                            Timestamp      = Get-Date
                            QueryMethod    = "GetHostEntry"
                            ResourceName   = $resourceName
                            BaseResource   = $resourceTypeBase
                            ResourceType   = $resourceType
                            EndpointType   = $endpointType
                            Uri            = "https://$_"
                            HostName       = if ($dnsResult) { $dnsResult.HostName }
                            IPAddress      = if ($dnsResult) { $dnsResult.AddressList }
                            PrivateLink    = $isPrivateLink
                            CNameTarget    = $cnameTarget
                        }
                        $results.Add($obj)

                        $foundMessage = "       $resourceName -> $ipAddresses [$resourceType]"
                        if ($isPrivateLink) { $foundMessage = "$foundMessage [PrivateLink]" }
                        if ($cnameTarget) { $foundMessage = "$foundMessage CNAME:$cnameTarget" }
                        $foundResources.Add($foundMessage)
                    }
                }
                catch {
                }
            }

            # Cache results, including empty result sets, so
            # repeated misses do not re-run the full enumeration.
            if (-not $SkipCache) {
                try {
                    $resultsToCache = if ($results.Count -gt 0) {
                        [array]$results
                    }
                    else {
                        @()
                    }

                    Set-BlackCatCache -Key $cacheKey -Data $resultsToCache `
                        -ExpirationMinutes $CacheExpirationMinutes `
                        -CacheType 'General' -MaxCacheSize $MaxCacheSize `
                        -CompressData:$CompressCache
                    Write-Verbose "Cached Azure resource results for: $Name (expires in $CacheExpirationMinutes minutes)"
                }
                catch {
                    Write-Verbose "Failed to cache results: $($_.Exception.Message)"
                }
            }

            # Display found resources immediately after parallel processing
            if ($foundResources.Count -gt 0) {
                foreach ($message in $foundResources) {
                    Write-Host $message -ForegroundColor Green
                }
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }

    end {
        Write-Verbose "Function $($MyInvocation.MyCommand.Name) completed"

        $noResultsMessage = if ($PrivateLinkOnly) {
            'No Azure Private Link resources found'
        }
        else {
            'No public Azure resources found'
        }

        if ($results -and $results.Count -gt 0) {
            Write-Host "`n Azure Resource Discovery Summary:" -ForegroundColor Magenta
            Write-Host "   Total Resources Found: $($results.Count)" -ForegroundColor Yellow

            # Group by resource type for summary
            $resourceTypeCounts = $results | Group-Object ResourceType | Sort-Object Count -Descending
            foreach ($group in $resourceTypeCounts) {
                Write-Host "   $($group.Name): $($group.Count)" -ForegroundColor White
            }

            # Return results in requested format
                switch ($OutputFormat) {
                    "JSON" { return $results | ConvertTo-Json -Depth 3 }
                    "CSV" { return $results | ConvertTo-CSV }
                    "Object" { return $results }
                    "Table"  { return $results | Format-Table -AutoSize }
                }
        }
        else {
            Write-Host "`n $noResultsMessage" -ForegroundColor Red
            Write-Information $noResultsMessage -InformationAction Continue
        }
    }
<#
.SYNOPSIS
    Finds publicly accessible Azure resources.

.DESCRIPTION
    Discovers Azure resource endpoints through DNS permutation and testing.
    By default it enumerates publicly accessible Azure resources. When
    PrivateLinkOnly is specified, it limits enumeration to Azure Private
    Link endpoints.

.PARAMETER Name
    The base name of the Azure resource to search for. Must match the pattern: starts and ends with an alphanumeric character, and may contain hyphens.

.PARAMETER WordList
    Optional. Path to a file containing additional words (one per line) to use for generating name permutations.
    These words will be combined with the base name to create potential resource names.
    Aliases: word-list, w

.PARAMETER ThrottleLimit
    Optional. The maximum number of concurrent DNS resolution operations. Default is 50.
    Adjust based on system resources and network capacity.
    Aliases: throttle-limit, t, threads

.PARAMETER OutputFormat
    Optional. Specifies the output format for results. Valid values are:
    - Object: Returns PowerShell objects (default when piping)
    - JSON: Returns results in JSON format
    - CSV: Returns results in CSV format
    Aliases: output, o

.PARAMETER SkipCache
    Bypasses the cache and forces a fresh DNS enumeration.
    Default: False (cache is used if available)

.PARAMETER CacheExpirationMinutes
    Number of minutes to store results in cache before expiry.
    Default: 30 minutes

.PARAMETER MaxCacheSize
    Maximum number of entries to keep in the cache (LRU eviction).
    Default: 100

.PARAMETER CompressCache
    Enables compression of cached data to reduce memory usage.

.PARAMETER PrivateLinkOnly
    Limits DNS enumeration to Azure Private Link endpoint suffixes only.
    This skips public Azure endpoint suffixes and is useful when searching
    specifically for private endpoint naming patterns.

.PARAMETER FastMode
    Reduces the search scope to high-signal Azure endpoint suffixes only.
    This improves runtime but may miss resources that only appear on less
    common Azure service domains.

.EXAMPLE
    Find-AzurePublicResource -Name "contoso" -WordList "./wordlist.txt" -ThrottleLimit 100 -OutputFormat JSON

    Searches for Azure resources using "contoso" with custom permutations from wordlist.txt,
    using 100 concurrent threads, and returns results in JSON format.

.EXAMPLE
    Find-AzurePublicResource -Name "example" -OutputFormat Table

    Searches for Azure resources and displays results in a formatted table.

.EXAMPLE
    Find-AzurePublicResource -Name "contoso" -PrivateLinkOnly

    Searches only Azure Private Link DNS suffixes for resources matching
    the name "contoso".

.EXAMPLE
    Find-AzurePublicResource -Name "contoso" -FastMode

    Searches a reduced, high-signal set of public Azure endpoint suffixes
    for faster initial triage.

.EXAMPLE
    Find-AzurePublicResource -Name "contoso" -PrivateLinkOnly -FastMode

    Searches a reduced, high-signal set of Azure Private Link endpoint
    suffixes for faster private endpoint triage.



.NOTES
    - Requires PowerShell 7+ for parallel processing functionality
    - Useful for reconnaissance and security assessments of Azure environments
    - Only DNS names that successfully resolve are returned as results
    - FastMode prioritizes speed over coverage by reducing endpoint suffixes

.LINK
    MITRE ATT&CK Tactic: TA0043 - Reconnaissance
    https://attack.mitre.org/tactics/TA0043/

.LINK
    MITRE ATT&CK Technique: T1593.002 - Search Open Websites/Domains: Search Engines
    https://attack.mitre.org/techniques/T1593/002/
#>
}