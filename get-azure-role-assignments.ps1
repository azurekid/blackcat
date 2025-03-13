# Replace with your access token
$accessToken = 'YOUR_ACCESS_TOKEN'
$subscriptionId = 'YOUR_SUBSCRIPTION_ID'

# Step 1: Get the current user's object ID
$userResponse = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/me" -Headers @{Authorization = "Bearer $accessToken"}
$userObjectId = $userResponse.id

# Step 2: List groups the user is a member of
$groupsResponse = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/me/memberOf" -Headers @{Authorization = "Bearer $accessToken"}
$groupIds = $groupsResponse.value | ForEach-Object { $_.id }

# Step 3: List role assignments for the user and their groups
$roleAssignmentsUri = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Authorization/roleAssignments?api-version=2020-10-01-preview&`$filter=principalId eq '$userObjectId'"
$roleAssignmentsResponse = Invoke-RestMethod -Uri $roleAssignmentsUri -Headers @{Authorization = "Bearer $accessToken"}
$roleAssignments = $roleAssignmentsResponse.value

foreach ($groupId in $groupIds) {
    $groupRoleAssignmentsUri = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Authorization/roleAssignments?api-version=2020-10-01-preview&`$filter=principalId eq '$groupId'"
    $groupRoleAssignmentsResponse = Invoke-RestMethod -Uri $groupRoleAssignmentsUri -Headers @{Authorization = "Bearer $accessToken"}
    $roleAssignments += $groupRoleAssignmentsResponse.value
}

# Step 4: List role definitions
$roleDefinitionsUri = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Authorization/roleDefinitions?api-version=2020-10-01-preview"
$roleDefinitionsResponse = Invoke-RestMethod -Uri $roleDefinitionsUri -Headers @{Authorization = "Bearer $accessToken"}
$roleDefinitions = @{}
foreach ($role in $roleDefinitionsResponse.value) {
    $roleDefinitions[$role.id] = $role
}

# Combine role assignments with role definitions
$userRoles = @()
foreach ($assignment in $roleAssignments) {
    $roleDefinitionId = $assignment.properties.roleDefinitionId
    $roleDefinition = $roleDefinitions[$roleDefinitionId]
    $userRoles += [pscustomobject]@{
        RoleName    = $roleDefinition.properties.roleName
        Permissions = $roleDefinition.properties.permissions
    }
}

# Print user roles and permissions
foreach ($role in $userRoles) {
    Write-Output "Role: $($role.RoleName)"
    foreach ($permission in $role.Permissions) {
        Write-Output "  Actions: $($permission.actions)"
        Write-Output "  NotActions: $($permission.notActions)"
    }
}
