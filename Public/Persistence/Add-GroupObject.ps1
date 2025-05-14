
function Add-GroupObject {
    [CmdletBinding(DefaultParameterSetName = 'ObjectId')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'ObjectId')]
        [string]$GroupObjectId,

        [Parameter(Mandatory = $true, ParameterSetName = 'Name')]
        [string]$GroupName,

        [Parameter(Mandatory = $false)]
        [string]$ObjectId,

        [Parameter(Mandatory = $false)]
        [string]$UserPrincipalName,

        [Parameter(Mandatory = $false)]
        [string]$ServicePrincipalName,

        [Parameter(Mandatory = $false)]
        [string]$ServicePrincipalId,

        [Parameter(Mandatory = $false)]
        [string]$ApplicationId,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Owner', 'Member')]
        [string]$ObjectType = 'Owner'
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }
    process {
        try {
            # Resolve group ObjectId if Name is provided
            if ($PSCmdlet.ParameterSetName -eq 'Name') {
                $group = Invoke-MsGraph -relativeUrl "groups?`$filter=startswith(displayName,'$GroupName')" | Select-Object -First 1
                if (-not $group) {
                    throw "No group found with display name starting with '$GroupName'."
                }
                $GroupObjectId = $group.id
            }

            # Resolve ObjectId if not provided
            if (-not $ObjectId) {
                switch ($true) {
                    { $UserPrincipalName } {
                        $user = Invoke-MsGraph -relativeUrl "users?`$filter=userPrincipalName eq '$UserPrincipalName'" | Select-Object -First 1
                        if (-not $user) { throw "No user found with userPrincipalName '$UserPrincipalName'." }
                        $ObjectId = $user.id
                        break
                    }
                    { $ServicePrincipalId } {
                        $sp = Invoke-MsGraph -relativeUrl "servicePrincipals/$ServicePrincipalId"
                        if (-not $sp) { throw "No service principal found with id '$ServicePrincipalId'." }
                        $ObjectId = $sp.id
                        break
                    }
                    { $ServicePrincipalName } {
                        $sp = Invoke-MsGraph -relativeUrl "servicePrincipals?`$filter=displayName eq '$ServicePrincipalName'" | Select-Object -First 1
                        if (-not $sp) { throw "No service principal found with displayName '$ServicePrincipalName'." }
                        $ObjectId = $sp.id
                        break
                    }
                    { $ApplicationId } {
                        $sp = Invoke-MsGraph -relativeUrl "servicePrincipals?`$filter=appId eq '$ApplicationId'" | Select-Object -First 1
                        if (-not $sp) { throw "No service principal found with applicationId '$ApplicationId'." }
                        $ObjectId = $sp.id
                        break
                    }
                    default {
                        throw "You must provide ObjectId, UserPrincipalName, ServicePrincipalId, ServicePrincipalName, or ApplicationId."
                    }
                }
            }

            # Prepare the request body
            $body = @{
                "@odata.id" = "https://graph.microsoft.com/beta/directoryObjects/$ObjectId"
            } | ConvertTo-Json

            # Set endpoint and check for existing membership/ownership
            if ($ObjectType -eq 'Owner') {
                $url = "https://graph.microsoft.com/beta/groups/$GroupObjectId/owners/`$ref"
                $existing = Invoke-MsGraph -relativeUrl "groups/$GroupObjectId/owners"
            } else {
                $url = "https://graph.microsoft.com/beta/groups/$GroupObjectId/members/`$ref"
                $existing = Invoke-MsGraph -relativeUrl "groups/$GroupObjectId/members"
            }

            if ($existing | Where-Object { $_.id -eq $ObjectId }) {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Identity is already $ObjectType of the group."
                return
            }

            $requestParameters = @{
                Uri         = $url
                Headers     = $script:graphHeader
                Method      = 'POST'
                Body        = $body
                ContentType = 'application/json'
                ErrorAction = 'SilentlyContinue'
            }

            Invoke-RestMethod @requestParameters

            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "$ObjectType with $ObjectId added to group with id $GroupObjectId." -Severity Information
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $_.Exception.Message -Severity 'Error'
        }
    }
<#
.SYNOPSIS
    Adds an object (user, service principal, or application) as a member or owner to an Azure AD group.

.DESCRIPTION
    The Add-GroupObject function adds a specified object (user, service principal, or application) to an Azure AD group as either a member or an owner.
    The group can be specified by ObjectId or by Name. The object to add can be specified by ObjectId, UserPrincipalName, ServicePrincipalId, ServicePrincipalName, or ApplicationId.
    The function checks for existing membership or ownership before attempting to add the object.

.PARAMETER GroupObjectId
    The ObjectId of the Azure AD group. Mandatory if using the 'ObjectId' parameter set.

.PARAMETER GroupName
    The display name of the Azure AD group. Mandatory if using the 'Name' parameter set.

.PARAMETER ObjectId
    The ObjectId of the object (user, service principal, or application) to add to the group.

.PARAMETER UserPrincipalName
    The UserPrincipalName of the user to add to the group.

.PARAMETER ServicePrincipalName
    The display name of the service principal to add to the group.

.PARAMETER ServicePrincipalId
    The ObjectId of the service principal to add to the group.

.PARAMETER ApplicationId
    The ApplicationId of the service principal to add to the group.

.PARAMETER ObjectType
    Specifies whether to add the object as an 'Owner' or 'Member' of the group. Default is 'Owner'.

.EXAMPLE
    Add-GroupObject -GroupObjectId "12345678-90ab-cdef-1234-567890abcdef" -UserPrincipalName "user@domain.com" -ObjectType "Member"

    Adds the user with the specified UserPrincipalName as a member to the specified group.

.EXAMPLE
    Add-GroupObject -GroupName "MyGroup" -ServicePrincipalId "abcdef12-3456-7890-abcd-ef1234567890" -ObjectType "Owner"

    Adds the service principal as an owner to the group with a display name starting with "MyGroup".

.NOTES
    Requires appropriate permissions to manage group memberships and ownerships in Azure AD.
    Uses Microsoft Graph API via custom helper functions (Invoke-MsGraph, Write-Message, etc.).

#>
}
