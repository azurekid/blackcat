function Set-AzureApplication {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$DisplayName = 'MS-PIM',

        [Parameter(Mandatory = $false)]
        [ValidateSet('SingleTenant', 'MultiTenant')]
        [string]$SignInAudience = 'SingleTenant'
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
    }

    process {
        try {
            Write-Verbose "Creating Azure AD Application"
            $uri = "$($sessionVariables.graphUri)/applications"

            $applicationBody = @{
                displayName = $DisplayName
            } | ConvertTo-Json -Depth 10

            $requestParam = @{
                Headers = $script:graphHeader
                Uri     = $uri
                Method  = 'POST'
                Body    = $applicationBody
                ContentType = 'application/json'
            }

            $appRegistration = Invoke-RestMethod @requestParam


                Write-Verbose "Creating Service Principal for the application"
                $spUri = "$($sessionVariables.graphUri)/servicePrincipals"

                $spBody = @{
                    appId = $appRegistration.appId
                } | ConvertTo-Json

                $spRequest = @{
                    Headers = $script:graphHeader
                    Uri     = $spUri
                    Method  = 'POST'
                    Body    = $spBody
                    ContentType = 'application/json'
                }

                $servicePrincipal = Invoke-RestMethod @spRequest

                # Add Global Administrator role
                Write-Verbose "Adding Global Administrator role to Service Principal"
                $roleUri = "$($sessionVariables.graphUri)/directoryRoles/roleTemplateId=62e90394-69f5-4237-9190-012177145e10/members/`$ref"

                $roleBody = @{
                    "@odata.id" = "$($sessionVariables.graphUri)/directoryObjects/$($servicePrincipal.id)"
                } | ConvertTo-Json

                $roleRequest = @{
                    Headers = $script:graphHeader
                    Uri     = $roleUri
                    Method  = 'POST'
                    Body    = $roleBody
                    ContentType = 'application/json'
                }

                Invoke-RestMethod @roleRequest

                return @{
                    Application = $appRegistration
                    ServicePrincipal = $servicePrincipal
                }

            return $appRegistration
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
}