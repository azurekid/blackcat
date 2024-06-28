function Set-FederatedIdentity {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$Name,

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
                Headers     = $authHeader
                Uri         = $uri
                Method      = 'PUT'
                ContentType = 'application/json'
                Body        = $body
            }

            (Invoke-RestMethod @requestParam)
        }
        catch {
            Write-Host -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) #-Severity 'Error'
        }
    }
}
