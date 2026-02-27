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
        [ValidateSet("Object", "JSON", "CSV")]
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
        [switch]$CompressCache
    )

    begin {
        $validDnsNames = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
    }

    process {
        Write-Host " Analyzing Azure resources for: $Name" -ForegroundColor Green

        # Generate cache key and check for cached results
        $cacheParams = @{ Name = $Name }
        $cacheKey = ConvertTo-CacheKey `
            -BaseIdentifier "Find-AzurePublicResource" `
            -Parameters $cacheParams

        if (-not $SkipCache) {
            try {
                $cachedResult = Get-BlackCatCache -Key $cacheKey -CacheType 'General'
                if ($null -ne $cachedResult) {
                    Write-Verbose "Retrieved Azure resource results from cache for: $Name"
                    return $cachedResult
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

            $dnsNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

            $domains = @(
                # Storage
                'blob.core.windows.net',           # Blob Storage
                'file.core.windows.net',           # File Storage
                'table.core.windows.net',          # Table Storage
                'queue.core.windows.net',          # Queue Storage
                'dfs.core.windows.net',            # Data Lake Storage Gen2
                'privatelink.blob.core.windows.net',   # Blob Private Link
                'privatelink.file.core.windows.net',   # File Private Link
                'privatelink.table.core.windows.net',  # Table Private Link
                'privatelink.queue.core.windows.net',  # Queue Private Link
                'privatelink.dfs.core.windows.net',    # ADLS Gen2 Private

                # Databases
                'database.windows.net',            # SQL Database
                'documents.azure.com',             # Cosmos DB
                'redis.cache.windows.net',         # Redis Cache
                'mysql.database.azure.com',        # MySQL
                'postgres.database.azure.com',     # PostgreSQL
                'mariadb.database.azure.com',      # MariaDB
                'privatelink.database.windows.net',    # SQL Private Link
                'privatelink.documents.azure.com',     # Cosmos Private Link
                'privatelink.redis.cache.windows.net', # Redis Private Link
                'privatelink.mysql.database.azure.com',# MySQL Private Link
                'privatelink.postgres.database.azure.com', # PostgreSQL Private
                'privatelink.mariadb.database.azure.com',  # MariaDB Private

                # Security
                'vault.azure.net',                 # Key Vault
                'privatelink.vaultcore.azure.net', # Key Vault Private Link

                # Compute & Containers
                'azurecr.io',                      # Container Registry
                'azurewebsites.net',               # App Service/Functions
                'scm.azurewebsites.net',           # App Service Kudu
                'privatelink.azurecr.io',          # ACR Private Link
                'privatelink.azurewebsites.net',   # App Service Private Link
                'privatelink.scm.azurewebsites.net', # Kudu Private Link

                # AI/ML
                'cognitiveservices.azure.com',
                'openai.azure.com',                # Azure OpenAI
                'search.windows.net',              # Azure Search
                'azureml.net',                     # Machine Learning
                'privatelink.cognitiveservices.azure.com', # Cognitive Private
                'privatelink.search.windows.net',  # Search Private Link
                'privatelink.azureml.net',         # Machine Learning Private

                # Integration
                'servicebus.windows.net',
                'azure-api.net',                   # API Management
                'service.signalr.net',             # SignalR Service
                'webpubsub.azure.com',             # Web PubSub
                'privatelink.servicebus.windows.net', # Service Bus Private
                'privatelink.azure-api.net',       # API Management Private
                'privatelink.service.signalr.net', # SignalR Private Link
                'privatelink.webpubsub.azure.com', # Web PubSub Private

                # Other
                'azureedge.net',                   # CDN
                'azure-devices.net',               # IoT Hub
                'eventgrid.azure.net',             # Event Grid
                'azuremicroservices.io',           # Spring Apps
                'azuresynapse.net',                # Synapse Analytics
                'batch.azure.com',                 # Azure Batch
                'privatelink.eventgrid.azure.net', # Event Grid Private Link
                'privatelink.azuremicroservices.io', # Spring Apps Private
                'privatelink.azuresynapse.net'     # Synapse Private Link
            )

            $domains | ForEach-Object {
                $domain = $_
                $permutations | ForEach-Object {
                    [void] $dnsNames.Add(('{0}{1}.{2}' -f $Name, $_, $domain))
                    [void] $dnsNames.Add(('{1}{0}.{2}' -f $Name, $_, $domain))
                    [void] $dnsNames.Add(('{0}.{1}' -f $Name, $domain))
                }
            }

            $totalDns = $dnsNames.Count
            Write-Host "     Testing $totalDns DNS name candidates..." -ForegroundColor Yellow
            Write-Host "   Starting DNS resolution with $ThrottleLimit concurrent threads..." -ForegroundColor Cyan

            $results = [System.Collections.Concurrent.ConcurrentBag[psobject]]::new()

            # Create a thread-safe collection to track found resources for immediate display
            $foundResources = [System.Collections.Concurrent.ConcurrentBag[string]]::new()

            $dnsNames | Sort-Object -Unique | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
                function Get-ResourceType {
                    param($dnsName)
                    switch -Regex ($dnsName) {
                        # Storage
                        '\.blob\.core\.windows\.net$'         { return 'StorageBlob' }
                        '\.file\.core\.windows\.net$'         { return 'StorageFile' }
                        '\.table\.core\.windows\.net$'        { return 'StorageTable' }
                        '\.queue\.core\.windows\.net$'        { return 'StorageQueue' }
                        '\.dfs\.core\.windows\.net$'          { return 'DataLakeStorage' }
                        '\.privatelink\.blob\.core\.windows\.net$' { return 'StorageBlob' }
                        '\.privatelink\.file\.core\.windows\.net$' { return 'StorageFile' }
                        '\.privatelink\.table\.core\.windows\.net$' { return 'StorageTable' }
                        '\.privatelink\.queue\.core\.windows\.net$' { return 'StorageQueue' }
                        '\.privatelink\.dfs\.core\.windows\.net$' { return 'DataLakeStorage' }

                        # Databases
                        '\.database\.windows\.net$'           { return 'SqlDatabase' }
                        '\.documents\.azure\.com$'            { return 'CosmosDB' }
                        '\.redis\.cache\.windows\.net$'       { return 'RedisCache' }
                        '\.mysql\.database\.azure\.com$'      { return 'MySQL' }
                        '\.postgres\.database\.azure\.com$'   { return 'PostgreSQL' }
                        '\.mariadb\.database\.azure\.com$'    { return 'MariaDB' }
                        '\.privatelink\.database\.windows\.net$' { return 'SqlDatabase' }
                        '\.privatelink\.documents\.azure\.com$' { return 'CosmosDB' }
                        '\.privatelink\.redis\.cache\.windows\.net$' { return 'RedisCache' }
                        '\.privatelink\.mysql\.database\.azure\.com$' { return 'MySQL' }
                        '\.privatelink\.postgres\.database\.azure\.com$' { return 'PostgreSQL' }
                        '\.privatelink\.mariadb\.database\.azure\.com$' { return 'MariaDB' }

                        # Security
                        '\.vault\.azure\.net$'                { return 'KeyVault' }
                        '\.vaultcore\.azure\.net$'            { return 'KeyVault' }
                        '\.privatelink\.vaultcore\.azure\.net$' { return 'KeyVault' }

                        # Compute & Containers
                        '\.azurecr\.io$'                      { return 'ContainerRegistry' }
                        '\.azurewebsites\.net$'               { return 'AppService' }
                        '\.scm\.azurewebsites\.net$'          { return 'AppServiceKudu' }
                        '\.privatelink\.azurecr\.io$'        { return 'ContainerRegistry' }
                        '\.privatelink\.azurewebsites\.net$' { return 'AppService' }
                        '\.privatelink\.scm\.azurewebsites\.net$' { return 'AppServiceKudu' }

                        # AI/ML
                        '\.cognitiveservices\.azure\.com$'    { return 'CognitiveServices' }
                        '\.openai\.azure\.com$'               { return 'AzureOpenAI' }
                        '\.search\.windows\.net$'             { return 'AzureSearch' }
                        '\.azureml\.net$'                     { return 'MachineLearning' }
                        '\.privatelink\.cognitiveservices\.azure\.com$' { return 'CognitiveServices' }
                        '\.privatelink\.search\.windows\.net$' { return 'AzureSearch' }
                        '\.privatelink\.azureml\.net$'       { return 'MachineLearning' }

                        # Integration
                        '\.servicebus\.windows\.net$'         { return 'ServiceBus' }
                        '\.azure-api\.net$'                   { return 'APIManagement' }
                        '\.service\.signalr\.net$'            { return 'SignalR' }
                        '\.webpubsub\.azure\.com$'            { return 'WebPubSub' }
                        '\.privatelink\.servicebus\.windows\.net$' { return 'ServiceBus' }
                        '\.privatelink\.azure-api\.net$'     { return 'APIManagement' }
                        '\.privatelink\.service\.signalr\.net$' { return 'SignalR' }
                        '\.privatelink\.webpubsub\.azure\.com$' { return 'WebPubSub' }

                        # Other
                        '\.azureedge\.net$'                   { return 'CDN' }
                        '\.azure-devices\.net$'               { return 'IoTHub' }
                        '\.eventgrid\.azure\.net$'            { return 'EventGrid' }
                        '\.azuremicroservices\.io$'           { return 'SpringApps' }
                        '\.azuresynapse\.net$'                { return 'SynapseAnalytics' }
                        '\.batch\.azure\.com$'                { return 'AzureBatch' }
                        '\.privatelink\.eventgrid\.azure\.net$' { return 'EventGrid' }
                        '\.privatelink\.azuremicroservices\.io$' { return 'SpringApps' }
                        '\.privatelink\.azuresynapse\.net$'  { return 'SynapseAnalytics' }

                        default                               { return 'Unknown' }
                    }
                }

                try {
                    $validDnsNames = $using:validDnsNames
                    $results = $using:results
                    $foundResources = $using:foundResources
                    $recordTypes = [System.Collections.Generic.HashSet[string]]::new()
                    $cnameTarget = $null
                    $dnsResult = $null

                    try {
                        $dohUrl = "https://cloudflare-dns.com/dns-query?name=$_&type=CNAME"
                        $dohResp = Invoke-RestMethod -Uri $dohUrl `
                            -Headers @{ Accept = 'application/dns-json' } `
                            -TimeoutSec 5 -ErrorAction Stop
                        $cnameAnswer = $dohResp.Answer |
                            Where-Object { $_.type -eq 5 }
                        if ($cnameAnswer) {
                            $cnameTarget = ($cnameAnswer | Select-Object -First 1).data
                            if ($cnameTarget) {
                                [void]$recordTypes.Add('CNAME')
                            }
                        }
                    }
                    catch {
                    }

                    try {
                        $dnsResult = [System.Net.Dns]::GetHostEntry($_)
                        if ($dnsResult -and $dnsResult.AddressList.Count -gt 0) {
                            [void]$recordTypes.Add('A')
                        }
                    }
                    catch [System.Net.Sockets.SocketException] {
                    }

                    if ($recordTypes.Count -gt 0) {
                        $resourceTypeBase = Get-ResourceType -dnsName $_
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

            # Cache results if any were found
            if (-not $SkipCache -and $results -and $results.Count -gt 0) {
                try {
                    Set-BlackCatCache -Key $cacheKey -Data $results `
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
                    default  { return $results | Format-Table -AutoSize }
                }
        }
        else {
            Write-Host "`n No public Azure resources found" -ForegroundColor Red
            Write-Information "No public Azure resources found" -InformationAction Continue
        }
    }
<#
.SYNOPSIS
    Finds publicly accessible Azure resources.

.DESCRIPTION
    Discovers publicly accessible Azure resources through DNS permutation and testing. Enumerates potential Azure resource names in specific patterns and tests each for public accessibility. Useful for identifying overlooked exposed resources and weak naming conventions.

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

.EXAMPLE
    Find-AzurePublicResource -Name "contoso" -WordList "./wordlist.txt" -ThrottleLimit 100 -OutputFormat JSON

    Searches for Azure resources using "contoso" with custom permutations from wordlist.txt,
    using 100 concurrent threads, and returns results in JSON format.

.EXAMPLE
    Find-AzurePublicResource -Name "example" -OutputFormat Table

    Searches for Azure resources and displays results in a formatted table.



.NOTES
    - Requires PowerShell 7+ for parallel processing functionality
    - Useful for reconnaissance and security assessments of Azure environments
    - Only DNS names that successfully resolve are returned as results

.LINK
    MITRE ATT&CK Tactic: TA0043 - Reconnaissance
    https://attack.mitre.org/tactics/TA0043/

.LINK
    MITRE ATT&CK Technique: T1593.002 - Search Open Websites/Domains: Search Engines
    https://attack.mitre.org/techniques/T1593/002/
#>
}