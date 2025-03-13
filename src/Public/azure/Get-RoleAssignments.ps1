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

            $subscriptionsResponse = (Invoke-RestMethod @requestParam).value
            $subscriptions = $subscriptionsResponse.subscriptionId
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }

        try {
            if ($CurrentUser) {
                $ObjectId = (Get-CurrentUser).Id
            }

            if ($ObjectId) {
                $Groups = @(Invoke-MsGraph -relativeUrl "users/$ObjectId/memberOf").id
                Write-Verbose "Retrieving groups for user: $ObjectId"

            }
            else {
                $Groups = @()
            }

            Write-Verbose  "Retrieving role assignments for $($subscriptions.Count) subscriptions"
            $subscriptions | ForEach-Object -Parallel {
                try {
                    $baseUri             = $using:baseUri
                    $authHeader          = $using:script:authHeader
                    $roleAssignmentsList = $using:roleAssignmentsList
                    $ObjectId            = $using:ObjectId
                    $Groups              = $using:Groups
                    $azureRoles          = $using:script:SessionVariables.AzureRoles
                    $PrincipalType       = $using:PrincipalType
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
                    foreach ($principalId in $principalIds) {
                        $filterUri = "$roleAssignmentsUri&`$filter=principalId eq '$principalId'"

                        $roleAssignmentsRequestParam = @{
                            Headers = $authHeader
                            Uri     = $filterUri
                            Method  = 'GET'
                        }

                        $roleAssignmentsResponse += (Invoke-RestMethod @roleAssignmentsRequestParam).value
                    }

                    if ($PrincipalType) {
                        $roleAssignmentsResponse += @(Invoke-RestMethod @roleAssignmentsRequestParam).value | Where-Object { $_.properties.principalType -eq $PrincipalType }
                    }
                    else {
                        $roleAssignmentsResponse += @(Invoke-RestMethod @roleAssignmentsRequestParam).value
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
                                $roleAssignmentsList.Add($roleAssignmentObject)
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
        Retrieves all role assignments for all subscriptions for the current user context.

    .DESCRIPTION
        The Get-RoleAssignments function makes API calls to retrieve all subscriptions and their respective role assignments for the current user context. It can filter the role assignments based on the provided PrincipalType, ObjectId, or CurrentUser switch.

    .PARAMETER CurrentUser
        If specified, filters the role assignments to only include those for the current user.

    .PARAMETER PrincipalType
        Specifies the type of principal to filter the role assignments. Valid values are 'User', 'Group', 'ServicePrincipal', 'Other'.

    .PARAMETER ObjectId
        Specifies the ObjectId to filter the role assignments.

    .PARAMETER SubscriptionId
        Specifies the SubscriptionId to filter the role assignments.

    .PARAMETER ThrottleLimit
        Specifies the maximum number of concurrent operations that can be performed in parallel. Default value is 10 due to rate limits on the RBAC API.
        Tested on tenant with 175 subscriptions and 23,000 role assignments, the function completes in 2 minutes.
        With a ThrottleLimit of 10. with a ThrottleLimit of 1000 the function completes in 8 minute.

    .OUTPUTS
        Returns a collection of PSCustomObjects containing the following properties:
        - PrincipalType: The type of principal (e.g., User, Group, ServicePrincipal)
        - PrincipalId: The unique identifier of the principal
        - RoleName: The name of the role
        - Scope: The scope of the role assignment

    .EXAMPLE
        ```powershell
        Get-RoleAssignments -CurrentUser
        ```
        This example calls the Get-RoleAssignments function to retrieve role assignments for the current user.

    .EXAMPLE
        ```powershell
        Get-RoleAssignments -PrincipalType 'Group'
        ```
        This example calls the Get-RoleAssignments function to retrieve role assignments for all groups.

    .EXAMPLE
        ```powershell
        Get-RoleAssignments -PrincipalType 'ServicePrincipal' -ObjectId 'exampleObjectId'
        ```
        This example calls the Get-RoleAssignments function to retrieve role assignments for a specific user with the given ObjectId.
    #>
}