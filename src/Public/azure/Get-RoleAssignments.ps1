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

            $subscriptionsResponse = (Invoke-RestMethod @requestParam).value
            $subscriptions = $subscriptionsResponse.subscriptionId
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }

        try {
            $subscriptions | ForEach-Object -Parallel {
                try {
                    $baseUri = $using:baseUri
                    $authHeader = $using:script:authHeader
                    $roleAssignmentsList = $using:roleAssignmentsList

                    $subscriptionId = $_
                    $roleDefinitionsUri = "$($baseUri)/subscriptions/$subscriptionId/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01"
                    $roleDefinitionsRequestParam = @{
                        Headers = $authHeader
                        Uri     = $roleDefinitionsUri
                        Method  = 'GET'
                    }

                    Write-Host "Retrieving role definitions for subscription: $subscriptionId"

                    # $roleDefinitionResponse = (Invoke-RestMethod @roleDefinitionsRequestParam).value
                    # Write-Host "Role Definitions: $($roleDefinitionResponse.Count)"

                    # Write-Host "Retrieving role assignments for subscription: $subscriptionId"
                    # $roleAssignmentsUri = "$($baseUri)/subscriptions/$subscriptionId/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01"
                    # $roleAssignmentsRequestParam = @{
                    #     Headers = $authHeader
                    #     Uri     = $roleAssignmentsUri
                    #     Method  = 'GET'
                    # }
                    # $roleAssignmentsResponse = (Invoke-RestMethod @roleAssignmentsRequestParam).value

                    # foreach ($roleAssignment in $roleAssignmentsResponse) {
                    #     $roleAssignmentObject = [PSCustomObject]@{
                    #         PrincipalType    = $roleAssignment.properties.principalType
                    #         PrincipalId      = $roleAssignment.properties.principalId
                    #         Scope            = $roleAssignment.properties.scope
                    #     }

                    #     $roleId = ($roleAssignment.properties.roleDefinitionId -split '/')[-1]
                    #     $memberObject = @{
                    #         MemberType	= 'NoteProperty'
                    #         Name		= 'RoleName'
                    #         Value		= ($roleDefinitionResponse | Where-Object { $_.id -match $roleId }).properties.roleName
                    #     }
                    #     $roleAssignmentObject | Add-Member @memberObject
                    #     $roleAssignmentsList.Add($roleAssignmentObject)
                    # }
                }
                catch {
                    Write-Information "$($MyInvocation.MyCommand.Name): Error processing subscription '$_'" -InformationAction Continue
                }
            } -ThrottleLimit $ThrottleLimit
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }

        $filteredAssignments = $roleDefinitionResponse

        if ($CurrentUser) {
            $UserId = (Get-CurrentScope).'User Object Id'
            $filteredAssignments = $filteredAssignments | Where-Object { $_.PrincipalId -eq $UserId }
        }

        if ($ObjectId) {
            $filteredAssignments = $filteredAssignments | Where-Object { $_.PrincipalId -eq $ObjectId }
        }

        if ($PrincipalType) {
            $filteredAssignments = $filteredAssignments | Where-Object { $_.PrincipalType -eq $PrincipalType }
        }

        if ($filteredAssignments.Count -eq 0) {
            Write-Verbose "No role assignments found for the specified criteria."
        }

        return $filteredAssignments | Select-Object PrincipalId, PrincipalType, RoleName, Scope | Sort-Object PrincipalId, Scope}

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
        Get-RoleAssignments -PrincipalType 'User' -ObjectId 'exampleObjectId'
        ```
        This example calls the Get-RoleAssignments function to retrieve role assignments for a specific user with the given ObjectId.

    .LINK
        For more information, see the related documentation or contact support.

    .NOTES
        File: Get-RoleAssignments.ps1
        Author: Rogier Dijkman
        Version: 1.0
        Requires: PowerShell 7.0 or later
        Requires: Azure Management API access
        Requires: Appropriate permissions to read role assignment information
    #>
}