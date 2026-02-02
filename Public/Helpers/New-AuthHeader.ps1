function New-AuthHeader {
    [cmdletbinding(SupportsShouldProcess = $true)]
    [OutputType([System.Collections.Hashtable])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Azure', 'Batch', 'Cache', 'CosmosDB', 'DataLake', 'DevOps', 'EventGrid', 'EventHub', 'IoTHub', 'KeyVault', 'LogAnalytics', 'MSGraph', 'RedisCache', 'SQLDatabase', 'ServiceBus', 'Storage', 'Synapse', 'Other')]
        [string]$EndpointType,

        [Parameter(Mandatory = $false)]
        [ValidatePattern('^(https?)://[^\s/$.?#].[^\s]*$')]
        [string]$EndpointUri
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
                $tokenValue = ConvertFrom-AzAccessToken -Token $token.Token
                
                if ([string]::IsNullOrEmpty($tokenValue)) {
                    throw "Failed to retrieve valid access token for $EndpointType"
                }

                # Create and return the authentication header
                $authHeader = @{
                    'Authorization' = "Bearer $tokenValue"
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
        Creates an authentication header for Azure REST API interactions.

    .DESCRIPTION
        The `New-AuthHeader` function generates an authentication header for various Azure services and APIs.
        It uses the current Azure context to retrieve an access token for the specified endpoint type.
        The function supports predefined Azure endpoints as well as custom endpoints when 'Other' is selected.

    .PARAMETER EndpointType
        Specifies the type of Azure endpoint to authenticate against.
        Acceptable values are:
        'Azure', 'Batch', 'Cache', 'CosmosDB', 'DataLake', 'DevOps', 'EventGrid', 'EventHub', 'IoTHub',
        'KeyVault', 'LogAnalytics', 'MSGraph', 'RedisCache', 'SQLDatabase', 'ServiceBus', 'Storage',
        'Synapse', 'Other'.

    .PARAMETER EndpointUri
        Specifies a custom endpoint URI when 'Other' is selected as the EndpointType.
        This parameter is optional but required when 'Other' is used. It must be a valid HTTP or HTTPS URL.

    .EXAMPLE
        New-AuthHeader -EndpointType 'MSGraph'
        Generates an authentication header for accessing the Microsoft Graph API.

    .EXAMPLE
        New-AuthHeader -EndpointType 'KeyVault'
        Generates an authentication header for accessing the Azure Key Vault API.

    .EXAMPLE
        New-AuthHeader -EndpointType 'Other' -EndpointUri 'https://custom.endpoint.com'
        Generates an authentication header for a custom endpoint.

    .NOTES
        Author: Rogier Dijkman
        Prerequisite: Az.Accounts module must be installed and the user must be logged in using `Connect-AzAccount`.
        The function uses `Get-AzAccessToken` to retrieve the access token for the specified endpoint.

    .LINK
        MITRE ATT&CK Tactic: TA0006 - Credential Access
        https://attack.mitre.org/tactics/TA0006/

    .LINK
        MITRE ATT&CK Technique: T1550.001 - Use Alternate Authentication Material: Application Access Token
        https://attack.mitre.org/techniques/T1550/001/
    #>
}