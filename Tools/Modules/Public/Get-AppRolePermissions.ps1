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
        [ValidateSet( [appRoleNames] )]
        [string]$appRoleName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [string]$appRoleId,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet( 'Application', 'Delegated' )]
        [string]$Type = 'Application'

    )

    begin {
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

            # $currentItem = [PSCustomObject]@{
            #     DisplayName = $object.Permission
            #     Type        = $object.Type
            #     appRoleId   = $object.Id
            # }
            return $object
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
}