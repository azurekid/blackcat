function Set-FederatedIdentity {
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "GitHub")]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias('resource-id')]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceIdCompleter(
            "Microsoft.ManagedIdentity/userAssignedIdentities"
        )][string]$Id,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
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

        [Parameter(Mandatory = $true, ParameterSetName = "GitHub")]
        [Alias('github-organization')]
        [string]$GitHubOrganization,

        [Parameter(Mandatory = $true, ParameterSetName = "GitHub")]
        [Alias('github-repository')]
        [string]$GitHubRepository,

        [Parameter(Mandatory = $false, ParameterSetName = "GitHub")]
        [Alias('branch-name')]
        [string]$Branch = 'main',

        [Parameter(Mandatory = $true, ParameterSetName = "Custom")]
        [Alias('issuer-url')]
        [string]$Issuer,

        [Parameter(Mandatory = $true, ParameterSetName = "Custom")]
        [string]$Subject,

        [Parameter(Mandatory = $false, ParameterSetName = "Custom")]
        [Parameter(Mandatory = $false, ParameterSetName = "GitHub")]
        [string[]]$Audiences = @("api://AzureADTokenExchange"),

        [Parameter(Mandatory = $false, ParameterSetName = "Remove")]
        [switch]$Remove,

        [Parameter(Mandatory = $false, ParameterSetName = "Get")]
        [switch]$Get
    )

    begin {
        [void] $ResourceGroupName
        Write-Verbose " Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {
        # Resolve managed identity name to resource ID if needed
        if ($ManagedIdentityName -and -not $Id) {
            Write-Verbose "Resolving ManagedIdentity: $ManagedIdentityName"
            $uami = Get-ManagedIdentity -Name $ManagedIdentityName -OutputFormat Object
            if ($uami) {
                $Id = $uami.id
            }
            else {
                Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message "Managed identity not found: $ManagedIdentityName" -Severity 'Error'
                return
            }
        }

        if (-not $Id) {
            Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message "No managed identity specified. Use -Id or -ManagedIdentityName (-Name is the FIC credential name)" -Severity 'Error'
            return
        }

        $ficUri = '{0}{1}/federatedIdentityCredentials/{2}?api-version=2023-01-31' -f $script:SessionVariables.armUri, $Id, $Name

        # Handle Get operation
        if ($Get) {
            $ficListUri = '{0}{1}/federatedIdentityCredentials?api-version=2023-01-31' -f $script:SessionVariables.armUri, $Id
            $ficListParams = @{
                Uri       = $ficListUri
                Headers   = $script:authHeader
                Method    = 'GET'
                UserAgent = $script:SessionVariables.userAgent
            }
            try {
                $result = Invoke-RestMethod @ficListParams
                return $result.value
            }
            catch {
                Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message $_.Exception.Message -Severity 'Error'
                return
            }
        }

        # Handle Remove operation
        if ($Remove) {
            if ($PSCmdlet.ShouldProcess("Federated Identity Credential: $Name", "Remove")) {
                $ficParams = @{
                    Uri       = $ficUri
                    Headers   = $script:authHeader
                    Method    = 'DELETE'
                    UserAgent = $script:SessionVariables.userAgent
                }
                try {
                    Invoke-RestMethod @ficParams | Out-Null
                    Write-Host "Removed FIC: $Name" -ForegroundColor Green
                    return $true
                }
                catch {
                    if ($_.Exception.Response.StatusCode -eq 404) {
                        Write-Warning "FIC not found: $Name"
                    }
                    else {
                        Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message $_.Exception.Message -Severity 'Error'
                    }
                    return $false
                }
            }
            return
        }

        # Build issuer and subject based on parameter set
        switch ($PSCmdlet.ParameterSetName) {
            "GitHub" {
                $issuerUrl = "https://token.actions.githubusercontent.com"
                $subjectClaim = "repo:$($GitHubOrganization)/$($GitHubRepository):ref:refs/heads/$Branch"
                $description = "GitHub Actions: $GitHubOrganization/$GitHubRepository (branch: $Branch)"
            }
            "Custom" {
                $issuerUrl = $Issuer
                $subjectClaim = $Subject
                $description = "Custom OIDC: $Issuer"
            }
        }

        # Create or update FIC
        if ($PSCmdlet.ShouldProcess($description, "Set Federated Identity Credential")) {
            try {
                $ficBody = @{
                    properties = @{
                        issuer    = $issuerUrl
                        subject   = $subjectClaim
                        audiences = $Audiences
                    }
                } | ConvertTo-Json

                $ficParams = @{
                    Headers     = $script:authHeader
                    Uri         = $ficUri
                    Method      = 'PUT'
                    ContentType = 'application/json'
                    Body        = $ficBody
                    UserAgent   = $script:SessionVariables.userAgent
                }

                $result = Invoke-RestMethod @ficParams
                Write-Host "Set FIC: $Name" -ForegroundColor Green
                return $result
            }
            catch {
                Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message $_.Exception.Message -Severity 'Error'
                return $null
            }
        }
    }
<#
.SYNOPSIS
Sets or removes federated identity credentials for managed identities.

.DESCRIPTION
Manages federated identity credentials for UAMIs to enable OIDC-based authentication. Supports:
- GitHub Actions integration (default)
- Custom OIDC providers with custom issuer/subject
- Removal of existing credentials
- Querying existing credentials

.PARAMETER Id
Full ARM resource ID of the UAMI.

.PARAMETER ManagedIdentityName
UAMI display name (resolved via Get-ManagedIdentity).

.PARAMETER ResourceGroupName
Resource group for tab-completion. Not required.

.PARAMETER Name
FIC name. Defaults to 'federatedCredential'.

.PARAMETER GitHubOrganization
GitHub organization name (for GitHub Actions).

.PARAMETER GitHubRepository
GitHub repository name (for GitHub Actions).

.PARAMETER Branch
GitHub branch name. Defaults to 'main'.

.PARAMETER Issuer
Custom OIDC issuer URL (e.g., https://myoidc.blob.core.windows.net/oidc).

.PARAMETER Subject
Custom OIDC subject claim (e.g., 'repo:org/repo:ref:refs/heads/main').

.PARAMETER Audiences
Audience claim(s). Defaults to 'api://AzureADTokenExchange'.

.PARAMETER Remove
Removes the specified FIC.

.PARAMETER Get
Lists all FICs for the UAMI.

.EXAMPLE
Set-FederatedIdentity -ManagedIdentityName "uami-cicd" -GitHubOrganization "myorg" -GitHubRepository "myrepo"

Creates GitHub Actions FIC for main branch.

.EXAMPLE
Set-FederatedIdentity -ManagedIdentityName "uami-prod" -Name "custom-fic" -Issuer "https://bc.blob.core.windows.net/oidc" -Subject "blackcat-token-exchange"

Creates custom OIDC FIC.

.EXAMPLE
Set-FederatedIdentity -ManagedIdentityName "uami-prod" -Name "old-fic" -Remove

Removes the specified FIC.

.EXAMPLE
Set-FederatedIdentity -ManagedIdentityName "uami-prod" -Get

Lists all FICs for the UAMI.

.OUTPUTS
[PSCustomObject] FIC details (when creating/updating)
[Boolean] Success status (when removing)
[Array] List of FICs (when using -Get)

.NOTES
Author: BlackCat Security Framework

Required permissions:
- Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/write
- Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/delete

.LINK
MITRE ATT&CK Tactic: TA0003 - Persistence
https://attack.mitre.org/tactics/TA0003/

.LINK
MITRE ATT&CK Technique: T1098.001 - Additional Cloud Credentials
https://attack.mitre.org/techniques/T1098/001/
#>
}