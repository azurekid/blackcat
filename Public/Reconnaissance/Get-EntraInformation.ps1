function Get-EntraInformation {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'ObjectId')]
        [string]$ObjectId,

        [Parameter(Mandatory = $true, ParameterSetName = 'Name')]
        [string]$Name,

        [Parameter(Mandatory = $true, ParameterSetName = 'UserPrincipalName')]
        [ValidatePattern('^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$', ErrorMessage = "The value '{1}' is not a valid UPN format")]
        [string]$UserPrincipalName,

        [Parameter(ParameterSetName = 'ObjectId')]
        [Parameter(ParameterSetName = 'Name')]
        [Parameter(ParameterSetName = 'UserPrincipalName')]
        [switch]$Group
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'

        $userInfo = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
    }

    process {
        try {
            # Construct query based on parameter set
            switch ($PSCmdlet.ParameterSetName) {
                'ObjectId' {
                    if ($Group) {
                        $response = Invoke-MsGraph -relativeUrl "groups/$ObjectId" -NoBatch
                        $isGroup = $true
                    } else {
                        $response = Invoke-MsGraph -relativeUrl "users/$ObjectId" -NoBatch
                        $isGroup = $false
                    }
                }
                'Name' {
                    if ($Group) {
                        $response = Invoke-MsGraph -relativeUrl "groups?`$filter=startswith(displayName,'$Name')"
                        $isGroup = $true
                    } else {
                        $response = Invoke-MsGraph -relativeUrl "users?`$filter=startswith(displayName,'$Name') or startswith(userPrincipalName,'$Name')"
                        $isGroup = $false
                    }
                }
                'UserPrincipalName' {
                    if ($Group) {
                        Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "The -Group parameter cannot be used with -UserPrincipalName. parameter." -Severity 'Error'
                    }
                    $response = Invoke-MsGraph -relativeUrl "users?`$filter=userPrincipalName eq '$UserPrincipalName'"
                    $isGroup = $false
                }
            }
            $roleDetails = Invoke-MsGraph -relativeUrl 'roleManagement/directory/roleDefinitions'

            # foreach ($item in $response) {
                $response | ForEach-Object {
                    $item = $_

                if ($isGroup) {
                    # Get group members
                    $members = Invoke-MsGraph -relativeUrl "groups/$($item.id)/members"

                    # Get group roles and permissions
                    $roles = Invoke-MsGraph -relativeUrl "groups/$($item.id)/transitiveMemberOf/microsoft.graph.directoryRole"

                    # Create custom object with group information
                    $currentItem = [PSCustomObject]@{
                        DisplayName     = $item.displayName
                        ObjectId        = $item.id
                        Description     = $item.description
                        Roles           = $roles.displayName
                        Members         = $members.displayName
                        GroupType       = $item.groupTypes
                        MailEnabled     = $item.mailEnabled
                        SecurityEnabled = $item.securityEnabled
                        IsPrivileged    = $False
                    }

                } else {
                    # Get group memberships
                    $groups = Invoke-MsGraph -relativeUrl "users/$($item.id)/memberOf"

                    # Get directory roles
                    $roles = Invoke-MsGraph -relativeUrl "users/$($item.id)/transitiveMemberOf/microsoft.graph.directoryRole"

                    $currentItem = [PSCustomObject]@{
                        DisplayName       = $item.displayName
                        ObjectId          = $item.id
                        UserPrincipalName = $item.userPrincipalName
                        JobTitle          = $item.jobTitle
                        Department        = $item.department
                        GroupMemberships  = $groups.displayName
                        Roles             = $roles.displayName
                        Mail              = $item.mail
                        AccountEnabled    = $item.accountEnabled
                        IsPrivileged      = $False
                    }

                }
                foreach ($role in $roles) {
                    $privileged = ($roleDetails | Where-Object { $_.displayName -eq $role.displayName }).IsPrivileged

                    if ($privileged -eq $true) {
                        $currentItem.IsPrivileged = $true

                    }
                }

                ($userInfo).Add($currentItem)
            }
            return $userInfo
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
<#
.SYNOPSIS
Retrieves information about Azure AD users or groups using Microsoft Graph API.

.DESCRIPTION
The Get-EntraInformation function queries Microsoft Graph API to retrieve detailed information about Azure AD users or groups.
It supports querying by ObjectId or Name and can return additional details such as group memberships, roles, and permissions.

.PARAMETER ObjectId
Specifies the ObjectId of the user or group to retrieve information for. This parameter is mandatory when using the 'ObjectId' parameter set.

.PARAMETER Name
Specifies the display name or userPrincipalName of the user or group to retrieve information for. This parameter is mandatory when using the 'Name' parameter set.

.PARAMETER Group
Indicates that the query is for a group. If not specified, the query is assumed to be for a user.

.EXAMPLE
Get-EntraInformation -ObjectId "12345-abcde-67890" -Group
Retrieves information about the group with the specified ObjectId.

.EXAMPLE
Get-EntraInformation -Name "John Doe"
Retrieves information about the user with the specified display name or userPrincipalName.

.EXAMPLE
Get-EntraInformation -Name "Marketing" -Group
Retrieves information about groups with display names starting with "Marketing".

.NOTES
- This function requires the Invoke-MsGraph cmdlet to interact with Microsoft Graph API.
- Ensure that the required permissions are granted to the application or user executing this function.

.OUTPUTS
[PSCustomObject]
Returns a custom object containing detailed information about the user or group, including roles, memberships, and other attributes.

#>
}