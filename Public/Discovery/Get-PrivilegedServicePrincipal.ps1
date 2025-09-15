function Get-PrivilegedServicePrincipal {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateSet('Critical', 'High', 'Medium', 'Low', 'All')]
        [string]$Criticality = 'All',

        [Parameter(Mandatory = $false)]
        [string]$PermissionPattern,

        [Parameter(Mandatory = $false)]
        [string]$ServicePrincipalName,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Object', 'JSON', 'CSV', 'Table')]
        [string]$OutputFormat = 'Object'
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'

        # Load privileged roles from file
        $privilegedRolesPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "support-files/privileged-roles.json"
        if (Test-Path $privilegedRolesPath) {
            $privilegedRolesData = Get-Content $privilegedRolesPath -Raw | ConvertFrom-Json
            $privilegedRoles = $privilegedRolesData.privilegedRoles
            Write-Verbose "Loaded $($privilegedRoles.Count) privileged roles"
        }
        else {
            Write-Warning "Privileged roles file not found at $privilegedRolesPath"
            return
        }

        # Filter by criticality
        if ($Criticality -ne 'All') {
            $privilegedRoles = $privilegedRoles | Where-Object { $_.criticality -eq $Criticality }
            Write-Verbose "Filtered to $($privilegedRoles.Count) $Criticality roles"
        }

        # Get role definitions from Entra ID
        try {
            Write-Verbose "Retrieving role definitions from Entra ID"
            $roleDefinitions = Invoke-MsGraph -relativeUrl 'roleManagement/directory/roleDefinitions'
            Write-Verbose "Retrieved $($roleDefinitions.Count) role definitions"
        }
        catch {
            Write-Warning "Failed to retrieve role definitions: $($_.Exception.Message)"
            return
        }
    }

    process {
        try {
            # Get all role assignments
            Write-Verbose "Retrieving role assignments"
            $roleAssignments = Invoke-MsGraph -relativeUrl 'roleManagement/directory/roleAssignments'
            
            if (-not $roleAssignments) {
                Write-Warning "No role assignments found."
                return
            }
            
            Write-Verbose "Retrieved $($roleAssignments.Count) role assignments"
            
            # Debug the first few assignments
            foreach ($assignment in $roleAssignments | Select-Object -First 3) {
                Write-Verbose "Assignment: ID=$($assignment.id), RoleDefID=$($assignment.roleDefinitionId), PrincipalID=$($assignment.principalId)"
            }
            
            # Create a hashtable for service principal cache
            $spLookup = @{}
            
            # Create a mapping of privileged roles by ID
            $privilegedRoleMap = @{}
            foreach ($privilegedRole in $privilegedRoles) {
                $privilegedRoleMap[$privilegedRole.roleId] = $privilegedRole
                Write-Verbose "Added privileged role to map: $($privilegedRole.roleName) ($($privilegedRole.roleId))"
            }
            
            # Process results
            $results = @()
            
            # Process each role assignment
            foreach ($assignment in $roleAssignments) {
                # Skip if no role definition ID
                if (-not $assignment.roleDefinitionId) {
                    continue
                }
                
                # Get the role definition ID (format may vary)
                $roleId = $assignment.roleDefinitionId
                
                # Check if this is a privileged role
                $privilegedRole = $null
                
                # First try direct match
                if ($privilegedRoleMap.ContainsKey($roleId)) {
                    $privilegedRole = $privilegedRoleMap[$roleId]
                }
                else {
                    # Try extracting GUID if present
                    if ($roleId -match "([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$") {
                        $extractedId = $matches[1]
                        if ($privilegedRoleMap.ContainsKey($extractedId)) {
                            $privilegedRole = $privilegedRoleMap[$extractedId]
                        }
                    }
                }
                
                # If we found a privileged role assignment
                if ($privilegedRole) {
                    Write-Verbose "Found privileged role assignment: $($privilegedRole.roleName)"
                    
                    # Get the principal ID
                    $principalId = $assignment.principalId
                    
                    # Check if we've already fetched this service principal
                    if (-not $spLookup.ContainsKey($principalId)) {
                        try {
                            Write-Verbose "Looking up service principal with ID: $principalId"
                            $sp = Invoke-MsGraph -relativeUrl "servicePrincipals/$principalId" -NoBatch -OutputFormat Object -ErrorAction SilentlyContinue
                            
                            if ($sp -and $sp.id) {
                                $spLookup[$principalId] = $sp
                                Write-Verbose "Found service principal: $($sp.displayName)"
                            }
                        }
                        catch {
                            Write-Verbose "Not a service principal or error retrieving: $principalId"
                            # Silently continue - this may be a user or group
                            continue
                        }
                    }
                    
                    # Check if we found a service principal
                    if ($spLookup.ContainsKey($principalId)) {
                        $sp = $spLookup[$principalId]
                        
                        # Apply name filter if provided
                        if ($ServicePrincipalName -and -not ($sp.displayName -like "*$ServicePrincipalName*")) {
                            Write-Verbose "Service principal does not match name filter: $($sp.displayName)"
                            continue
                        }
                        
                        # Check permissions if pattern is provided
                        $skipDueToPermission = $false
                        if ($PermissionPattern) {
                            $hasMatch = $false
                            
                            # Get detailed SP info if needed
                            if (-not $sp.oauth2PermissionGrants -and -not $sp.appRoleAssignments) {
                                try {
                                    $spDetails = Invoke-MsGraph -relativeUrl "servicePrincipals/$($sp.id)?`$expand=oauth2PermissionGrants,appRoleAssignments" -NoBatch -OutputFormat Object
                                    if ($spDetails) {
                                        $sp = $spDetails
                                        $spLookup[$principalId] = $spDetails # Update cache
                                    }
                                }
                                catch {
                                    Write-Verbose "Failed to get detailed permissions: $($_.Exception.Message)"
                                }
                            }
                            
                            # Check delegated permissions
                            if ($sp.oauth2PermissionGrants) {
                                foreach ($grant in $sp.oauth2PermissionGrants) {
                                    if ($grant.scope -like "*$PermissionPattern*") {
                                        $hasMatch = $true
                                        Write-Verbose "Found matching permission: $($grant.scope)"
                                        break
                                    }
                                }
                            }
                            
                            # Check app permissions
                            if (-not $hasMatch -and $sp.appRoleAssignments) {
                                foreach ($appRole in $sp.appRoleAssignments) {
                                    if ($appRole.appRoleId -like "*$PermissionPattern*") {
                                        $hasMatch = $true
                                        Write-Verbose "Found matching app role: $($appRole.appRoleId)"
                                        break
                                    }
                                }
                            }
                            
                            if (-not $hasMatch) {
                                $skipDueToPermission = $true
                            }
                        }
                        
                        # Add to results if passes all filters
                        if (-not $skipDueToPermission) {
                            # Only add if not already in results
                            if (-not ($results | Where-Object { $_.Id -eq $sp.id })) {
                                $results += [PSCustomObject]@{
                                    Id = $sp.id
                                    AppId = $sp.appId
                                    DisplayName = $sp.displayName
                                    Role = $privilegedRole.roleName
                                    Criticality = $privilegedRole.criticality
                                    ServicePrincipalType = $sp.servicePrincipalType
                                    IsEnabled = $sp.accountEnabled
                                    CreatedDateTime = $sp.createdDateTime
                                }
                                
                                Write-Verbose "Added to results: $($sp.displayName) with role $($privilegedRole.roleName)"
                            }
                        }
                    }
                }
            }
            
            # Sort results by criticality and name
            $results = $results | Sort-Object -Property @{
                Expression = {
                    switch ($_.Criticality) {
                        "Critical" { 4 }
                        "High" { 3 }
                        "Medium" { 2 }
                        "Low" { 1 }
                        default { 0 }
                    }
                }
            }, DisplayName -Descending
            
            # Return results
            if ($results.Count -eq 0) {
                Write-Host "No privileged service principals found matching the criteria." -ForegroundColor Yellow
                return $null
            }
            else {
                Write-Host "Found $($results.Count) privileged service principals." -ForegroundColor Green
                
                # Format output
                $formatParam = @{
                    Data = $results
                    OutputFormat = $OutputFormat
                    FunctionName = $MyInvocation.MyCommand.Name
                }
                
                return Format-BlackCatOutput @formatParam
            }
        }
        catch {
            Write-Warning "An error occurred while retrieving privileged service principals: $($_.Exception.Message)"
            Write-Verbose "Stack Trace: $($_.ScriptStackTrace)"
            return $null
        }
    }

    end {
        Write-Verbose "Completed function $($MyInvocation.MyCommand.Name)"
    }

    <#
    .SYNOPSIS
        Discovers privileged service principals in Entra ID.

    .DESCRIPTION
        This function identifies service principals that have been assigned privileged roles in Entra ID.
        It categorizes roles by criticality (Critical, High, Medium, Low) and provides detailed information
        about each service principal with privileged access.

    .PARAMETER Criticality
        Filter results by role criticality level.
        Valid values: Critical, High, Medium, Low, All
        Default: All

    .PARAMETER PermissionPattern
        Filter results by permission name pattern. Only returns service principals with permissions matching the pattern.

    .PARAMETER ServicePrincipalName
        Filter results by service principal display name (partial match).

    .PARAMETER OutputFormat
        Specifies the output format.
        Valid values: Object, JSON, CSV, Table
        Default: Object

    .EXAMPLE
        Get-PrivilegedServicePrincipal -Criticality Critical -OutputFormat Table

        Returns all service principals with Critical roles and displays them in a table format.

    .EXAMPLE
        Get-PrivilegedServicePrincipal -PermissionPattern "*ReadWrite*"

        Returns all service principals with privileged roles that have permissions containing "ReadWrite".

    .EXAMPLE
        Get-PrivilegedServicePrincipal -ServicePrincipalName "Azure" -OutputFormat JSON

        Returns all privileged service principals with "Azure" in their name and exports the results as JSON.

    .NOTES
        Requires the BlackCat module and appropriate Entra ID permissions to enumerate role assignments.
        Uses the support-files/privileged-roles.json file to define privileged roles and their criticality levels.
    #>
}
