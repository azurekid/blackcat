function Set-FederatedIdentity {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('resource-id')]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceIdCompleter(
            "Microsoft.ManagedIdentity/userAssignedIdentities"
        )][string]$Id,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias('federated-identity-name')]
        [string]$Name = 'federatedCredential',

        [Parameter(Mandatory = $true)]
        [Alias('github-organization')]
        [string]$GitHubOrganization,

        [Parameter(Mandatory = $true)]
        [Alias('github-repository')]
        [string]$GitHubRepository,

        [Parameter(Mandatory = $false)]
        [Alias('branch-name')]
        [string]$Branch = 'main'
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
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
Sets a federated identity credential for a user-assigned managed identity to enable GitHub Actions authentication.

.DESCRIPTION
The Set-AzFederatedIdentity cmdlet creates or updates a federated identity credential that enables GitHub Actions workflows
to authenticate to Azure using OpenID Connect. This links a specific GitHub repository and branch to a user-assigned managed identity.

.PARAMETER Id
The resource ID of the user-assigned managed identity in Azure. This should be the full resource ID path.

.PARAMETER Name
The name of the federated credential to create. Defaults to 'federatedCredential'.

.PARAMETER GitHubOrganization
The GitHub organization name where the repository is located.

.PARAMETER GitHubRepository
The name of the GitHub repository to federate with the managed identity.

.PARAMETER Branch
The branch name to associate with the federated credential. Defaults to 'main'.

.EXAMPLE
Set-AzFederatedIdentity -Id "/subscriptions/12345678-1234-1234-1234-123456789012/resourcegroups/myRG/providers/Microsoft.ManagedIdentity/userAssignedIdentities/myIdentity" -GitHubOrganization "myorg" -GitHubRepository "myrepo"

Creates a federated credential for the specified managed identity, linking it to the main branch of the myorg/myrepo GitHub repository.

.EXAMPLE
Set-AzFederatedIdentity -Id "/subscriptions/12345678-1234-1234-1234-123456789012/resourcegroups/myRG/providers/Microsoft.ManagedIdentity/userAssignedIdentities/myIdentity" -Name "dev-credential" -GitHubOrganization "myorg" -GitHubRepository "myrepo" -Branch "development"

Creates a federated credential named "dev-credential" for the specified managed identity, linking it to the development branch of the myorg/myrepo GitHub repository.

.NOTES
Requires appropriate Azure RBAC permissions to manage managed identities.
The function uses Azure REST API version 2023-01-31.

.LINK
https://learn.microsoft.com/en-us/azure/active-directory/develop/workload-identity-federation-create-trust-github
#>
}