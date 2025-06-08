<#
.SYNOPSIS
    Finds publicly accessible Azure resources by generating and resolving possible DNS names.

.DESCRIPTION
    The Find-AzurePublicResource function generates permutations of Azure resource names using a base name and an optional wordlist.
    It constructs DNS names for various Azure services (e.g., Storage, CosmosDB, KeyVault, AppService) and attempts to resolve them.
    Successfully resolved DNS names are returned with their resource type and URI, indicating potentially public Azure resources.

.PARAMETER Name
    The base name of the Azure resource to search for. Must match the pattern: starts and ends with an alphanumeric character, and may contain hyphens.

.PARAMETER WordList
    Optional. Path to a file containing additional words (one per line) to use for generating name permutations.

.PARAMETER ThrottleLimit
    Optional. The maximum number of concurrent DNS resolution operations. Default is 50.

.EXAMPLE
    Find-AzurePublicResource -Name "mycompany" -WordList "./words.txt" -ThrottleLimit 100

    Searches for public Azure resources using "mycompany" as the base name, with permutations from "words.txt", and up to 100 concurrent lookups.

.NOTES
    - Requires PowerShell 7+ for parallel processing.
    - Useful for reconnaissance and security assessments of Azure environments.
    - Only DNS names that resolve are returned as results.

#>
function Find-AzurePublicResource {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9-]+[A-Za-z0-9]$', ErrorMessage = "It does not match expected pattern '{1}'")]
        [string]$Name,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias("word-list", "w")]
        [string]$WordList,

        [Parameter(Mandatory = $false)]
        [Alias("throttle-limit", 't', 'threads')]
        [int]$ThrottleLimit = 50
    )

    begin {
        $validDnsNames = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
    }

    process {
        try {
            if ($WordList) {
                $permutations = [System.Collections.Generic.HashSet[string]](Get-Content $WordList)
                Write-Verbose "Loaded $($permutations.Count) permutations from '$WordList'"
            }

            $permutations += $sessionVariables.permutations
            Write-Verbose "Loaded $($permutations.Count) permutations from session"

            $dnsNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

            $domains = @(
                # Storage
                'blob.core.windows.net',
                'file.core.windows.net',
                'table.core.windows.net',
                'queue.core.windows.net',
                'dfs.core.windows.net',            # Data Lake Storage Gen2

                # Databases
                'database.windows.net',            # SQL Database
                'documents.azure.com',             # Cosmos DB
                'redis.cache.windows.net',         # Redis Cache
                'mysql.database.azure.com',        # MySQL
                'postgres.database.azure.com',     # PostgreSQL
                'mariadb.database.azure.com',      # MariaDB

                # Security
                'vault.azure.net',                 # Key Vault

                # Compute & Containers
                'azurecr.io',                      # Container Registry
                'azurewebsites.net',               # App Service/Functions
                'scm.azurewebsites.net',           # App Service Kudu
                'azurestaticapps.net',             # Static Web Apps
                'staticapp.azurestaticapps.net',   # Static Web Apps alternate

                # AI/ML
                'cognitiveservices.azure.com',
                'openai.azure.com',                # Azure OpenAI
                'search.windows.net',              # Azure Search
                'azureml.net',                     # Machine Learning

                # Integration
                'servicebus.windows.net',
                'azure-api.net',                   # API Management
                'azurefd.net',                     # Front Door
                'service.signalr.net',             # SignalR Service
                'webpubsub.azure.com',             # Web PubSub

                # Other
                'azureedge.net',                   # CDN
                'azurefd.net',                     # Front Door
                'azure-devices.net',               # IoT Hub
                'eventgrid.azure.net',             # Event Grid
                'azuremicroservices.io',           # Spring Apps
                'azuresynapse.net',                # Synapse Analytics
                'atlas.microsoft.com',             # Azure Maps
                'batch.azure.com'                  # Azure Batch
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
            Write-Verbose "Starting DNS resolution for $totalDns names..."

            $results = [System.Collections.Concurrent.ConcurrentBag[psobject]]::new()

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

                        # Databases
                        '\.database\.windows\.net$'           { return 'SqlDatabase' }
                        '\.documents\.azure\.com$'            { return 'CosmosDB' }
                        '\.redis\.cache\.windows\.net$'       { return 'RedisCache' }
                        '\.mysql\.database\.azure\.com$'      { return 'MySQL' }
                        '\.postgres\.database\.azure\.com$'   { return 'PostgreSQL' }
                        '\.mariadb\.database\.azure\.com$'    { return 'MariaDB' }

                        # Security
                        '\.vault\.azure\.net$'                { return 'KeyVault' }

                        # Compute & Containers
                        '\.azurecr\.io$'                      { return 'ContainerRegistry' }
                        '\.azurewebsites\.net$'               { return 'AppService' }
                        '\.scm\.azurewebsites\.net$'          { return 'AppServiceKudu' }
                        '\.azurestaticapps\.net$'             { return 'StaticWebApp' }
                        '\.staticapp\.azurestaticapps\.net$'  { return 'StaticWebApp' }

                        # AI/ML
                        '\.cognitiveservices\.azure\.com$'    { return 'CognitiveServices' }
                        '\.openai\.azure\.com$'               { return 'AzureOpenAI' }
                        '\.search\.windows\.net$'             { return 'AzureSearch' }
                        '\.azureml\.net$'                     { return 'MachineLearning' }

                        # Integration
                        '\.servicebus\.windows\.net$'         { return 'ServiceBus' }
                        '\.azure-api\.net$'                   { return 'APIManagement' }
                        '\.azurefd\.net$'                     { return 'FrontDoor' }
                        '\.service\.signalr\.net$'            { return 'SignalR' }
                        '\.webpubsub\.azure\.com$'            { return 'WebPubSub' }

                        # Other
                        '\.azureedge\.net$'                   { return 'CDN' }
                        '\.azure-devices\.net$'               { return 'IoTHub' }
                        '\.eventgrid\.azure\.net$'            { return 'EventGrid' }
                        '\.azuremicroservices\.io$'           { return 'SpringApps' }
                        '\.azuresynapse\.net$'                { return 'SynapseAnalytics' }
                        '\.atlas\.microsoft\.com$'            { return 'AzureMaps' }
                        '\.batch\.azure\.com$'                { return 'AzureBatch' }

                        default                               { return 'Unknown' }
                    }
                }

                try {
                    $validDnsNames = $using:validDnsNames
                    $results = $using:results
                    if ([System.Net.Dns]::GetHostEntry($_)) {
                        $resourceType = Get-ResourceType -dnsName $_
                        $obj = [PSCustomObject]@{
                            ResourceName = $_.Split('.')[0]
                            ResourceType = $resourceType
                            Uri          = "https://$_"
                        }
                        $results.Add($obj)
                    }
                }
                catch [System.Net.Sockets.SocketException] {
                }
            }
            $results.ToArray() | Sort-Object Uri
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
}
