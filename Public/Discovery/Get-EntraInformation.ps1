function Get-EntraInformation {
    [cmdletbinding(DefaultParameterSetName = 'Other')]
    param (
        [Parameter(Mandatory = $false, ParameterSetName = 'ObjectId')]
        [string]$ObjectId,

        [Parameter(Mandatory = $false, ParameterSetName = 'Name')]
        [string]$Name,

        [Parameter(Mandatory = $false, ParameterSetName = 'UserPrincipalName')]
        [ValidatePattern('^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$', ErrorMessage = "The value '{1}' is not a valid UPN format")]
        [string]$UserPrincipalName,

        [Parameter(ParameterSetName = 'ObjectId')]
        [Parameter(ParameterSetName = 'Name')]
        [Parameter(ParameterSetName = 'UserPrincipalName')]
        [Parameter(ParameterSetName = 'Other')]
        [switch]$Group,

        [Parameter(Mandatory = $false, ParameterSetName = 'Other')]
        [switch]$CurrentUser
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
                'Other' {
                    $isGroup = $false
                    $response = $null

                    if ($CurrentUser) {
                        # Detect service principal context first (GUID account or token AppId), then fall back to /me for users
                        $spAppId = $null

                        # Try from current access token
                        try {
                            if ($script:SessionVariables -and $script:SessionVariables.accessToken) {
                                $rawToken = $script:SessionVariables.accessToken
                                if ($rawToken -and ($rawToken -split '\.').Count -ge 2) {
                                    $tokenInfo = ConvertFrom-JWT -Base64JWT $rawToken
                                    if ($tokenInfo.AppId) { $spAppId = $tokenInfo.AppId }
                                }
                            }
                        }
                        catch {
                            Write-Verbose "Could not parse access token for AppId: $($_.Exception.Message)"
                        }

                        # Try from Az context account Id (GUID implies SPN)
                        if (-not $spAppId) {
                            try {
                                $ctx = Get-AzContext -ErrorAction SilentlyContinue
                                if ($ctx -and $ctx.Account -and $ctx.Account.Id -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
                                    $spAppId = $ctx.Account.Id
                                }
                            }
                            catch {
                                Write-Verbose "Az context lookup failed: $($_.Exception.Message)"
                            }
                        }

                        if ($spAppId) {
                            Write-Verbose "Current context appears to be a service principal (AppId: $spAppId). Fetching permissions."
                            return Get-ServicePrincipalsPermission -AppId $spAppId
                        }

                        # User context fallback
                        try {
                            $response = Invoke-MsGraph -relativeUrl "me" -NoBatch
                        }
                        catch {
                            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "'/me' request failed and no service principal AppId could be determined for -CurrentUser" -Severity 'Error'
                            return
                        }
                    }
                    else {
                        $response = Invoke-MsGraph -relativeUrl "me" -NoBatch
                    }
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
                    # Get group memberships and filter out null/empty display names
                    $groups = Invoke-MsGraph -relativeUrl "users/$($item.id)/memberOf"
                    $groupDisplayNames = @()
                    foreach ($g in $groups) { if ($g.displayName) { $groupDisplayNames += $g.displayName } }

                    # Get directory roles and filter out null/empty display names
                    $roles = Invoke-MsGraph -relativeUrl "users/$($item.id)/transitiveMemberOf/microsoft.graph.directoryRole"
                    $roleDisplayNames = @()
                    foreach ($r in $roles) { if ($r.displayName) { $roleDisplayNames += $r.displayName } }

                    $currentItem = [PSCustomObject]@{
                        DisplayName       = $item.displayName
                        ObjectId          = $item.id
                        UserPrincipalName = $item.userPrincipalName
                        JobTitle          = $item.jobTitle
                        Department        = $item.department
                        GroupMemberships  = $groupDisplayNames
                        Roles             = $roleDisplayNames
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
Queries Microsoft Graph API for detailed info about Azure AD users, groups, or memberships.

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

.LINK
MITRE ATT&CK Tactic: TA0007 - Discovery
https://attack.mitre.org/tactics/TA0007/

.LINK
MITRE ATT&CK Technique: T1087.004 - Account Discovery: Cloud Account
https://attack.mitre.org/techniques/T1087/004/

#>
}