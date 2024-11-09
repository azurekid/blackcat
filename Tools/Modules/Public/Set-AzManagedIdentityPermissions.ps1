function Set-AzManagedIdentityPermissions {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [string]$servicePrincipalId,

        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [string]$resourceId,

        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [string]$appRoleId

    )

    begin {
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
    }

    process {

        try {

            Write-Verbose "Get Service Principals App Role Assignments"
            # Invoke-GraphRecursive -Url "$($sessionVariables.graphUri)/servicePrincipals/appRoleAssignments"
            $uri = "$($sessionVariables.graphUri)/servicePrincipals/$servicePrincipalId/appRoleAssignments"

            $requestParam = @{
                Headers = $script:graphHeader
                Uri     = $uri
                Method  = 'POST'
                ContentType = 'application/json'
                Body    = @{
                    principalId = $servicePrincipalId
                    resourceId  = $resourceId
                    appRoleId   = $appRoleId
                } | ConvertTo-Json
            }

            # $apiResponse = (
            Invoke-RestMethod @requestParam # .value

        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
}