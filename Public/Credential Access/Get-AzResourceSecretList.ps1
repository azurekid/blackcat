function Get-AzResourceSecretList {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('throttle-limit')]
        [int]$ThrottleLimit = 100,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Object", "JSON", "CSV", "Table")]
        [Alias("output", "o")]
        [string]$OutputFormat = "JSON"
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
        
        $result = New-Object System.Collections.ArrayList
        $stats = @{ 
            StartTime = Get-Date
            TotalResources = 0
            ResourcesWithSecrets = 0
            ResourceTypes = 0
            ProcessingErrors = 0
        }
        
        # Thread-safe counters for parallel processing
        $resourcesWithSecretsCount = [ref]0
        $processingErrorsCount = [ref]0
        $criticalSeverityCount = [ref]0
        $highSeverityCount = [ref]0
        $mediumSeverityCount = [ref]0
        $lowSeverityCount = [ref]0
    }

    process {
        try {
            Write-Host "Starting Azure Resource Secret Discovery..." -ForegroundColor Green
            
            $baseUri = "https://management.azure.com"

            # Get all resources from supported types
            Write-Host "  Collecting Azure resources..." -ForegroundColor Cyan
            $allResources = @()
            $resourceTypes = @(
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
            
            # foreach ($resourceType in $resourceTypes) {
                try {
                    $resources = Invoke-AzBatch -Silent
                    if ($resources) {
                        $allResources += $resources
                    }
                }
                catch {
                    Write-Verbose "Failed to get resources for type $resourceType`: $($_.Exception.Message)"
                    [void][System.Threading.Interlocked]::Increment($processingErrorsCount)
                }
            # }

            $stats.TotalResources = $allResources.Count
            Write-Host "    Found $($allResources.Count) total resources to analyze" -ForegroundColor Green

            if ($allResources.Count -eq 0) {
                Write-Host "No resources found to analyze" -ForegroundColor Yellow
                return $result
            }

            if ($allResources.Count -gt 20) {
                Write-Host "  Processing $($allResources.Count) resources, this may take a while..." -ForegroundColor Yellow
            }

            Write-Host "  Analyzing resource secrets across $($allResources.Count) resources with $ThrottleLimit concurrent threads..." -ForegroundColor Cyan

            $allResources | ForEach-Object -Parallel {
                $baseUri = $using:baseUri
                $result = $using:result
                $resourcesWithSecretsCount = $using:resourcesWithSecretsCount
                $processingErrorsCount = $using:processingErrorsCount
                $criticalSeverityCount = $using:criticalSeverityCount
                $highSeverityCount = $using:highSeverityCount
                $mediumSeverityCount = $using:mediumSeverityCount
                $lowSeverityCount = $using:lowSeverityCount
                $resource = $_

                try {
                    $resourceType = $resource.type
                    Write-Verbose "Processing resource: $($resource.name) of type: $resourceType"

                    $secretObject = [PSCustomObject]@{
                        ResourceName = $resource.name
                        ResourceType = $resourceType
                        ResourceId = $resource.id
                        ResourceGroup = $resource.resourceGroup
                        Location = $resource.location
                        SubscriptionId = ($resource.id -split '/')[2]
                        Severity = "Medium"  # Default severity, will be updated based on secret types
                        Keys = @()
                        Secrets = @()
                        Credentials = $null
                        AdminKeys = $null
                        AppSettings = @{}
                        ConnectionStrings = @{}
                        FunctionKeys = $null
                        ProcessingErrors = @()
                        ProcessedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss UTC')
                        HasSecrets = $false
                        SecretTypes = @()
                    }

                switch ($resourceType) {
                    'microsoft.storage/storageaccounts' {
                        try {
                            # Get storage account keys
                            $keysUri = "$($baseUri)$($resource.id)/listKeys?api-version=2023-01-01"
                            $keys = (Invoke-RestMethod -Uri $keysUri -Headers $using:script:authHeader -Method Post).keys
                            $secretObject.Keys = $keys
                            $secretObject.SecretTypes += "Storage Keys"
                            
                            # Try to get Kerberos keys if available
                            try {
                                $kerberosKeysUri = "$($baseUri)$($resource.id)/listKerberosKeys?api-version=2023-01-01"
                                $kerberosKeys = Invoke-RestMethod -Uri $kerberosKeysUri -Headers $using:script:authHeader -Method Post
                                if ($kerberosKeys) {
                                    $secretObject.Keys += $kerberosKeys
                                    $secretObject.SecretTypes += "Kerberos Keys"
                                }
                            }
                            catch {
                                # Kerberos keys might not be available for all storage accounts
                                Write-Verbose "Kerberos keys not available for storage account $($resource.name)"
                            }
                            $secretObject.Severity = "High"  # Storage keys are high severity
                        }
                        catch {
                            Write-Verbose "Could not retrieve storage account keys for $($resource.name): $($_.Exception.Message)"
                            $secretObject.ProcessingErrors += "Storage keys retrieval failed"
                        }
                    }
                    'microsoft.web/sites' {
                        # Get App Service configuration and connection strings
                        try {
                            # Get application settings
                            $settingsUri = "$($baseUri)$($resource.id)/config/appsettings/list?api-version=2022-03-01"
                            $appSettings = Invoke-RestMethod -Uri $settingsUri -Headers $using:script:authHeader -Method Post
                            $secretObject.AppSettings = $appSettings.properties
                            if ($appSettings.properties.Count -gt 0) {
                                $secretObject.SecretTypes += "App Settings"
                            }
                            
                            # Get connection strings
                            $connectionUri = "$($baseUri)$($resource.id)/config/connectionstrings/list?api-version=2022-03-01"
                            $connectionStrings = Invoke-RestMethod -Uri $connectionUri -Headers $using:script:authHeader -Method Post
                            $secretObject.ConnectionStrings = $connectionStrings.properties
                            if ($connectionStrings.properties.Count -gt 0) {
                                $secretObject.SecretTypes += "Connection Strings"
                            }
                            
                            # Check if it's a Function App and get function keys
                            if ($resource.kind -like "*functionapp*") {
                                try {
                                    $functionKeysUri = "$($baseUri)$($resource.id)/host/default/listKeys?api-version=2022-03-01"
                                    $functionKeys = Invoke-RestMethod -Uri $functionKeysUri -Headers $using:script:authHeader -Method Post
                                    $secretObject.FunctionKeys = $functionKeys
                                    if ($functionKeys) {
                                        $secretObject.SecretTypes += "Function Keys"
                                    }
                                }
                                catch {
                                    Write-Verbose "Could not retrieve function keys for $($resource.name): $($_.Exception.Message)"
                                    $secretObject.ProcessingErrors += "Function keys retrieval failed"
                                }
                            }
                            $secretObject.Severity = "Medium"  # App settings are medium severity
                        }
                        catch {
                            Write-Verbose "Could not retrieve web app secrets for $($resource.name): $($_.Exception.Message)"
                            $secretObject.ProcessingErrors += "Web app secrets retrieval failed"
                        }
                    }
                    'microsoft.servicebus/namespaces' {
                        try {
                            # Get authorization rules first
                            $authRulesUri = "$($baseUri)$($resource.id)/authorizationRules?api-version=2021-11-01"
                            $authRules = (Invoke-RestMethod -Uri $authRulesUri -Headers $using:script:authHeader -Method Get).value
                            
                            $allKeys = @()
                            foreach ($rule in $authRules) {
                                try {
                                    $keysUri = "$($baseUri)$($rule.id)/listKeys?api-version=2021-11-01"
                                    $keys = Invoke-RestMethod -Uri $keysUri -Headers $using:script:authHeader -Method Post
                                    $allKeys += $keys
                                }
                                catch {
                                    Write-Verbose "Could not retrieve Service Bus authorization rule keys for $($rule.name): $($_.Exception.Message)"
                                    $secretObject.ProcessingErrors += "Service Bus auth rule keys retrieval failed"
                                }
                            }
                            $secretObject.Keys = $allKeys
                            if ($allKeys.Count -gt 0) {
                                $secretObject.SecretTypes += "Service Bus Keys"
                                $secretObject.Severity = "High"  # Service Bus keys are high severity
                            }
                        }
                        catch {
                            Write-Verbose "Could not retrieve Service Bus keys for $($resource.name): $($_.Exception.Message)"
                            $secretObject.ProcessingErrors += "Service Bus keys retrieval failed"
                        }
                    }
                    'microsoft.documentdb/databaseaccounts' {
                        try {
                            # Get primary keys
                            $keysUri = "$($baseUri)$($resource.id)/listKeys?api-version=2023-04-15"
                            $keys = Invoke-RestMethod -Uri $keysUri -Headers $using:script:authHeader -Method Post
                            
                            # Also get read-only keys
                            $readOnlyKeysUri = "$($baseUri)$($resource.id)/readonlykeys?api-version=2023-04-15"
                            $readOnlyKeys = Invoke-RestMethod -Uri $readOnlyKeysUri -Headers $using:script:authHeader -Method Post
                            
                            # Combine all keys
                            $allKeys = @()
                            $allKeys += $keys
                            $allKeys += $readOnlyKeys
                            
                            $secretObject.Keys = $allKeys
                            if ($allKeys.Count -gt 0) {
                                $secretObject.SecretTypes += "CosmosDB Keys"
                                $secretObject.Severity = "High"  # CosmosDB keys are high severity
                            }
                        }
                        catch {
                            Write-Verbose "Could not retrieve CosmosDB keys for $($resource.name): $($_.Exception.Message)"
                            $secretObject.ProcessingErrors += "CosmosDB keys retrieval failed"
                        }
                    }
                    'microsoft.containerregistry/registries' {
                        try {
                            $uri = "$($baseUri)$($resource.id)/listCredentials?api-version=2023-07-01"
                            $creds = Invoke-RestMethod -Uri $uri -Headers $using:script:authHeader -Method Post
                            $secretObject.Credentials = $creds
                            if ($creds) {
                                $secretObject.SecretTypes += "Container Registry Credentials"
                                $secretObject.Severity = "Medium"
                            }
                        }
                        catch {
                            Write-Verbose "Could not retrieve container registry credentials for $($resource.name): $($_.Exception.Message)"
                            $secretObject.ProcessingErrors += "Container registry credentials retrieval failed"
                        }
                    }
                    'microsoft.search/searchservices' {
                        try {
                            $uri = "$($baseUri)$($resource.id)/listAdminKeys?api-version=2021-04-01-preview"
                            $keys = Invoke-RestMethod -Uri $uri -Headers $using:script:authHeader -Method Post
                            $secretObject.AdminKeys = $keys
                            if ($keys) {
                                $secretObject.SecretTypes += "Search Admin Keys"
                                $secretObject.Severity = "Medium"
                            }
                        }
                        catch {
                            Write-Verbose "Could not retrieve search service keys for $($resource.name): $($_.Exception.Message)"
                            $secretObject.ProcessingErrors += "Search service keys retrieval failed"
                        }
                    }
                    'microsoft.dbforpostgresql/flexibleservers' {
                        try {
                            $uri = "$($baseUri)$($resource.id)/listAdminCredentials?api-version=2023-03-01-preview"
                            $creds = Invoke-RestMethod -Uri $uri -Headers $using:script:authHeader -Method Post
                            $secretObject.Credentials = $creds
                            if ($creds) {
                                $secretObject.SecretTypes += "PostgreSQL Credentials"
                                $secretObject.Severity = "Medium"
                            }
                        }
                        catch {
                            Write-Verbose "Could not retrieve PostgreSQL credentials for $($resource.name): $($_.Exception.Message)"
                            $secretObject.ProcessingErrors += "PostgreSQL credentials retrieval failed"
                        }
                    }
                    'microsoft.dbformysql/flexibleservers' {
                        try {
                            $uri = "$($baseUri)$($resource.id)/listAdminCredentials?api-version=2023-06-01-preview"
                            $creds = Invoke-RestMethod -Uri $uri -Headers $using:script:authHeader -Method Post
                            $secretObject.Credentials = $creds
                            if ($creds) {
                                $secretObject.SecretTypes += "MySQL Credentials"
                                $secretObject.Severity = "Medium"
                            }
                        }
                        catch {
                            Write-Verbose "Could not retrieve MySQL credentials for $($resource.name): $($_.Exception.Message)"
                            $secretObject.ProcessingErrors += "MySQL credentials retrieval failed"
                        }
                    }
                    'microsoft.cache/redis' {
                        try {
                            $uri = "$($baseUri)$($resource.id)/listKeys?api-version=2023-08-01"
                            $keys = Invoke-RestMethod -Uri $uri -Headers $using:script:authHeader -Method Post
                            $secretObject.Keys = $keys
                            if ($keys) {
                                $secretObject.SecretTypes += "Redis Keys"
                                $secretObject.Severity = "High"  # Redis keys are high severity
                            }
                        }
                        catch {
                            Write-Verbose "Could not retrieve Redis keys for $($resource.name): $($_.Exception.Message)"
                            $secretObject.ProcessingErrors += "Redis keys retrieval failed"
                        }
                    }
                    'microsoft.apimanagement/service' {
                        try {
                            # Get tenant access information
                            $tenantAccessUri = "$($baseUri)$($resource.id)/tenant/access?api-version=2022-08-01"
                            $tenantAccess = Invoke-RestMethod -Uri $tenantAccessUri -Headers $using:script:authHeader -Method Get
                            
                            # Get tenant access secrets
                            $secretsUri = "$($baseUri)$($resource.id)/tenant/access/listSecrets?api-version=2022-08-01"
                            $secrets = Invoke-RestMethod -Uri $secretsUri -Headers $using:script:authHeader -Method Post
                            
                            $secretObject.Secrets = $secrets
                            $secretObject.Credentials = $tenantAccess
                            if ($secrets -or $tenantAccess) {
                                $secretObject.SecretTypes += "API Management Secrets"
                                $secretObject.Severity = "Medium"
                            }
                        }
                        catch {
                            Write-Verbose "Could not retrieve API Management secrets for $($resource.name): $($_.Exception.Message)"
                            $secretObject.ProcessingErrors += "API Management secrets retrieval failed"
                        }
                    }
                    'microsoft.devices/iothubs' {
                        try {
                            $uri = "$($baseUri)$($resource.id)/listKeys?api-version=2021-07-02"
                            $keys = Invoke-RestMethod -Uri $uri -Headers $using:script:authHeader -Method Post
                            $secretObject.Keys = $keys.value
                            if ($keys.value) {
                                $secretObject.SecretTypes += "IoT Hub Keys"
                                $secretObject.Severity = "Medium"
                            }
                        }
                        catch {
                            Write-Verbose "Could not retrieve IoT Hub keys for $($resource.name): $($_.Exception.Message)"
                            $secretObject.ProcessingErrors += "IoT Hub keys retrieval failed"
                        }
                    }
                    'microsoft.eventhub/namespaces' {
                        try {
                            # Get authorization rules first
                            $authRulesUri = "$($baseUri)$($resource.id)/authorizationRules?api-version=2021-11-01"
                            $authRules = (Invoke-RestMethod -Uri $authRulesUri -Headers $using:script:authHeader -Method Get).value
                            
                            $allKeys = @()
                            foreach ($rule in $authRules) {
                                try {
                                    $keysUri = "$($baseUri)$($rule.id)/listKeys?api-version=2021-11-01"
                                    $keys = Invoke-RestMethod -Uri $keysUri -Headers $using:script:authHeader -Method Post
                                    $allKeys += $keys
                                }
                                catch {
                                    Write-Verbose "Could not retrieve Event Hub authorization rule keys for $($rule.name): $($_.Exception.Message)"
                                    $secretObject.ProcessingErrors += "Event Hub auth rule keys retrieval failed"
                                }
                            }
                            $secretObject.Keys = $allKeys
                            if ($allKeys.Count -gt 0) {
                                $secretObject.SecretTypes += "Event Hub Keys"
                                $secretObject.Severity = "High"
                            }
                        }
                        catch {
                            Write-Verbose "Could not retrieve Event Hub keys for $($resource.name): $($_.Exception.Message)"
                            $secretObject.ProcessingErrors += "Event Hub keys retrieval failed"
                        }
                    }
                    'microsoft.notificationhubs/namespaces' {
                        try {
                            # Get authorization rules first
                            $authRulesUri = "$($baseUri)$($resource.id)/authorizationRules?api-version=2017-04-01"
                            $authRules = (Invoke-RestMethod -Uri $authRulesUri -Headers $using:script:authHeader -Method Get).value
                            
                            $allKeys = @()
                            foreach ($rule in $authRules) {
                                try {
                                    $keysUri = "$($baseUri)$($rule.id)/listKeys?api-version=2017-04-01"
                                    $keys = Invoke-RestMethod -Uri $keysUri -Headers $using:script:authHeader -Method Post
                                    $allKeys += $keys
                                }
                                catch {
                                    Write-Verbose "Could not retrieve Notification Hub authorization rule keys for $($rule.name): $($_.Exception.Message)"
                                    $secretObject.ProcessingErrors += "Notification Hub auth rule keys retrieval failed"
                                }
                            }
                            $secretObject.Keys = $allKeys
                            if ($allKeys.Count -gt 0) {
                                $secretObject.SecretTypes += "Notification Hub Keys"
                                $secretObject.Severity = "High"
                            }
                        }
                        catch {
                            Write-Verbose "Could not retrieve Notification Hub keys for $($resource.name): $($_.Exception.Message)"
                            $secretObject.ProcessingErrors += "Notification Hub keys retrieval failed"
                        }
                    }
                    'microsoft.relay/namespaces' {
                        try {
                            # Get authorization rules first
                            $authRulesUri = "$($baseUri)$($resource.id)/authorizationRules?api-version=2021-11-01"
                            $authRules = (Invoke-RestMethod -Uri $authRulesUri -Headers $using:script:authHeader -Method Get).value
                            
                            $allKeys = @()
                            foreach ($rule in $authRules) {
                                try {
                                    $keysUri = "$($baseUri)$($rule.id)/listKeys?api-version=2021-11-01"
                                    $keys = Invoke-RestMethod -Uri $keysUri -Headers $using:script:authHeader -Method Post
                                    $allKeys += $keys
                                }
                                catch {
                                    Write-Verbose "Could not retrieve Relay authorization rule keys for $($rule.name): $($_.Exception.Message)"
                                    $secretObject.ProcessingErrors += "Relay auth rule keys retrieval failed"
                                }
                            }
                            $secretObject.Keys = $allKeys
                            if ($allKeys.Count -gt 0) {
                                $secretObject.SecretTypes += "Relay Keys"
                                $secretObject.Severity = "High"
                            }
                        }
                        catch {
                            Write-Verbose "Could not retrieve Relay keys for $($resource.name): $($_.Exception.Message)"
                            $secretObject.ProcessingErrors += "Relay keys retrieval failed"
                        }
                    }
                    'microsoft.signalrservice/signalr' {
                        try {
                            $uri = "$($baseUri)$($resource.id)/listKeys?api-version=2023-02-01"
                            $keys = Invoke-RestMethod -Uri $uri -Headers $using:script:authHeader -Method Post
                            $secretObject.Keys = $keys
                            if ($keys) {
                                $secretObject.SecretTypes += "SignalR Keys"
                                $secretObject.Severity = "Medium"
                            }
                        }
                        catch {
                            Write-Verbose "Could not retrieve SignalR keys for $($resource.name): $($_.Exception.Message)"
                            $secretObject.ProcessingErrors += "SignalR keys retrieval failed"
                        }
                    }
                    'microsoft.cognitiveservices/accounts' {
                        try {
                            $uri = "$($baseUri)$($resource.id)/listKeys?api-version=2023-05-01"
                            $keys = Invoke-RestMethod -Uri $uri -Headers $using:script:authHeader -Method Post
                            $secretObject.Keys = $keys
                            if ($keys) {
                                $secretObject.SecretTypes += "Cognitive Services Keys"
                                $secretObject.Severity = "Medium"
                            }
                        }
                        catch {
                            Write-Verbose "Could not retrieve Cognitive Services keys for $($resource.name): $($_.Exception.Message)"
                            $secretObject.ProcessingErrors += "Cognitive Services keys retrieval failed"
                        }
                    }
                    'microsoft.maps/accounts' {
                        try {
                            $uri = "$($baseUri)$($resource.id)/listKeys?api-version=2021-12-01-preview"
                            $keys = Invoke-RestMethod -Uri $uri -Headers $using:script:authHeader -Method Post
                            $secretObject.Keys = $keys
                            if ($keys) {
                                $secretObject.SecretTypes += "Maps Keys"
                                $secretObject.Severity = "Medium"
                            }
                        }
                        catch {
                            Write-Verbose "Could not retrieve Maps keys for $($resource.name): $($_.Exception.Message)"
                            $secretObject.ProcessingErrors += "Maps keys retrieval failed"
                        }
                    }
                    'microsoft.media/mediaservices' {
                        try {
                            $uri = "$($baseUri)$($resource.id)/listKeys?api-version=2020-05-01"
                            $keys = Invoke-RestMethod -Uri $uri -Headers $using:script:authHeader -Method Post
                            $secretObject.Keys = $keys
                            if ($keys) {
                                $secretObject.SecretTypes += "Media Services Keys"
                                $secretObject.Severity = "Medium"
                            }
                        }
                        catch {
                            Write-Verbose "Could not retrieve Media Services keys for $($resource.name): $($_.Exception.Message)"
                            $secretObject.ProcessingErrors += "Media Services keys retrieval failed"
                        }
                    }
                    'microsoft.automation/automationaccounts' {
                        try {
                            # Get automation account keys
                            $uri = "$($baseUri)$($resource.id)/listKeys?api-version=2020-01-13-preview"
                            $keys = Invoke-RestMethod -Uri $uri -Headers $using:script:authHeader -Method Post
                            $secretObject.Keys = $keys
                            
                            # Also try to get variables and credentials
                            try {
                                $variablesUri = "$($baseUri)$($resource.id)/variables?api-version=2020-01-13-preview"
                                $variables = (Invoke-RestMethod -Uri $variablesUri -Headers $using:script:authHeader -Method Get).value
                                $secretObject.Secrets = $variables
                            }
                            catch {
                                Write-Verbose "Could not retrieve Automation Account variables for $($resource.name): $($_.Exception.Message)"
                                $secretObject.ProcessingErrors += "Automation Account variables retrieval failed"
                            }
                            
                            if ($keys -or $secretObject.Secrets) {
                                $secretObject.SecretTypes += "Automation Account Keys"
                                $secretObject.Severity = "Medium"
                            }
                        }
                        catch {
                            Write-Verbose "Could not retrieve Automation Account keys for $($resource.name): $($_.Exception.Message)"
                            $secretObject.ProcessingErrors += "Automation Account keys retrieval failed"
                        }
                    }
                }

                # Determine if we have any secrets and set the flag
                $hasSecrets = ($secretObject.Keys.Count -gt 0 -or 
                              $secretObject.Secrets.Count -gt 0 -or 
                              $null -ne $secretObject.Credentials -or 
                              $null -ne $secretObject.AdminKeys -or 
                              $secretObject.AppSettings.Count -gt 0 -or 
                              $secretObject.ConnectionStrings.Count -gt 0 -or 
                              $null -ne $secretObject.FunctionKeys)
                
                $secretObject.HasSecrets = $hasSecrets

                # Only add the secret object if we successfully retrieved some secrets
                if ($hasSecrets) {
                    # Count by severity level using thread-safe operations
                    switch ($secretObject.Severity) {
                        "Critical" { [void][System.Threading.Interlocked]::Increment($criticalSeverityCount) }
                        "High" { [void][System.Threading.Interlocked]::Increment($highSeverityCount) }
                        "Medium" { [void][System.Threading.Interlocked]::Increment($mediumSeverityCount) }
                        "Low" { [void][System.Threading.Interlocked]::Increment($lowSeverityCount) }
                    }
                    
                    [void][System.Threading.Interlocked]::Increment($resourcesWithSecretsCount)
                    [void]$result.Add($secretObject)
                    Write-Verbose "Successfully processed $($resource.name) - found secrets"
                } else {
                    Write-Verbose "No secrets found for $($resource.name)"
                }
                }
                catch {
                    Write-Verbose "Error processing resource $($resource.name): $($_.Exception.Message)"
                    [void][System.Threading.Interlocked]::Increment($processingErrorsCount)
                    # Continue processing other resources even if one fails
                }
            } -ThrottleLimit $ThrottleLimit

            Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message "Found $($result.Count) resources with secrets" -Severity 'Information'

        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "$($_.Exception.Message)" -Severity 'Error'
        }
    }

    end {
        $Duration = (Get-Date) - $stats.StartTime
        
        # Update stats with final counts from thread-safe counters
        $stats.ResourcesWithSecrets = $resourcesWithSecretsCount.Value
        $stats.ProcessingErrors = $processingErrorsCount.Value
        $stats.ResourceTypes = ($result | Group-Object ResourceType).Count
        
        Write-Host "`nAzure Resource Secret Discovery Summary:" -ForegroundColor Magenta
        Write-Host "   Total Resources Analyzed: $($stats.TotalResources)" -ForegroundColor White
        Write-Host "   Resources with Secrets Found: $($stats.ResourcesWithSecrets)" -ForegroundColor Yellow
        Write-Host "   Resource Types with Secrets: $($stats.ResourceTypes)" -ForegroundColor Cyan
        Write-Host "   Processing Errors: $($stats.ProcessingErrors)" -ForegroundColor Red
        Write-Host "   Duration: $($Duration.TotalSeconds.ToString('F2')) seconds" -ForegroundColor White
        
        if ($result.Count -gt 0) {
            # Group by severity level for summary
            $severityLevelCounts = $result | Group-Object Severity | Sort-Object @{Expression = {
                    switch ($_.Name) {
                        "Critical" { 1 }
                        "High" { 2 }
                        "Medium" { 3 }
                        "Low" { 4 }
                    }
                }
            }
            
            Write-Host "`n   Severity Level Breakdown:" -ForegroundColor White
            foreach ($group in $severityLevelCounts) {
                $emoji = switch ($group.Name) {
                    "Critical" { "" }
                    "High" { "" }
                    "Medium" { "" }
                    "Low" { "" }
                }
                Write-Host "      $emoji $($group.Name): $($group.Count)" -ForegroundColor White
            }
            
            # Group by resource type for summary
            $resourceTypeCounts = $result | Group-Object ResourceType | Sort-Object Count -Descending
            Write-Host "`n   Resource Type Breakdown:" -ForegroundColor White
            foreach ($group in $resourceTypeCounts) {
                $shortType = ($group.Name -split '/')[-1]  # Get just the resource type name
                Write-Host "      $shortType`: $($group.Count)" -ForegroundColor Cyan
            }
            
            # Return results in requested format
            switch ($OutputFormat) {
                "JSON" { 
                    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    $jsonOutput = $result | ConvertTo-Json -Depth 10
                    $jsonFilePath = "AzureResourceSecrets_$timestamp.json"
                    $jsonOutput | Out-File -FilePath $jsonFilePath -Encoding UTF8
                    Write-Host "JSON output saved to: $jsonFilePath" -ForegroundColor Green
                    # File created, no console output needed
                    return
                }
                "CSV" { 
                    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    $csvOutput = $result | ConvertTo-CSV
                    $csvFilePath = "AzureResourceSecrets_$timestamp.csv"
                    $csvOutput | Out-File -FilePath $csvFilePath -Encoding UTF8
                    Write-Host "CSV output saved to: $csvFilePath" -ForegroundColor Green
                    # File created, no console output needed
                    return
                }
                "Object" { return $result }
                "Table" { 
                    if ($result.Count -gt 0) {
                        return $result | Format-Table -AutoSize 
                    } else {
                        Write-Host "`nNo resources with secrets found" -ForegroundColor Red
                        return @()
                    }
                }
            }
        }
        else {
            # Handle case when no secrets found based on output format
            switch ($OutputFormat) {
                "JSON" { 
                    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    $jsonOutput = @() | ConvertTo-Json
                    $jsonFilePath = "AzureResourceSecrets_$timestamp.json"
                    $jsonOutput | Out-File -FilePath $jsonFilePath -Encoding UTF8
                    Write-Host "Empty JSON output saved to: $jsonFilePath" -ForegroundColor Green
                    return
                }
                "CSV" { 
                    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    $csvOutput = @() | ConvertTo-CSV
                    $csvFilePath = "AzureResourceSecrets_$timestamp.csv"
                    $csvOutput | Out-File -FilePath $csvFilePath -Encoding UTF8
                    Write-Host "Empty CSV output saved to: $csvFilePath" -ForegroundColor Green
                    return
                }
                "Object" { 
                    Write-Host "`nNo resources with secrets found" -ForegroundColor Red
                    Write-Information "No resources with secrets found" -InformationAction Continue
                    return @()
                }
                "Table" { 
                    Write-Host "`nNo resources with secrets found" -ForegroundColor Red
                    Write-Information "No resources with secrets found" -InformationAction Continue
                    return @()
                }
            }
        }
        
        Write-Verbose " Completed function $($MyInvocation.MyCommand.Name)"
    }

    <#
    .SYNOPSIS
        Retrieves secrets from various Azure resources in the current context.

    .DESCRIPTION
        The Get-AzResourceSecretList function collects secrets from different Azure resources including:
        - Key Vault secrets (retrieves actual secret values using data plane API) - Critical severity
        - Storage Account keys (including Kerberos keys where available) - High severity
        - App Service application settings and connection strings - Medium severity
        - Function App keys (for function apps) - Medium severity
        - Service Bus namespace authorization rule keys - High severity
        - Event Hub namespace authorization rule keys - High severity
        - Notification Hub namespace authorization rule keys - High severity
        - Relay namespace authorization rule keys - High severity
        - Cosmos DB keys (both primary and read-only) - High severity
        - Container Registry credentials - Medium severity
        - Search Service admin keys - Medium severity
        - PostgreSQL Flexible Server credentials - Medium severity
        - MySQL Flexible Server credentials - Medium severity
        - Redis Cache keys - High severity
        - API Management tenant access secrets - Medium severity
        - IoT Hub keys - Medium severity
        - SignalR Service keys - Medium severity
        - Cognitive Services keys - Medium severity
        - Azure Maps keys - Medium severity
        - Media Services keys - Medium severity
        - Automation Account keys and variables - Medium severity
        
        The function uses parallel processing for optimal performance and provides proper error handling 
        to continue processing even if some resources fail. Results are organized by severity level and 
        only include resources that have retrievable secrets.

    .PARAMETER ThrottleLimit
        Specifies the maximum number of concurrent operations that can be performed in parallel.
        Default value is 100.

    .PARAMETER OutputFormat
        Optional. Specifies the output format for results. Valid values are:
        - Object: Returns PowerShell objects (default when piping)
        - JSON: Creates timestamped JSON file (AzureResourceSecrets_TIMESTAMP.json) with no console output
        - CSV: Creates timestamped CSV file (AzureResourceSecrets_TIMESTAMP.csv) with no console output
        - Table: Returns results in a formatted table (default)
        Aliases: output, o

    .OUTPUTS
        Returns an array of PSCustomObjects containing the following properties:
        - ResourceName: The name of the Azure resource
        - ResourceType: The type of the Azure resource
        - ResourceId: The full resource ID
        - ResourceGroup: The resource group name
        - Location: The Azure region
        - SubscriptionId: The subscription ID
        - Severity: Risk level (Critical, High, Medium, Low) based on secret types
        - Keys: Array of keys/credentials retrieved
        - Secrets: Array of secrets retrieved (Key Vault)
        - Credentials: Credential objects (Container Registry, Database servers)
        - AdminKeys: Administrative keys (Search services)
        - AppSettings: Application settings (Web Apps)
        - ConnectionStrings: Connection strings (Web Apps)
        - FunctionKeys: Function keys (Function Apps)
        - ProcessingErrors: Array of any errors encountered during processing
        - ProcessedAt: Timestamp of when the resource was processed
        - HasSecrets: Boolean indicating if any secrets were found
        - SecretTypes: Array of secret types found in the resource

    .EXAMPLE
        Get-AzResourceSecretList
        Returns all resources with secrets using default throttle limit and table format.

    .EXAMPLE
        Get-AzResourceSecretList -ThrottleLimit 200
        Returns all resources with secrets using a custom throttle limit of 200.

    .EXAMPLE
        Get-AzResourceSecretList -OutputFormat JSON
        Creates a timestamped JSON file (e.g., AzureResourceSecrets_20250629_143022.json) in the current directory.
        No console output is displayed; only file creation confirmation message is shown.

    .EXAMPLE
        Get-AzResourceSecretList -OutputFormat CSV -ThrottleLimit 50
        Creates a timestamped CSV file (e.g., AzureResourceSecrets_20250629_143022.csv) in the current directory.
        Uses a throttle limit of 50. No console output is displayed; only file creation confirmation message is shown.

    .EXAMPLE
        Get-AzResourceSecretList -Verbose
        Returns all resources with secrets with detailed progress information.

    .EXAMPLE
        $secrets = Get-AzResourceSecretList -OutputFormat Object
        $criticalSecrets = $secrets | Where-Object { $_.Severity -eq "Critical" }
        Stores results in a variable and filters for critical severity secrets.

    .NOTES
        File: Get-AzResourceSecretList.ps1
        Author: Script Author
        Version: 2.0
        Requires: PowerShell 7.0 or later for parallel processing
        Requires: Azure authentication and appropriate permissions to read resource secrets
        
        The function checks 20 different Azure resource types and assigns severity levels based on the 
        sensitivity and potential impact of the secrets:

        CRITICAL severity (direct access to sensitive data/broad permissions):
        - Key Vault secrets (actual secret values retrieved via data plane API)

        HIGH severity (infrastructure keys and database access):
        - Storage Account keys
        - Service Bus keys
        - Event Hub keys
        - Cosmos DB keys
        - Redis Cache keys

        MEDIUM severity (application-level secrets and service keys):
        - App Service settings and connection strings
        - Function App keys
        - Container Registry credentials
        - Search Service admin keys
        - Database server credentials
        - API Management secrets
        - IoT Hub keys
        - SignalR Service keys
        - Cognitive Services keys
        - Azure Maps keys
        - Media Services keys
        - Automation Account keys

    .LINK
        MITRE ATT&CK Tactic: TA0006 - Credential Access
        https://attack.mitre.org/tactics/TA0006/

    .LINK
        MITRE ATT&CK Technique: T1555.006 - Credentials from Password Stores: Cloud Secrets Management Stores
        https://attack.mitre.org/techniques/T1555/006/

    #>
}