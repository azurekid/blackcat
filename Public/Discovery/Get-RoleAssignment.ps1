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
        [int]$ThrottleLimit = 10
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat

        $roleAssignmentsList = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()
        $subscriptions = @()
        $randomUserAgent = $sessionVariables.userAgent
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
                    $userAgent           = $using:randomUserAgent
                    $roleAssignmentsList = $using:roleAssignmentsList
                    $ObjectId            = $using:ObjectId
                    $Groups              = $using:Groups
                    $azureRoles          = $using:script:SessionVariables.AzureRoles
                    $PrincipalType       = $using:PrincipalType
                    $IsCustom            = $using:IsCustom
                    $ExcludeCustom       = $using:ExcludeCustom
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
                                    Write-Verbose "Retrieving custom role definition for subscription: $subscriptionId"
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

    .OUTPUTS
        Returns a collection of custom objects with the following properties:
        - PrincipalType: The type of Azure AD principal (e.g., User, Group, ServicePrincipal).
        - PrincipalId: The Azure AD Object ID of the principal.
        - RoleName: The display name of the RBAC role.
        - Scope: The resource scope of the role assignment.
        - IsCustom: Indicates whether the role is a custom role.

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

    .NOTES
        - Requires appropriate Azure RBAC permissions to read role assignments at the queried scope.
        - Be mindful of API rate limits when adjusting the `ThrottleLimit` parameter.
        - The function uses parallel processing to improve performance when querying multiple subscriptions.
    #>
}