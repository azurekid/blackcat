function Get-FederatedAppCredential {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias('Id', 'object-id')]
        [ValidatePattern('^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$', ErrorMessage = "It does not match expected pattern '{1}'")]
        [string]$ObjectId,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias('application-id')]
        [ValidatePattern('^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$', ErrorMessage = "It does not match expected pattern '{1}'")]
        [string]$AppId
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
    }

    process {

        try {
                if ($AppId) {
                    Write-Verbose "Get Application with Application Id $($AppId)"
                    $ObjectId = (Invoke-MsGraph -relativeUrl "applications(appId='$AppId')" -NoBatch).id
                }

                Write-Verbose "Get Federated Identity Credentials for Application with ObjectId $($ObjectId)"
                Invoke-MsGraph -relativeUrl "applications/$ObjectId/federatedIdentityCredentials"
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
<#
.SYNOPSIS
Retrieves federated identity credentials for a specified Microsoft Entra application.

.DESCRIPTION
The `Get-FederatedAppCredential` function retrieves federated identity credentials associated with a Microsoft Entra application. You can specify the application using its Object ID or Application ID (GUID). If the Application ID is provided, the function resolves it to the corresponding Object ID before retrieving the credentials.

.PARAMETER ObjectId
The Object ID (GUID) of the Microsoft Entra application. This parameter must match the pattern of a valid GUID (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx).

.PARAMETER AppId
The Application ID (GUID) of the Microsoft Entra application. This parameter must match the pattern of a valid GUID (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx). If provided, it will be resolved to the corresponding Object ID.

.EXAMPLE
Get-FederatedAppCredential -ObjectId "12345678-1234-1234-1234-123456789012"
Retrieves all federated identity credentials for the specified application using its Object ID.

.EXAMPLE
Get-FederatedAppCredential -AppId "87654321-4321-4321-4321-210987654321"
Retrieves all federated identity credentials for the specified application using its Application ID.

.EXAMPLE
Invoke-MsGraph -relativeUrl "applications" | Get-FederatedAppCredential
Retrieves all federated identity credentials for all applications returned by the `Invoke-MsGraph` command.

.EXAMPLE
Get-AzAdApplication -All $true | Get-FederatedAppCredential
Retrieves all federated identity credentials for all applications returned by the `Get-AzAdApplication` command.

.LINK
https://learn.microsoft.com/en-us/graph/api/application-list-federatedidentitycredentials
#>
}