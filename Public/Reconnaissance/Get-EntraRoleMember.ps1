using namespace System.Management.Automation

class EntraRoleNames : IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        try {
            if ($null -ne $script:SessionVariables -and $null -ne $script:SessionVariables.Roles) {
                return ($script:SessionVariables.Roles |
                       Select-Object -ExpandProperty DisplayName |
                       Sort-Object)
            }
            else {
                return @('Global Administrator', 'User Administrator', 'Privileged Role Administrator')
            }
        }
        catch {
            Write-Warning "Error retrieving role names: $_"
            return @('ErrorLoadingRoleNames')
        }
    }
}

function Get-PrincipalDetails {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$PrincipalIds,

        [Parameter(Mandatory = $true)]
        [hashtable]$ResultHashtable
    )

    if ($PrincipalIds.Count -eq 1) {
        $principalId = $PrincipalIds[0]

        try {
            $objectInfo = Invoke-MsGraph -relativeUrl "directoryObjects/$principalId" -NoBatch -OutputFormat Object -ErrorAction SilentlyContinue
            if ($objectInfo) {
                $principalType = "Unknown"
                if ($objectInfo.'@odata.type' -match '#microsoft.graph.user') {
                    $principalType = "User"
                }
                elseif ($objectInfo.'@odata.type' -match '#microsoft.graph.group') {
                    $principalType = "Group"
                }
                elseif ($objectInfo.'@odata.type' -match '#microsoft.graph.servicePrincipal') {
                    $principalType = "ServicePrincipal"
                }

                $ResultHashtable[$principalId] = @{
                    Type = $principalType
                    Details = $objectInfo
                }
                return
            }
        }
        catch {
            Write-Verbose "DirectoryObjects endpoint failed for $principalId, trying individual endpoints"
        }

        try {
            $userInfo = Invoke-MsGraph -relativeUrl "users/$principalId" -NoBatch -OutputFormat Object -ErrorAction Stop
            $ResultHashtable[$principalId] = @{
                Type = "User"
                Details = $userInfo
            }
            return
        }
        catch {
            Write-Verbose "User endpoint failed for $principalId"
        }

        try {
            $groupInfo = Invoke-MsGraph -relativeUrl "groups/$principalId" -NoBatch -OutputFormat Object -ErrorAction Stop
            $ResultHashtable[$principalId] = @{
                Type = "Group"
                Details = $groupInfo
            }
            return
        }
        catch {
            Write-Verbose "Group endpoint failed for $principalId"
        }

        try {
            $spInfo = Invoke-MsGraph -relativeUrl "servicePrincipals/$principalId" -NoBatch -OutputFormat Object -ErrorAction Stop
            $ResultHashtable[$principalId] = @{
                Type = "ServicePrincipal"
                Details = $spInfo
            }
            return
        }
        catch {
            Write-Verbose "ServicePrincipal endpoint failed for $principalId"
        }

        $ResultHashtable[$principalId] = @{
            Type = "Unknown"
            Details = $null
        }
        return
    }

    $batchRequests = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($principalId in $PrincipalIds) {
        $batchRequests.Add(@{
            id = $principalId
            method = "GET"
            url = "/directoryObjects/$principalId"
        })
    }

    if ($batchRequests.Count -gt 0) {
        $batchResults = Invoke-MsGraph -BatchRequests $batchRequests -ErrorAction SilentlyContinue

        foreach ($principalId in $PrincipalIds) {
            $result = $batchResults[$principalId]

            if ($result -and $result.Success -eq $true) {
                $objectInfo = $result.Data

                $principalType = "Unknown"
                if ($objectInfo.'@odata.type' -match '#microsoft.graph.user') {
                    $principalType = "User"
                }
                elseif ($objectInfo.'@odata.type' -match '#microsoft.graph.group') {
                    $principalType = "Group"
                }
                elseif ($objectInfo.'@odata.type' -match '#microsoft.graph.servicePrincipal') {
                    $principalType = "ServicePrincipal"
                }

                $ResultHashtable[$principalId] = @{
                    Type = $principalType
                    Details = $objectInfo
                }
            }
            else {
                $wasFound = $false

                try {
                    $userInfo = Get-MgUser -UserId $principalId -ErrorAction Stop
                    $ResultHashtable[$principalId] = @{
                        Type = "User"
                        Details = $userInfo
                    }
                    $wasFound = $true
                }
                catch {
                    Write-Verbose "Principal $principalId not found as user"
                }

                if (-not $wasFound) {
                    try {
                        $groupInfo = Get-MgGroup -GroupId $principalId -ErrorAction Stop
                        $ResultHashtable[$principalId] = @{
                            Type = "Group"
                            Details = $groupInfo
                        }
                        $wasFound = $true
                    }
                    catch {
                        Write-Verbose "Principal $principalId not found as group"
                    }
                }

                if (-not $wasFound) {
                    try {
                        $spInfo = Get-MgServicePrincipal -ServicePrincipalId $principalId -ErrorAction Stop
                        $ResultHashtable[$principalId] = @{
                            Type = "ServicePrincipal"
                            Details = $spInfo
                        }
                        $wasFound = $true
                    }
                    catch {
                        Write-Verbose "Principal $principalId not found as service principal"
                    }
                }

                if (-not $wasFound) {
                    $ResultHashtable[$principalId] = @{
                        Type = "Unknown"
                        Details = $null
                    }
                }
            }
        }
    }
}

function Get-EntraRoleMember {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet([EntraRoleNames])]
        [string]$RoleName = "Global Administrator",

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$RoleId,

        [Parameter(Mandatory = $false)]
        [switch]$ShowSummary,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Object", "JSON", "CSV", "Table")]
        [string]$OutputFormat = "Table"
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'

        $startTime = Get-Date

        $script:RoleName = $RoleName
        $script:RoleId = $RoleId
        $script:roleMembers = $null
        $script:principalTypes = @{
            "User" = 0
            "Group" = 0
            "ServicePrincipal" = 0
            "Unknown" = 0
        }
    }

    process {
        try {
            if (-not $RoleId) {
                $roleDefinition = $null

                # Check if session variables are available and populated
                if ($null -eq $script:SessionVariables -or $null -eq $script:SessionVariables.Roles -or $script:SessionVariables.Roles.Count -lt 10) {
                    Write-Verbose "Role session variables not available or incomplete. Attempting to initialize them..."

                    # Check if we have an access token before trying to update roles
                    if ($script:SessionVariables -and $script:SessionVariables.AccessToken) {
                        Write-Verbose "Access token exists, refreshing Entra role definitions..."
                        try {
                            $refreshSuccess = Update-EntraRoles -ErrorAction Stop
                            if (-not $refreshSuccess) {
                                Write-Warning "Failed to initialize role definitions"
                            }
                        }
                        catch {
                            Write-Warning "Error initializing role definitions: $_"
                        }
                    }
                    else {
                        Write-Warning "No access token found. You must authenticate first with Connect-Entra or Connect-MSGraph"
                    }
                }

                # Now try to use the roles (whether they were just refreshed or already existed)
                if ($null -ne $script:SessionVariables -and $null -ne $script:SessionVariables.Roles) {
                    $roleDefinition = $script:SessionVariables.Roles | Where-Object { $_.DisplayName -eq $RoleName } | Select-Object -First 1

                    if ($roleDefinition) {
                        $roleId = $roleDefinition.Id
                    }
                    else {
                        Write-Warning "Could not find role definition for: $RoleName"
                        throw "Role '$RoleName' not found. Check the role name or provide a role ID directly."
                    }
                }
                else {
                    throw "Session variables for roles not available. Ensure you're connected with Connect-Entra before calling this function."
                }

                Write-Host "Using role: $RoleName (ID: $roleId)" -ForegroundColor Cyan
            } else {
                $roleId = $RoleId
                $roleDefinition = $null

                # Check if session variables need to be initialized
                if ($null -eq $script:SessionVariables -or $null -eq $script:SessionVariables.Roles -or $script:SessionVariables.Roles.Count -lt 10) {
                    Write-Verbose "Role session variables not available or incomplete. Attempting to initialize them..."

                    # Check if we have an access token before trying to update roles
                    if ($script:SessionVariables -and $script:SessionVariables.AccessToken) {
                        Write-Verbose "Access token exists, refreshing Entra role definitions..."
                        try {
                            $refreshSuccess = Update-EntraRoles -ErrorAction Stop
                            if (-not $refreshSuccess) {
                                Write-Warning "Failed to initialize role definitions"
                            }
                        }
                        catch {
                            Write-Warning "Error initializing role definitions: $_"
                        }
                    }
                    else {
                        Write-Warning "No access token found. You must authenticate first with Connect-Entra or Connect-MSGraph"
                    }
                }

                # Try to use the role ID to get the display name
                if ($null -ne $script:SessionVariables -and $null -ne $script:SessionVariables.Roles) {
                    $roleDefinition = $script:SessionVariables.Roles | Where-Object { $_.Id -eq $roleId } | Select-Object -First 1

                    if ($roleDefinition) {
                        $RoleName = $roleDefinition.DisplayName
                        Write-Host "Using role: $RoleName (ID: $roleId)" -ForegroundColor Cyan
                    }
                    else {
                        Write-Host "Using role with ID: $roleId" -ForegroundColor Cyan
                    }
                }
                else {
                    Write-Host "Using role with ID: $roleId" -ForegroundColor Cyan
                }
            }

            $script:RoleName = $RoleName
            $script:RoleId = $roleId

            try {
                $allRoleAssignments = Invoke-MsGraph -relativeUrl "roleManagement/directory/roleAssignments" -OutputFormat Object
                if (-not $allRoleAssignments -or $allRoleAssignments.Count -eq 0) {
                    Write-Warning "No role assignments were returned. This may be due to permissions issues."
                    throw "No role assignments found. Check that you have Directory.Read.All permissions."
                }

                $targetRoleAssignments = $allRoleAssignments | Where-Object { $_.roleDefinitionId -eq $roleId }

                if (-not $targetRoleAssignments -or $targetRoleAssignments.Count -eq 0) {
                    Write-Host "No $RoleName assignments found" -ForegroundColor Yellow
                    return $null
                }

                Write-Host "Found $($targetRoleAssignments.Count) $RoleName assignments" -ForegroundColor Cyan
            }
            catch {
                Write-Warning "Error retrieving role assignments: $($_.Exception.Message)"
                throw "Failed to retrieve role assignments. Check your permissions and network connectivity."
            }
            $script:roleMembers = [System.Collections.Generic.List[PSCustomObject]]::new()
            $script:principalTypes = @{
                "User" = 0
                "Group" = 0
                "ServicePrincipal" = 0
                "Unknown" = 0
            }

            $principalIdToAssignment = @{}
            foreach ($assignment in $targetRoleAssignments) {
                $principalId = $assignment.principalId

                if ($principalId -match '^[0-9]{1,2}$' -or $principalId.Length -lt 5) {
                    Write-Verbose "Skipping invalid principal ID: $principalId"
                    continue
                }

                $principalIdToAssignment[$principalId] = $assignment
            }

            $uniquePrincipalIds = @($principalIdToAssignment.Keys)
            $script:roleMembers = [System.Collections.Generic.List[PSCustomObject]]::new()
            $principalDetails = @{}
            $script:principalTypes = @{
                "User" = 0
                "Group" = 0
                "ServicePrincipal" = 0
                "Unknown" = 0
            }

            $batchSize = 20
            for ($i = 0; $i -lt $uniquePrincipalIds.Count; $i += $batchSize) {
                $batchPrincipalIds = $uniquePrincipalIds[$i..([Math]::Min($i + $batchSize - 1, $uniquePrincipalIds.Count - 1))]

                Get-PrincipalDetails -PrincipalIds $batchPrincipalIds -ResultHashtable $principalDetails

                foreach ($principalId in $batchPrincipalIds) {
                    if ($principalDetails.ContainsKey($principalId)) {
                        $script:principalTypes[$principalDetails[$principalId].Type]++
                    }
                    else {
                        $script:principalTypes["Unknown"]++
                    }
                }

                foreach ($principalId in $batchPrincipalIds) {
                    $principalInfo = $principalDetails[$principalId]
                    $assignment = $principalIdToAssignment[$principalId]
                    $details = $principalInfo.Details
                    $isUnknown = ($principalInfo.Type -eq "Unknown" -or $null -eq $details)

                    $roleMember = [PSCustomObject]@{
                        PrincipalId          = $principalId
                        PrincipalType        = $isUnknown ? "Unknown" : $principalInfo.Type
                        DisplayName          = $isUnknown ? "Possibly Deleted or Inaccessible Object" : $details.displayName
                        UserPrincipalName    = ($principalInfo.Type -eq "User" -and $details) ? $details.userPrincipalName : $null
                        Email                = $details ? $details.mail : $null
                        AccountEnabled       = ($principalInfo.Type -eq "User" -and $details) ? $details.accountEnabled : $null
                        AssignmentId         = $assignment.id
                        AssignmentScope      = $assignment.directoryScopeId
                        RoleName             = $RoleName
                        RoleId               = $roleId
                        Status               = $isUnknown ? "Possibly Deleted or Inaccessible" : "Active"
                    }

                    $script:roleMembers.Add($roleMember)
                }
            }

            if ($ShowSummary) {
                $duration = (Get-Date) - $startTime

                Write-Host "`n📊 Role Member Discovery Summary:" -ForegroundColor Magenta
                Write-Host "   Role: $RoleName (ID: $roleId)" -ForegroundColor Cyan
                Write-Host "   Total Members Found: $($script:roleMembers.Count)" -ForegroundColor Green

                $principalTypeSummary = $script:roleMembers | Group-Object PrincipalType
                foreach ($group in $principalTypeSummary) {
                    $color = switch ($group.Name) {
                        "User"             { "Green" }
                        "Group"            { "Yellow" }
                        "ServicePrincipal" { "Cyan" }
                        "Unknown"          { "Red" }
                        default            { "White" }
                    }
                    Write-Host "   $($group.Name): $($group.Count)" -ForegroundColor $color
                }

                if ($script:principalTypes["User"] -gt 0) {
                    $enabledUsers = $script:roleMembers | Where-Object { $_.PrincipalType -eq "User" -and $_.AccountEnabled -eq $true } | Measure-Object
                    $disabledUsers = $script:roleMembers | Where-Object { $_.PrincipalType -eq "User" -and $_.AccountEnabled -eq $false } | Measure-Object

                    if ($enabledUsers.Count -gt 0) {
                        Write-Host "   Enabled Users: $($enabledUsers.Count)" -ForegroundColor Green
                    }
                    if ($disabledUsers.Count -gt 0) {
                        Write-Host "   Disabled Users: $($disabledUsers.Count)" -ForegroundColor Yellow
                    }
                }

                $directoryScopes = $script:roleMembers | Where-Object { $_.AssignmentScope -ne "/" } | Measure-Object
                if ($directoryScopes.Count -gt 0) {
                    Write-Host "   Scoped Assignments: $($directoryScopes.Count)" -ForegroundColor Yellow
                }

                if ($script:principalTypes["Group"] -gt 0) {
                    Write-Host "`n⚠️  Note: Group members also inherit this role but are not included in this count" -ForegroundColor Yellow
                }

                Write-Host "   Duration: $($duration.TotalSeconds.ToString('F2')) seconds" -ForegroundColor White
                Write-Host "   Processing Rate: $([math]::Round($script:roleMembers.Count / $duration.TotalSeconds, 2)) principals/second" -ForegroundColor White

                Write-Host "`n✅ Role member analysis completed successfully!" -ForegroundColor Green
            }

            $processingRate = if ($script:roleMembers.Count -gt 0 -and $duration.TotalSeconds -gt 0) {
                [math]::Round($script:roleMembers.Count / $duration.TotalSeconds, 2)
            } else { 0 }

            Write-Verbose "Processed $($script:roleMembers.Count) role members at $processingRate items/second"

            $formatParam = @{
                Data         = $script:roleMembers
                OutputFormat = $OutputFormat
                FunctionName = $MyInvocation.MyCommand.Name
                FilePrefix   = "$($RoleName.Replace(' ', ''))-Members"
            }

            try {
                return Format-BlackCatOutput @formatParam
            }
            catch {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Error formatting output: $($_.Exception.Message)" -Severity 'Warning'
                return $script:roleMembers
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
            return $null
        }
    } # End of process block

    end {
        # Calculate performance metrics
        $endTime = Get-Date
        $duration = $endTime - $startTime
        $totalSeconds = $duration.TotalSeconds

        # Log completion metrics
        if (-not $ShowSummary) {
            Write-Verbose "Function completed in $($totalSeconds.ToString('F2')) seconds"

            # Write detailed metrics to log if available
            $metrics = @{
                FunctionName = $MyInvocation.MyCommand.Name
                DurationSeconds = $totalSeconds
                RoleName = $script:RoleName
                RoleId = $script:RoleId
                MemberCount = $script:roleMembers?.Count ?? 0
                UserCount = $script:principalTypes["User"]
                GroupCount = $script:principalTypes["Group"]
                ServicePrincipalCount = $script:principalTypes["ServicePrincipal"]
                UnknownCount = $script:principalTypes["Unknown"]
            }
        }
    }

<#
.SYNOPSIS
    Gets all members of a specified Microsoft Entra ID (Azure AD) role.

.DESCRIPTION
    The Get-EntraRoleMember function identifies all members (users, groups, or service principals)
    assigned to a specific Entra ID role. It first identifies the role definition by name or ID,
    then finds all assignments for that role, and determines the principal type and details
    for each assignment.

.PARAMETER RoleName
    Specifies the display name of the Entra ID role to query. This parameter has tab completion
    for all available Entra ID roles. Default is "Global Administrator".

.PARAMETER RoleId
    Specifies the ID of the Entra ID role to query. If provided, this takes precedence over RoleName.

.PARAMETER ShowSummary
    When specified, displays a summary of the role members including counts by principal type
    and execution duration.

.PARAMETER OutputFormat
    Specifies the output format of the results. Valid values are:
    - Object: Returns PowerShell objects (default for pipeline operations)
    - JSON: Returns a JSON string
    - CSV: Returns a CSV string
    - Table: Displays the results as a formatted table (default)

.EXAMPLE
    Get-EntraRoleMember
    Retrieves all Global Administrators in the tenant (default role) and displays them in a table format.

.EXAMPLE
    Get-EntraRoleMember -RoleName "User Administrator" -OutputFormat JSON
    Retrieves all User Administrators and exports the results to a JSON file.

.EXAMPLE
    Get-EntraRoleMember -RoleName "Conditional Access Administrator" -ShowSummary
    Retrieves all Conditional Access Administrators and displays a summary of the results.

.EXAMPLE
    Get-EntraRoleMember -RoleId "9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3" -OutputFormat Object
    Retrieves members of the role with the specified ID and returns them as PowerShell objects.
#>
}
