function Set-ManagedIdentityPermission {
    [cmdletbinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [Alias('service-principal-id')]
        [string]$servicePrincipalId,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $false)]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [Alias('resource-id')]
        [string]$resourceId,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [Alias('app-role-id')]
        [string]$appRoleId,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet( [appRoleNames] )]
        [Alias('app-role-name')]
        [string]$appRoleName
    )

    begin {
        # Sets the authentication header to the Microsoft Graph API
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
    }

    process {
        if ($PSCmdlet.ShouldProcess("Service Principal ID: $servicePrincipalId, Resource ID: $resourceId, App Role ID: $appRoleId")) {
            try {
                if (-not $appRoleId) {
                    $appRoleId = (Get-AppRolePermission -appRoleName $appRoleName).appRoleId
                }

                Write-Verbose "Get Service Principals App Role Assignments"
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

                try {
                    Write-Verbose "Assigning App Role to Service Principal"
                    Invoke-RestMethod @requestParam
                } catch {
                    Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message ($_.ErrorDetails.Message | ConvertFrom-Json).Error.Message -Severity 'Information'
                }
            } catch {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
            }
        }
    }
}
