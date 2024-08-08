function Set-AzFederatedIdentity {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$Name = 'federatedCredential',

        [Parameter(Mandatory = $true)]
        [string]$GitHubOrganization,

        [Parameter(Mandatory = $true)]
        [string]$GitHubRepository,

        [Parameter(Mandatory = $false)]
        [string]$Branch = 'main'
    )

    begin {
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {
        try {
            $baseUri = 'https://management.azure.com'
            $uri = '{0}{1}/federatedIdentityCredentials/{2}?api-version=2023-01-31' -f $baseUri, $Id, $Name

            $body = @{
                properties = @{
                    issuer    = "https://token.actions.githubusercontent.com"
                    subject   = "repo:$($GitHubOrganization)/$($GitHubRepository):ref:refs/heads/$Branch"
                    audiences = @("api://AzureADTokenExchange")
                }
            } | ConvertTo-Json

            $requestParam = @{
                Headers     = $script:authHeader
                Uri         = $uri
                Method      = 'PUT'
                ContentType = 'application/json'
                Body        = $body
            }

            (Invoke-RestMethod @requestParam)
        }
        catch {
            Write-Message $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
<#
.SYNOPSIS
Sets the federated identity to a GitHub repository.

.DESCRIPTION
The Set-FederatedIdentity function sets the federated identity to a GitHub repository by making a PUT request to the Azure Management API.

.PARAMETER Id
The ID of the user-assigned managed identity.

.PARAMETER Name
The name of the user-assigned managed identity.

.PARAMETER GitHubOrganization
The name of the GitHub organization.

.PARAMETER GitHubRepository
The name of the GitHub repository.

.PARAMETER Branch
The branch name of the GitHub repository. Default value is 'main'.

.EXAMPLE
Set-FederatedIdentity -Id "/subscriptions/xxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourcegroups/myRG/providers/Microsoft.ManagedIdentity/userAssignedIdentities/MyIdentity" -GitHubOrganization "MyOrg" -GitHubRepository "MyRepo" -Branch "main"
Sets the federated identity for the GitHub repository "MyRepo" in the organization "MyOrg" with the ID "123456" and the name "MyFederatedIdentity" on the "main" branch.

#>
}
