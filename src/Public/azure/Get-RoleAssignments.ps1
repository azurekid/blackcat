function Get-RoleAssignments {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [switch]$CurrentUser,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [ValidateSet('User', 'Group', 'ServicePrincipal', 'Other')]
        [string]$PrincipalType,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [string]$ObjectId,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [int]$ThrottleLimit = 1000
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
        $roleAssignmentsList = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()
        $subscriptions = @()
    }

    process {
        try {
            Write-Verbose "Retrieving all subscriptions for the current user context"
            $baseUri = 'https://management.azure.com'
            $subscriptionsUri = "$($baseUri)/subscriptions?api-version=2020-01-01"
            $requestParam = @{
                Headers = $script:authHeader
                Uri     = $subscriptionsUri
                Method  = 'GET'
            }

            if ($SubscriptionId) {
                $requestParam.subscriptionsUri += '&$filter={0}' -f "subscriptionId eq '$SubscriptionId'"
            }

            $subscriptionsResponse = (Invoke-RestMethod @requestParam).value
            $subscriptions = $subscriptionsResponse.subscriptionId
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Found $($subscriptions.Count) subscriptions" -Severity 'Information'
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }

        try {
            if ($CurrentUser) {
                $ObjectId = (Get-CurrentUser).Id
            }

            $subscriptions | ForEach-Object -Parallel {
                try {
                    $baseUri = $using:baseUri
                    $authHeader = $using:script:authHeader
                    $roleAssignmentsList = $using:roleAssignmentsList
                    $ObjectId = $using:ObjectId
                    $azureRoles = $using:script:SessionVariables.AzureRoles
                    $PrincipalType = $using:PrincipalType
                    $subscriptionId = $_

                    Write-Host "Retrieving role assignments for subscription: $subscriptionId"
                    $roleAssignmentsUri = "$($baseUri)/subscriptions/$subscriptionId/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01"

                    if ($ObjectId) {
                        $roleAssignmentsUri += '&$filter={0}' -f "PrincipalId eq '$ObjectId'"
                    }

                    $roleAssignmentsRequestParam = @{
                        Headers = $authHeader
                        Uri     = $roleAssignmentsUri
                        Method  = 'GET'
                    }

                    if ($PrincipalType) {
                        $roleAssignmentsResponse = (Invoke-RestMethod @roleAssignmentsRequestParam).value | Where-Object { $_.properties.principalType -eq $PrincipalType }
                    }
                    else {
                        $roleAssignmentsResponse = (Invoke-RestMethod @roleAssignmentsRequestParam).value
                    }

                    foreach ($roleAssignment in $roleAssignmentsResponse) {
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
                            $roleDefinitionsUri = "$($baseUri)/subscriptions/$subscriptionId/providers/Microsoft.Authorization/roleDefinitions?`$filter=type eq 'CustomRole'&api-version=2022-05-01-preview"
                            $roleDefinitionsRequestParam = @{
                                Headers = $authHeader
                                Uri     = $roleDefinitionsUri
                                Method  = 'GET'
                            }

                            Write-Verbose "Retrieving role custom role definitions for subscription: $subscriptionId"
                            $azureRoles += (Invoke-RestMethod @roleDefinitionsRequestParam).value
                            Write-Verbose "Retrieved $($azureRoles.Count) role definitions for subscription: $subscriptionId"

                            $roleName = ($azureRoles | Where-Object { $_.id -match $roleId } ).Name
                            $roleAssignmentObject.IsCustom = $true
                        }

                        if ($roleName) {
                            $memberObject = @{
                                MemberType	= 'NoteProperty'
                                Name       = 'RoleName'
                                Value      = ($azureRoles | Where-Object { $_.id -match $roleId } ).Name
                            }
                            $roleAssignmentObject | Add-Member @memberObject
                            $roleAssignmentsList.Add($roleAssignmentObject)
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
            Write-Verbose "No role assignments found for the specified criteria."
        }

        return $roleAssignmentsList #| Select-Object PrincipalId, PrincipalType, RoleName, Scope | Sort-Object PrincipalId, Scope
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

    .PARAMETER ThrottleLimit
        Specifies the maximum number of concurrent operations that can be performed in parallel. Default value is 1000.

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