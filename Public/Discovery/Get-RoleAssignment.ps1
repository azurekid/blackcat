function Get-RoleAssignment {
    [cmdletbinding()]
    [OutputType([System.Collections.Concurrent.ConcurrentBag[PSCustomObject]])]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('current-user')]
        [switch]$CurrentUser,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [ValidateSet('User', 'Group', 'ServicePrincipal')]
        [Alias('principal-type')]
        [string]$PrincipalType,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('is-custom')]
        [switch]$IsCustom,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('object-id', 'PrincipalId', 'principal-id', 'id')]
        [string]$ObjectId,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[0-9a-fA-F-]{36}$', ErrorMessage = "It does not match expected pattern '{1}'")]
        [Alias('subscription-id')]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('exclude-custom')]
        [switch]$ExcludeCustom,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('throttle-limit')]
        [int]$ThrottleLimit = 10,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Object", "JSON", "CSV", "Table")]
        [Alias("output", "o")]
        [string]$OutputFormat = "Table",

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('include-eligible', 'eligible')]
        [switch]$IncludeEligible,

        [Parameter(Mandatory = $false)]
        [Alias('skip-cache')]
        [switch]$SkipCache,

        [Parameter(Mandatory = $false)]
        [Alias('cache-expiration')]
        [int]$CacheExpirationMinutes = 60,

        [Parameter(Mandatory = $false)]
        [Alias('max-cache-size')]
        [int]$MaxCacheSize = 100,

        [Parameter(Mandatory = $false)]
        [Alias('compress-cache')]
        [switch]$CompressCache
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        
        # Only use MSGraph authentication if CurrentUser is specified
        if ($CurrentUser) {
            $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
        } else {
            $MyInvocation.MyCommand.Name | Invoke-BlackCat
        }

        $startTime = Get-Date
        Write-Host " Starting Azure RBAC Role Assignment Analysis..." -ForegroundColor Green
        
        if ($CurrentUser) {
            Write-Host "   Mode: Current User Analysis" -ForegroundColor Cyan
        }
        if ($PrincipalType) {
            Write-Host "   Filter: Principal Type = $PrincipalType" -ForegroundColor Cyan
        }
        if ($ObjectId) {
            Write-Host "  🆔 Filter: Object ID = $ObjectId" -ForegroundColor Cyan
        }
        if ($SubscriptionId) {
            Write-Host "   Scope: Specific Subscription = $SubscriptionId" -ForegroundColor Cyan
        }
        if ($IsCustom) {
            Write-Host "   Filter: Custom Roles Only" -ForegroundColor Cyan
        }
        if ($ExcludeCustom) {
            Write-Host "   Filter: Excluding Custom Role Details" -ForegroundColor Cyan
        }
        if ($IncludeEligible) {
            Write-Host "   Include: PIM Eligible Role Assignments" -ForegroundColor Cyan
        }

        $roleAssignmentsList = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()
        $subscriptions = @()
        $randomUserAgent = $script:SessionVariables.userAgent
    }

    process {
        # Create cache key based on function parameters
        $cacheKeyParams = @{
            CurrentUser = $CurrentUser.ToString()
            PrincipalType = $PrincipalType
            ObjectId = $ObjectId
            SubscriptionId = $SubscriptionId
            IsCustom = $IsCustom.ToString()
            ExcludeCustom = $ExcludeCustom.ToString()
            IncludeEligible = $IncludeEligible.ToString()
        }
        $cacheKey = ConvertTo-CacheKey -BaseIdentifier "Get-RoleAssignment" -Parameters $cacheKeyParams

        # Try to get cached results first
        if (-not $SkipCache) {
            $cachedResults = Get-BlackCatCache -Key $cacheKey -CacheType 'MSGraph'
            if ($null -ne $cachedResults) {
                Write-Host " Retrieved role assignments from cache" -ForegroundColor Green
                
                # Return cached results in requested format
                switch ($OutputFormat) {
                    "JSON" {
                        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                        $jsonOutput = $cachedResults | ConvertTo-Json -Depth 3
                        $jsonFilePath = "RoleAssignments_$timestamp.json"
                        $jsonOutput | Out-File -FilePath $jsonFilePath -Encoding UTF8
                        Write-Host " JSON output saved to: $jsonFilePath" -ForegroundColor Green
                        return
                    }
                    "CSV" {
                        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                        $csvOutput = $cachedResults | ConvertTo-Csv -NoTypeInformation
                        $csvFilePath = "RoleAssignments_$timestamp.csv"
                        $csvOutput | Out-File -FilePath $csvFilePath -Encoding UTF8
                        Write-Host " CSV output saved to: $csvFilePath" -ForegroundColor Green
                        return
                    }
                    "Object" { return $cachedResults }
                    "Table" { return $cachedResults | Format-Table -Property PrincipalType, PrincipalId, RoleName, Scope -AutoSize }
                }
            }
        }

        try {
            # Cache subscription retrieval separately for better performance
            $subscriptionCacheKey = ConvertTo-CacheKey -BaseIdentifier "Get-RoleAssignment-Subscriptions" -Parameters @{
                SubscriptionId = $SubscriptionId
            }
            
            $subscriptionOperation = {
                Write-Host " Retrieving all subscriptions for the current user context..." -ForegroundColor Green
                $baseUri = 'https://management.azure.com'
                
                if ($SubscriptionId) {
                    # Request specific subscription
                    $subscriptionsUri = "$($baseUri)/subscriptions/$SubscriptionId?api-version=2020-01-01"
                } else {
                    # Request all subscriptions
                    $subscriptionsUri = "$($baseUri)/subscriptions?api-version=2020-01-01"
                }
                
                $requestParam = @{
                    Headers = $script:authHeader
                    Uri     = $subscriptionsUri
                    Method  = 'GET'
                }

                if ($SubscriptionId) {
                    # Single subscription response
                    $subscriptionResponse = Invoke-RestMethod @requestParam
                    $retrievedSubscriptions = @($subscriptionResponse.subscriptionId)
                } else {
                    # Multiple subscriptions response
                    $retrievedSubscriptions = (Invoke-RestMethod @requestParam).value.subscriptionId
                }
                
                Write-Host "   Found $($retrievedSubscriptions.Count) accessible subscriptions" -ForegroundColor Cyan
                return $retrievedSubscriptions
            }

            $subscriptions = Invoke-CacheableOperation -CacheKey $subscriptionCacheKey -CacheType 'MSGraph' -Operation $subscriptionOperation -SkipCache $SkipCache -CacheExpirationMinutes $CacheExpirationMinutes -MaxCacheSize $MaxCacheSize -CompressCache $CompressCache -OperationName "subscription retrieval"

        }
        catch {
            Write-Host " Error retrieving subscriptions: $($_.Exception.Message)" -ForegroundColor Red
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }

        # Main role assignment processing wrapped in cacheable operation
        $roleAssignmentOperation = {
            param($CurrentUserFlag, $ObjectIdParam, $SubscriptionsParam, $PrincipalTypeParam, $IsCustomParam, $ExcludeCustomParam, $IncludeEligibleParam, $ThrottleLimitParam)
            
            $roleAssignmentsList = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()
            $randomUserAgent = $script:SessionVariables.userAgent
            $baseUri = 'https://management.azure.com'

            try {
                $ObjectId = $ObjectIdParam
                $Groups = @()
                $principalType = $null
                
                if ($CurrentUserFlag) {
                    # Detect authentication type from Azure context
                    $azContext = Get-AzContext
                    $accountType = $azContext.Account.Type
                    
                    if ($accountType -eq 'ServicePrincipal') {
                        # Service Principal authentication - use Graph API to get SP's object ID
                        Write-Host "   Retrieving current Service Principal's object ID..." -ForegroundColor Yellow
                        $appId = $azContext.Account.Id
                        $spObject = Invoke-MsGraph -relativeUrl "servicePrincipals?`$filter=appId eq '$appId'" -NoBatch
                        $ObjectId = $spObject.value[0].id
                        $principalType = 'ServicePrincipal'
                        Write-Host "     Current Service Principal ID: $ObjectId" -ForegroundColor Green
                        
                        # Service Principals can also be members of groups
                        Write-Host "   Retrieving group memberships for Service Principal..." -ForegroundColor Yellow
                        try {
                            $Groups = @(Invoke-MsGraph -relativeUrl "servicePrincipals/$ObjectId/memberOf").id
                            Write-Host "     Found $($Groups.Count) group memberships" -ForegroundColor Green
                        }
                        catch {
                            Write-Verbose "Could not retrieve group memberships for Service Principal: $($_.Exception.Message)"
                        }
                    }
                    else {
                        # User authentication - use /me endpoint
                        Write-Host "   Retrieving current user's object ID..." -ForegroundColor Yellow
                        $userObject = Invoke-MsGraph -relativeUrl "me" -NoBatch
                        $ObjectId = $userObject.id
                        $principalType = 'User'
                        Write-Host "     Current user ID: $ObjectId" -ForegroundColor Green
                        
                        # Get user's group memberships
                        Write-Host "   Retrieving group memberships for user: $ObjectId..." -ForegroundColor Yellow
                        $Groups = @(Invoke-MsGraph -relativeUrl "users/$ObjectId/memberOf").id
                        Write-Host "     Found $($Groups.Count) group memberships" -ForegroundColor Green
                    }
                }
                elseif ($ObjectId) {
                    Write-Host "   Retrieving group memberships for principal: $ObjectId..." -ForegroundColor Yellow
                    # Try user first, then service principal
                    try {
                        $Groups = @(Invoke-MsGraph -relativeUrl "users/$ObjectId/memberOf").id
                        Write-Host "     Found $($Groups.Count) group memberships" -ForegroundColor Green
                    }
                    catch {
                        try {
                            $Groups = @(Invoke-MsGraph -relativeUrl "servicePrincipals/$ObjectId/memberOf").id
                            Write-Host "     Found $($Groups.Count) group memberships (Service Principal)" -ForegroundColor Green
                        }
                        catch {
                            Write-Verbose "Could not retrieve group memberships: $($_.Exception.Message)"
                        }
                    }
                }

                Write-Host "   Analyzing role assignments across $($SubscriptionsParam.Count) subscriptions with $ThrottleLimitParam concurrent threads..." -ForegroundColor Cyan
                $SubscriptionsParam | ForEach-Object -Parallel {
                try {
                    $baseUri             = $using:baseUri
                    $authHeader          = $using:script:authHeader
                    $userAgent           = $using:randomUserAgent
                    $roleAssignmentsList = $using:roleAssignmentsList
                    $ObjectId            = $using:ObjectId
                    $Groups              = $using:Groups
                    $azureRoles          = $using:script:SessionVariables.AzureRoles
                    $PrincipalType       = $using:PrincipalType
                    $IsCustom            = $using:IsCustom
                    $ExcludeCustom       = $using:ExcludeCustom
                    $subscriptionId      = $_

                    Write-Verbose " Processing subscription: $subscriptionId"
                    $roleAssignmentsUri = "$($baseUri)/subscriptions/$subscriptionId/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01"

                    $principalIds = @()
                    if ($ObjectId) {
                        $principalIds += $ObjectId
                    }
                    if ($Groups.length -gt 0) {
                        $principalIds += $Groups
                    }

                    $roleAssignmentsResponse = @()
                    $roleAssignmentsRequestParam = @{
                        Headers   = $authHeader
                        Method    = 'GET'
                        Uri       = $roleAssignmentsUri
                        UserAgent = $userAgent
                    }

                    if ($principalIds) {
                        foreach ($principalId in $principalIds) {
                            $roleAssignmentsRequestParam.Uri = "$roleAssignmentsUri&`$filter=principalId eq '$principalId'"
                            $roleAssignmentsResponse += (Invoke-RestMethod @roleAssignmentsRequestParam).value
                        }
                    } else {
                        $roleAssignmentsResponse += @(Invoke-RestMethod @roleAssignmentsRequestParam).value
                    }

                    if ($PrincipalType) {
                        $roleAssignmentsResponse = $roleAssignmentsResponse | Where-Object { $_.properties.principalType -eq $PrincipalType }
                    }

                    foreach ($roleAssignment in $roleAssignmentsResponse) {
                        if ($roleAssignment.properties.principalType) {
                            $roleAssignmentObject = [PSCustomObject]@{
                                PrincipalType = $roleAssignment.properties.principalType
                                PrincipalId   = $roleAssignment.properties.principalId
                                Scope         = $roleAssignment.properties.scope
                                RoleId        = $roleAssignment.properties.roleDefinitionId -split '/' | Select-Object -Last 1
                                IsCustom      = $false
                                IsEligible    = $false
                            }

                            $roleId = ($roleAssignment.properties.roleDefinitionId -split '/')[-1]
                            $roleName = ($azureRoles | Where-Object { $_.id -match $roleId } ).Name

                            if (-not($roleName)) {
                                $roleDefinitionsUri = "$($baseUri)/subscriptions/$subscriptionId/providers/Microsoft.Authorization/roleDefinitions/$($roleId)?`$filter=type eq 'CustomRole'&api-version=2022-05-01-preview"
                                $roleDefinitionsRequestParam = @{
                                    Headers = $authHeader
                                    Uri     = $roleDefinitionsUri
                                    Method  = 'GET'
                                    UserAgent = $userAgent
                                }

                                if (-not $ExcludeCustom) {
                                    Write-Verbose " Retrieving custom role definition for subscription: $subscriptionId"
                                    $roleName = (Invoke-RestMethod @roleDefinitionsRequestParam).properties.roleName
                                }

                                $roleAssignmentObject.IsCustom = $true
                            }

                            if ($roleName) {
                                $memberObject = @{
                                    MemberType = 'NoteProperty'
                                    Name       = 'RoleName'
                                    Value      = $roleName
                                }
                                $roleAssignmentObject | Add-Member @memberObject

                                if (-not $IsCustom -or $roleAssignmentObject.IsCustom) {
                                    $roleAssignmentsList.Add($roleAssignmentObject)
                                    Write-Verbose " Found: $($roleAssignmentObject.PrincipalType) -> $roleName (Subscription: $subscriptionId)"
                                }
                            }
                        }
                    }
                }
                catch {
                    Write-Information " Error processing subscription '$subscriptionId': $($_.Exception.Message)" -InformationAction Continue
                }                } -ThrottleLimit $ThrottleLimitParam

            # Process PIM eligible role assignments if requested
            if ($IncludeEligibleParam) {
                Write-Host "   Retrieving PIM eligible role assignments..." -ForegroundColor Yellow
                
                $SubscriptionsParam | ForEach-Object -Parallel {
                    try {
                        $baseUri             = $using:baseUri
                        $authHeader          = $using:script:authHeader
                        $userAgent           = $using:randomUserAgent
                        $roleAssignmentsList = $using:roleAssignmentsList
                        $ObjectId            = $using:ObjectId
                        $Groups              = $using:Groups
                        $azureRoles          = $using:script:SessionVariables.AzureRoles
                        $PrincipalType       = $using:PrincipalType
                        $IsCustom            = $using:IsCustom
                        $ExcludeCustom       = $using:ExcludeCustom
                        $subscriptionId      = $_

                        Write-Verbose " Processing PIM eligible assignments for subscription: $subscriptionId"
                        
                        # Query PIM eligible role assignments
                        $pimUri = "$($baseUri)/subscriptions/$subscriptionId/providers/Microsoft.Authorization/roleEligibilityScheduleInstances?api-version=2020-10-01"
                        
                        $principalIds = @()
                        if ($ObjectId) {
                            $principalIds += $ObjectId
                        }
                        if ($Groups.length -gt 0) {
                            $principalIds += $Groups
                        }

                        $pimRequestParam = @{
                            Headers   = $authHeader
                            Method    = 'GET'
                            Uri       = $pimUri
                            UserAgent = $userAgent
                        }

                        $pimResponse = @()
                        if ($principalIds) {
                            foreach ($principalId in $principalIds) {
                                $pimRequestParam.Uri = "$pimUri&`$filter=principalId eq '$principalId'"
                                try {
                                    $pimResponse += (Invoke-RestMethod @pimRequestParam).value
                                }
                                catch {
                                    Write-Verbose " No PIM eligible assignments found for principal $principalId in subscription $subscriptionId"
                                }
                            }
                        } else {
                            try {
                                $pimResponse += @(Invoke-RestMethod @pimRequestParam).value
                            }
                            catch {
                                Write-Verbose " No PIM eligible assignments found in subscription $subscriptionId or insufficient permissions"
                            }
                        }

                        if ($PrincipalType) {
                            $pimResponse = $pimResponse | Where-Object { $_.properties.principalType -eq $PrincipalType }
                        }

                        foreach ($eligibleAssignment in $pimResponse) {
                            if ($eligibleAssignment.properties.principalType) {
                                $roleAssignmentObject = [PSCustomObject]@{
                                    PrincipalType = $eligibleAssignment.properties.principalType
                                    PrincipalId   = $eligibleAssignment.properties.principalId
                                    Scope         = $eligibleAssignment.properties.scope
                                    RoleId        = $eligibleAssignment.properties.roleDefinitionId -split '/' | Select-Object -Last 1
                                    IsCustom      = $false
                                    IsEligible    = $true
                                    StartDateTime = $eligibleAssignment.properties.startDateTime
                                    EndDateTime   = $eligibleAssignment.properties.endDateTime
                                    Status        = $eligibleAssignment.properties.status
                                }

                                $roleId = ($eligibleAssignment.properties.roleDefinitionId -split '/')[-1]
                                $roleName = ($azureRoles | Where-Object { $_.id -match $roleId } ).Name

                                if (-not($roleName)) {
                                    $roleDefinitionsUri = "$($baseUri)/subscriptions/$subscriptionId/providers/Microsoft.Authorization/roleDefinitions/$($roleId)?api-version=2022-05-01-preview"
                                    $roleDefinitionsRequestParam = @{
                                        Headers = $authHeader
                                        Uri     = $roleDefinitionsUri
                                        Method  = 'GET'
                                        UserAgent = $userAgent
                                    }

                                    if (-not $ExcludeCustom) {
                                        Write-Verbose " Retrieving custom role definition for PIM assignment in subscription: $subscriptionId"
                                        try {
                                            $roleName = (Invoke-RestMethod @roleDefinitionsRequestParam).properties.roleName
                                        }
                                        catch {
                                            $roleName = "Unknown Role"
                                        }
                                    }

                                    $roleAssignmentObject.IsCustom = $true
                                }

                                if ($roleName) {
                                    $memberObject = @{
                                        MemberType = 'NoteProperty'
                                        Name       = 'RoleName'
                                        Value      = $roleName
                                    }
                                    $roleAssignmentObject | Add-Member @memberObject

                                    if (-not $IsCustom -or $roleAssignmentObject.IsCustom) {
                                        $roleAssignmentsList.Add($roleAssignmentObject)
                                        Write-Verbose " Found PIM Eligible: $($roleAssignmentObject.PrincipalType) -> $roleName (Subscription: $subscriptionId)"
                                    }
                                }
                            }
                        }
                    }
                    catch {
                        Write-Information " Error processing PIM eligible assignments for subscription '$subscriptionId': $($_.Exception.Message)" -InformationAction Continue
                    }
                } -ThrottleLimit $ThrottleLimitParam
            }
            
            # Convert ConcurrentBag to array for return
            return @($roleAssignmentsList)
            }
            catch {
                Write-Host " Error processing role assignments: $($_.Exception.Message)" -ForegroundColor Red
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
                return @()
            }
        }

        # Execute the role assignment operation with caching
        $result = Invoke-CacheableOperation -CacheKey $cacheKey -CacheType 'MSGraph' -Operation { 
            & $roleAssignmentOperation $CurrentUser $ObjectId $subscriptions $PrincipalType $IsCustom $ExcludeCustom $IncludeEligible $ThrottleLimit 
        } -SkipCache $SkipCache -CacheExpirationMinutes $CacheExpirationMinutes -MaxCacheSize $MaxCacheSize -CompressCache $CompressCache -OperationName "role assignment retrieval"

        if ($result.Count -eq 0) {
            Write-Host " No role assignments found for the specified criteria" -ForegroundColor Yellow
        } else {
            $duration = (Get-Date) - $startTime
            Write-Host "`n Role Assignment Discovery Summary:" -ForegroundColor Magenta
            Write-Host "   Total Role Assignments Found: $($result.Count)" -ForegroundColor Green
            
            # Show active vs eligible assignment breakdown if IncludeEligible was used
            if ($IncludeEligible) {
                $activeAssignments = $result | Where-Object { $_.IsEligible -eq $false }
                $eligibleAssignments = $result | Where-Object { $_.IsEligible -eq $true }
                Write-Host "   Active Assignments: $($activeAssignments.Count)" -ForegroundColor Green
                Write-Host "   Eligible (PIM) Assignments: $($eligibleAssignments.Count)" -ForegroundColor Cyan
            }
            
            # Group by principal type for summary
            $principalTypeSummary = $result | Group-Object PrincipalType
            foreach ($group in $principalTypeSummary) {
                Write-Host "   $($group.Name): $($group.Count)" -ForegroundColor Cyan
            }
            
            # Show custom role count if any
            $customRoles = $result | Where-Object { $_.IsCustom -eq $true }
            if ($customRoles.Count -gt 0) {
                Write-Host "   Custom Roles: $($customRoles.Count)" -ForegroundColor Yellow
            }
            
            Write-Host "   Duration: $($duration.TotalSeconds.ToString('F2')) seconds" -ForegroundColor White
        }

        Write-Host " Role assignment analysis completed successfully!" -ForegroundColor Green
        
        # Return results in requested format
        switch ($OutputFormat) {
            "JSON" {
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $jsonOutput = $result | ConvertTo-Json -Depth 3
                $jsonFilePath = "RoleAssignments_$timestamp.json"
                $jsonOutput | Out-File -FilePath $jsonFilePath -Encoding UTF8
                Write-Host " JSON output saved to: $jsonFilePath" -ForegroundColor Green
                # File created, no console output needed
                return
            }
            "CSV" {
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $csvOutput = $result | ConvertTo-Csv -NoTypeInformation
                $csvFilePath = "RoleAssignments_$timestamp.csv"
                $csvOutput | Out-File -FilePath $csvFilePath -Encoding UTF8
                Write-Host " CSV output saved to: $csvFilePath" -ForegroundColor Green
                # File created, no console output needed
                return
            }
            "Object" { return $result }
            "Table" { return $result | Format-Table -Property PrincipalType, PrincipalId, RoleName, Scope -AutoSize }
        }
    }
    <#
    .SYNOPSIS
        Retrieves Azure Role-Based Access Control (RBAC) role assignments for the authenticated context.

    .DESCRIPTION
        The `Get-RoleAssignment` function retrieves RBAC role assignments across Azure subscriptions for the authenticated user or specified criteria.
        It supports filtering by principal type, object ID, subscription ID, and custom roles. The function uses parallel processing to optimize performance
        when querying multiple subscriptions, with a configurable throttle limit to respect API rate limits.

    .PARAMETER CurrentUser
        Filters results to show role assignments for the currently authenticated user. This parameter is a switch.

    .PARAMETER PrincipalType
        Filters results by the type of principal. Valid options are:
        - User
        - Group
        - ServicePrincipal

    .PARAMETER ObjectId
        Filters results by a specific Azure AD Object ID (GUID). This can be used to target a specific user, group, or service principal.

    .PARAMETER SubscriptionId
        Limits the query to a specific subscription ID. If omitted, the function queries all accessible subscriptions.

    .PARAMETER IsCustom
        Filters results to include only custom roles. This parameter is a switch.

    .PARAMETER ExcludeCustom
        Skips retrieving custom role definitions. This parameter is a switch.

    .PARAMETER ThrottleLimit
        Specifies the maximum number of concurrent operations. The default value is 10. Adjust this value to balance performance and API rate limits.

    .PARAMETER OutputFormat
        Specifies the output format for results. Valid values are:
        - Object: Returns PowerShell objects (default)
        - JSON: Returns results in JSON format
        - CSV: Returns results in CSV format
        - Table: Returns results in formatted table
        Aliases: output, o

    .PARAMETER IncludeEligible
        Includes PIM (Privileged Identity Management) eligible role assignments in addition to active assignments. 
        Eligible assignments are roles that can be activated on-demand through Azure PIM.
        Aliases: include-eligible, eligible

    .PARAMETER SkipCache
        Bypasses the cache and forces a fresh retrieval of role assignments. Use this when you need the most current data.
        Aliases: skip-cache

    .PARAMETER CacheExpirationMinutes
        Specifies how long cached results should be considered valid, in minutes. Default is 60 minutes.
        Cached data older than this will be automatically refreshed on the next request.
        Aliases: cache-expiration

    .PARAMETER MaxCacheSize
        Specifies the maximum number of cache entries to maintain. Default is 100.
        When the limit is reached, the least recently used entries are removed.
        Aliases: max-cache-size

    .PARAMETER CompressCache
        Enables compression for cached data to reduce memory usage. Recommended for large role assignment datasets.
        Aliases: compress-cache

    .OUTPUTS
        Returns a collection of custom objects with the following properties:
        - PrincipalType: The type of Azure AD principal (e.g., User, Group, ServicePrincipal).
        - PrincipalId: The Azure AD Object ID of the principal.
        - RoleName: The display name of the RBAC role.
        - Scope: The resource scope of the role assignment.
        - IsCustom: Indicates whether the role is a custom role.
        - IsEligible: Indicates whether this is a PIM eligible assignment (requires activation).
        
        For PIM eligible assignments (when IncludeEligible is used), additional properties include:
        - StartDateTime: When the eligible assignment begins.
        - EndDateTime: When the eligible assignment expires.
        - Status: The current status of the eligible assignment.

    .EXAMPLE
        Get-RoleAssignment -CurrentUser
        Retrieves all role assignments for the currently authenticated user across all accessible subscriptions.

    .EXAMPLE
        Get-RoleAssignment -PrincipalType Group
        Lists all role assignments granted to Azure AD groups across all accessible subscriptions.

    .EXAMPLE
        Get-RoleAssignment -PrincipalType ServicePrincipal -ObjectId '00000000-0000-0000-0000-000000000000'
        Retrieves role assignments for a specific service principal identified by its Object ID.

    .EXAMPLE
        Get-RoleAssignment -SubscriptionId '00000000-0000-0000-0000-000000000000' -ThrottleLimit 20
        Retrieves all role assignments in the specified subscription with an increased throttle limit for concurrent operations.

    .EXAMPLE
        Get-RoleAssignment -CurrentUser -OutputFormat JSON
        Retrieves all role assignments for the currently authenticated user and returns results in JSON format.

    .EXAMPLE
        Get-RoleAssignment -PrincipalType Group -OutputFormat Table
        Lists all role assignments granted to Azure AD groups and displays results in a formatted table.

    .EXAMPLE
        Get-RoleAssignment -CurrentUser -IncludeEligible
        Retrieves both active and PIM eligible role assignments for the currently authenticated user.

    .EXAMPLE
        Get-RoleAssignment -PrincipalType ServicePrincipal -IncludeEligible -OutputFormat JSON
        Retrieves all active and PIM eligible role assignments for service principals and exports to JSON.

    .EXAMPLE
        Get-RoleAssignment -CurrentUser -SkipCache
        Retrieves all role assignments for the currently authenticated user, bypassing the cache to get fresh data.

    .EXAMPLE
        Get-RoleAssignment -PrincipalType Group -CacheExpirationMinutes 30 -CompressCache
        Retrieves role assignments for groups with a 30-minute cache expiration and compression enabled.

    .EXAMPLE
        Get-RoleAssignment -SubscriptionId '00000000-0000-0000-0000-000000000000' -MaxCacheSize 200
        Retrieves role assignments for a specific subscription with an increased cache size limit.

    .NOTES
        - Requires appropriate Azure RBAC permissions to read role assignments at the queried scope.
        - Be mindful of API rate limits when adjusting the `ThrottleLimit` parameter.
        - The function uses parallel processing to improve performance when querying multiple subscriptions.
        - Results are automatically cached for improved performance. Use -SkipCache to force fresh data retrieval.
        - Cache expiration is set to 60 minutes by default but can be customized with -CacheExpirationMinutes.
        - Large datasets can be compressed in cache using -CompressCache to reduce memory usage.

    .LINK
        MITRE ATT&CK Tactic: TA0007 - Discovery
        https://attack.mitre.org/tactics/TA0007/

    .LINK
        MITRE ATT&CK Technique: T1087.004 - Account Discovery: Cloud Account
        https://attack.mitre.org/techniques/T1087/004/
    #>
}