function Add-EntraApplication {
    [cmdletbinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory = $false)]
        [string]$DisplayName = 'MS-PIM'
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
<#
.SYNOPSIS
Creates an Entra ID Application and its associated Service Principal, and assigns the Global Administrator role to the Service Principal.

.DESCRIPTION
The Add-EntraApplication function automates the creation of an Entra ID Application and its corresponding Service Principal.
It also assigns the Global Administrator role to the Service Principal. This function uses Microsoft Graph API to perform the operations.

.PARAMETER DisplayName
Specifies the display name of the Entra ID Application. Defaults to 'MS-PIM' if not provided.

This example creates an Entra ID Application named "MyApp" with a sign-in audience of "MultiTenant",
creates its Service Principal, and assigns the Global Administrator role to the Service Principal.

.NOTES
- This function requires an authenticated session with Microsoft Graph API.
- Ensure that the necessary permissions are granted to the account executing this function.

.OUTPUTS
A hashtable containing the created Entra ID Application and Service Principal objects.

.LINK
https://learn.microsoft.com/en-us/graph/overview
#>
}