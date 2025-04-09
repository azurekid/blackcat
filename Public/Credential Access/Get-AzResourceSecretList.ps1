function Get-AzResourceSecretList {
    [cmdletbinding()]
    param ()

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {
        # try {
            $secretsByType = @{}
            $baseUri = "https://management.azure.com"

            # Get all resources or filter by specific types
            $resources = @(
                # 'Microsoft.KeyVault/vaults',
                # 'Microsoft.Storage/storageAccounts',
                'Microsoft.Web/sites'
                # 'Microsoft.ServiceBus/namespaces',
                # 'Microsoft.DocumentDB/databaseAccounts',
                # 'Microsoft.ContainerRegistry/registries',
                # 'Microsoft.Search/searchServices',
                # 'Microsoft.DBforPostgreSQL/flexibleServers',
                # 'Microsoft.DBforMySQL/flexibleServers',
                # 'Microsoft.Cache/Redis',
                # 'Microsoft.ApiManagement/service',
                # 'Microsoft.Devices/IotHubs'
            ) | ForEach-Object {
                Invoke-AzBatch -ResourceType $_
            }

            foreach ($resource in $resources) {
                $resourceType = $resource.type
                if (!$secretsByType.ContainsKey($resourceType)) {
                    $secretsByType[$resourceType] = @()
                }

                $secretObject = [PSCustomObject]@{
                    ResourceName = $resource.name
                    ResourceType = $resourceType
                    ResourceId = $resource.id
                    Keys = @()
                }

                switch ($resourceType) {
                    # 'microsoft.keyvault/vaults' {
                    #     $secrets = (Invoke-RestMethod -Uri $uri -Headers $script:authHeader -Method Get).value
                    #     $secretObject.Secrets = $secrets
                    # }
                    'microsoft.storage/storageaccounts' {
                        $uri = "$($baseUri)$($resource.id)/listKeys?api-version=2024-01-01"
                        $keys = (Invoke-RestMethod -Uri $uri -Headers $script:authHeader -Method Post).keys
                        $secretObject.Keys = $keys
                    }
                    'microsoft.web/sites' {
                        $uri = "$($baseUri)$($resource.id)/functions/admin/token?api-version=2024-04-01"

                        # $resourceIds = (Invoke-RestMethod -Uri $uri -Headers $script:authHeader -Method Get).value.id
                        # foreach ($resourceId in $resourceIds) {
                            # $functionUri = "$($baseUri)$($resourceId)/listKeys?api-version=2022-03-01"
                            # write-host $functionUri
                            $secretObject = Invoke-RestMethod -Uri $uri -Headers $script:authHeader -Method Get
                            Write-Output "Function keys $($resourceId): $($functionKeys)"

                            pause
                        # }
                        # $functionKeys = Invoke-RestMethod -Uri $uri -Headers $script:authHeader -Method Get
                        # return $functionKeys
                        # $secretObject.MasterKey = $functionKeys.masterKey
                    }
                    'microsoft.servicebus/namespaces' {
                        $uri = "$($baseUri)$($resource.id)/listKeys?api-version=2021-11-01"
                        $keys = Invoke-RestMethod -Uri $uri -Headers $script:authHeader -Method Post
                        $secretObject.Keys = $keys
                    }
                    'microsoft.documentdb/databaseaccounts' {
                        $uri = "$($baseUri)$($resource.id)/listKeys?api-version=2021-10-15"
                        $keys = Invoke-RestMethod -Uri $uri -Headers $script:authHeader -Method Post
                        $secretObject.Keys = $keys
                    }
                    'microsoft.containerregistry/registries' {
                        $uri = "$($baseUri)$($resource.id)/listCredentials?api-version=2023-07-01"
                        $creds = Invoke-RestMethod -Uri $uri -Headers $script:authHeader -Method Post
                        $secretObject.Credentials = $creds
                    }
                    'microsoft.search/searchservices' {
                        $uri = "$($baseUri)$($resource.id)/listAdminKeys?api-version=2021-04-01-preview"
                        $keys = Invoke-RestMethod -Uri $uri -Headers $script:authHeader -Method Post
                        $secretObject.AdminKeys = $keys
                    }
                    'microsoft.dbforpostgresql/flexibleservers' {
                        $uri = "$($baseUri)$($resource.id)/listAdminCredentials?api-version=2023-03-01-preview"
                        $creds = Invoke-RestMethod -Uri $uri -Headers $script:authHeader -Method Post
                        $secretObject.Credentials = $creds
                    }
                    'microsoft.dbformysql/flexibleservers' {
                        $uri = "$($baseUri)$($resource.id)/listAdminCredentials?api-version=2023-06-01-preview"
                        $creds = Invoke-RestMethod -Uri $uri -Headers $script:authHeader -Method Post
                        $secretObject.Credentials = $creds
                    }
                    'microsoft.cache/redis' {
                        $uri = "$($baseUri)$($resource.id)/listKeys?api-version=2023-08-01"
                        $keys = Invoke-RestMethod -Uri $uri -Headers $script:authHeader -Method Post
                        $secretObject.Keys = $keys
                    }
                    'microsoft.apimanagement/service' {
                        $uri = "$($baseUri)$($resource.id)/listSecrets?api-version=2022-08-01"
                        $secrets = Invoke-RestMethod -Uri $uri -Headers $script:authHeader -Method Post
                        $secretObject.Secrets = $secrets
                    }
                    'microsoft.devices/iothubs' {
                        $uri = "$($baseUri)$($resource.id)/listKeys?api-version=2021-07-02"
                        $keys = Invoke-RestMethod -Uri $uri -Headers $script:authHeader -Method Post
                        $secretObject.Keys = $keys
                    }
                }

                $secretsByType[$resourceType] += $secretObject
            }

        # }
        # catch {
        #     Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        # }
        return $secretObject
    }

    <#
    .SYNOPSIS
        Retrieves secrets from various Azure resources in the current context.

    .DESCRIPTION
        The Get-AzResourceSecretList function collects secrets from different Azure resources including:
        - Key Vault secrets
        - Storage Account keys
        - Function App keys
        - Service Bus namespace keys
        - Cosmos DB keys
        - Container Registry credentials
        - Search Service admin keys
        - PostgreSQL Flexible Server credentials
        - MySQL Flexible Server credentials
        - Redis Cache keys
        - API Management secrets
        - IoT Hub keys
        Results are grouped by resource type.

    .EXAMPLE
        ```powershell
        Get-AzResourceSecretList
        ```
        Returns a hashtable of secrets organized by resource type.

    .NOTES
        Author: Rogier Dijkman
        SECURITY WARNING: This function returns sensitive information. Use with caution.
    #>
}