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
        
        # Start timing analytics
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        $privilegedPermissions = @{
            # Critical permissions - can read/write anything
            'Directory.ReadWrite.All'                     = @{ Name = 'Directory.ReadWrite.All'; Criticality = 'Critical'; Description = 'Read and write directory data' }
            'Application.ReadWrite.All'                   = @{ Name = 'Application.ReadWrite.All'; Criticality = 'Critical'; Description = 'Read and write all applications' }
            'AppRoleAssignment.ReadWrite.All'             = @{ Name = 'AppRoleAssignment.ReadWrite.All'; Criticality = 'Critical'; Description = 'Manage app role assignments for any app' }
            'RoleManagement.ReadWrite.Directory'          = @{ Name = 'RoleManagement.ReadWrite.Directory'; Criticality = 'Critical'; Description = 'Read and write role management data' }
            'Domain.ReadWrite.All'                        = @{ Name = 'Domain.ReadWrite.All'; Criticality = 'Critical'; Description = 'Read and write domains' }
            
            # High permissions - significant access
            'User.ReadWrite.All'                          = @{ Name = 'User.ReadWrite.All'; Criticality = 'High'; Description = 'Read and write all users' }
            'Group.ReadWrite.All'                         = @{ Name = 'Group.ReadWrite.All'; Criticality = 'High'; Description = 'Read and write all groups' }
            'Directory.Read.All'                          = @{ Name = 'Directory.Read.All'; Criticality = 'High'; Description = 'Read directory data' }
            'Application.Read.All'                        = @{ Name = 'Application.Read.All'; Criticality = 'High'; Description = 'Read all applications' }
            'DeviceManagementConfiguration.ReadWrite.All' = @{ Name = 'DeviceManagementConfiguration.ReadWrite.All'; Criticality = 'High'; Description = 'Read and write device management configuration' }
            'Policy.ReadWrite.All'                        = @{ Name = 'Policy.ReadWrite.All'; Criticality = 'High'; Description = 'Read and write organization policies' }
            'RoleManagement.Read.Directory'               = @{ Name = 'RoleManagement.Read.Directory'; Criticality = 'High'; Description = 'Read role management data' }
            'PrivilegedAccess.ReadWrite.AzureAD'          = @{ Name = 'PrivilegedAccess.ReadWrite.AzureAD'; Criticality = 'High'; Description = 'Read and write privileged access settings' }
            
            # Medium permissions - moderate access
            'User.Read.All'                               = @{ Name = 'User.Read.All'; Criticality = 'Medium'; Description = 'Read all users' }
            'Group.Read.All'                              = @{ Name = 'Group.Read.All'; Criticality = 'Medium'; Description = 'Read all groups' }
            'Mail.ReadWrite'                              = @{ Name = 'Mail.ReadWrite'; Criticality = 'Medium'; Description = 'Read and write mail' }
            'Files.ReadWrite.All'                         = @{ Name = 'Files.ReadWrite.All'; Criticality = 'Medium'; Description = 'Read and write all files' }
            'Sites.ReadWrite.All'                         = @{ Name = 'Sites.ReadWrite.All'; Criticality = 'Medium'; Description = 'Read and write all site collections' }
            'DeviceManagementConfiguration.Read.All'      = @{ Name = 'DeviceManagementConfiguration.Read.All'; Criticality = 'Medium'; Description = 'Read device management configuration' }
            
            # Low permissions - limited but notable access
            'Mail.Read'                                   = @{ Name = 'Mail.Read'; Criticality = 'Low'; Description = 'Read mail' }
            'Files.Read.All'                              = @{ Name = 'Files.Read.All'; Criticality = 'Low'; Description = 'Read all files' }
            'Calendars.ReadWrite'                         = @{ Name = 'Calendars.ReadWrite'; Criticality = 'Low'; Description = 'Read and write calendars' }
        }

        if ($Criticality -ne 'All') {
            $privilegedPermissions = $privilegedPermissions.GetEnumerator() | Where-Object { $_.Value.Criticality -eq $Criticality } | ForEach-Object { @{ $_.Key = $_.Value } }
            Write-Verbose "Filtered to $($privilegedPermissions.Count) $Criticality permissions"
        }

        Write-Output "Loaded $($privilegedPermissions.Count) privileged permissions"
    }

    process {
        try {
            Write-Verbose "Retrieving service principals with optimized query"
            $queryUrl = "servicePrincipals?`$filter=servicePrincipalType eq 'Application'&`$select=id,appId,displayName,servicePrincipalType,accountEnabled,createdDateTime"
            
            $servicePrincipals = Invoke-MsGraph -relativeUrl $queryUrl
            
            if (-not $servicePrincipals) {
                Write-Warning "No service principals found."
                return
            }
            
            Write-Verbose "Retrieved $($servicePrincipals.Count) application service principals"
            
            $resourceCache = @{}
            
            $results = @()
            $totalCount = $servicePrincipals.Count
            
            if ($ServicePrincipalName) {
                $servicePrincipals = $servicePrincipals | Where-Object { $_.displayName -like "*$ServicePrincipalName*" }
                Write-Verbose "Filtered to $($servicePrincipals.Count) service principals matching name pattern"
            }
            
            if ($servicePrincipals.Count -eq 0) {
                Write-Verbose "No service principals to process after filtering"
                return $null
            }
            
            Write-Verbose "Processing $($servicePrincipals.Count) service principals for privileged permissions using batch processing"
            
            $allBatchRequests = @()
            $requestMap = @{}
            
            for ($i = 0; $i -lt $servicePrincipals.Count; $i++) {
                $sp = $servicePrincipals[$i]
                
                $appRoleRequestId = "appRole_$i"
                $allBatchRequests += @{
                    id = $appRoleRequestId
                    method = "GET"
                    url = "/servicePrincipals/$($sp.id)/appRoleAssignments?`$select=resourceId,appRoleId"
                }
                $requestMap[$appRoleRequestId] = @{ ServicePrincipal = $sp; Type = "AppRole" }
                
                $oauth2RequestId = "oauth2_$i"
                $allBatchRequests += @{
                    id = $oauth2RequestId
                    method = "GET"
                    url = "/servicePrincipals/$($sp.id)/oauth2PermissionGrants?`$select=resourceId,scope"
                }
                $requestMap[$oauth2RequestId] = @{ ServicePrincipal = $sp; Type = "OAuth2" }
            }
            
            Write-Verbose "Created $($allBatchRequests.Count) batch requests for $($servicePrincipals.Count) service principals"
            
            $batchAnalytics = @{
                TotalBatches = [math]::Ceiling($allBatchRequests.Count / 10.0)
                SuccessfulBatches = 0
                FailedBatches = 0
                IndividualFallbacks = 0
                BatchStartTime = Get-Date
            }
            
            $allBatchResponses = @{}
            $batchSize = 20
            
            for ($batchIndex = 0; $batchIndex -lt $allBatchRequests.Count; $batchIndex += $batchSize) {
                $batchRequests = $allBatchRequests[$batchIndex..([Math]::Min($batchIndex + $batchSize - 1, $allBatchRequests.Count - 1))]
                
                Write-Verbose "Executing batch $([Math]::Floor($batchIndex / $batchSize) + 1) with $($batchRequests.Count) requests"
                
                try {
                    $batchPayload = @{
                        requests = $batchRequests
                    } | ConvertTo-Json -Depth 10
                    
                    $batchResponse = Invoke-RestMethod -Uri "$($sessionVariables.graphUri)/`$batch" -Method POST -Headers $script:graphHeader -ContentType "application/json" -Body $batchPayload -UserAgent $sessionVariables.userAgent
                    
                    foreach ($response in $batchResponse.responses) {
                        if ($response.status -eq 200 -and $response.body) {
                            $allBatchResponses[$response.id] = $response.body
                        } else {
                            Write-Verbose "Request $($response.id) failed with status $($response.status)"
                        }
                    }
                    $batchAnalytics.SuccessfulBatches++
                }
                catch {
                    Write-Warning "Batch request failed: $($_.Exception.Message). Falling back to individual calls for this batch."
                    $batchAnalytics.FailedBatches++
                    
                    foreach ($request in $batchRequests) {
                        try {
                            $url = $request.url.TrimStart('/')
                            $individualResponse = Invoke-MsGraph -relativeUrl $url -NoBatch -OutputFormat Object -ErrorAction SilentlyContinue
                            if ($individualResponse) {
                                $allBatchResponses[$request.id] = $individualResponse
                            }
                            $batchAnalytics.IndividualFallbacks++
                        }
                        catch {
                            Write-Verbose "Individual fallback request failed for $($request.id)"
                        }
                    }
                }
            }
            
            $batchAnalytics.BatchEndTime = Get-Date
            $batchAnalytics.BatchProcessingTime = ($batchAnalytics.BatchEndTime - $batchAnalytics.BatchStartTime).TotalSeconds
            
            Write-Verbose "Completed batch processing. Processing responses for $($servicePrincipals.Count) service principals"
            
            for ($i = 0; $i -lt $servicePrincipals.Count; $i++) {
                $sp = $servicePrincipals[$i]
                $foundPermissions = @()
                
                # Show progress every 50 SPs
                if ($i % 50 -eq 0) {
                    Write-Verbose "Processing service principal $($i + 1) of $($servicePrincipals.Count): $($sp.displayName)"
                }
                
                $appRoleRequestId = "appRole_$i"
                if ($allBatchResponses.ContainsKey($appRoleRequestId)) {
                    $appRoleData = $allBatchResponses[$appRoleRequestId]
                    $appRoleAssignments = if ($appRoleData.value) { $appRoleData.value } else { $appRoleData }
                    
                    if ($appRoleAssignments) {
                        foreach ($appRole in $appRoleAssignments) {
                            try {
                                $resource = $null
                                if ($resourceCache.ContainsKey($appRole.resourceId)) {
                                    $resource = $resourceCache[$appRole.resourceId]
                                }
                                else {
                                    $resource = Invoke-MsGraph -relativeUrl "servicePrincipals/$($appRole.resourceId)?`$select=displayName,appRoles" -NoBatch -OutputFormat Object -ErrorAction SilentlyContinue
                                    if ($resource) {
                                        $resourceCache[$appRole.resourceId] = $resource
                                    }
                                }
                                
                                if ($resource -and $resource.appRoles) {
                                    # Find the specific app role
                                    $roleDefinition = $resource.appRoles | Where-Object { $_.id -eq $appRole.appRoleId }
                                    
                                    if ($roleDefinition -and $privilegedPermissions.ContainsKey($roleDefinition.value)) {
                                        $foundPermissions += @{
                                            PermissionName = $roleDefinition.value
                                            PermissionType = 'Application'
                                            Resource = $resource.displayName
                                            Criticality = $privilegedPermissions[$roleDefinition.value].Criticality
                                            Description = $privilegedPermissions[$roleDefinition.value].Description
                                        }
                                        Write-Verbose "Found privileged app permission: $($roleDefinition.value) on $($sp.displayName)"
                                    }
                                }
                            }
                            catch {
                                # Silently continue
                            }
                        }
                    }
                }
                
                $oauth2RequestId = "oauth2_$i"
                if ($allBatchResponses.ContainsKey($oauth2RequestId)) {
                    $oauth2Data = $allBatchResponses[$oauth2RequestId]
                    $oauth2Grants = if ($oauth2Data.value) { $oauth2Data.value } else { $oauth2Data }
                    
                    if ($oauth2Grants) {
                        foreach ($grant in $oauth2Grants) {
                            if ($grant.scope) {
                                $scopes = $grant.scope -split '\s+'
                                foreach ($scope in $scopes) {
                                    if ($privilegedPermissions.ContainsKey($scope)) {
                                        try {
                                            $resource = $null
                                            if ($resourceCache.ContainsKey($grant.resourceId)) {
                                                $resource = $resourceCache[$grant.resourceId]
                                            }
                                            else {
                                                $resource = Invoke-MsGraph -relativeUrl "servicePrincipals/$($grant.resourceId)?`$select=displayName" -NoBatch -OutputFormat Object -ErrorAction SilentlyContinue
                                                if ($resource) {
                                                    $resourceCache[$grant.resourceId] = $resource
                                                }
                                            }
                                            
                                            $foundPermissions += @{
                                                PermissionName = $scope
                                                PermissionType = 'Delegated'
                                                Resource = if ($resource) { $resource.displayName } else { 'Unknown' }
                                                Criticality = $privilegedPermissions[$scope].Criticality
                                                Description = $privilegedPermissions[$scope].Description
                                            }
                                            Write-Verbose "Found privileged delegated permission: $scope on $($sp.displayName)"
                                        }
                                        catch {
                                            # Silently continue
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                if ($PermissionPattern -and $foundPermissions.Count -gt 0) {
                    $foundPermissions = $foundPermissions | Where-Object { $_.PermissionName -like "*$PermissionPattern*" }
                }
                
                if ($foundPermissions.Count -gt 0) {
                    # Get the highest criticality level
                    $highestCriticality = ($foundPermissions.Criticality | ForEach-Object {
                            switch ($_) {
                                "Critical" { 4 }
                                "High" { 3 }
                                "Medium" { 2 }
                                "Low" { 1 }
                                default { 0 }
                            }
                        } | Measure-Object -Maximum).Maximum
                    
                    $criticalityName = switch ($highestCriticality) {
                        4 { "Critical" }
                        3 { "High" }
                        2 { "Medium" }
                        1 { "Low" }
                        default { "Unknown" }
                    }
                    
                    $results += [PSCustomObject]@{
                        Id                   = $sp.id
                        AppId                = $sp.appId
                        DisplayName          = $sp.displayName
                        PermissionCount      = $foundPermissions.Count
                        Permissions          = $foundPermissions
                        HighestCriticality   = $criticalityName
                        ServicePrincipalType = $sp.servicePrincipalType
                        IsEnabled            = $sp.accountEnabled
                        CreatedDateTime      = $sp.createdDateTime
                    }
                    
                    Write-Verbose "Added privileged SP: $($sp.displayName) with $($foundPermissions.Count) permissions"
                }
            }
            
            Write-Verbose "Completed processing. Found $($results.Count) privileged service principals from $($servicePrincipals.Count) processed (reduced from $totalCount total)"
            
            $results = $results | Sort-Object -Property @{
                Expression = {
                    switch ($_.HighestCriticality) {
                        "Critical" { 4 }
                        "High" { 3 }
                        "Medium" { 2 }
                        "Low" { 1 }
                        default { 0 }
                    }
                }
            }, DisplayName -Descending
            
            if ($results.Count -eq 0) {
                Write-Host "No privileged service principals found matching the criteria." -ForegroundColor Yellow
                return $null
            }
            else {
                Write-Host "Found $($results.Count) privileged service principals." -ForegroundColor Green
                
                $formatParam = @{
                    Data         = $results
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
        $stopwatch.Stop()
        $elapsedTime = $stopwatch.Elapsed
        $totalSeconds = [math]::Round($elapsedTime.TotalSeconds, 2)
        
        Write-Host "`n=== Execution Analytics ===" -ForegroundColor Cyan
        Write-Host "Total execution time: $totalSeconds seconds" -ForegroundColor Green
        
        # Show batch processing analytics if available
        if ($batchAnalytics) {
            $batchTime = [math]::Round($batchAnalytics.BatchProcessingTime, 2)
            $batchEfficiency = if ($batchAnalytics.TotalBatches -gt 0) { 
                [math]::Round(($batchAnalytics.SuccessfulBatches / $batchAnalytics.TotalBatches) * 100, 1)
            } else { 0 }
            
            Write-Host "`nBatch Processing Analytics:" -ForegroundColor Yellow
            Write-Host "  - Total batches: $($batchAnalytics.TotalBatches)" -ForegroundColor White
            Write-Host "  - Successful batches: $($batchAnalytics.SuccessfulBatches)" -ForegroundColor Green
            Write-Host "  - Failed batches: $($batchAnalytics.FailedBatches)" -ForegroundColor Red
            Write-Host "  - Individual fallbacks: $($batchAnalytics.IndividualFallbacks)" -ForegroundColor Yellow
            Write-Host "  - Batch efficiency: $batchEfficiency%" -ForegroundColor Cyan
            Write-Host "  - Batch processing time: $batchTime seconds" -ForegroundColor White
        }
        
        Write-Host "`nTime breakdown:" -ForegroundColor Yellow
        Write-Host "  - Minutes: $($elapsedTime.Minutes)" -ForegroundColor White
        Write-Host "  - Seconds: $($elapsedTime.Seconds)" -ForegroundColor White
        Write-Host "  - Milliseconds: $($elapsedTime.Milliseconds)" -ForegroundColor White
        Write-Host "  - Total seconds: $totalSeconds" -ForegroundColor Cyan
        
        Write-Verbose "Completed function $($MyInvocation.MyCommand.Name) in $totalSeconds seconds"
    }

    <#
    .SYNOPSIS
        Discovers service principals with privileged permissions in Entra ID.

    .DESCRIPTION
        This function identifies service principals that have been granted privileged permissions in Entra ID.
        It checks both application permissions (app roles) and delegated permissions (OAuth2 scopes) to identify
        service principals with high-risk access. Permissions are categorized by criticality level (Critical, High, Medium, Low).

    .PARAMETER Criticality
        Filter results by permission criticality level.
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

        Returns all service principals with Critical permissions and displays them in a table format.

    .EXAMPLE
        Get-PrivilegedServicePrincipal -PermissionPattern "*ReadWrite*"

        Returns all service principals with permissions containing "ReadWrite".

    .EXAMPLE
        Get-PrivilegedServicePrincipal -ServicePrincipalName "Azure" -OutputFormat JSON

        Returns all service principals with "Azure" in their name that have privileged permissions and exports the results as JSON.

        Performs a stealthy scan of only the first 50 service principals looking for Critical permissions.

    .NOTES
        Requires the BlackCat module and appropriate Entra ID permissions to enumerate service principals and their permissions.
        
        Privileged permissions checked include:
        - Critical: Directory.ReadWrite.All, Application.ReadWrite.All, AppRoleAssignment.ReadWrite.All
        - High: User.ReadWrite.All, Group.ReadWrite.All, Directory.Read.All
        - Medium: User.Read.All, Group.Read.All, Mail.ReadWrite, Files.ReadWrite.All
        - Low: Mail.Read, Files.Read.All, Calendars.ReadWrite
    #>
}