using namespace System.Management.Automation

function Set-ManagedIdentityPermission {
    [cmdletbinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'ResourceId')]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'ResourceId')]
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'CommonResource')]        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceNameCompleterAttribute(
            "Microsoft.ManagedIdentity/userAssignedIdentities",
            "ResourceGroupName"
        )]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9-]+[A-Za-z0-9]$', ErrorMessage = "It does not match expected pattern '{1}'")]
        [Alias('name', 'identity-name', 'user-assigned-identity', 'service-principal-name')]
        [string]$servicePrincipalName,

        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceGroupCompleterAttribute()]
        [Alias('rg', 'resource-group')]
        [string[]]$ResourceGroupName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'ResourceId')]
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'CommonResource')]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [Alias('service-principal-id', 'ObjectId')]
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

        [Parameter(Mandatory = $false, ParameterSetName = 'CommonResource')]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [Alias('resource-sp-id')]
        [string]$ResourceServicePrincipalId,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [Alias('app-role-id')]
        [string]$appRoleId,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('app-role-name')]
        [string]$appRoleName,

        [Parameter(Mandatory = $false)]
        [switch]$Remove
    )

    begin {
        # Sets the authentication header to the Microsoft Graph API
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
        
        # Resolve servicePrincipalId if only name is provided
        if ($servicePrincipalName -and -not $servicePrincipalId) {
            Write-Verbose "Resolving service principal by name: $servicePrincipalName"
            try {
                $spLookup = Invoke-MsGraph -relativeUrl "servicePrincipals?`$filter=displayName eq '$servicePrincipalName'" -NoBatch
                
                if (-not $spLookup -or -not $spLookup.value -or $spLookup.value.Count -eq 0) {
                    throw "Could not find service principal with name '$servicePrincipalName'"
                }
                
                $servicePrincipalId = $spLookup.value[0].id
                Write-Verbose "Resolved service principal name '$servicePrincipalName' to ID: $servicePrincipalId"
            }
            catch {
                throw "Error resolving service principal by name: $_"
            }
        }
        
        # Validate that we have a servicePrincipalId
        if (-not $servicePrincipalId) {
            throw "Either -servicePrincipalId or -servicePrincipalName must be provided"
        }
        
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
            # If ResourceServicePrincipalId is provided, use it directly (skip lookup)
            if ($ResourceServicePrincipalId) {
                Write-Verbose "Using provided ResourceServicePrincipalId: $ResourceServicePrincipalId"
                $resourceId = $ResourceServicePrincipalId
            }
            else {
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
        $action = if ($Remove) { "Remove" } else { "Assign" }
        if ($PSCmdlet.ShouldProcess("Service Principal ID: $servicePrincipalId, Resource ID: $resourceId, App Role Name: $appRoleName", $action)) {
            try {
                if (-not $appRoleId) {
                    $appRoleId = (Get-AppRolePermission -appRoleName $appRoleName).appRoleId
                }

                Write-Verbose "Get Service Principals App Role Assignments"
                $uri = "$($sessionVariables.graphUri)/servicePrincipals/$servicePrincipalId/appRoleAssignments"

                if ($Remove) {
                    # Get existing app role assignments to find the one to remove
                    try {
                        Write-Verbose "Getting existing app role assignments to find assignment ID"
                        $getParam = @{
                            Headers     = $script:graphHeader
                            Uri         = $uri
                            Method      = 'GET'
                            ContentType = 'application/json'
                            UserAgent   = $($sessionVariables.userAgent)
                        }
                        
                        $existingAssignments = Invoke-RestMethod @getParam
                        
                        # Find the assignment that matches the appRoleId
                        $assignmentToRemove = $existingAssignments.value | Where-Object { $_.appRoleId -eq $appRoleId }
                        
                        if (-not $assignmentToRemove) {
                            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "App role assignment '$appRoleName' not found on service principal" -Severity 'Warning'
                            return
                        }
                        
                        # Delete the assignment
                        $deleteUri = "$uri/$($assignmentToRemove.id)"
                        $deleteParam = @{
                            Headers     = $script:graphHeader
                            Uri         = $deleteUri
                            Method      = 'DELETE'
                            ContentType = 'application/json'
                            UserAgent   = $($sessionVariables.userAgent)
                        }
                        
                        Write-Verbose "Removing App Role '$appRoleName' from Service Principal"
                        Invoke-RestMethod @deleteParam
                        Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Successfully removed app role '$appRoleName' from service principal" -Severity 'Information'
                    }
                    catch {
                        Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message ($_.ErrorDetails.Message | ConvertFrom-Json).Error.Message -Severity 'Error'
                    }
                }
                else {
                    # Add the app role assignment
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
            }
            catch {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
            }
        }
    }
    <#
.SYNOPSIS
Assigns or removes a specific app role to/from a managed identity (service principal) in Azure using Microsoft Graph API.

.DESCRIPTION
Assigns or removes app roles to/from service principals using Microsoft Graph API.

.PARAMETER servicePrincipalId
The unique identifier (GUID) of the service principal to which the app role will be assigned. This parameter is mandatory.

.PARAMETER servicePrincipalName
Optional. The display name of the service principal (UAMI name) instead of providing the object ID.
If specified, the function will resolve the name to an object ID automatically.
Either -servicePrincipalId or -servicePrincipalName must be provided (not both required).

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

.PARAMETER ResourceServicePrincipalId
Optional. The service principal ID (object ID) of the resource in your tenant. When provided, the function skips
the lookup of the resource service principal, which requires Application.Read.All permission.
This is useful in bootstrap scenarios where the identity doesn't have permission to read service principals yet.
You can obtain this value once using: (Get-AzADServicePrincipal -ApplicationId "00000003-0000-0000-c000-000000000000").Id

.PARAMETER appRoleId
The unique identifier (GUID) of the app role to be assigned. This parameter is optional. If not provided, it will be resolved using the `appRoleName` parameter.

.PARAMETER appRoleName
The name of the app role to be assigned or removed. This parameter is mandatory and must match one of the predefined app role names.

Use tab completion to see all available permissions when the module is properly loaded.

.PARAMETER Remove
A switch parameter that, when specified, removes the app role assignment instead of adding it.
The function will look up existing assignments and delete the one matching the specified appRoleName.

.EXAMPLE
# Using UAMI display name instead of ID
Set-ManagedIdentityPermission -servicePrincipalName "uami-hr-cicd-automation" `
                              -CommonResource MicrosoftGraph `
                              -appRoleName "Application.ReadWrite.All"

This example assigns the "Application.ReadWrite.All" app role by looking up the UAMI by its display name.

.EXAMPLE
Set-ManagedIdentityPermission -servicePrincipalId "12345678-1234-1234-1234-123456789abc" `
                              -resourceId "87654321-4321-4321-4321-cba987654321" `
                              -appRoleName "Application.ReadWrite.All"

This example assigns the "Application.ReadWrite.All" app role to the specified service principal for the given resource.

.EXAMPLE
# Remove an app role assignment from a managed identity
Set-ManagedIdentityPermission -servicePrincipalId "12345678-1234-1234-1234-123456789abc" `
                              -CommonResource MicrosoftGraph `
                              -appRoleName "Application.ReadWrite.All" `
                              -Remove

This example removes the "Application.ReadWrite.All" app role from the specified service principal.

.EXAMPLE
# Using a common resource name instead of looking up the resource ID
Set-ManagedIdentityPermission -servicePrincipalId "12345678-1234-1234-1234-123456789abc" `
                              -CommonResource MicrosoftGraph `
                              -appRoleName "Application.ReadWrite.All"

This example assigns the "Application.ReadWrite.All" app role to the specified service principal for Microsoft Graph,
without needing to manually look up the resource ID.

.EXAMPLE
# Bootstrap scenario - when you don't have permission to look up service principals
# First get the Microsoft Graph SP ID from your tenant (one-time lookup by an admin)
Set-ManagedIdentityPermission -servicePrincipalId "12345678-1234-1234-1234-123456789abc" `
                              -CommonResource MicrosoftGraph `
                              -ResourceServicePrincipalId "your-tenant-msgraph-sp-id" `
                              -appRoleName "RoleManagement.ReadWrite.Directory"

This example uses the -ResourceServicePrincipalId parameter to bypass the service principal lookup,
which is useful when the identity doesn't have Application.Read.All permission yet.

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

.LINK
MITRE ATT&CK Tactic: TA0003 - Persistence
https://attack.mitre.org/tactics/TA0003/

.LINK
MITRE ATT&CK Technique: T1098.003 - Account Manipulation: Additional Cloud Roles
https://attack.mitre.org/techniques/T1098/003/

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