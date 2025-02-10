function Get-RoleAssignments {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        # [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9-]+[A-Za-z0-9]$', ErrorMessage = "It does not match expected pattern '{1}'")]
        [string]$UserId
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
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
            Write-Output $requestParam
            pause

            $subscriptionsResponse = (Invoke-RestMethod @requestParam).value
            Write-Output $subscriptionsResponse
            pause

            foreach ($subscription in $subscriptionsResponse) {
                $subscriptionId = $subscription.subscriptionId
                Write-Verbose "Retrieving role assignments for subscription: $subscriptionId"
                $roleAssignmentsUri = "$($baseUri)/subscriptions/$subscriptionId/providers/Microsoft.Authorization/roleAssignments?api-version=2020-04-01-preview"
                $roleAssignmentsRequestParam = @{
                    Headers = $script:authHeader
                    Uri     = $roleAssignmentsUri
                    Method  = 'GET'
                }
                $roleAssignmentsResponse = (Invoke-RestMethod @roleAssignmentsRequestParam).value

                foreach ($roleAssignment in $roleAssignmentsResponse) {
                    if ($roleAssignment.properties.principalId -eq $UserId) {
                        Write-Output $roleAssignment
                    }
                }
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }

    <#
    .SYNOPSIS
        This function retrieves all role assignments for all subscriptions for the current user context.

    .DESCRIPTION
        The Get-RoleAssignments function makes API calls to retrieve all subscriptions and their respective role assignments for the current user context. It filters the role assignments based on the provided user ID.

    .PARAMETER UserId
        The UserId parameter is a mandatory string that must match the pattern '^[A-Za-z0-9][A-Za-z0-9-]+[A-Za-z0-9]$'. It is used to identify the user whose role assignments are to be retrieved.

    .EXAMPLE
        ```powershell
        Get-RoleAssignments -UserId "exampleUserId"
        ```
        This example calls the Get-RoleAssignments function with the specified UserId.

    .LINK
        For more information, see the related documentation or contact support.

    .NOTES
    Author: Rogier Dijkman
    #>
}