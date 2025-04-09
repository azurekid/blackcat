function Get-EntraInformation {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'ObjectId')]
        [string]$ObjectId,

        [Parameter(Mandatory = $true, ParameterSetName = 'Name')]
        [string]$Name,

        [Parameter(ParameterSetName = 'ObjectId')]
        [Parameter(ParameterSetName = 'Name')]
        [switch]$Group
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
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
            }

            foreach ($item in $response) {
                if ($isGroup) {
                    # Get group members
                    $members = Invoke-MsGraph -relativeUrl "groups/$($item.id)/members"

                    # Get group roles and permissions
                    $roles = Invoke-MsGraph -relativeUrl "groups/$($item.id)/transitiveMemberOf/microsoft.graph.directoryRole"

                    # Create custom object with group information
                    [PSCustomObject]@{
                        DisplayName      = $item.displayName
                        ObjectId        = $item.id
                        Description     = $item.description
                        Roles           = $roles.displayName
                        Members         = $members.displayName
                        GroupType       = $item.groupTypes
                        MailEnabled     = $item.mailEnabled
                        SecurityEnabled = $item.securityEnabled
                    }
                } else {
                    # Rest of the code for users remains the same
                    # Get group memberships
                    $groups = Invoke-MsGraph -relativeUrl "users/$($item.id)/memberOf"

                    # Get directory roles
                    $roles = Invoke-MsGraph -relativeUrl "users/$($item.id)/transitiveMemberOf/microsoft.graph.directoryRole"

                    # Create custom object with user information
                    [PSCustomObject]@{
                        UserPrincipalName = $item.userPrincipalName
                        DisplayName       = $item.displayName
                        ObjectId          = $item.id
                        GroupMemberships  = $groups.displayName
                        Roles             = $roles.displayName
                        Mail              = $item.mail
                        JobTitle          = $item.jobTitle
                        Department        = $item.department
                    }
                }
            }
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