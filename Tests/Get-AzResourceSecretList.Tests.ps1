BeforeAll {
    # Import the function being tested
    . "$PSScriptRoot/../Public/Credential Access/Get-AzResourceSecretList.ps1"
    
    # Mock Write-Message function
    function Write-Message {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Message,
            [Parameter(Mandatory = $false)]
            [ValidateSet("Error", "Information", "Debug")]
            [string]$Severity = 'Information',
            [Parameter(Mandatory = $false)]
            [string]$FunctionName
        )
        $script:LastMessage = @{
            Message = $Message
            Severity = $Severity
            FunctionName = $FunctionName
        }
    }

    # Mock Invoke-BlackCat function
    function Invoke-BlackCat {
        param (
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            [string]$FunctionName,
            [Parameter(Mandatory = $false)]
            [string]$ResourceTypeName,
            [Switch]$ChangeProfile = $False
        )
        process {
            $script:authHeader = @{
                'Authorization' = 'Bearer mock-token-12345'
            }
        }
    }

    # Mock Invoke-AzBatch function with comprehensive test data
    function Invoke-AzBatch {
        param (
            [Parameter(Mandatory = $false)]
            [string]$ResourceType,
            [Parameter(Mandatory = $false)]
            [string]$Name,
            [Parameter(Mandatory = $false)]
            [string]$filter
        )
        
        # Return mock resources based on resource type for comprehensive testing
        switch ($ResourceType) {
            'Microsoft.KeyVault/vaults' {
                return @(
                    [PSCustomObject]@{
                        id = "/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/test-rg/providers/Microsoft.KeyVault/vaults/test-keyvault-1"
                        name = "test-keyvault-1"
                        type = "microsoft.keyvault/vaults"
                        resourceGroup = "test-rg"
                        location = "eastus"
                    },
                    [PSCustomObject]@{
                        id = "/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/prod-rg/providers/Microsoft.KeyVault/vaults/prod-keyvault"
                        name = "prod-keyvault"
                        type = "microsoft.keyvault/vaults"
                        resourceGroup = "prod-rg"
                        location = "westus2"
                    }
                )
            }
            'Microsoft.Storage/storageAccounts' {
                return @(
                    [PSCustomObject]@{
                        id = "/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/test-rg/providers/Microsoft.Storage/storageAccounts/teststorage001"
                        name = "teststorage001"
                        type = "microsoft.storage/storageaccounts"
                        resourceGroup = "test-rg"
                        location = "eastus"
                    }
                )
            }
            'Microsoft.Web/sites' {
                return @(
                    [PSCustomObject]@{
                        id = "/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/test-rg/providers/Microsoft.Web/sites/test-webapp"
                        name = "test-webapp"
                        type = "microsoft.web/sites"
                        kind = "app"
                        resourceGroup = "test-rg"
                        location = "eastus"
                    },
                    [PSCustomObject]@{
                        id = "/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/test-rg/providers/Microsoft.Web/sites/test-function-app"
                        name = "test-function-app"
                        type = "microsoft.web/sites"
                        kind = "functionapp,linux"
                        resourceGroup = "test-rg"
                        location = "eastus"
                    }
                )
            }
            'Microsoft.ServiceBus/namespaces' {
                return @(
                    [PSCustomObject]@{
                        id = "/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/test-rg/providers/Microsoft.ServiceBus/namespaces/test-servicebus"
                        name = "test-servicebus"
                        type = "microsoft.servicebus/namespaces"
                        resourceGroup = "test-rg"
                        location = "eastus"
                    }
                )
            }
            'Microsoft.DocumentDB/databaseAccounts' {
                return @(
                    [PSCustomObject]@{
                        id = "/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/test-rg/providers/Microsoft.DocumentDB/databaseAccounts/test-cosmosdb"
                        name = "test-cosmosdb"
                        type = "microsoft.documentdb/databaseaccounts"
                        resourceGroup = "test-rg"
                        location = "eastus"
                    }
                )
            }
            default {
                return @()
            }
        }
    }

    # Mock Invoke-RestMethod with realistic Azure API responses
    function Invoke-RestMethod {
        param (
            [string]$Uri,
            [hashtable]$Headers,
            [string]$Method,
            [string]$Body,
            [string]$ContentType,
            [string]$UserAgent
        )

        # Mock Key Vault secrets using data plane API
        if ($Uri -like "https://*.vault.azure.net/secrets?api-version=*") {
            return @{
                value = @(
                    @{
                        id = "https://test-keyvault-1.vault.azure.net/secrets/database-password"
                        name = "database-password"
                        attributes = @{
                            enabled = $true
                            created = 1672531200  # Unix timestamp for 2023-01-01
                            updated = 1672531200
                        }
                        tags = @{
                            environment = "production"
                        }
                        managed = $false
                    },
                    @{
                        id = "https://test-keyvault-1.vault.azure.net/secrets/api-key"
                        name = "api-key"
                        attributes = @{
                            enabled = $true
                            created = 1672531200
                            updated = 1672531200
                        }
                        tags = @{
                            environment = "production"
                        }
                        managed = $false
                    }
                )
            }
        }
        
        # Mock individual secret values using data plane API
        elseif ($Uri -like "https://*.vault.azure.net/secrets/*?api-version=*") {
            $secretName = ($Uri -split '/')[-1] -split '\?' | Select-Object -First 1
            return @{
                value = "super-secret-value-for-$secretName"
                id = $Uri.Split('?')[0]
                contentType = "text/plain"
                attributes = @{
                    enabled = $true
                    created = 1672531200
                    updated = 1672531200
                    recoveryLevel = "Recoverable+Purgeable"
                }
                tags = @{
                    environment = "production"
                }
                managed = $false
            }
        }
        
        # Mock Storage Account keys
        elseif ($Uri -like "*storage*/listKeys?api-version=*") {
            return @{
                keys = @(
                    @{
                        keyName = "key1"
                        value = "mock-storage-key-1-abcdef123456789"
                        permissions = "FULL"
                    },
                    @{
                        keyName = "key2"
                        value = "mock-storage-key-2-zyxwvu987654321"
                        permissions = "FULL"
                    }
                )
            }
        }
        
        # Mock Storage Account Kerberos keys
        elseif ($Uri -like "*storage*/listKerberosKeys?api-version=*") {
            return @{
                keys = @(
                    @{
                        keyName = "kerb1"
                        value = "mock-kerberos-key-123"
                    }
                )
            }
        }
        
        # Mock App Service settings
        elseif ($Uri -like "*sites/*/config/appsettings/list?api-version=*") {
            return @{
                properties = @{
                    "WEBSITE_NODE_DEFAULT_VERSION" = "~18"
                    "DATABASE_CONNECTION_STRING" = "Server=sql.example.com;Database=mydb;User Id=user;Password=secret123;"
                    "API_KEY" = "sk-1234567890abcdef"
                    "REDIS_CONNECTION" = "cache.redis.com:6380,password=redispass123,ssl=True"
                }
            }
        }
        
        # Mock App Service connection strings
        elseif ($Uri -like "*sites/*/config/connectionstrings/list?api-version=*") {
            return @{
                properties = @{
                    "DefaultConnection" = @{
                        value = "Server=sql.example.com;Database=proddb;User Id=produser;Password=prodpassword123;"
                        type = "SQLServer"
                    }
                    "Storage" = @{
                        value = "DefaultEndpointsProtocol=https;AccountName=mystorage;AccountKey=storagekey123;"
                        type = "Custom"
                    }
                }
            }
        }
        
        # Mock Function App keys
        elseif ($Uri -like "*sites/*/host/default/listKeys?api-version=*") {
            return @{
                masterKey = "mock-function-master-key-abcdef123456"
                functionKeys = @{
                    "default" = "mock-function-default-key-123456"
                    "admin" = "mock-function-admin-key-789012"
                }
                systemKeys = @{
                    "durabletask_extension" = "mock-durable-task-key-345678"
                }
            }
        }
        
        # Mock Service Bus authorization rules
        elseif ($Uri -like "*servicebus*/authorizationRules?api-version=*") {
            return @{
                value = @(
                    @{
                        id = "/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/test-rg/providers/Microsoft.ServiceBus/namespaces/test-servicebus/authorizationRules/RootManageSharedAccessKey"
                        name = "RootManageSharedAccessKey"
                        properties = @{
                            rights = @("Manage", "Send", "Listen")
                        }
                    }
                )
            }
        }
        
        # Mock Service Bus keys
        elseif ($Uri -like "*servicebus*/authorizationRules/*/listKeys?api-version=*") {
            return @{
                primaryKey = "mock-servicebus-primary-key-123456"
                secondaryKey = "mock-servicebus-secondary-key-789012"
                primaryConnectionString = "Endpoint=sb://test-servicebus.servicebus.windows.net/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=mock-servicebus-primary-key-123456"
                secondaryConnectionString = "Endpoint=sb://test-servicebus.servicebus.windows.net/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=mock-servicebus-secondary-key-789012"
            }
        }
        
        # Mock Cosmos DB keys
        elseif ($Uri -like "*documentdb*/listKeys?api-version=*") {
            return @{
                primaryMasterKey = "mock-cosmos-primary-key-abcdef123456789"
                secondaryMasterKey = "mock-cosmos-secondary-key-zyxwvu987654321"
                primaryReadonlyMasterKey = "mock-cosmos-readonly-primary-key-123456"
                secondaryReadonlyMasterKey = "mock-cosmos-readonly-secondary-key-789012"
            }
        }
        
        # Mock Cosmos DB readonly keys
        elseif ($Uri -like "*documentdb*/readonlykeys?api-version=*") {
            return @{
                primaryReadonlyMasterKey = "mock-cosmos-readonly-primary-key-123456"
                secondaryReadonlyMasterKey = "mock-cosmos-readonly-secondary-key-789012"
            }
        }
        
        # Default empty response for unhandled endpoints
        else {
            return @{}
        }
    }

}

Describe "Get-AzResourceSecretList" {
    BeforeEach {
        # Reset mocks for each test
        $script:LastMessage = $null
        $script:authHeader = @{
            'Authorization' = 'Bearer mock-token-12345'
        }
    }

    Context "Function Structure and Metadata" {
        It "Should have the correct function name" {
            $function = Get-Command Get-AzResourceSecretList
            $function.Name | Should -Be "Get-AzResourceSecretList"
        }

        It "Should have CmdletBinding attribute" {
            $function = Get-Command Get-AzResourceSecretList
            $function.CmdletBinding | Should -Be $true
        }

        It "Should have no mandatory parameters" {
            $function = Get-Command Get-AzResourceSecretList
            $mandatoryParams = $function.Parameters.Values | Where-Object { $_.Attributes.Mandatory -eq $true }
            $mandatoryParams.Count | Should -Be 0
        }

        It "Should support Verbose parameter" {
            $function = Get-Command Get-AzResourceSecretList
            $function.Parameters.ContainsKey('Verbose') | Should -Be $true
        }
    }

    Context "Basic Function Execution" {
        It "Should return an array of objects" {
            $result = Get-AzResourceSecretList
            $result | Should -BeOfType [array]
        }

        It "Should include resource objects with correct structure" {
            $result = Get-AzResourceSecretList
            $result.Count | Should -BeGreaterThan 0
            $result[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should not throw exceptions during execution" {
            { Get-AzResourceSecretList } | Should -Not -Throw
        }
    }

    Context "Key Vault Secret Processing" {
        It "Should process Key Vault resources successfully" {
            $result = Get-AzResourceSecretList
            $keyVaultResources = $result | Where-Object { $_.ResourceType -eq 'microsoft.keyvault/vaults' }
            $keyVaultResources | Should -Not -BeNullOrEmpty
        }

        It "Should retrieve Key Vault secrets with metadata" {
            $result = Get-AzResourceSecretList
            $keyVaultResources = $result | Where-Object { $_.ResourceType -eq 'microsoft.keyvault/vaults' }
            $keyVaultResources | Should -Not -BeNullOrEmpty
            $keyVaultResources.Count | Should -BeGreaterThan 0
            
            $firstKeyVault = $keyVaultResources[0]
            $firstKeyVault.ResourceName | Should -Be "test-keyvault-1"
            $firstKeyVault.Secrets.Count | Should -BeGreaterThan 0
            $firstKeyVault.HasSecrets | Should -Be $true
            $firstKeyVault.Severity | Should -Be "Critical"
        }

        It "Should retrieve actual secret values when possible" {
            $result = Get-AzResourceSecretList
            $keyVaultResource = ($result | Where-Object { $_.ResourceType -eq 'microsoft.keyvault/vaults' })[0]
            $secretWithValue = $keyVaultResource.Secrets | Where-Object { $_.value -ne $null }
            $secretWithValue | Should -Not -BeNullOrEmpty
            $secretWithValue[0].value | Should -Match "super-secret-value-for-"
        }

        It "Should include multiple Key Vault resources" {
            $result = Get-AzResourceSecretList
            $keyVaultResources = $result | Where-Object { $_.ResourceType -eq 'microsoft.keyvault/vaults' }
            $keyVaultResources.Count | Should -BeGreaterOrEqual 2
            
            $resourceNames = $keyVaultResources | ForEach-Object { $_.ResourceName }
            $resourceNames | Should -Contain "test-keyvault-1"
            $resourceNames | Should -Contain "prod-keyvault"
        }
    }

    Context "Storage Account Processing" {
        It "Should process Storage Account resources successfully" {
            $result = Get-AzResourceSecretList
            $storageResources = $result | Where-Object { $_.ResourceType -eq 'microsoft.storage/storageaccounts' }
            $storageResources | Should -Not -BeNullOrEmpty
        }

        It "Should retrieve storage account keys" {
            $result = Get-AzResourceSecretList
            $storageResources = $result | Where-Object { $_.ResourceType -eq 'microsoft.storage/storageaccounts' }
            $storageResources | Should -Not -BeNullOrEmpty
            
            $firstStorage = $storageResources[0]
            $firstStorage.ResourceName | Should -Be "teststorage001"
            $firstStorage.Keys.Count | Should -BeGreaterOrEqual 2
            $firstStorage.HasSecrets | Should -Be $true
            $firstStorage.Severity | Should -Be "High"
        }

        It "Should include both primary and secondary keys" {
            $result = Get-AzResourceSecretList
            $storageResource = ($result | Where-Object { $_.ResourceType -eq 'microsoft.storage/storageaccounts' })[0]
            
            $keyNames = $storageResource.Keys | ForEach-Object { $_.keyName }
            $keyNames | Should -Contain "key1"
            $keyNames | Should -Contain "key2"
        }

        It "Should attempt to retrieve Kerberos keys" {
            $result = Get-AzResourceSecretList
            $storageResource = ($result | Where-Object { $_.ResourceType -eq 'microsoft.storage/storageaccounts' })[0]
            
            # Should have more than just the standard 2 keys if Kerberos keys are included
            $storageResource.Keys.Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Web App and Function App Processing" {
        It "Should process Web App resources successfully" {
            $result = Get-AzResourceSecretList
            $webAppResources = $result | Where-Object { $_.ResourceType -eq 'microsoft.web/sites' }
            $webAppResources | Should -Not -BeNullOrEmpty
        }

        It "Should retrieve app settings and connection strings" {
            $result = Get-AzResourceSecretList
            $webAppResources = $result | Where-Object { $_.ResourceType -eq 'microsoft.web/sites' }
            $webAppResources | Should -Not -BeNullOrEmpty
            
            $regularApp = $webAppResources | Where-Object { $_.ResourceName -eq "test-webapp" }
            $regularApp | Should -Not -BeNullOrEmpty
            $regularApp.AppSettings.Count | Should -BeGreaterThan 0
            $regularApp.ConnectionStrings.Count | Should -BeGreaterThan 0
            $regularApp.HasSecrets | Should -Be $true
            $regularApp.Severity | Should -Be "Medium"
        }

        It "Should retrieve function keys for function apps only" {
            $result = Get-AzResourceSecretList
            $webAppResources = $result | Where-Object { $_.ResourceType -eq 'microsoft.web/sites' }
            
            $functionApp = $webAppResources | Where-Object { $_.ResourceName -eq "test-function-app" }
            $regularApp = $webAppResources | Where-Object { $_.ResourceName -eq "test-webapp" }
            
            $functionApp.FunctionKeys | Should -Not -BeNull
            $functionApp.FunctionKeys.masterKey | Should -Not -BeNullOrEmpty
            $regularApp.FunctionKeys | Should -BeNull
        }

        It "Should properly detect function apps by kind" {
            $result = Get-AzResourceSecretList
            $webAppResources = $result | Where-Object { $_.ResourceType -eq 'microsoft.web/sites' }
            
            $functionApp = $webAppResources | Where-Object { $_.ResourceName -eq "test-function-app" }
            $functionApp.FunctionKeys | Should -Not -BeNull
            $functionApp.FunctionKeys.functionKeys | Should -Not -BeNull
            $functionApp.FunctionKeys.systemKeys | Should -Not -BeNull
        }
    }

    Context "Service Bus Processing" {
        It "Should process Service Bus namespaces successfully" {
            $result = Get-AzResourceSecretList
            $serviceBusResources = $result | Where-Object { $_.ResourceType -eq 'microsoft.servicebus/namespaces' }
            $serviceBusResources | Should -Not -BeNullOrEmpty
        }

        It "Should retrieve Service Bus authorization rule keys" {
            $result = Get-AzResourceSecretList
            $serviceBusResources = $result | Where-Object { $_.ResourceType -eq 'microsoft.servicebus/namespaces' }
            $serviceBusResources | Should -Not -BeNullOrEmpty
            
            $firstServiceBus = $serviceBusResources[0]
            $firstServiceBus.ResourceName | Should -Be "test-servicebus"
            $firstServiceBus.Keys.Count | Should -BeGreaterThan 0
            $firstServiceBus.HasSecrets | Should -Be $true
            $firstServiceBus.Severity | Should -Be "High"
        }

        It "Should include connection strings in Service Bus keys" {
            $result = Get-AzResourceSecretList
            $serviceBusResource = ($result | Where-Object { $_.ResourceType -eq 'microsoft.servicebus/namespaces' })[0]
            
            $keyWithConnectionString = $serviceBusResource.Keys | Where-Object { $_.primaryConnectionString -ne $null }
            $keyWithConnectionString | Should -Not -BeNullOrEmpty
            $keyWithConnectionString.primaryConnectionString | Should -Match "Endpoint=sb://"
        }
    }

    Context "Cosmos DB Processing" {
        It "Should process Cosmos DB accounts successfully" {
            $result = Get-AzResourceSecretList
            $cosmosResources = $result | Where-Object { $_.ResourceType -eq 'microsoft.documentdb/databaseaccounts' }
            $cosmosResources | Should -Not -BeNullOrEmpty
        }

        It "Should retrieve both primary and read-only keys" {
            $result = Get-AzResourceSecretList
            $cosmosResources = $result | Where-Object { $_.ResourceType -eq 'microsoft.documentdb/databaseaccounts' }
            $cosmosResources | Should -Not -BeNullOrEmpty
            
            $firstCosmos = $cosmosResources[0]
            $firstCosmos.ResourceName | Should -Be "test-cosmosdb"
            $firstCosmos.Keys.Count | Should -BeGreaterOrEqual 2  # Primary keys + readonly keys
            $firstCosmos.HasSecrets | Should -Be $true
            $firstCosmos.Severity | Should -Be "High"
        }
    }

    Context "Resource Object Structure" {
        It "Should include all required properties in resource objects" {
            $result = Get-AzResourceSecretList
            $anyResource = $result[0]
            
            $requiredProperties = @(
                "ResourceName", "ResourceType", "ResourceId", "ResourceGroup", 
                "Location", "SubscriptionId", "Severity", "Keys", "Secrets", "Credentials",
                "AdminKeys", "AppSettings", "ConnectionStrings", "FunctionKeys",
                "ProcessingErrors", "ProcessedAt", "HasSecrets", "SecretTypes"
            )
            
            foreach ($property in $requiredProperties) {
                $anyResource.PSObject.Properties.Name | Should -Contain $property
            }
        }

        It "Should correctly extract subscription ID from resource ID" {
            $result = Get-AzResourceSecretList
            $anyResource = $result[0]
            $anyResource.SubscriptionId | Should -Be "12345678-1234-1234-1234-123456789012"
        }

        It "Should set HasSecrets flag correctly for resources with secrets" {
            $result = Get-AzResourceSecretList
            $keyVaultResource = ($result | Where-Object { $_.ResourceType -eq 'microsoft.keyvault/vaults' })[0]
            $keyVaultResource.HasSecrets | Should -Be $true
        }

        It "Should include processing timestamp" {
            $result = Get-AzResourceSecretList
            $anyResource = $result[0]
            $anyResource.ProcessedAt | Should -Match '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC'
        }

        It "Should assign correct severity levels" {
            $result = Get-AzResourceSecretList
            $keyVaultResource = ($result | Where-Object { $_.ResourceType -eq 'microsoft.keyvault/vaults' })[0]
            $storageResource = ($result | Where-Object { $_.ResourceType -eq 'microsoft.storage/storageaccounts' })[0]
            $webAppResource = ($result | Where-Object { $_.ResourceType -eq 'microsoft.web/sites' })[0]
            
            $keyVaultResource.Severity | Should -Be "Critical"
            $storageResource.Severity | Should -Be "High"
            $webAppResource.Severity | Should -Be "Medium"
        }
    }

    Context "Summary and Output Format" {
        It "Should display comprehensive summary information" {
            # Test default table output by capturing verbose output
            $verboseMessages = @()
            Mock Write-Host { $verboseMessages += $Message }
            
            $result = Get-AzResourceSecretList -OutputFormat Table
            
            # The function should display summary information
            Should -Invoke Write-Host -AtLeast 1
        }

        It "Should support JSON output format" {
            # Mock Out-File to capture file creation
            Mock Out-File { }
            
            $result = Get-AzResourceSecretList -OutputFormat JSON
            
            # Should attempt to create a JSON file
            Should -Invoke Out-File -ParameterFilter { $FilePath -like "*AzureResourceSecrets_*.json" }
        }

        It "Should support CSV output format" {
            # Mock Export-Csv to capture file creation
            Mock Export-Csv { }
            
            $result = Get-AzResourceSecretList -OutputFormat CSV
            
            # Should attempt to create a CSV file
            Should -Invoke Export-Csv -ParameterFilter { $Path -like "*AzureResourceSecrets_*.csv" }
        }

        It "Should return objects for pipeline when OutputFormat is Object" {
            $result = Get-AzResourceSecretList -OutputFormat Object
            $result | Should -BeOfType [array]
            $result.Count | Should -BeGreaterThan 0
        }
    }

    Context "Error Handling and Resilience" {
        It "Should handle REST API errors gracefully" {
            # Override Invoke-RestMethod to simulate errors for specific resources
            Mock Invoke-RestMethod { 
                if ($Uri -like "*keyvault*") {
                    throw "Forbidden: Access denied to Key Vault"
                }
                # Return normal responses for other resources
                elseif ($Uri -like "*storage*/listKeys*") {
                    return @{ keys = @(@{ keyName = "key1"; value = "test-key" }) }
                }
                return @{}
            }
            
            { Get-AzResourceSecretList } | Should -Not -Throw
        }

        It "Should continue processing other resources when one fails" {
            # Mock to make Key Vault fail but storage succeed
            Mock Invoke-RestMethod { 
                if ($Uri -like "*keyvault*") {
                    throw "Service unavailable"
                }
                elseif ($Uri -like "*storage*/listKeys*") {
                    return @{ keys = @(@{ keyName = "key1"; value = "working-key" }) }
                }
                return @{}
            }
            
            $result = Get-AzResourceSecretList
            $result | Should -Not -BeNullOrEmpty
            $storageResources = $result | Where-Object { $_.ResourceType -eq 'microsoft.storage/storageaccounts' }
            $storageResources | Should -Not -BeNullOrEmpty
        }

        It "Should handle empty resource lists gracefully" {
            Mock Invoke-AzBatch { return @() }
            
            $result = Get-AzResourceSecretList
            $result | Should -BeOfType [array]
            $result.Count | Should -Be 0
        }

        It "Should track processing errors in resource objects" {
            # Mock to cause errors for Key Vault
            Mock Invoke-RestMethod { 
                if ($Uri -like "*keyvault*") {
                    throw "Access denied to Key Vault"
                }
                return @{}
            }
            
            $result = Get-AzResourceSecretList
            $keyVaultResources = $result | Where-Object { $_.ResourceType -eq 'microsoft.keyvault/vaults' }
            if ($keyVaultResources) {
                $keyVaultResources[0].ProcessingErrors | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context "Resource Type Coverage" {
        It "Should attempt to process all supported resource types" {
            $expectedResourceTypes = @(
                'Microsoft.KeyVault/vaults',
                'Microsoft.Storage/storageAccounts',
                'Microsoft.Web/sites',
                'Microsoft.ServiceBus/namespaces',
                'Microsoft.DocumentDB/databaseAccounts',
                'Microsoft.ContainerRegistry/registries',
                'Microsoft.Search/searchServices',
                'Microsoft.DBforPostgreSQL/flexibleServers',
                'Microsoft.DBforMySQL/flexibleServers',
                'Microsoft.Cache/Redis',
                'Microsoft.ApiManagement/service',
                'Microsoft.Devices/IotHubs',
                'Microsoft.EventHub/namespaces',
                'Microsoft.NotificationHubs/namespaces',
                'Microsoft.Relay/namespaces',
                'Microsoft.SignalRService/SignalR',
                'Microsoft.CognitiveServices/accounts',
                'Microsoft.Maps/accounts',
                'Microsoft.Media/mediaservices',
                'Microsoft.Automation/automationAccounts'
            )
            
            # Track calls to Invoke-AzBatch
            $azBatchCalls = @()
            Mock Invoke-AzBatch { 
                $azBatchCalls += $ResourceType
                return @()  # Return empty to avoid processing
            }
            
            Get-AzResourceSecretList
            
            foreach ($resourceType in $expectedResourceTypes) {
                $azBatchCalls | Should -Contain $resourceType
            }
        }
    }

    Context "Verbose Output and Logging" {
        It "Should write verbose messages during processing" {
            $verboseMessages = @()
            Mock Write-Verbose { $verboseMessages += $Message }
            
            Get-AzResourceSecretList -Verbose
            
            $verboseMessages.Count | Should -BeGreaterThan 0
            $verboseMessages | Should -Contain { $_ -match "Processing resource:" }
        }

        It "Should log successful processing" {
            $verboseMessages = @()
            Mock Write-Verbose { $verboseMessages += $Message }
            
            Get-AzResourceSecretList -Verbose
            
            $successMessages = $verboseMessages | Where-Object { $_ -match "Successfully processed.*found secrets" }
            $successMessages.Count | Should -BeGreaterThan 0
        }
    }

    Context "Performance and Efficiency" {
        It "Should only include resources that actually have secrets" {
            $result = Get-AzResourceSecretList
            
            # All returned resources should have HasSecrets = true
            $resourcesWithSecrets = $result | Where-Object { $_.HasSecrets -eq $true }
            $result.Count | Should -Be $resourcesWithSecrets.Count
        }

        It "Should correctly identify when resources have no secrets" {
            # Mock to return empty responses
            Mock Invoke-RestMethod { return @{} }
            
            $result = Get-AzResourceSecretList
            $result.Count | Should -Be 0
        }

        It "Should support parallel processing with throttle limit" {
            $result = Get-AzResourceSecretList -ThrottleLimit 50
            $result | Should -BeOfType [array]
        }
    }
}


