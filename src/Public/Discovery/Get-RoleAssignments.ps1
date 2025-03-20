function Get-RoleAssignments {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('current-user')]
        [switch]$CurrentUser,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [ValidateSet('User', 'Group', 'ServicePrincipal', 'Other')]
        [Alias('principal-type')]
        [string]$PrincipalType,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('is-custom')]
        [switch]$IsCustom,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('object-id')]
        [string]$ObjectId,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[0-9a-fA-F-]{36}$', ErrorMessage = "It does not match expected pattern '{1}'")]
        [Alias('subscription-id')]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('throttle-limit')]
        [int]$ThrottleLimit = 10
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat

        $roleAssignmentsList = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()
        $userAgents = $sessionVariables.userAgents.agents
        $subscriptions = @()
    }

    process {
        try {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Retrieving all subscriptions for the current user context" -Severity 'Information'
            $baseUri = 'https://management.azure.com'
            $subscriptionsUri = "$($baseUri)/subscriptions?api-version=2020-01-01"
            $requestParam = @{
                Headers = $script:authHeader
                Uri     = $subscriptionsUri
                Method  = 'GET'
            }

            if ($SubscriptionId) {
                $requestParam.Uri += '&$filter={0}' -f "subscriptionId eq '$SubscriptionId'"
            }

            $subscriptions = (Invoke-RestMethod @requestParam).value.subscriptionId

        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }

        try {
            if ($CurrentUser) {
                Write-Verbose "Retrieving current user's object Id"
                $ObjectId = (Get-CurrentUser).Id
            }

            if ($ObjectId) {
                Write-Verbose "Retrieving groups for user: $ObjectId"
                $Groups = @(Invoke-MsGraph -relativeUrl "users/$ObjectId/memberOf").id

            }
            else {
                $Groups = @()
            }

            Write-Verbose  "Retrieving role assignments for $($subscriptions.Count) subscriptions"
            $subscriptions | ForEach-Object -Parallel {
                try {
                    $baseUri             = $using:baseUri
                    $authHeader          = $using:script:authHeader
                    $userAgents          = $using:userAgents
                    $roleAssignmentsList = $using:roleAssignmentsList
                    $ObjectId            = $using:ObjectId
                    $Groups              = $using:Groups
                    $azureRoles          = $using:script:SessionVariables.AzureRoles
                    $PrincipalType       = $using:PrincipalType
                    $IsCustom            = $using:IsCustom
                    $subscriptionId      = $_

                    Write-Verbose "Retrieving role assignments for subscription: $subscriptionId"
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
                        UserAgent = $($userAgents.value | Get-Random)
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
                            }

                            $roleId = ($roleAssignment.properties.roleDefinitionId -split '/')[-1]
                            $roleName = ($azureRoles | Where-Object { $_.id -match $roleId } ).Name

                            if (-not($roleName)) {
                                $roleDefinitionsUri = "$($baseUri)/subscriptions/$subscriptionId/providers/Microsoft.Authorization/roleDefinitions/$($roleId)?`$filter=type eq 'CustomRole'&api-version=2022-05-01-preview"
                                $roleDefinitionsRequestParam = @{
                                    Headers = $authHeader
                                    Uri     = $roleDefinitionsUri
                                    Method  = 'GET'
                                    UserAgent = $($userAgents.value | Get-Random)
                                }

                                Write-Verbose "Retrieving custom role definition for subscription: $subscriptionId"
                                $roleName = (Invoke-RestMethod @roleDefinitionsRequestParam).properties.roleName
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
                                }
                            }
                        }
                    }
                }
                catch {
                    Write-Information "$($MyInvocation.MyCommand.Name): Error processing subscription '$_'" -InformationAction Continue
                }
            } -ThrottleLimit $ThrottleLimit
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }

        if ($roleAssignmentsList.Count -eq 0) {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) "No role assignments found for the specified criteria." -severity 'Information'
        }

        Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Completed" -Severity 'Information'
        return $roleAssignmentsList
    }

    <#
    .SYNOPSIS
        Retrieves role assignments across Azure subscriptions for the authenticated context.

    .DESCRIPTION
        Get-RoleAssignments queries Azure RBAC (Role Based Access Control) assignments across all accessible 
        subscriptions or a specified subscription. It supports filtering by principal type, object ID, and 
        can isolate assignments for the current user.

        The function utilizes parallel processing to optimize performance when querying multiple subscriptions,
        with configurable throttling to respect API limits.

    .PARAMETER CurrentUser
        Switch parameter to filter results to only show role assignments for the currently authenticated user.

    .PARAMETER PrincipalType
        Filters results by principal type. Valid options:
        - User
        - Group
        - ServicePrincipal
        - Other

    .PARAMETER ObjectId
        Filters results by the specific Azure AD Object ID (GUID).

    .PARAMETER SubscriptionId
        Limits query to a single subscription ID. If omitted, queries all accessible subscriptions.

    .PARAMETER ThrottleLimit
        Maximum number of concurrent operations. Default is 10 to respect RBAC API rate limits.
        Performance notes:
        - 10 concurrent operations: ~2 minutes for 175 subscriptions/23K assignments
        - 1000 concurrent operations: ~8 minutes for same scope

    .OUTPUTS
        Array of custom objects containing:
        - PrincipalType: The Azure AD principal type
        - PrincipalId: The Azure AD object ID of the principal
        - RoleName: The display name of the RBAC role
        - Scope: The resource scope of the assignment

    .EXAMPLE
        Get-RoleAssignments -CurrentUser
        Returns all role assignments for the authenticated user across all accessible subscriptions.

    .EXAMPLE
        Get-RoleAssignments -PrincipalType Group
        Lists all role assignments granted to Azure AD groups across all accessible subscriptions.

    .EXAMPLE
        Get-RoleAssignments -PrincipalType ServicePrincipal -ObjectId '00000000-0000-0000-0000-000000000000'
        Retrieves role assignments for a specific service principal identified by its Object ID.

    .EXAMPLE
        Get-RoleAssignments -SubscriptionId '00000000-0000-0000-0000-000000000000' -ThrottleLimit 20
        Gets all role assignments in the specified subscription with increased concurrent operations.

    .NOTES
        Requires appropriate Azure RBAC permissions to read role assignments at the queried scope.
        Consider API rate limits when adjusting ThrottleLimit parameter.
    #>
}