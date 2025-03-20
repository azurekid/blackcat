function Get-FederatedApplications {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$', ErrorMessage = "It does not match expected pattern '{1}'")]
        [string]$Id
    )

    begin {
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
    }

    process {

        try {
                Write-Verbose "Get Federated Identity Credentials for Application $($id)"
                Invoke-MsGraph -relativeUrl "applications/$Id/federatedIdentityCredentials"
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
    <#
    .SYNOPSIS
    Retrieves federated identity credentials for a specified Microsoft Entra application.

    .DESCRIPTION
    The Get-MsFederatedApplications function retrieves all federated identity credentials associated with a Microsoft Entra application identified by its application ID (GUID).

    .PARAMETER Id
    The application ID (GUID) of the Microsoft Entra application. This parameter is mandatory and must match the pattern of a valid GUID (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx).

    .EXAMPLE
    Get-MsFederatedApplications -Id "12345678-1234-1234-1234-123456789012"
    Retrieves all federated identity credentials for the specified application.

    .EXAMPLE
    Invoke-MsGraph -relativeUrl "applications" | Get-MsFederatedApplications
    Retrieves all federated identity credentials for all application.

    .EXAMPLE
    Get-AzAdApplication -All $true | Get-MsFederatedApplications
    Retrieves all federated identity credentials for all applications.

    .LINK
    https://learn.microsoft.com/en-us/graph/api/application-list-federatedidentitycredentials
    #>
#>
}