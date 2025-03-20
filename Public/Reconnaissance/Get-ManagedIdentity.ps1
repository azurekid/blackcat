function Get-ManagedIdentity {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceNameCompleterAttribute(
            "Microsoft.ManagedIdentity/userAssignedIdentities",
            "ResourceGroupName"
        )]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9-]+[A-Za-z0-9]$', ErrorMessage = "It does not match expected pattern '{1}'")]
        [Alias('identity-name', 'user-assigned-identity')]
        [string]$Name,

        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceGroupCompleterAttribute()]
        [Alias('rg', 'resource-group')]
        [string[]]$ResourceGroupName
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {

        try {

            Write-Verbose "Get Managed Identity"
            $uri = "$($SessionVariables.baseUri)/providers/Microsoft.ManagedIdentity/userAssignedIdentities?api-version=2023-01-31"

            $requestParam = @{
                Headers = $script:authHeader
                Uri     = $uri
                Method  = 'GET'
            }
            $apiResponse = (Invoke-RestMethod @requestParam).value

            if ($name) {
                return $apiResponse | Where-Object { $_.name -eq $Name }
            } else {
                return $apiResponse
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
<#
.SYNOPSIS
Retrieves Azure Managed Identities.

.DESCRIPTION
The `Get-AzManagedIdentity` function retrieves user-assigned managed identities from Azure. It can filter the identities by name if provided.

.PARAMETER Name
The name of the managed identity to retrieve. This parameter is optional and can be provided from the pipeline by property name.

.EXAMPLE
# Example 1: Retrieve all managed identities
Get-AzManagedIdentity

.EXAMPLE
# Example 2: Retrieve a specific managed identity by name
Get-AzManagedIdentity -Name "myManagedIdentity"

.DEPENDENCIES
- `Invoke-BlackCat`: This function is invoked at the beginning of the script.
- `Invoke-RestMethod`: This cmdlet is used to make REST API calls to Azure.
- `Write-Message`: This function is used to log error messages.

.NOTES
- The function requires the `Microsoft.ManagedIdentity` provider and the `2023-01-31` API version.
#>
}