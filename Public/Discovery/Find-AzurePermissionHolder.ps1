function Find-AzurePermissionHolder {
    <#
    .SYNOPSIS
        Finds Azure users or service principals that have a specific permission.

    .DESCRIPTION
        Identifies Azure users, groups, and service principals with specific role permissions

    .PARAMETER Permission
        The permission to search for within Azure roles (e.g. 'Microsoft.KeyVault/vaults/accessPolicies/write').
        The function will find all principals with roles containing this permission.
        You can provide multiple permission patterns as an array.

    .PARAMETER IncludeGroups
        Includes group details in the results. By default, only users and service principals are returned.

    .PARAMETER SubscriptionId
        Limits the search to a specific subscription. If omitted, searches all accessible subscriptions.

    .PARAMETER PrincipalType
        Filters results by principal type. Valid options are: User, Group, ServicePrincipal.

    .PARAMETER OutputFormat
        Specifies the output format for results. Valid values are:
        - Object: Returns PowerShell objects (default)
        - JSON: Returns results in JSON format and saves to file
        - CSV: Returns results in CSV format and saves to file
        - Table: Returns results in formatted table
        Aliases: output, o

    .PARAMETER ResolvePrincipalNames
        When specified, resolves principal IDs to their display names using Microsoft Graph API.
        For users, includes both display name and UPN.
        
    .PARAMETER SkipCache
        Skips using the cache and forces a fresh API call.

    .OUTPUTS
        Returns a collection of custom objects with the following properties:
        - PrincipalId: The Azure AD Object ID of the principal
        - PrincipalType: The type of principal (User, Group, ServicePrincipal)
        - PrincipalName: The display name of the principal (only when ResolvePrincipalNames is used)
        - RoleName: The display name of the RBAC role
        - RoleDefinitionId: The ID of the role definition
        - Scope: The resource scope of the role assignment
        - MatchedPermissions: List of permissions granted by the role that matched the search criteria

    .EXAMPLE
        Find-AzurePermissionHolder -Permission "Microsoft.KeyVault/vaults/accessPolicies/write"
        Finds all users and service principals that have been assigned roles with key vault access policy write permissions.

    .EXAMPLE
        Find-AzurePermissionHolder -Permission "Microsoft.Compute/virtualMachines/start/action" -PrincipalType User -OutputFormat JSON
        Finds all users that can start virtual machines and outputs the results in JSON format.

    .EXAMPLE
        Find-AzurePermissionHolder -Permission @("Microsoft.Authorization/roleAssignments/write", "Microsoft.Authorization/roleDefinitions/write") -OutputFormat Table
        Finds all principals that can modify role assignments or role definitions, and outputs as a table.

    .NOTES
        This function requires appropriate Azure RBAC permissions to read role assignments and definitions.

    .LINK
        MITRE ATT&CK Tactic: TA0007 - Discovery
        https://attack.mitre.org/tactics/TA0007/

    .LINK
        MITRE ATT&CK Technique: T1069.003 - Permission Groups Discovery: Cloud Groups
        https://attack.mitre.org/techniques/T1069/003/
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string[]]$Permission,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeGroups,

        [Parameter(Mandatory = $false)]
        [ValidatePattern('^[0-9a-fA-F-]{36}$', ErrorMessage = "It does not match expected pattern '{1}'")]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $false)]
        [ValidateSet('User', 'Group', 'ServicePrincipal')]
        [string]$PrincipalType,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Object", "JSON", "CSV", "Table")]
        [Alias("output", "o")]
        [string]$OutputFormat = "Table",

        [Parameter(Mandatory = $false)]
        [switch]$SkipCache
    )

    Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"

    # Use BlackCat authentication
    $MyInvocation.MyCommand.Name | Invoke-BlackCat
    $startTime = Get-Date

    # Initialize variables
    $results = @()
    $roleDefinitionsCache = @{}
    $principalCache = @{}

    Write-Host "Starting Azure Permission Holder Analysis..." -ForegroundColor Green
    Write-Host "  Searching for permission: $($Permission -join ', ')" -ForegroundColor Cyan

    # Create cache key for results
    $cacheKeyParams = @{
        Permission = ($Permission -join '|')
        IncludeGroups = $IncludeGroups.IsPresent
        SubscriptionId = $SubscriptionId
        PrincipalType = $PrincipalType
    }
    $cacheKey = ConvertTo-CacheKey -BaseIdentifier "Find-AzurePermissionHolder" -Parameters $cacheKeyParams

    # Try to get cached results first
    if (-not $SkipCache) {
        $cachedResults = Get-BlackCatCache -Key $cacheKey -CacheType 'MSGraph'
        if ($null -ne $cachedResults) {
            Write-Host "Retrieved permission holders from cache" -ForegroundColor Green
            
            # Return cached results in requested format using BlackCat's standard output formatter
            $formatParam = @{
                Data = $cachedResults
                OutputFormat = $OutputFormat
                FunctionName = $MyInvocation.MyCommand.Name
                FilePrefix = "AzPermHolders-$($Permission[0].Split('/')[-1])"
            }
            return Format-BlackCatOutput @formatParam
        }
    }

    # Determine scope for role definitions query
    $scope = if ($SubscriptionId) {
        "/subscriptions/$SubscriptionId"
    } else {
        "/" # Tenant root scope
    }

    try {
        # Get role definitions via REST API
        $roleDefsUri = "https://management.azure.com$scope/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01"
        Write-Verbose "Fetching role definitions from: $roleDefsUri"
        
        $roleDefinitionsResponse = Invoke-RestMethod -Uri $roleDefsUri -Headers $script:authHeader -Method 'GET' -ErrorAction Stop
        $roleDefinitions = $roleDefinitionsResponse.value
        
        Write-Host "  Retrieved $($roleDefinitions.Count) role definitions" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to retrieve role definitions: $($_.Exception.Message)"
        return
    }

    $matchingRoles = @{}
    
    foreach ($roleDef in $roleDefinitions) {
        $roleId = $roleDef.name
        $roleName = $roleDef.properties.roleName
        $permissions = $roleDef.properties.permissions
        $roleActions = @()
        
        # Extract all actions from the role definition
        foreach ($permissionSet in $permissions) {
            if ($permissionSet.actions) {
                $roleActions += $permissionSet.actions
            }
        }
        
        # Check if any of the role's actions match our target permission(s)
        $matchingPermissions = @()
        
        foreach ($permissionPattern in $Permission) {
            foreach ($action in $roleActions) {
                if (Test-PermissionMatch -Pattern $action -Target $permissionPattern) {
                    # Check if this permission is blocked by notActions
                    $blocked = $false
                    foreach ($permissionSet in $permissions) {
                        if ($permissionSet.notActions) {
                            foreach ($notAction in $permissionSet.notActions) {
                                if (Test-PermissionMatch -Pattern $notAction -Target $permissionPattern) {
                                    $blocked = $true
                                    break
                                }
                            }
                        }
                    }
                    
                    if (-not $blocked) {
                        $matchingPermissions += $action
                        break
                    }
                }
            }
        }
        
        if ($matchingPermissions.Count -gt 0) {
            $matchingRoles[$roleId] = @{
                RoleName = $roleName
                RoleId = $roleId
                MatchingPermissions = $matchingPermissions
            }
            
            Write-Verbose "Found matching role: $roleName with permissions: $($matchingPermissions -join ', ')"
        }
        
        # Store all role definitions in cache for later lookup
        $roleDefinitionsCache[$roleId] = @{
            RoleName = $roleName
            Actions = $roleActions
        }
    }
    
    Write-Host "  Found $($matchingRoles.Count) roles with matching permissions" -ForegroundColor Green
    
    if ($matchingRoles.Count -eq 0) {
        Write-Host "No role definitions found with the specified permission(s). Check permission syntax." -ForegroundColor Yellow
        return
    }
    
    # Get all subscriptions if not specified
    $subscriptions = @()
    if ($SubscriptionId) {
        $subscriptions += $SubscriptionId
    } else {
        try {
            $subscriptionsUri = "https://management.azure.com/subscriptions?api-version=2020-01-01"
            $subscriptionsResponse = Invoke-RestMethod -Uri $subscriptionsUri -Headers $script:authHeader -Method 'GET' -ErrorAction Stop
            $subscriptions += $subscriptionsResponse.value.subscriptionId
            Write-Host "  Found $($subscriptions.Count) accessible subscriptions" -ForegroundColor Cyan
        }
        catch {
            Write-Error "Failed to retrieve subscriptions: $($_.Exception.Message)"
            return
        }
    }
    
    $matchingRoleIds = [string[]]$matchingRoles.Keys
    $roleAssignments = @()
    
    # Process each subscription to find role assignments
    foreach ($subId in $subscriptions) {
        try {
            Write-Verbose "Retrieving role assignments for subscription: $subId"
            
            # Get role assignments for this subscription
            $roleAssignmentsUri = "https://management.azure.com/subscriptions/$subId/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01"
            $roleAssignmentsResponse = Invoke-RestMethod -Uri $roleAssignmentsUri -Headers $script:authHeader -Method 'GET' -ErrorAction Stop
            $assignments = $roleAssignmentsResponse.value
            
            # Filter assignments to only those with matching role definitions
            $matchingAssignments = $assignments | Where-Object {
                $roleDefId = ($_.properties.roleDefinitionId -split '/')[-1]
                $matchingRoleIds -contains $roleDefId
            }
            
            if ($PrincipalType) {
                $matchingAssignments = $matchingAssignments | Where-Object {
                    $_.properties.principalType -eq $PrincipalType
                }
            }
            
            $roleAssignments += $matchingAssignments
            
            Write-Verbose "Found $($matchingAssignments.Count) matching role assignments in subscription $subId"
        }
        catch {
            Write-Warning "Error retrieving role assignments for subscription $subId`: $($_.Exception.Message)"
        }
    }
    
    Write-Host "  Found $($roleAssignments.Count) role assignments for matching roles" -ForegroundColor Green
    
    if ($roleAssignments.Count -eq 0) {
        Write-Host "No matching role assignments found." -ForegroundColor Yellow
        return
    }
    
    # Group principals by type
    $principalGroups = $roleAssignments | Group-Object { $_.properties.principalType }

    foreach ($group in $principalGroups) {
        $principalType = $group.Name
        $principalIds = $group.Group.properties.principalId | Select-Object -Unique
        
        # Skip groups if not requested
        if ($principalType -eq 'Group' -and -not $IncludeGroups) {
            continue
        }
    }
        
    foreach ($assignment in $roleAssignments) {
        $roleDefId = ($assignment.properties.roleDefinitionId -split '/')[-1]
        $principalId = $assignment.properties.principalId
        $principalType = $assignment.properties.principalType
        
        # Skip groups if not requested
        if ($principalType -eq 'Group' -and -not $IncludeGroups) {
            continue
        }
        
        # Principal details no longer needed in simplified result object
        # $principalDetail = $principalCache[$principalId]
        $roleInfo = $matchingRoles[$roleDefId]
        
        $result = [PSCustomObject]@{
            PrincipalId = $principalId
            PrincipalType = $principalType
            RoleName = $roleInfo.RoleName
            RoleDefinitionId = $roleDefId
            Scope = $assignment.properties.scope
            MatchedPermissions = ($roleInfo.MatchingPermissions | Select-Object -Unique) -join ', '
        }
        
        $results += $result
    }
    
    # Cache the results for future use
    try {
        Set-BlackCatCache -Key $cacheKey -Data $results -CacheType 'MSGraph'
        Write-Verbose "Saved results to cache with key: $cacheKey"
    }
    catch {
        Write-Verbose "Failed to save results to cache: $($_.Exception.Message)"
    }
    
    # Display summary
    $duration = [Math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
    Write-Host "`nPermission Holder Discovery Summary:" -ForegroundColor Magenta
    Write-Host "   Found $($results.Count) permission holders for '$($Permission -join ', ')'" -ForegroundColor Green
    
    # Group by principal type for summary
    $principalTypeSummary = $results | Group-Object PrincipalType
    foreach ($group in $principalTypeSummary) {
        Write-Host "   $($group.Name): $($group.Count)" -ForegroundColor Cyan
    }
    
    Write-Host "   Duration: $($duration) seconds" -ForegroundColor White
    Write-Host "Permission holder analysis completed successfully!" -ForegroundColor Green
    
    # Return results in the requested format using BlackCat's standard output formatter
    $formatParam = @{
        Data = $results
        OutputFormat = $OutputFormat
        FunctionName = $MyInvocation.MyCommand.Name
        FilePrefix = "AzPermHolders-$($Permission[0].Split('/')[-1])"
    }
    return Format-BlackCatOutput @formatParam
}

function Test-PermissionMatch {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Pattern,
        
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    if ($Pattern -eq $Target) {
        Write-Verbose "Permission match (exact): $Pattern = $Target"
        return $true
    }
    
    if ($Pattern -eq "*") {
        Write-Verbose "Permission match (global wildcard): $Pattern contains $Target"
        return $true
    }
    
    if ($Pattern.Contains("*")) {
        $regexPattern = '^' + [regex]::Escape($Pattern).Replace('\*', '.*') + '$'
        if ($Target -match $regexPattern) {
            Write-Verbose "Permission match (wildcard): $Target matches pattern $Pattern"
            return $true
        }
    }
    
    if ($Target.StartsWith("$Pattern/")) {
        Write-Verbose "Permission match (prefix): $Pattern is a prefix of $Target"
        return $true
    }
    
    if ($Pattern.StartsWith("$Target/")) {
        Write-Verbose "Permission match (prefix): $Target is a prefix of $Pattern"
        return $true
    }
    
    $actionMapping = @{
        'write' = @('read')
        'delete' = @('read')
        'action' = @('read')
        'all'    = @('read', 'write', 'delete', 'action')
    }
    
    if ($Pattern -match '^(.+)/([^/]+)$' -and $Target -match '^(.+)/([^/]+)$') {
        $patternBase = $matches[1]
        $patternAction = $matches[2].ToLower()
        
        # Reset $matches to avoid conflicts
        $null = $Target -match '^(.+)/([^/]+)$'
        $targetBase = $matches[1]
        $targetAction = $matches[2].ToLower()
        
        if ($patternBase -eq $targetBase -and 
            $actionMapping.ContainsKey($patternAction) -and 
            $actionMapping[$patternAction] -contains $targetAction) {
            Write-Verbose "Permission match (action hierarchy): $Pattern implies $Target"
            return $true
        }
    }    
    return $false
}


