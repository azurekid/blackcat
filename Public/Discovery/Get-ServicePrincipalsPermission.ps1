function Get-ServicePrincipalsPermission {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias('AppId','ApplicationId')]
        # [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [string]$servicePrincipalId
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        # Only invoke the authentication if we need to (tokens expired or not present)
        if (-not $script:graphHeader -or 
            -not $script:SessionVariables -or 
            -not $script:SessionVariables.accessToken -or 
            ($script:SessionVariables.ExpiresOn -and $script:SessionVariables.ExpiresOn - [datetime]::UtcNow.AddMinutes(-5) -le 0)) {
                
            Write-Verbose "Authentication needed - Initializing Graph API access"
            $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
        }
        else {
            Write-Verbose "Using existing authentication token - valid until $($script:SessionVariables.ExpiresOn)"
        }
    }

    process {
        try {
            # Resolve input that could be either service principal objectId or applicationId
            $resolvedSp = $null
            $resolvedSpId = $null

            # First try treating input as service principal objectId
            try {
                $resolvedSp = Invoke-MsGraph -relativeUrl "servicePrincipals/$servicePrincipalId" -NoBatch -ErrorAction Stop
                $resolvedSpId = $resolvedSp.id
                Write-Verbose "Resolved service principal by objectId: $resolvedSpId"
            }
            catch {
                Write-Verbose "Direct servicePrincipalId lookup failed, attempting appId lookup"
            }

            if (-not $resolvedSp) {
                $spByAppId = Invoke-MsGraph -relativeUrl "servicePrincipals?`$filter=appId eq '$servicePrincipalId'" -NoBatch
                if ($spByAppId.value -and $spByAppId.value.Count -gt 0) {
                    $resolvedSp = $spByAppId.value[0]
                    $resolvedSpId = $resolvedSp.id
                    Write-Verbose "Resolved service principal by applicationId to objectId: $resolvedSpId"
                }
            }

            if (-not $resolvedSpId) {
                throw "Unable to resolve service principal from identifier '$servicePrincipalId'"
            }

            Write-Verbose "Creating batch requests for service principal $resolvedSpId"
            
            # Create batch requests for all needed data
            $batchRequests = [System.Collections.Generic.List[hashtable]]::new()
            
            # Request 1: Get service principal details
            $batchRequests.Add(@{
                    id     = "spDetails"
                    method = "GET"
                    url    = "/servicePrincipals/$resolvedSpId"
                })
            
            # Request 2: Get app role assignments
            $batchRequests.Add(@{
                    id     = "appRoleAssignments"
                    method = "GET"
                    url    = "/servicePrincipals/$resolvedSpId/appRoleAssignments"
                })
            
            # Request 3: Get delegated permissions
            $batchRequests.Add(@{
                    id     = "delegatedPermissions"
                    method = "GET"
                    url    = "/oauth2PermissionGrants?`$filter=clientId eq '$resolvedSpId'"
                })
            
            # Request 4: Get app roles assigned to others
            $batchRequests.Add(@{
                    id     = "appRoleAssignedTo"
                    method = "GET"
                    url    = "/servicePrincipals/$resolvedSpId/appRoleAssignedTo"
                })
            
            # Request 5: Get directory roles and memberships
            $batchRequests.Add(@{
                    id     = "memberOf"
                    method = "GET"
                    url    = "/servicePrincipals/$resolvedSpId/transitiveMemberOf"
                })
            
            # Request 6: Get owned objects
            $batchRequests.Add(@{
                    id     = "ownedObjects"
                    method = "GET"
                    url    = "/servicePrincipals/$resolvedSpId/ownedObjects"
                })
            
            # Execute all requests in a single batch
            Write-Verbose "Executing batch request with $($batchRequests.Count) items"
            $batchResults = Invoke-MsGraph -BatchRequests $batchRequests
            
            # Extract results from batch response
            $spDetails = $batchResults["spDetails"].Data
            $appRoleAssignments = $batchResults["appRoleAssignments"].Data.value
            $delegatedPermissions = $batchResults["delegatedPermissions"].Data.value
            $appRoleAssignedTo = $batchResults["appRoleAssignedTo"].Data.value
            $memberOf = $batchResults["memberOf"].Data.value
            $ownedObjects = $batchResults["ownedObjects"].Data.value
            
            Write-Verbose "Successfully retrieved all service principal data in a single batch request"
            
            # Extract useful data for summary
            $appPermissions = $appRoleAssignments | ForEach-Object {
                # Try to resolve permission name from appRoleId
                $currentAppRoleId = $_.appRoleId
                $permissionName = "Unknown"
                if ($script:SessionVariables -and $script:SessionVariables.appRoleIds) {
                    $permissionObj = $script:SessionVariables.appRoleIds | Where-Object { $_.appRoleId -eq $currentAppRoleId }
                    if ($permissionObj) {
                        $permissionName = $permissionObj.Permission
                    }
                    else {
                        # Try to call Get-AppRolePermission directly
                        try {
                            $roleInfo = Get-AppRolePermission -appRoleId $currentAppRoleId -ErrorAction SilentlyContinue
                            if ($roleInfo -and $roleInfo.Permission) {
                                $permissionName = $roleInfo.Permission
                            }
                        }
                        catch {
                            # Silently continue if Get-AppRolePermission fails
                        }
                    }
                }

                [PSCustomObject]@{
                    'Resource DisplayName' = $_.resourceDisplayName
                    'PermissionId'         = $_.appRoleId
                    'Permission Name'      = $permissionName
                }
            }
            
            $delegatedPerms = $delegatedPermissions | ForEach-Object {
                [PSCustomObject]@{
                    ResourceId = $_.resourceId
                    Scopes     = $_.scope -split ' '
                }
            }
            
            # Extract owned objects with type information
            $ownedObjectsInfo = $ownedObjects | ForEach-Object {
                $type = $_.'@odata.type' -replace '#microsoft\.graph\.'
                [PSCustomObject]@{
                    DisplayName = $_.displayName
                    ObjectId    = $_.id
                    Type        = $type
                }
            }
            
            # Create summarized result object
            $result = [PSCustomObject]@{
                DisplayName              = $spDetails.displayName
                ObjectId                 = $spDetails.id
                AppId                    = $spDetails.appId
                ServicePrincipalType     = $spDetails.servicePrincipalType
                AccountEnabled           = $spDetails.accountEnabled
                AppRoles                 = $spDetails.appRoles.displayName
                GroupMemberships         = ($memberOf | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.group' }).displayName
                DirectoryRoles           = ($memberOf | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.directoryRole' }).displayName
                AppPermissions           = $appPermissions
                DelegatedPermissions     = $delegatedPerms
                OwnedObjects             = $ownedObjectsInfo
                IsPrivileged             = $false
            }
            
            # Check if the service principal has privileged roles
            $privilegedRoles = @('Global Administrator', 'Privileged Role Administrator', 'Application Administrator', 
                'Cloud Application Administrator', 'Hybrid Identity Administrator', 'Directory Synchronization Accounts')
            foreach ($role in $result.DirectoryRoles) {
                if ($role -in $privilegedRoles) {
                    $result.IsPrivileged = $true
                    break
                }
            }
            
            return $result
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
    <#
.SYNOPSIS
Conducts a comprehensive security analysis of a service principal, including its permissions, roles, and relationships.

.DESCRIPTION
The Get-ServicePrincipalsPermission function performs an in-depth analysis of an Azure service principal's
security posture and permissions. It provides a centralized view of critical information including:

- Core identity details (DisplayName, ObjectId/ServicePrincipalId, AppId)
- Application permissions with both IDs and human-readable names
- Delegated OAuth2 permissions and their scopes
- Group memberships and directory role assignments
- Owned objects with their types and names
- Security indicators like privileged role assignments
- Exposure assessment through permissions assigned to others

.PARAMETER servicePrincipalId
The unique identifier (GUID) of the service principal to analyze. This can be passed from the pipeline.

.EXAMPLE
Get-ServicePrincipalsPermission -servicePrincipalId "12345678-1234-1234-1234-1234567890ab"

Retrieves comprehensive security information about the specified service principal, including all permissions,
roles, and relationships.

.EXAMPLE
Get-ServicePrincipalsPermission -servicePrincipalId "12345678-1234-1234-1234-1234567890ab" -Verbose

Performs detailed analysis with progress information shown for each API call, useful for troubleshooting
or understanding the data collection process.

.EXAMPLE
Get-ServicePrincipalsPermission -servicePrincipalId "12345678-1234-1234-1234-1234567890ab" | Select-Object -ExpandProperty AppPermissions

Extracts just the application permissions assigned to the service principal, showing resource names,
permission IDs and human-readable permission names.

.OUTPUTS
[PSCustomObject]
Returns a structured object containing detailed security information about the service principal:
- Basic details: DisplayName, ServicePrincipalId/ObjectId, AppId, ServicePrincipalType
- Status: AccountEnabled
- Permissions: AppPermissions (with both IDs and names), DelegatedPermissions
- Relationships: GroupMemberships, DirectoryRoles, OwnedObjects (with types)
- Security indicators: IsPrivileged, AssignedPermissionsCount, OwnedObjectsCount

.NOTES
- Uses Microsoft Graph batch API to retrieve all data in a single HTTP request, significantly improving performance.
- IsPrivileged flag specifically checks for high-risk directory roles like Global Administrator.
- The function attempts to resolve permission names from IDs using session variables or the Get-AppRolePermission function.
- Aligned with the output format of other BlackCat reconnaissance functions for consistent analysis.
- Optimized for large environments with many service principals and complex permission structures.
#>
}