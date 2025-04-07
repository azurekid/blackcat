using namespace System.Management.Automation

# used for auto-generating the valid values for the AppRoleName parameter
class appRoleNames : IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        return ($script:SessionVariables.appRoleIds.Permission)
    }
}

function Get-AppRolePermissions {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [string]$appRoleId,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet( [appRoleNames] )]
        [string]$appRoleName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet( 'Application', 'Delegated' )]
        [string]$Type = 'Application'

    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {

        try {

            Write-Verbose "Get App Permissions"

            if ($appRoleName) {
                $object = ($script:SessionVariables.appRoleIds | Where-Object Permission -eq $appRoleName | Where-Object Type -eq $Type)
            } else {
                $object = ($script:SessionVariables.appRoleIds | Where-Object appRoleId -eq $appRoleId)
            }

            return $object
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
<#
.SYNOPSIS
Retrieves the permissions for a specified Microsoft App Role.

.DESCRIPTION
The Get-MsAppRolePermissions function retrieves the permissions associated with a specified Microsoft App Role. 
It can filter permissions based on the App Role ID or App Role Name and Type.

.PARAMETER appRoleId
The unique identifier (GUID) of the App Role. Must match the expected GUID pattern.

.PARAMETER appRoleName
The name of the App Role. Valid values are auto-generated from the session variables.

.PARAMETER Type
The type of the App Role. Valid values are 'Application' and 'Delegated'. Default is 'Application'.

.EXAMPLE
Get-MsAppRolePermissions -appRoleId "12345678-1234-1234-1234-1234567890ab"

.EXAMPLE
Get-MsAppRolePermissions -appRoleName "User.Read" -Type "Delegated"

.EXAMPLE
Get-MsServicePrincipalsPermissions | Get-MsAppRolePermissions

.NOTES
This function uses session variables to retrieve the App Role permissions. Ensure that the session variables are properly initialized before calling this function.

#>
}