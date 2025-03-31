function New-AuthHeader {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('MSGraph', 'KeyVault', 'Azure', 'LogAnalytics', 'Other')]
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

    <#
    .SYNOPSIS
        Creates an authentication header for Azure REST API calls.

    .DESCRIPTION
        Creates an authentication header using the current Azure context for different Azure endpoints
        including Microsoft Graph, Key Vault, and Azure Management API.

    .PARAMETER EndpointType
        The type of endpoint to authenticate against. Valid values are 'MSGraph', 'KeyVault', 'Azure', 'LogAnalytics'.

    .EXAMPLE
        Create-AuthHeader -EndpointType 'MSGraph'
        Creates an authentication header for Microsoft Graph API calls.

    .EXAMPLE
        Create-AuthHeader -EndpointType 'KeyVault'
        Creates an authentication header for Key Vault API calls.

    .NOTES
        Author: Rogier Dijkman
        Requires: Az.Accounts module
    #>
}
