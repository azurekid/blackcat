function New-AuthHeader {
    [cmdletbinding(SupportsShouldProcess = $true)]
    [OutputType([System.Collections.Hashtable])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Azure', 'Batch', 'Cache', 'CosmosDB', 'DataLake', 'DevOps', 'EventGrid', 'EventHub', 'IoTHub', 'KeyVault', 'LogAnalytics', 'MSGraph', 'RedisCache', 'SQLDatabase', 'ServiceBus', 'Storage', 'Synapse', 'Other')]
        [string]$EndpointType,

        [Parameter(Mandatory = $false)]
        [ValidatePattern('^(https?)://[^\s/$.?#].[^\s]*$')]
        [string]$endpointUri
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"

        if ($EndpointType -eq 'Other') {
            if ([string]::IsNullOrWhiteSpace($endpointUri)) {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "When 'Other' is selected as EndpointType, 'endpointUri' cannot be empty." -Severity 'Error'
            }

            # Use the provided endpoint URI
            $endpoints = @{
                Other = $endpointUri
            }
        } else {
            # Use predefined endpoints for other types
            $endpoints = @{
                Azure        = 'https://management.azure.com'
                Batch        = 'https://batch.azure.com'
                Cache        = 'https://cache.azure.com'
                CosmosDB     = 'https://cosmos.azure.com'
                DataLake     = 'https://datalake.azure.net'
                DevOps       = '499b84ac-1321-427f-aa17-267ca6975798'
                EventGrid    = 'https://eventgrid.azure.net'
                EventHub     = 'https://eventhub.azure.net'
                IoTHub       = 'https://iothub.azure.net'
                KeyVault     = 'https://vault.azure.net'
                LogAnalytics = 'https://api.loganalytics.io'
                MSGraph      = 'https://graph.microsoft.com'
                RedisCache   = 'https://cache.azure.com'
                SQLDatabase  = 'https://database.windows.net'
                ServiceBus   = 'https://servicebus.azure.net'
                Storage      = 'https://storage.azure.com'
                Synapse      = 'https://dev.azuresynapse.net'
            }
        }
    }

    process {
        if ($PSCmdlet.ShouldProcess("EndpointType: $EndpointType", "Generate authentication header")) {
            try {
                # Get the access token for the specified endpoint
                $context = Get-AzContext
                if (-not $context) {
                    Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "No Azure context found. Please run Connect-AzAccount first." -Severity 'Error'
                }

                $token = Get-AzAccessToken -ResourceUrl $endpoints[$EndpointType]

                # Create and return the authentication header
                $authHeader = @{
                    'Authorization' = "Bearer $($token.Token)"
                    'Content-Type'  = 'application/json'
                }

                return $authHeader
            }
            catch {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
            }
        }
    }

    <#
    .SYNOPSIS
        Generates an authentication header for Azure REST API interactions.

    .DESCRIPTION
        This function creates an authentication header based on the current Azure context.
        It supports various Azure endpoints, including Microsoft Graph, Key Vault, Azure Management API,
        Log Analytics, and several others.

    .PARAMETER EndpointType
        Specifies the type of Azure endpoint to authenticate against.
        Acceptable values are: 'MSGraph', 'KeyVault', 'Azure', 'LogAnalytics', 'Other'.

    .EXAMPLE
        Create-AuthHeader -EndpointType 'MSGraph'
        Generates an authentication header for accessing Microsoft Graph API.

    .EXAMPLE
        Create-AuthHeader -EndpointType 'KeyVault'
        Generates an authentication header for accessing Key Vault API.

    .NOTES
        Author: Rogier Dijkman
        Prerequisite: Az.Accounts module
    #>
}
