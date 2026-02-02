# Find-EntraPermissionHolder.ps1
# Part of BlackCat Security Module - Entra ID Permission Discovery Functions
# Optimized for performance and thorough permission analysis

function Test-EntraPermissionMatch {
    <#
    .SYNOPSIS
        Tests if a permission pattern matches a target permission.

    .DESCRIPTION
        Helper function that determines whether a permission pattern (which may include wildcards)
        matches a specific permission target. Supports various wildcard patterns and permission hierarchies.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$PermissionPattern,

        [Parameter(Mandatory = $true)]
        [string]$TargetPermission
    )

    # Fast path: Exact match chec
    if ($PermissionPattern -eq $TargetPermission) {
        Write-Verbose "Permission match (exact): $PermissionPattern = $TargetPermission"
        return $true
    }

    # Handle global wildcards (applies to all Microsoft Directory permissions)
    if ($PermissionPattern -eq 'microsoft.directory/*' -or $PermissionPattern -eq '*') {
        if ($TargetPermission.StartsWith('microsoft.directory/')) {
            Write-Verbose "Permission match (global wildcard): $PermissionPattern contains $TargetPermission"
            return $true
        }
    }
    
    # Handle full wildcard pattern (*)
    if ($PermissionPattern -eq "*") {
        Write-Verbose "Permission match (global wildcard): $PermissionPattern matches all permissions"
        return $true
    }
    
    # Handle trailing wildcards (e.g., microsoft.directory/users/*)
    if ($PermissionPattern.EndsWith('/*')) {
        $parentPath = $PermissionPattern.TrimEnd('/*')
        if ($TargetPermission.StartsWith($parentPath + '/')) {
            Write-Verbose "Permission match (trailing wildcard): $PermissionPattern contains $TargetPermission"
            return $true
        }
    }

    # Handle embedded wildcards (e.g., microsoft.directory/*/create)
    if ($PermissionPattern.Contains('/*')) {
        $patternParts = $PermissionPattern.Split('/')
        $targetParts = $TargetPermission.Split('/')

        # Quick length check for optimization
        if ($patternParts.Count -ne $targetParts.Count) {
            return $false
        }

        # Check each segment with optimized loop
        $segmentMatches = $true
        for ($i = 0; $i -lt $patternParts.Count; $i++) {
            if ($patternParts[$i] -ne '*' -and $patternParts[$i] -ne $targetParts[$i]) {
                $segmentMatches = $false
                break
            }
        }

        if ($segmentMatches) {
            Write-Verbose "Permission match (embedded wildcard): $PermissionPattern matches $TargetPermission"
            return $true
        }
    }
    
    # Handle complex wildcard patterns with regex conversion
    if ($PermissionPattern.Contains("*")) {
        $regexPattern = '^' + [regex]::Escape($PermissionPattern).Replace('\*', '.*') + '$'
        if ($TargetPermission -match $regexPattern) {
            Write-Verbose "Permission match (complex wildcard): $TargetPermission matches pattern $PermissionPattern"
            return $true
        }
    }
    
    # Handle prefix relationship - if target is more specific than pattern
    if ($TargetPermission.StartsWith("$PermissionPattern/")) {
        Write-Verbose "Permission match (prefix): $PermissionPattern is a prefix of $TargetPermission"
        return $true
    }
    
    # Handle prefix relationship - if pattern is more specific than target
    if ($PermissionPattern.StartsWith("$TargetPermission/")) {
        Write-Verbose "Permission match (prefix): $TargetPermission is a prefix of $PermissionPattern"
        return $true
    }

    # Handle special permission relationships (permission hierarchy)
    if ($PermissionPattern -eq 'microsoft.directory/applications/allProperties/allTasks') {
        if ($TargetPermission -eq 'microsoft.directory/applications/allProperties/read' -or
            $TargetPermission -eq 'microsoft.directory/applications/allProperties/update') {
            Write-Verbose "Permission match (hierarchy): $PermissionPattern contains $TargetPermission"
            return $true
        }
    }

    # The reverse relationship
    if ($TargetPermission -eq 'microsoft.directory/applications/allProperties/allTasks') {
        if ($PermissionPattern -eq 'microsoft.directory/applications/allProperties/read' -or
            $PermissionPattern -eq 'microsoft.directory/applications/allProperties/update') {
            Write-Verbose "Permission match (hierarchy): $TargetPermission contains $PermissionPattern"
            return $true
        }
    }
    
    # Handle action hierarchy (similar to Azure RBAC)
    # In Entra ID, permissions often follow similar hierarchy patterns as in Azure
    if ($PermissionPattern -match '^(.+)/([^/]+)$' -and $TargetPermission -match '^(.+)/([^/]+)$') {
        $patternBase = $matches[1]
        $patternAction = $matches[2].ToLower()
        
        # Reset $matches to avoid conflicts
        $null = $TargetPermission -match '^(.+)/([^/]+)$'
        $targetBase = $matches[1]
        $targetAction = $matches[2].ToLower()
        
        # Common action hierarchy in Microsoft Directory permissions
        $actionMapping = @{
            'write'   = @('read')
            'update'  = @('read') 
            'delete'  = @('read')
            'action'  = @('read')
            'manage'  = @('read', 'write', 'update', 'delete')
            'allTasks' = @('read', 'write', 'update', 'delete', 'action')
        }
        
        if ($patternBase -eq $targetBase -and 
            $actionMapping.ContainsKey($patternAction) -and 
            $actionMapping[$patternAction] -contains $targetAction) {
            Write-Verbose "Permission match (action hierarchy): $PermissionPattern implies $TargetPermission"
            return $true
        }
    }

    # No match found
    return $false
}

function Find-RolesWithPermission {
    <#
    .SYNOPSIS
        Finds roles that have a specific permission.

    .DESCRIPTION
        Identifies all Entra ID roles that contain the specified permission,
        taking into account wildcard patterns and permission hierarchies.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Permission
    )

    Write-Verbose "Getting role definitions from Microsoft Graph..."

    # Get all role definitions
    try {
        $response = Invoke-MsGraph -relativeUrl "roleManagement/directory/roleDefinitions" -NoBatch -ErrorAction Stop
        $roleDefinitions = $response.value
        Write-Verbose "Retrieved $($roleDefinitions.Count) role definitions"
    }
    catch {
        Write-Error "Failed to get role definitions: $_"
        return $null
    }

    # Global Administrator role ID (has all permissions)
    $globalAdminRoleId = '62e90394-69f5-4237-9190-012177145e10'

    # Check if this permission exists in any role first
    $permissionExists = $false
    
    # Special case: Global wildcard
    if ($Permission -eq '*') {
        Write-Verbose "Using global wildcard pattern - will match all permissions"
        $permissionExists = $true
    } else {
        foreach ($roleDef in $roleDefinitions) {
            foreach ($rolePermission in $roleDef.rolePermissions) {
                # Check exact matches first (fastest check)
                if ($rolePermission.allowedResourceActions -contains $Permission) {
                    $permissionExists = $true
                    break
                }

                # Then check patterns
                foreach ($action in $rolePermission.allowedResourceActions) {
                    if (Test-EntraPermissionMatch -PermissionPattern $action -TargetPermission $Permission) {
                        $permissionExists = $true
                        break
                    }
                    
                    # Also check the reverse case - if our search pattern matches any actual permission
                    if (Test-EntraPermissionMatch -PermissionPattern $Permission -TargetPermission $action) {
                        $permissionExists = $true
                        break
                    }
                }

                if ($permissionExists) { break }
            }

            if ($permissionExists) { break }
        }
    }

    if (-not $permissionExists) {
        Write-Warning "The permission '$Permission' does not exist in any role definition."
        return $null
    }

    # Find all roles that have this permission
    $matchingRoles = $roleDefinitions | Where-Object {
        $roleDefinition = $_

        # Special case for Global Administrator which has all valid permissions
        if (($roleDefinition.id -eq $globalAdminRoleId -or
            $roleDefinition.templateId -eq $globalAdminRoleId) -and
            $permissionExists) {
            Write-Verbose "Global Administrator role automatically matches all valid permissions"
            return $true
        }
        
        # Special handling for global wildcard pattern '*'
        if ($Permission -eq '*') {
            # Return all roles that have any permissions
            $hasPermissions = $roleDefinition.rolePermissions | 
                Where-Object { $_.allowedResourceActions -and $_.allowedResourceActions.Count -gt 0 }
            return $null -ne $hasPermissions
        }

        # Check all permissions in this role
        foreach ($rolePermission in $roleDefinition.rolePermissions) {
            foreach ($action in $rolePermission.allowedResourceActions) {
                # Check if the role's permission satisfies our search pattern
                if (Test-EntraPermissionMatch -PermissionPattern $action -TargetPermission $Permission) {
                    return $true
                }
                
                # Also check if our search pattern would match this role's permission
                if (Test-EntraPermissionMatch -PermissionPattern $Permission -TargetPermission $action) {
                    return $true
                }
            }
        }

        return $false
    }

    return $matchingRoles
}

function Resolve-GroupMembers {
    <#
    .SYNOPSIS
        Resolves members of groups, including nested members.

    .DESCRIPTION
        Resolves the members of specified groups, handling nested members
        when possible. Uses parallel processing for better performance.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Groups,

        [Parameter(Mandatory = $false)]
        [int]$ThrottleLimit = 10
    )

    $resolvedMembers = [System.Collections.Generic.Dictionary[string, object]]::new()

    # Filter out non-group principals
    $groupsToResolve = $Groups | Where-Object { $_.PrincipalType -eq 'group' }

    if ($groupsToResolve.Count -eq 0) {
        return $resolvedMembers
    }

    Write-Host "  Resolving $($groupsToResolve.Count) groups..." -ForegroundColor Cyan

    # Process each group with parallel processing (but ensure module functions are available)
    foreach ($group in $groupsToResolve) {
        $groupId = $group.PrincipalId
        
        try {
            # Try transitive members first for nested resolution
            $members = $null
            
            try {
                # Try Microsoft Graph API transitive members endpoint
                $members = Invoke-MsGraph -relativeUrl "groups/$groupId/transitiveMembers" -NoBatch -ErrorAction Stop
                $isTransitive = $true
            }
            catch {
                # Fall back to direct members if transitive fails
                $members = Invoke-MsGraph -relativeUrl "groups/$groupId/members" -NoBatch -ErrorAction Stop
                $isTransitive = $false
            }
            
            if ($members -and $members.value) {
                $groupMembers = $members.value | ForEach-Object {
                    $member = $_
                    $memberType = $member.'@odata.type' -replace "#microsoft.graph.", ""
                    
                    [PSCustomObject]@{
                        ObjectId = $member.id
                        DisplayName = $member.displayName
                        UserPrincipalName = if ($memberType -eq "user") { $member.userPrincipalName } else { $null }
                        PrincipalType = $memberType
                        AppId = if ($memberType -eq "servicePrincipal") { $member.appId } else { $null }
                        IsNested = $isTransitive
                    }
                }
                
                # Use thread-safe way to update the dictionary
                [System.Threading.Monitor]::Enter($resolvedMembers)
                try {
                    $resolvedMembers[$groupId] = $groupMembers
                }
                finally {
                    [System.Threading.Monitor]::Exit($resolvedMembers)
                }
            }
            else {
                # Empty group or error case
                [System.Threading.Monitor]::Enter($resolvedMembers)
                try {
                    $resolvedMembers[$groupId] = @()
                }
                finally {
                    [System.Threading.Monitor]::Exit($resolvedMembers)
                }
            }
        }
        catch {
            Write-Warning "Failed to resolve group $($group.PrincipalName) ($groupId): $_"
            
            # Record the error in the dictionary
            [System.Threading.Monitor]::Enter($resolvedMembers)
            try {
                $resolvedMembers[$groupId] = @(
                    [PSCustomObject]@{
                        ObjectId = $groupId
                        DisplayName = "Error: $($_.Exception.Message)"
                        PrincipalType = "Error"
                        UserPrincipalName = $null
                        AppId = $null
                    }
                )
            }
            finally {
                [System.Threading.Monitor]::Exit($resolvedMembers)
            }
        }
    }    return $resolvedMembers
}

function Find-EntraPermissionHolder {
    <#
    .SYNOPSIS
        Find Microsoft Entra ID (Azure AD) principals that have a specific permission.

    .DESCRIPTION
        The Find-EntraPermissionHolder function identifies all roles containing a specific permission
        and then returns all principals (users, groups, or service principals) assigned to those roles.

        This function leverages the existing Get-EntraRoleMember and Get-EntraIDPermissions functions
        to efficiently identify who has specific permissions in your Entra ID tenant, which is useful
        for security audits, compliance checks, and permission discovery during incident response
        or threat hunting activities.

        The function supports:
        - Finding all roles that contain a specific permission
        - Identifying all principals assigned to those roles
        - Resolving group memberships to see nested users with the permission
        - Identifying both active and eligible (PIM) role assignments
        - Output in various formats for further analysis

    .PARAMETER Permission
        The specific permission string to search for (e.g., "microsoft.directory/applications/create").
        The function supports exact permission strings as well as various wildcard patterns:
        - Trailing wildcards: "microsoft.directory/users/*" (all user permissions)
        - Embedded wildcards: "microsoft.directory/*/create" (all create permissions)
        - Global wildcards: "*" (all permissions)
        - Complex patterns: "microsoft.directory/*role*" (any permission containing "role")

    .PARAMETER IncludeEligible
        Include principals with eligible assignments (PIM) in addition to active assignments.
        Note: Requires RoleManagement.Read.Directory permission.

    .PARAMETER ResolveGroups
        When specified, resolves group memberships to include users who have the permission via group membership.
        This shows the complete permission inheritance chain and is useful for thorough security audits.

    .PARAMETER IncludeAUScope
        Include assignments scoped to Administrative Units, not just directory-wide assignments.
        By default, only directory-wide assignments are included.

    .PARAMETER OutputPath
        Path to export the results to a CSV file. The directory will be created if it doesn't exist.
        Results are still returned to the pipeline even when exporting.

    .PARAMETER ThrottleLimit
        Limit the number of concurrent operations for performance tuning.
        Default is 10 concurrent operations. Increase for faster processing in larger environments,
        decrease if experiencing throttling or resource constraints.

    .PARAMETER OutputFormat
        Format for the output: "Object" (raw PowerShell objects), "JSON" (formatted JSON string),
        "CSV" (comma-separated values), or "Table" (formatted table view, default).
        Use "Object" when piping to other commands for further processing.

    .EXAMPLE
        Find-EntraPermissionHolder -Permission "microsoft.directory/applications/create"

        Returns all principals that can create applications in Entra ID.

    .EXAMPLE
        Find-EntraPermissionHolder -Permission "microsoft.directory/servicePrincipals/credentials/update" -ResolveGroups

        Returns all principals that can update service principal credentials, including nested group memberships.

    .EXAMPLE
        Find-EntraPermissionHolder -Permission "microsoft.directory/*" -OutputFormat CSV -OutputPath "~/Desktop/all-admins.csv"

        Finds all principals with any Microsoft Directory permissions and exports results to a CSV file.
        
    .EXAMPLE
        Find-EntraPermissionHolder -Permission "microsoft.directory/*role*/*" -ResolveGroups
        
        Uses wildcards to find all principals with any permission containing "role" anywhere in the path,
        including resolving group memberships to show all users who have access.

    .EXAMPLE
        Find-EntraPermissionHolder -Permission "microsoft.directory/users/delete" -IncludeEligible -IncludeAUScope

        Returns all principals (active and PIM eligible) that can delete users, including those
        with permissions scoped to specific Administrative Units.

    .NOTES
        Author: BlackCat Security
        Required Permissions:
          - Directory.Read.All (minimum requirement)
          - RoleManagement.Read.Directory (for PIM eligible assignments)
          - GroupMember.Read.All (for resolving group memberships)

        Performance Notes:
          - Use the ThrottleLimit parameter to adjust parallel processing performance
          - For large tenants, resolving groups can take significant time

    .LINK
        MITRE ATT&CK Tactic: TA0007 - Discovery
        https://attack.mitre.org/tactics/TA0007/

    .LINK
        MITRE ATT&CK Technique: T1069.003 - Permission Groups Discovery: Cloud Groups
        https://attack.mitre.org/techniques/T1069/003/
    #>
    [cmdletbinding()]
    [OutputType([System.Collections.Generic.List[PSCustomObject]])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $false, Position = 0)]
        [string]$Permission,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('include-eligible')]
        [switch]$IncludeEligible,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('resolve-groups')]
        [switch]$ResolveGroups,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('include-au-scope')]
        [switch]$IncludeAUScope,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('output-path')]
        [string]$OutputPath,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('throttle-limit')]
        [int]$ThrottleLimit = 10,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Object", "JSON", "CSV", "Table")]
        [Alias("output", "o")]
        [string]$OutputFormat = "Table"
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $startTime = Get-Date

        # Ensure we have a valid Graph connection
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'

        # Create collection for results
        $permissionHolders = [System.Collections.Generic.List[PSCustomObject]]::new()

        Write-Host " Finding Entra ID principals with permission: $Permission" -ForegroundColor Green
        Write-Host "   Started at: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor DarkGray
    }

    process {
        # Step 1: Find all roles that contain the specified permission
        $matchingRoles = Find-RolesWithPermission -Permission $Permission

        if (-not $matchingRoles -or $matchingRoles.Count -eq 0) {
            Write-Host "  No roles found containing the permission: $Permission" -ForegroundColor Yellow
            return
        }

        Write-Host "  Found $($matchingRoles.Count) roles containing the permission: $Permission" -ForegroundColor Green

        # List the identified roles in verbose mode
        if ($VerbosePreference -eq 'Continue') {
            foreach ($role in $matchingRoles) {
                Write-Host "    - $($role.displayName)" -ForegroundColor Cyan
            }
        }

        # Step 2: For each role, get all members using Get-EntraRoleMember
        foreach ($role in $matchingRoles) {
            $roleName = $role.displayName
            $roleId = $role.id

            Write-Verbose "Getting members for role: $roleName"

            try {
                # Get role members directly using Microsoft Graph API to avoid Get-EntraRoleMember restrictions
                Write-Verbose "Getting role assignments for role: $roleName ($roleId)"

                # Get all role assignments
                $roleAssignments = Invoke-MsGraph -relativeUrl "roleManagement/directory/roleAssignments" -NoBatch -ErrorAction Stop
                $targetAssignments = $roleAssignments.value | Where-Object { $_.roleDefinitionId -eq $roleId }

                if (-not $targetAssignments -or $targetAssignments.Count -eq 0) {
                    Write-Verbose "No assignments found for role: $roleName"
                    continue
                }

                Write-Verbose "Found $($targetAssignments.Count) assignments for role: $roleName"

                # Get principal details for all assignments
                $principalIds = $targetAssignments.principalId | Select-Object -Unique
                $principalDetails = @{}

                # Get principal details individually (simpler than batch processing)
                foreach ($principalId in $principalIds) {
                    try {
                        $principalData = Invoke-MsGraph -relativeUrl "directoryObjects/$principalId" -NoBatch -ErrorAction Stop
                        $principalType = $principalData.'@odata.type' -replace "#microsoft.graph.", ""

                        $principalDetails[$principalId] = [PSCustomObject]@{
                            Type = $principalType
                            Details = $principalData
                        }
                    }
                    catch {
                        Write-Verbose "Could not get details for principal $principalId`: $_"
                        # Create a placeholder for missing principals
                        $principalDetails[$principalId] = [PSCustomObject]@{
                            Type = "Unknown"
                            Details = [PSCustomObject]@{
                                displayName = "Unknown Principal"
                                userPrincipalName = $null
                                appId = $null
                            }
                        }
                    }
                }

                # Process each assignment
                foreach ($assignment in $targetAssignments) {
                    $principalId = $assignment.principalId
                    $principalInfo = $principalDetails[$principalId]

                    if (-not $principalInfo) {
                        Write-Verbose "Could not get details for principal: $principalId"
                        continue
                    }

                    # Skip if not including eligible assignments and this is an eligible assignment
                    if (-not $IncludeEligible -and $assignment.assignmentType -eq "Eligible") {
                        Write-Verbose "Skipping eligible assignment for principal: $principalId"
                        continue
                    }

                    # Determine scope - directory-wide or administrative unit
                    $scope = "Directory"
                    $scopeDisplayName = "Directory (Global)"

                    # Only include AU-scoped assignments if requested
                    if ($IncludeAUScope -and $assignment.directoryScopeId -and $assignment.directoryScopeId -ne "/") {
                        $scope = "AdministrativeUnit"
                        $scopeDisplayName = "AU: $($assignment.directoryScopeDisplayName)"
                    } elseif ($assignment.directoryScopeId -and $assignment.directoryScopeId -ne "/" -and -not $IncludeAUScope) {
                        # Skip AU-scoped assignments if not requested
                        Write-Verbose "Skipping AU-scoped assignment for principal: $principalId"
                        continue
                    }

                    # Create member object
                    $member = [PSCustomObject]@{
                        PrincipalId = $principalId
                        PrincipalType = $principalInfo.Type
                        DisplayName = $principalInfo.Details.displayName
                        UserPrincipalName = if ($principalInfo.Type -eq "user") { $principalInfo.Details.userPrincipalName } else { $null }
                        AppId = if ($principalInfo.Type -eq "servicePrincipal") { $principalInfo.Details.appId } else { $null }
                        AssignmentState = if ($assignment.assignmentType -eq "Eligible") { "Eligible" } else { "Active" }
                        DirectoryScopeId = $assignment.directoryScopeId
                        DirectoryScopeDisplayName = $assignment.directoryScopeDisplayName
                        AssignmentId = $assignment.id
                    }

                    # Add to results collection
                    $permissionHolders.Add([PSCustomObject]@{
                        Permission = $Permission
                        RoleDisplayName = $roleName
                        RoleId = $roleId
                        RoleDescription = $role.description
                        AssignmentType = $member.AssignmentState
                        Scope = $scope
                        ScopeDisplayName = $scopeDisplayName
                        PrincipalId = $member.PrincipalId
                        PrincipalName = $member.DisplayName
                        PrincipalType = $member.PrincipalType
                        UserPrincipalName = $member.UserPrincipalName
                        AppId = $member.AppId
                        ResolvedMembers = @()
                        AssignmentId = $member.AssignmentId
                    })
                }
            }
            catch {
                Write-Warning "Error getting members for role '$roleName': $_"
            }
        }

        # Step 3: Resolve group memberships if requested
        if ($ResolveGroups -and $permissionHolders.Count -gt 0) {
            $groupPrincipals = $permissionHolders | Where-Object { $_.PrincipalType -eq 'group' }

            if ($groupPrincipals.Count -gt 0) {
                # Resolve all group members
                $resolvedGroups = Resolve-GroupMembers -Groups $groupPrincipals -ThrottleLimit $ThrottleLimit

                # Update the original objects with resolved members
                foreach ($holder in $permissionHolders) {
                    if ($holder.PrincipalType -eq 'group' -and $resolvedGroups.ContainsKey($holder.PrincipalId)) {
                        $holder.ResolvedMembers = $resolvedGroups[$holder.PrincipalId]
                        $holder | Add-Member -NotePropertyName "ResolvedMemberCount" -NotePropertyValue $holder.ResolvedMembers.Count -Force
                    }
                }

                # Summarize results
                $resolvedUsers = ($resolvedGroups.Values | ForEach-Object { $_ } | Where-Object { $_.PrincipalType -eq "user" }).Count
                $resolvedSPs = ($resolvedGroups.Values | ForEach-Object { $_ } | Where-Object { $_.PrincipalType -eq "servicePrincipal" }).Count
                $nestedGroups = ($resolvedGroups.Values | ForEach-Object { $_ } | Where-Object { $_.PrincipalType -eq "group" -or $_.PrincipalType -eq "NestedGroup" -or $_.PrincipalType -eq "DirectGroup" }).Count

                Write-Host "     Resolved $resolvedUsers users and $resolvedSPs service principals from $($groupPrincipals.Count) groups" -ForegroundColor Green
                if ($nestedGroups -gt 0) {
                    Write-Host "     Found $nestedGroups nested groups in the permission chain" -ForegroundColor Cyan
                }
            }
        }
    }

    end {
        # Calculate execution time
        $executionTime = (Get-Date) - $startTime
        $formattedTime = "{0:mm\:ss\.fff}" -f $executionTime

        # Summarize findings
        $groupedResults = $permissionHolders | Group-Object -Property PrincipalType

        Write-Host "`nPermission Analysis Complete" -ForegroundColor Green
        Write-Host "  Permission searched: $Permission"
        Write-Host "  Execution time: $formattedTime" -ForegroundColor DarkGray

        foreach ($group in $groupedResults) {
            $pluralSuffix = if ($group.Count -ne 1) { "s" } else { "" }
            $color = switch ($group.Name) {
                "user"             { "Green" }
                "group"            { "Yellow" }
                "servicePrincipal" { "Cyan" }
                default            { "White" }
            }
            Write-Host "  Found $($group.Count) $($group.Name)$pluralSuffix with the permission" -ForegroundColor $color
        }

        # Handle direct export to file if requested
        if ($OutputPath) {
            Write-Host "  Exporting results to $OutputPath" -ForegroundColor Cyan
            try {
                # Create directory if it doesn't exist
                $directory = Split-Path -Parent $OutputPath
                if (-not (Test-Path $directory)) {
                    New-Item -ItemType Directory -Path $directory -Force | Out-Null
                }

                # Export to CSV
                $permissionHolders | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
                Write-Host "     Export completed successfully: $OutputPath" -ForegroundColor Green
            }
            catch {
                Write-Warning "Error exporting to $OutputPath`: $_"
            }
        }

        # Format and return output based on requested format
        switch ($OutputFormat) {
            "Table" {
                # Create a more compact, user-friendly view for table display
                $userFocusedOutput = $permissionHolders | ForEach-Object {
                    [PSCustomObject]@{
                        "PrincipalName"     = $_.PrincipalName
                        "PrincipalType"     = $_.PrincipalType
                        "Role"              = $_.RoleDisplayName
                        "AssignmentType"    = $_.AssignmentType
                        "UserPrincipalName" = $_.UserPrincipalName
                        "Scope"             = $_.ScopeDisplayName
                    }
                }

                return Format-BlackCatOutput -Data $userFocusedOutput -OutputFormat $OutputFormat -FunctionName $MyInvocation.MyCommand.Name -FilePrefix "EntraPermHolders-$($Permission.Split('/')[-1])"
            }

            "Object" {
                return $permissionHolders
            }

            default {
                # For JSON, CSV formats, return the complete data structure
                return Format-BlackCatOutput -Data $permissionHolders -OutputFormat $OutputFormat -FunctionName $MyInvocation.MyCommand.Name -FilePrefix "EntraPermHolders-$($Permission.Split('/')[-1])"
            }
        }
    }
}
