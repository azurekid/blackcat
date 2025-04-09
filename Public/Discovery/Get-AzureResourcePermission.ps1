function Get-AzureResourcePermission {
    [cmdletbinding()]
    [OutputType([System.Collections.Concurrent.ConcurrentBag[PSCustomObject]])]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[0-9a-fA-F-]{36}$', ErrorMessage = "It does not match expected pattern '{1}'")]
        [Alias('subscription-id')]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('resource-group')]
        [string]$ResourceGroup,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('resource-type')]
        [string]$ResourceType,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('permission-type')]
        [ValidateSet('Write', 'Action', 'All')]
        [string]$PermissionType = 'Write',

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('throttle-limit')]
        [int]$ThrottleLimit = 100
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $resourcePermissions = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()
        $baseUri = 'https://management.azure.com'
    }

    process {
        try {
            Write-Verbose "Retrieving all resources for the current user context"

                if ($SubscriptionId -and $ResourceGroup) {
                    $resources = Invoke-AzBatch -filter $filterString
                }
                elseif ($SubscriptionId) {
                    $resources = Invoke-AzBatch -filter "| where subscriptionId == '$SubscriptionId'"
                }
                elseif ($ResourceGroup) {
                    $resources = Invoke-AzBatch -filter "| where resourceGroup == '$ResourceGroup'"
                }
                elseif ($ResourceType){
                    $resources = Invoke-AzBatch -resourceType $ResourceType
                }
                else {
                    $resources = Invoke-AzBatch
                }


            Write-Verbose "Processing $($resources.Count) resources"
            if ($resources.Count -gt 20) {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Processing $($resources.Count) resources, this may take a while" -Severity 'Information'
            }

            $resources | ForEach-Object -Parallel {
                $resourceId          = $_.id
                $permissionType      = $using:PermissionType
                $resourcePermissions = $using:resourcePermissions
                $baseUri             = $using:baseUri

                Write-Verbose "Check permissions for each resource: $($_.name)"

                    # Check permissions for each resource
                    $permissionsUri = "$baseUri$resourceId/providers/Microsoft.Authorization/permissions?api-version=2018-07-01"

                    $permRequestParam = @{
                        Headers = $using:script:authHeader
                        Uri     = $permissionsUri
                        Method  = 'GET'
                        ErrorAction = 'SilentlyContinue'
                    }

                    try {
                        $permissions = (Invoke-RestMethod @permRequestParam).value

                        # Filter permissions based on the requested type
                        $filteredPermissions = $permissions
                        if ($permissionType -eq 'Write') {
                            $filteredPermissions = $permissions | Where-Object { $_.actions -match '/write' -or $_.actions -eq '*' }
                        }
                        elseif ($permissionType -eq 'Action') {
                            $filteredPermissions = $permissions | Where-Object { $_.actions -match '/action' -or $_.actions -contains '*' }
                        }

                        if ($filteredPermissions.Count -gt 0) {
                            $resourceObject = [PSCustomObject]@{
                                ResourceId   = $resourceId
                                ResourceName = $_.name
                                ResourceType = $_.type
                                Subscription = $_.subscriptionId
                                ResourceGroup = $_.resourceGroup
                                Permissions  = $filteredPermissions
                                HasWritePermission  = ($permissions | Where-Object { $_.actions -match '/write$' -or $_.actions -eq '*' }).Count -gt 0
                                HasActionPermission = ($permissions | Where-Object { $_.actions -match '/action$'}).Count -gt 0
                            }
                            $resourcePermissions.Add($resourceObject)
                        }
                    }
                    catch {
                        Write-Verbose "Unable to fetch permissions for resource: $resourceId"
                    }
            } -ThrottleLimit $ThrottleLimit

            Write-Verbose "Completed retrieving resource permissions"
            return $resourcePermissions
        }
        catch {
            Write-Error "Error while retrieving resource permissions: $($_.Exception.Message)"
        }
    }
    <#
    .SYNOPSIS
        Validates which Azure resources the authenticated user has write or action permissions on.

    .DESCRIPTION
        The Get-AzureResourcePermission function identifies Azure resources where the authenticated user
        has specified permissions (write, action, or both). It supports filtering by subscription, resource group,
        and resource type, and processes subscriptions in parallel for efficiency.

    .PARAMETER SubscriptionId
        Optional. Specifies a specific subscription ID to check. If omitted, all accessible subscriptions are checked.

    .PARAMETER ResourceGroup
        Optional. Filters resources to a specific resource group.

    .PARAMETER ResourceType
        Optional. Filters resources by their type (e.g., 'Microsoft.Compute/virtualMachines' or just 'virtualMachines').

    .PARAMETER PermissionType
        Optional. Specifies what kind of permissions to check for. Valid options:
        - Write: Checks for write permissions
        - Action: Checks for action permissions
        - All: Checks for both write and action permissions (default)

    .PARAMETER ThrottleLimit
        Optional. Specifies the maximum number of concurrent operations. Default is 100.

    .OUTPUTS
        Returns a collection of resources with their permission details, including:
        - ResourceId: The full resource ID
        - ResourceName: The name of the resource
        - ResourceType: The type of the resource
        - Subscription: The subscription ID
        - ResourceGroup: The resource group name
        - Permissions: Detailed permission objects
        - HasWritePermission: Boolean indicating if the user has write permissions
        - HasActionPermission: Boolean indicating if the user has action permissions

    .EXAMPLE
        Get-AzureResourcePermission -PermissionType Write
        Returns all resources across all subscriptions where the user has write permissions.

    .EXAMPLE
        Get-AzureResourcePermission -SubscriptionId "00000000-0000-0000-0000-000000000000" -ResourceGroup "MyResourceGroup"
        Returns resources in the specified subscription and resource group where the user has any permissions.

    .EXAMPLE
        Get-AzureResourcePermission -ResourceType "virtualMachines" -PermissionType Action
        Returns all virtual machine resources where the user has action permissions.

    .NOTES
        - Requires authentication to Azure with appropriate permissions
        - Performance depends on the number of resources and subscriptions
    #>
}