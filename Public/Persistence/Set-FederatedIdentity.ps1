function Set-FederatedIdentity {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, ParameterSetName = "ByResourceId")]
        [Alias('resource-id')]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceIdCompleter(
            "Microsoft.ManagedIdentity/userAssignedIdentities"
        )][string]$Id,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = "ByName")]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceNameCompleterAttribute(
            "Microsoft.ManagedIdentity/userAssignedIdentities",
            "ResourceGroupName"
        )]
        [Alias('identity-name', 'user-assigned-identity')]
        [string]$ManagedIdentityName,

        [Parameter(Mandatory = $false)]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceGroupCompleterAttribute()]
        [Alias('rg', 'resource-group')]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias('federated-identity-name', 'credential-name')]
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
        [void] $ResourceGroupName # Only used to trigger the ResourceGroupCompleter
        
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {
        # Resolve managed identity name to resource ID if needed
        if ($ManagedIdentityName -and -not $Id) {
            Write-Host " Looking up Managed Identity: $ManagedIdentityName..." -ForegroundColor Cyan
            $uami = Get-ManagedIdentity -Name $ManagedIdentityName -OutputFormat Object
            if ($uami) {
                $Id = $uami.id
                Write-Host "     Found: $($uami.name)" -ForegroundColor Green
            }
            else {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Managed identity not found: $ManagedIdentityName" -Severity 'Error'
                return
            }
        }

        if (-not $Id) {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Either -Id or -ManagedIdentityName must be provided" -Severity 'Error'
            return
        }

        if ($PSCmdlet.ShouldProcess("Federated Identity Credential for $GitHubOrganization/$GitHubRepository on branch $Branch")) {
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
                    UserAgent   = $($sessionVariables.userAgent)
                }

                (Invoke-RestMethod @requestParam)
            }
            catch {
                Write-Message $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
            }
        }
    }
<#
.SYNOPSIS
Sets a federated identity credential for a managed identity.

.DESCRIPTION
Sets a federated identity credential for a managed identity to enable OIDC-based authentication. This enables external workloads (GitHub Actions, GitLab CI, etc.) to obtain Azure access tokens without storing credentials. Useful for establishing persistent access from external CI/CD systems.

.PARAMETER Id
The resource ID of the user-assigned managed identity in Azure. This should be the full resource ID path.
Aliases: resource-id

.PARAMETER ManagedIdentityName
The name of the user-assigned managed identity. The function will automatically look up the resource ID.
Aliases: identity-name, user-assigned-identity

.PARAMETER Name
The name of the federated credential to create. Defaults to 'federatedCredential'.
Aliases: federated-identity-name, credential-name

.PARAMETER GitHubOrganization
The GitHub organization name where the repository is located.

.PARAMETER GitHubRepository
The name of the GitHub repository to federate with the managed identity.

.PARAMETER Branch
The branch name to associate with the federated credential. Defaults to 'main'.

.EXAMPLE
Set-FederatedIdentity -ManagedIdentityName "uami-hr-cicd-automation" -GitHubOrganization "myorg" -GitHubRepository "myrepo"

Creates a federated credential using the managed identity name, linking it to the main branch of the myorg/myrepo GitHub repository.

.EXAMPLE
Set-FederatedIdentity -Id "/subscriptions/12345678-1234-1234-1234-123456789012/resourcegroups/myRG/providers/Microsoft.ManagedIdentity/userAssignedIdentities/myIdentity" -GitHubOrganization "myorg" -GitHubRepository "myrepo"

Creates a federated credential using the full resource ID.

.EXAMPLE
Set-FederatedIdentity -ManagedIdentityName "myIdentity" -Name "dev-credential" -GitHubOrganization "myorg" -GitHubRepository "myrepo" -Branch "development"

Creates a federated credential named "dev-credential" linking to the development branch.

.EXAMPLE
Get-ManagedIdentity -Name "myIdentity" | Set-FederatedIdentity -GitHubOrganization "myorg" -GitHubRepository "myrepo"

Pipes a managed identity to create a federated credential.

.NOTES
Requires appropriate Azure RBAC permissions to manage managed identities.
The function uses Azure REST API version 2023-01-31.

.LINK
https://learn.microsoft.com/en-us/azure/active-directory/develop/workload-identity-federation-create-trust-github

.LINK
MITRE ATT&CK Tactic: TA0003 - Persistence
https://attack.mitre.org/tactics/TA0003/

.LINK
MITRE ATT&CK Technique: T1098.001 - Account Manipulation: Additional Cloud Credentials
https://attack.mitre.org/techniques/T1098/001/
#>
}