# Import the necessary namespace
using namespace System.Management.Automation

# used for auto-generating the valid values for the AppRoleName parameter
class appRoleNames : IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        return ($script:SessionVariables.appRoleIds.Permission)
    }
}

function Set-ManagedIdentityPermissions {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [Alias('service-principal-id')]
        [string]$servicePrincipalId,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $false)]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [Alias('resource-id')]
        [string]$resourceId,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [Alias('app-role-id')]
        [string]$appRoleId,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet( [appRoleNames] )]
        [Alias('app-role-name')]
        [string]$appRoleName
    )

    begin {
        # Sets the authentication header to the Microsoft Graph API
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
    }

    process {

        try {

            if (-not $appRoleId) {
                $appRoleId = (Get-AppRolePermissions -appRoleName $appRoleName).appRoleId
            }

            Write-Verbose "Get Service Principals App Role Assignments"
            $uri = "$($sessionVariables.graphUri)/servicePrincipals/$servicePrincipalId/appRoleAssignments"

            $requestParam = @{
                Headers = $script:graphHeader
                Uri     = $uri
                Method  = 'POST'
                ContentType = 'application/json'
                Body    = @{
                    principalId = $servicePrincipalId
                    resourceId  = $resourceId
                    appRoleId   = $appRoleId
                } | ConvertTo-Json
            }

            try {
                Write-Verbose "Assigning App Role to Service Principal"
                Invoke-RestMethod @requestParam
            } catch {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message ($_.ErrorDetails.Message | ConvertFrom-Json).Error.Message -Severity 'Information'
            }
        } catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
<#
.SYNOPSIS
Assigns an Azure Managed Identity to a specified application role.

.DESCRIPTION
The Set-ManagedIdentityPermissions function assigns an Azure Managed Identity (service principal) to a specified application role.
It uses the Microsoft Graph API to perform the assignment.

.PARAMETER servicePrincipalId
The unique identifier (GUID) of the service principal to which the application role will be assigned.
This parameter is mandatory and must match the GUID pattern.

.PARAMETER resourceId
The unique identifier (GUID) of the resource to which the service principal is being assigned.
This parameter is mandatory and must match the GUID pattern.

.PARAMETER appRoleId
The unique identifier (GUID) of the application role to be assigned.
This parameter is optional and must match the GUID pattern if provided.

.PARAMETER appRoleName
The name of the application role to be assigned.
This parameter is mandatory and must match one of the valid application role names.

.EXAMPLE
Set-ManagedIdentityPermissions -servicePrincipalId "12345678-1234-1234-1234-1234567890ab" -resourceId "87654321-4321-4321-4321-abcdef123456" -appRoleName "User.Read.All"

This example assigns the service principal with ID "12345678-1234-1234-1234-1234567890ab" to the application role named 'User.Read' for the resource with ID "87654321-4321-4321-4321-abcdef123456".

.NOTES
This function requires the Microsoft Graph API and appropriate permissions to assign roles to service principals.
#>
}