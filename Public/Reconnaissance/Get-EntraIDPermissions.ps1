function Get-EntraIDPermissions {
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'ObjectId')]
        [string]$ObjectId,

        [Parameter(Mandatory = $true, ParameterSetName = 'Name')]
        [string]$Name,

        [Parameter(Mandatory = $true, ParameterSetName = 'UserPrincipalName')]
        [ValidatePattern('^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$', ErrorMessage = "The value '{1}' is not a valid UPN format")]
        [string]$UserPrincipalName,

        [Parameter(Mandatory = $false)]
        [switch]$ShowActions,

        [Parameter(ParameterSetName = 'ObjectId')]
        [Parameter(ParameterSetName = 'Name')]
        [Parameter(ParameterSetName = 'UserPrincipalName')]
        [switch]$Group
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'

        $permissionsOverview = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
    }

    process {
        try {
            # Construct query based on parameter set
            switch ($PSCmdlet.ParameterSetName) {
                'ObjectId' {
                    if ($Group) {
                        $response = Get-EntraInformation -ObjectId $ObjectId -Group
                    }
                    else {
                        $response = Get-EntraInformation -ObjectId $ObjectId
                    }
                }
                'Name' {
                    if ($Group) {
                        $response = Get-EntraInformation -Name $Name -Group
                    }
                    else {
                        $response = Get-EntraInformation -Name $ObjectId
                    }
                }
                'UserPrincipalName' {
                    if ($Group) {
                        Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "The -Group parameter cannot be used with -UserPrincipalName. parameter." -Severity 'Error'
                    }
                    $response = Get-EntraInformation -UserPrincipalName $UserPrincipalName
                }
            }

            if (-not $response) {
                Write-Error "$($PSCmdlet.ParameterSetName) not found."
                return
            }

            $roleDetails = Invoke-MsGraph -relativeUrl 'roleManagement/directory/roleDefinitions'

            $response.Roles | ForEach-Object {
                $roleName = $_
                Write-Host "Processing role: $roleName" -ForegroundColor Yellow
                $roleDetail = $roleDetails | Where-Object { $_.displayName -eq $roleName }
                # Write-Host "Role ID Details: $($roleDetail | ConvertTo-Json -Depth 3)" -ForegroundColor Green
                if ($roleDetail) {
                    $currentItem = [PSCustomObject]@{
                        RoleName     = $roleDetail.displayName
                        Description  = $roleDetail.description
                        Actions      = $roleDetail.rolePermissions.allowedResourceActions | Where-Object { $_ -notmatch 'read' }
                        IsPrivileged = $roleDetail.isPrivileged
                    }
                    ($permissionsOverview).Add($currentItem)
                }
            }

            if ($permissionsOverview.Count -eq 0) {
                Write-Error "No permissions found for the user."
                return
            }

            if ($ShowActions) {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Actions this user can perform:"
                return $permissionsOverview.Actions | Sort-Object -Unique
            } else {
                return $permissionsOverview
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
<#
.SYNOPSIS
    Retrieves and lists all permissions a user or group has in Microsoft Entra ID.

.DESCRIPTION
    The Get-EntraIDPermissions function queries Microsoft Graph API to retrieve all roles and associated permissions
    that a specified user or group has in Microsoft Entra ID (formerly Azure AD). It provides detailed information
    about each role including description, associated actions, and whether the role is privileged.

    The function can identify targets using Object ID, Name, or User Principal Name, and can optionally display
    only the actions a user can perform rather than full role details.

.PARAMETER ObjectId
    The unique Object ID of the user or group in Entra ID.

.PARAMETER Name
    The display name of the user or group in Entra ID.

.PARAMETER UserPrincipalName
    The User Principal Name (UPN) of the user in the format username@domain.com.

.PARAMETER ShowActions
    When specified, returns only the list of actions the user can perform instead of full role details.

.PARAMETER Group
    Indicates that the query should target a group rather than a user. Cannot be used with UserPrincipalName.

.EXAMPLE
    Get-EntraIDPermissions -UserPrincipalName "john.doe@contoso.com"

    Retrieves all role permissions for the specified user.

.EXAMPLE
    Get-EntraIDPermissions -ObjectId "12345678-1234-1234-1234-123456789012" -Group

    Retrieves all role permissions for the specified group.

.EXAMPLE
    Get-EntraIDPermissions -Name "IT Administrators" -Group -ShowActions

    Returns only the actions that members of the "IT Administrators" group can perform.

.OUTPUTS
    System.Management.Automation.PSCustomObject[]
    Returns collection of custom objects with role details including RoleName, Description, Actions, and IsPrivileged.
    When -ShowActions is specified, returns a string array of unique actions.

.NOTES
    Requires appropriate Microsoft Graph API permissions to query user/group roles and permissions.
    The function filters out read permissions by default when showing actions.
#>
}