function Set-FunctionAppSecret {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9-]+[A-Za-z0-9]$', ErrorMessage = "It does not match expected pattern '{1}'")]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceNameCompleterAttribute(
            "Microsoft.Web/sites",
            "ResourceGroupName"
        )][string]$Name,

        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceGroupCompleterAttribute()]
        [Alias('rg', 'resource-group')]
        [string[]]$ResourceGroupName,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$KeyName = "_master",

        [Parameter(Mandatory = $false)]
        [string]$KeyValue = $sessionVariables.default
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {
        try {
            $baseUri = "https://management.azure.com"
            $resourceId = (Invoke-AzBatch -ResourceType 'Microsoft.Web/sites' | Where-Object Name -eq "$Name").id
            $uri = "$($baseUri)$resourceId/host/default/functionKeys/$($KeyName)?api-version=2024-04-01"

            # Prepare the request body
            $body = @{
                properties = @{
                    value = $KeyValue
                }
            }

            $requestParam = @{
                Headers     = $authHeader
                Uri         = $uri
                Method      = 'PUT'
                Body        = $body | ConvertTo-Json -Depth 10
                ContentType = 'application/json'
            }

            $apiResponse = Invoke-RestMethod @requestParam
            return $apiResponse

        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
    <#
    .SYNOPSIS
        Creates or updates secrets for an Azure Function App.

    .DESCRIPTION
        The New-FunctionAppSecret function creates or updates secrets for an Azure Function App.
        It can manage both host-level secrets and function-level secrets.

    .PARAMETER Name
        The name of the function app. Auto-completes with existing function app names.

    .PARAMETER KeyName
        The name of the key to create or update. Defaults to "blackcat".

    .PARAMETER KeyValue
        Optional. The value to set for the key. If not provided, a default value will be used.

    .EXAMPLE
        New-FunctionAppSecret -Name "myfuncapp"
        Creates a new host secret by replacing the _master key with a default value.
        The value is set to the default value in the session variable which is a base64 encoded string.

    .EXAMPLE
        New-FunctionAppSecret -Name "myfuncapp" -KeyName "mykey" -KeyValue "myvalue"
        Creates or updates a host secret with the specified key name and value.

    .LINK
        https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/create-or-update-host-secret
        https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/create-or-update-function-secret

    .NOTES
        Author: Rogier Dijkman
    #>
}