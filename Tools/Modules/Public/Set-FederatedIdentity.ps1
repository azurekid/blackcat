function Set-FederatedIdentity {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$GitHubOrganization,

        [Parameter(Mandatory = $true)]
        [string]$GitHubRepository,

        [Parameter(Mandatory = $false)]
        [string]$Branch = 'main'
    )

    $baseUri = 'https://management.azure.com'
    $uri = '{0}{1}/federatedIdentityCredentials/{2}?api-version=2023-01-31' -f $baseUri, $Id, $Name

    $body = @{
        properties = @{
            issuer = "https://token.actions.githubusercontent.com"
            subject = "repo:$($GitHubOrganization)/$($GitHubRepository):ref:refs/heads/$Branch"
            audiences = @("api://AzureADTokenExchange")
        }
    } | ConvertTo-Json

    Invoke-RestMethod -Uri $uri -Method PUT -Body $body @aadRequestHeader -ContentType 'application/json'
}
