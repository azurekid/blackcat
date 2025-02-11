function Get-RoleAssignments {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$UserId,

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
                    $UserId = $using:UserId

                    $subscriptionId = $_
                    Write-Verbose "Retrieving role definitions for subscription: $subscriptionId"
                    $roleDefinitionsUri = "$($baseUri)/subscriptions/$subscriptionId/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01"
                    $roleDefinitionsRequestParam = @{
                        Headers = $authHeader
                        Uri     = $roleDefinitionsUri
                        Method  = 'GET'
                    }

                    $roleDefinitionResponse = (Invoke-RestMethod @roleDefinitionsRequestParam).value

                    Write-Verbose "Retrieving role assignments for subscription: $subscriptionId"
                    $roleAssignmentsUri = "$($baseUri)/subscriptions/$subscriptionId/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01"
                    $roleAssignmentsRequestParam = @{
                        Headers = $authHeader
                        Uri     = $roleAssignmentsUri
                        Method  = 'GET'
                    }
                    $roleAssignmentsResponse = (Invoke-RestMethod @roleAssignmentsRequestParam).value

                    foreach ($roleAssignment in $roleAssignmentsResponse) {
                        $roleAssignmentObject = [PSCustomObject]@{
                            PrincipalType    = $roleAssignment.properties.principalType
                            PrincipalId      = $roleAssignment.properties.principalId
                            RoleDefinitionId = $roleAssignment.properties.roleDefinitionId
                            Scope            = $roleAssignment.properties.scope
                        }

                        $roleId = ($roleAssignmentObject.RoleDefinitionId -split '/')[-1]
                        $roleAssignmentObject | Add-Member -MemberType NoteProperty -Name RoleName -Value ($roleDefinitionResponse | Where-Object { $_.id -match $roleId }).properties.roleName
                        $roleAssignmentsList.Add($roleAssignmentObject)
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

        if ($UserId) {
            return $roleAssignmentsList | Where-Object { $_.principalId -eq $UserId }
        }
        else {
            return $roleAssignmentsList
        }
    }

    <#
    .SYNOPSIS
        This function retrieves all role assignments for all subscriptions for the current user context.

    .DESCRIPTION
        The Get-RoleAssignments function makes API calls to retrieve all subscriptions and their respective role assignments for the current user context. It filters the role assignments based on the provided user ID.

    .PARAMETER UserId
        The UserId parameter is an optional string that is used to identify the user whose role assignments are to be retrieved.

    .PARAMETER ThrottleLimit
        Specifies the maximum number of concurrent operations that can be performed in parallel.
        Default value is 1000.

    .OUTPUTS
        Returns a collection of PSCustomObjects containing the following properties:
        - PrincipalType: The type of principal (e.g., User, Group, ServicePrincipal)
        - PrincipalId: The unique identifier of the principal
        - RoleDefinitionId: The unique identifier of the role definition
        - Scope: The scope of the role assignment
        - RoleName: The name of the role

    .EXAMPLE
        ```powershell
        Get-RoleAssignments -UserId "exampleUserId"
        ```
        This example calls the Get-RoleAssignments function with the specified UserId.

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