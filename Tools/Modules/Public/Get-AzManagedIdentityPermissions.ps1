function Get-AzManagedIdentityPermissions {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [string]$servicePrincipalId
    )

    begin {
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
    }

    process {

        try {

            Write-Verbose "Get Service Principals App Role Assignments"
            $uri = "$($sessionVariables.graphUri)/servicePrincipals/$servicePrincipalId/appRoleAssignments"

            $requestParam = @{
                Headers = $script:graphHeader
                Uri     = $uri
                Method  = 'GET'
            }

            return (Invoke-RestMethod @requestParam).value

        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
}