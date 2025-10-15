using namespace System.Management.Automation

function Set-ManagedIdentityPermission {
    [cmdletbinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'ResourceId')]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [Alias('service-principal-id')]
        [string]$servicePrincipalId,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $false, ParameterSetName = 'ResourceId')]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [Alias('resource-id')]
        [string]$resourceId,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'CommonResource')]
        [ValidateSet(
            'MicrosoftGraph', 
            'AzureKeyVault', 
            'AzureStorage', 
            'AzureRM', 
            'MicrosoftOffice365', 
            'AzureAD', 
            'Dynamics365', 
            'PowerBI', 
            'AzureDataLake'
        )]
        [string]$CommonResource,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [Alias('app-role-id')]
        [string]$appRoleId,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('app-role-name')]
        [string]$appRoleName
    )

    begin {
        # Sets the authentication header to the Microsoft Graph API
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
        
        # Define common resource appIds
        $commonResourceAppIds = @{
            'MicrosoftGraph'     = '00000003-0000-0000-c000-000000000000'
            'AzureKeyVault'      = '00000002-0000-0000-c000-000000000000'
            'AzureStorage'       = '00000002-0000-0000-0000-000000000000'
            'AzureRM'            = '797f4846-ba00-4fd7-ba43-dac1f8f63013'
            'MicrosoftOffice365' = '00000002-0000-0000-0000-000000000001'
            'AzureAD'            = '00000002-0000-0000-c000-000000000000'
            'Dynamics365'        = '00000007-0000-0000-c000-000000000000'
            'PowerBI'            = '00000009-0000-0000-c000-000000000000'
            'AzureDataLake'      = 'e9f49c6b-5ce5-44c8-925d-015017e9f7ad'
        }
        
        # If using CommonResource, resolve the Resource ID
        if ($PSCmdlet.ParameterSetName -eq 'CommonResource') {
            Write-Verbose "Resolving resource ID for common resource: $CommonResource"
            
            $appId = $commonResourceAppIds[$CommonResource]
            if (-not $appId) {
                throw "Could not find appId for common resource: $CommonResource"
            }
            
            Write-Verbose "Looking up service principal for app ID: $appId"
            try {
                $spLookup = Invoke-MsGraph -relativeUrl "servicePrincipals?`$filter=appId eq '$appId'" -NoBatch
                
                if (-not $spLookup -or -not $spLookup.value -or $spLookup.value.Count -eq 0) {
                    throw "Could not find service principal for $CommonResource (AppId: $appId)"
                }
                
                $resourceId = $spLookup.value[0].id
                Write-Verbose "Resolved $CommonResource to resourceId: $resourceId"
            }
            catch {
                throw "Error resolving resourceId for $CommonResource : $_"
            }
        }
        
        # Validate appRoleName parameter against available permissions
        if ($script:SessionVariables -and $script:SessionVariables.appRoleIds) {
            $availablePermissions = $script:SessionVariables.appRoleIds | Where-Object Type -eq 'Application' | Select-Object -ExpandProperty Permission
            Write-Verbose "Available app role permissions loaded: $($availablePermissions.Count) total permissions"
            
            if ($appRoleName -and $appRoleName -notin $availablePermissions) {
                $errorMessage = "Invalid appRoleName '$appRoleName'. Valid values are: $($availablePermissions -join ', ')"
                throw [System.ArgumentException]::new($errorMessage, 'appRoleName')
            }
        }
        else {
            Write-Warning "SessionVariables not available for validation. Proceeding without validation."
        }
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
                    Headers     = $script:graphHeader
                    Uri         = $uri
                    Method      = 'POST'
                    ContentType = 'application/json'
                    UserAgent   = $($sessionVariables.userAgent)
                    Body        = @{
                        principalId = $servicePrincipalId
                        resourceId  = $resourceId
                        appRoleId   = $appRoleId
                    } | ConvertTo-Json
                }

                try {
                    Write-Verbose "Assigning App Role to Service Principal"
                    Invoke-RestMethod @requestParam
                }
                catch {
                    Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message ($_.ErrorDetails.Message | ConvertFrom-Json).Error.Message -Severity 'Information'
                }
            }
            catch {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
            }
        }
    }
    <#
.SYNOPSIS
Assigns a specific app role to a managed identity (service principal) in Azure using Microsoft Graph API.

.DESCRIPTION
The `Set-ManagedIdentityPermission` function assigns an app role to a service principal by making a POST request to the Microsoft Graph API.
It supports specifying the service principal ID, resource ID, app role ID, and app role name. If the app role ID is not provided, it will
be resolved based on the app role name.

The function includes intelligent tab completion for the appRoleName parameter, showing all available Microsoft Graph application permissions.
If the BlackCat session data is not available, it falls back to common permissions.

.PARAMETER servicePrincipalId
The unique identifier (GUID) of the service principal to which the app role will be assigned. This parameter is mandatory.

.PARAMETER resourceId
The unique identifier (GUID) of the resource (application) that defines the app role. This parameter is mandatory when not using the CommonResource parameter.
For Microsoft Graph permissions, this should be the service principal ID of Microsoft Graph (00000003-0000-0000-c000-000000000000).

.PARAMETER CommonResource
Specifies a common Azure resource by name instead of providing the resourceId directly. The function will automatically
resolve the appropriate service principal ID. Valid options include:
- MicrosoftGraph: Microsoft Graph API
- AzureKeyVault: Azure Key Vault
- AzureStorage: Azure Storage
- AzureRM: Azure Resource Manager
- MicrosoftOffice365: Microsoft Office 365
- AzureAD: Azure Active Directory Graph (legacy)
- Dynamics365: Dynamics 365
- PowerBI: Power BI Service
- AzureDataLake: Azure Data Lake

.PARAMETER appRoleId
The unique identifier (GUID) of the app role to be assigned. This parameter is optional. If not provided, it will be resolved using the `appRoleName` parameter.

.PARAMETER appRoleName
The name of the app role to be assigned. This parameter is mandatory and must match one of the predefined app role names.

Use tab completion to see all available permissions when the module is properly loaded.

.EXAMPLE
Set-ManagedIdentityPermission -servicePrincipalId "12345678-1234-1234-1234-123456789abc" `
                              -resourceId "87654321-4321-4321-4321-cba987654321" `
                              -appRoleName "Application.ReadWrite.All"

This example assigns the "Application.ReadWrite.All" app role to the specified service principal for the given resource.

.EXAMPLE
# Using a common resource name instead of looking up the resource ID
Set-ManagedIdentityPermission -servicePrincipalId "12345678-1234-1234-1234-123456789abc" `
                              -CommonResource MicrosoftGraph `
                              -appRoleName "Application.ReadWrite.All"

This example assigns the "Application.ReadWrite.All" app role to the specified service principal for Microsoft Graph,
without needing to manually look up the resource ID.

.EXAMPLE
# Assign permission to a User Assigned Managed Identity for Azure Key Vault
Set-ManagedIdentityPermission -servicePrincipalId $UamiObjectId `
                              -CommonResource AzureKeyVault `
                              -appRoleName "user_impersonation"

This example shows how to assign Azure Key Vault permissions to a User Assigned Managed Identity (UAMI)
using the CommonResource parameter.

.EXAMPLE
# Traditional approach - Get Microsoft Graph service principal ID first
$graphSp = Invoke-MsGraph -relativeUrl "servicePrincipals?`$filter=appId eq '00000003-0000-0000-c000-000000000000'" -NoBatch
$graphSpId = $graphSp.value[0].id

# Assign permission to UAMI
Set-ManagedIdentityPermission -servicePrincipalId $UamiObjectId -resourceId $graphSpId -appRoleName "Application.ReadWrite.All"

This example shows the traditional approach to assign Microsoft Graph permissions to a User Assigned Managed Identity (UAMI).

.EXAMPLE
Set-ManagedIdentityPermission -servicePrincipalId "12345678-1234-1234-1234-123456789abc" `
                               -resourceId "87654321-4321-4321-4321-cba987654321" `
                               -appRoleId "abcdef12-3456-7890-abcd-ef1234567890"

This example assigns the app role with the specified app role ID to the service principal for the given resource.

.NOTES
- This function requires authentication to the Microsoft Graph API. Ensure that the authentication header is set correctly.
- The function uses `Invoke-RestMethod` to make API calls and handles errors gracefully by logging messages.

#>
}

# Register argument completer for appRoleName parameter
Register-ArgumentCompleter -CommandName Set-ManagedIdentityPermission -ParameterName appRoleName -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    if ($script:SessionVariables -and $script:SessionVariables.appRoleIds) {
        $availablePermissions = $script:SessionVariables.appRoleIds | Where-Object Type -eq 'Application' | Select-Object -ExpandProperty Permission
        $availablePermissions | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
    else {
        # Fallback to common permissions if SessionVariables not available
        $commonPermissions = @(
            'Application.Read.All',
            'Application.ReadWrite.All',
            'AppRoleAssignment.ReadWrite.All',
            'Directory.Read.All',
            'Directory.ReadWrite.All',
            'User.Read.All',
            'User.ReadWrite.All',
            'Group.Read.All',
            'Group.ReadWrite.All'
        )
        $commonPermissions | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}