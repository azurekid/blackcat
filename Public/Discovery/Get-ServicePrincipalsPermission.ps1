function Get-ServicePrincipalsPermission {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [string]$servicePrincipalId
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
    }

    process {
        try {

            Write-Verbose "Get Service Principals App Role Assignments"
            $uri = "$($sessionVariables.graphUri)/servicePrincipals/$servicePrincipalId/appRoleAssignments"

            $requestParam = @{
                Headers = $script:graphHeader
                Uri     = $uri
                Method  = 'GET'
            }

            return (Invoke-RestMethod @requestParam).value

        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
<#
.SYNOPSIS
Retrieves the app role assignments for a specified service principal from Microsoft Graph.

.DESCRIPTION
The Get-ServicePrincipalsPermission function retrieves the app role assignments for a specified service principal from Microsoft Graph. It requires the service principal ID as a mandatory parameter.

.PARAMETER servicePrincipalId
The unique identifier (GUID) of the service principal. This parameter is mandatory and must match the expected GUID pattern.

.EXAMPLE
PS> Get-ServicePrincipalsPermission -servicePrincipalId "12345678-1234-1234-1234-1234567890ab"
This example retrieves the app role assignments for the specified service principal.

.NOTES
The function uses the Invoke-RestMethod cmdlet to send a GET request to the Microsoft Graph API and returns the app role assignments for the specified service principal.

#>
}