function Get-ResourcePermission {
    [cmdletbinding()]
    [OutputType([System.Collections.Concurrent.ConcurrentBag[PSCustomObject]])]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[0-9a-fA-F-]{36}$', ErrorMessage = "It does not match expected pattern '{1}'")]
        [Alias('subscription-id')]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceGroupCompleterAttribute()]
        [Alias('resource-group')]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceTypeCompleterAttribute()]
        [Alias('resource-type')]
        [string]$ResourceType,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('resource-name')]
        [string]$ResourceName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('permission-type')]
        [ValidateSet('Write', 'Action', 'All')]
        [string]$PermissionType = 'All',

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('throttle-limit')]
        [ValidateRange(1, 1000)]
        [int]$ThrottleLimit = 100,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Object", "JSON", "CSV", "Table")]
        [Alias("output", "o")]
        [string]$OutputFormat = "Table"
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
        
        Write-Host " Starting Azure Resource Permission Analysis..." -ForegroundColor Green
        
        if ($SubscriptionId) {
            Write-Host "   Scope: Specific Subscription = $SubscriptionId" -ForegroundColor Cyan
        }
        if ($ResourceGroupName) {
            Write-Host "   Filter: Resource Group = $ResourceGroupName" -ForegroundColor Cyan
        }
        if ($ResourceType) {
            Write-Host "   Filter: Resource Type = $ResourceType" -ForegroundColor Cyan
        }
        if ($ResourceName) {
            Write-Host "   Filter: Resource Name = $ResourceName" -ForegroundColor Cyan
        }
        Write-Host "   Permission Type: $PermissionType" -ForegroundColor Cyan
        
        $resourcePermissions = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()
        $baseUri = 'https://management.azure.com'
    }

    process {
        try {
            Write-Verbose "Retrieving all resources for the current user context"

            # Build a dynamic filter string based on provided parameters
            $filterParts = @()

            if ($SubscriptionId) {
                $filterParts += "| where subscriptionId == '$SubscriptionId'"
            }
            if ($ResourceGroupName) {
                $filterParts += "| where resourceGroup == '$ResourceGroupName'"
            }
            if ($ResourceType) {
                $filterParts += "| where type == '$($ResourceType.ToLower())'"
            }
            if ($ResourceName) {
                $filterParts += "| where name == '$ResourceName'"
            }

            if ($filterParts.Count -gt 0) {
                $filterString = $filterParts -join ' '
                $resources = Invoke-AzBatch -filter $filterString
                Write-Verbose "Filter string: $filterString"
            } else {
                $resources = Invoke-AzBatch
            }

            if (-not $resources -or $resources.Count -eq 0) {
                Write-Host " No resources found matching the specified criteria" -ForegroundColor Yellow
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "No resources found matching the specified criteria" -Severity 'Information'
                return $resourcePermissions
            }

            Write-Host "   Found $($resources.Count) resources to analyze" -ForegroundColor Cyan
            Write-Verbose "Processing $($resources.Count) resources"
            if ($resources.Count -gt 20) {
                Write-Host "   Processing $($resources.Count) resources, this may take a while..." -ForegroundColor Yellow
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Processing $($resources.Count) resources, this may take a while" -Severity 'Information'
            }

            Write-Host "   Analyzing resource permissions across $($resources.Count) resources with $ThrottleLimit concurrent threads..." -ForegroundColor Cyan
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

                    if (-not $permissions -or $permissions.Count -eq 0) {
                        Write-Verbose "No permissions found for resource: $resourceId"
                        continue
                    }

                    # Filter permissions based on the requested type
                    $filteredPermissions = $permissions
                    if ($permissionType -eq 'Write') {
                        $filteredPermissions = $permissions | Where-Object { 
                            ($_.actions -contains '*') -or 
                            ($_.actions | Where-Object { $_ -match '/write$' }) 
                        }
                    }
                    elseif ($permissionType -eq 'Action') {
                        $filteredPermissions = $permissions | Where-Object { 
                            ($_.actions -contains '*') -or 
                            ($_.actions | Where-Object { $_ -match '/action$' }) 
                        }
                    }

                    if ($filteredPermissions.Count -gt 0) {
                        $resourceObject = [PSCustomObject]@{
                            ResourceId   = $resourceId
                            ResourceName = $_.name
                            ResourceType = $_.type
                            Subscription = $_.subscriptionId
                            ResourceGroup = $_.resourceGroup
                            Permissions  = $filteredPermissions
                            HasWritePermission  = ($permissions | Where-Object { 
                                ($_.actions -contains '*') -or 
                                ($_.actions | Where-Object { $_ -match '/write$' }) 
                            }).Count -gt 0
                            HasActionPermission = ($permissions | Where-Object { 
                                ($_.actions -contains '*') -or 
                                ($_.actions | Where-Object { $_ -match '/action$' }) 
                            }).Count -gt 0
                        }
                        $resourcePermissions.Add($resourceObject)
                    }
                }
                catch {
                    Write-Verbose "Unable to fetch permissions for resource: $resourceId"
                }
            } -ThrottleLimit $ThrottleLimit

            Write-Verbose "Completed retrieving resource permissions"
            Write-Verbose "Found $($resourcePermissions.Count) resources with matching permissions"
        }
        catch {
            Write-Host " Error while retrieving resource permissions: $($_.Exception.Message)" -ForegroundColor Red
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }

        if ($resourcePermissions.Count -eq 0) {
            Write-Host " No resources found with the specified permission type" -ForegroundColor Yellow
        } else {
            Write-Host "`n Resource Permission Discovery Summary:" -ForegroundColor Magenta
            Write-Host "   Total Resources with Permissions: $($resourcePermissions.Count)" -ForegroundColor Green
            
            # Group by resource type for summary
            $resourceTypeSummary = $resourcePermissions | Group-Object ResourceType
            foreach ($group in $resourceTypeSummary) {
                Write-Host "   $($group.Name): $($group.Count)" -ForegroundColor Cyan
            }
            
            # Show permission type summary
            $writePermissions = $resourcePermissions | Where-Object { $_.HasWritePermission -eq $true }
            $actionPermissions = $resourcePermissions | Where-Object { $_.HasActionPermission -eq $true }
            if ($writePermissions.Count -gt 0) {
                Write-Host "   Write Permissions: $($writePermissions.Count)" -ForegroundColor Green
            }
            if ($actionPermissions.Count -gt 0) {
                Write-Host "   Action Permissions: $($actionPermissions.Count)" -ForegroundColor Yellow
            }
        }

        Write-Host " Resource permission analysis completed successfully!" -ForegroundColor Green
        
        # Convert ConcurrentBag to array for output formatting
        $result = @($resourcePermissions)
        
        # Return results in requested format
        switch ($OutputFormat) {
            "JSON" {
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $jsonOutput = $result | ConvertTo-Json -Depth 3
                $jsonFilePath = "ResourcePermissions_$timestamp.json"
                $jsonOutput | Out-File -FilePath $jsonFilePath -Encoding UTF8
                Write-Host " JSON output saved to: $jsonFilePath" -ForegroundColor Green
                # File created, no console output needed
                return
            }
            "CSV" {
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $csvOutput = $result | ConvertTo-Csv -NoTypeInformation
                $csvFilePath = "ResourcePermissions_$timestamp.csv"
                $csvOutput | Out-File -FilePath $csvFilePath -Encoding UTF8
                Write-Host " CSV output saved to: $csvFilePath" -ForegroundColor Green
                # File created, no console output needed
                return
            }
            "Object" { return $result }
            "Table" { return $result | Format-Table -AutoSize }
        }
    }

    end {
        Write-Verbose "Function $($MyInvocation.MyCommand.Name) completed"
    }
    <#
    .SYNOPSIS
        Validates user permissions on Azure resources.

    .DESCRIPTION
Validates which Azure resources the authenticated user has write or action permissions on. This function tests the current user's effective permissions across Azure subscriptions and resources by attempting operations and capturing authorization responses. Useful for privilege discovery and identifying exploitable resource access.
    .PARAMETER SubscriptionId
        Optional. Specifies a specific subscription ID to check. If omitted, all accessible subscriptions are checked.

    .PARAMETER ResourceGroupName
        Optional. Filters resources to a specific resource group.

    .PARAMETER ResourceType
        Optional. Filters resources by their type (e.g., 'Microsoft.Compute/virtualMachines' or just 'virtualMachines').

    .PARAMETER ResourceName
        Optional. Filters resources by their name.

    .PARAMETER PermissionType
        Optional. Specifies what kind of permissions to check for. Valid options:
        - Write: Checks for write permissions
        - Action: Checks for action permissions
        - All: Checks for both write and action permissions (default)

    .PARAMETER ThrottleLimit
        Optional. Specifies the maximum number of concurrent operations. Default is 100.

    .PARAMETER OutputFormat
        Optional. Specifies the output format for results. Valid options:
        - Object: Returns PowerShell objects (default when piping)
        - JSON: Returns results in JSON format and saves to file
        - CSV: Returns results in CSV format and saves to file  
        - Table: Returns results in formatted table (default)
        Aliases: output, o

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
        Get-ResourcePermission -PermissionType Write
        Returns all resources across all subscriptions where the user has write permissions in table format.

    .EXAMPLE
        Get-ResourcePermission -SubscriptionId "00000000-0000-0000-0000-000000000000" -ResourceGroupName "MyResourceGroup"
        Returns resources in the specified subscription and resource group where the user has any permissions.

    .EXAMPLE
        Get-ResourcePermission -ResourceType "virtualMachines" -PermissionType Action
        Returns all virtual machine resources where the user has action permissions.

    .EXAMPLE
        Get-ResourcePermission -PermissionType Write -OutputFormat JSON
        Returns all resources with write permissions and saves results to a timestamped JSON file.

    .EXAMPLE
        Get-ResourcePermission -OutputFormat CSV
        Returns all resources with permissions and saves results to a timestamped CSV file.

    .NOTES
        - Requires authentication to Azure with appropriate permissions
        - Performance depends on the number of resources and subscriptions

    .LINK
        MITRE ATT&CK Tactic: TA0007 - Discovery
        https://attack.mitre.org/tactics/TA0007/

    .LINK
        MITRE ATT&CK Technique: T1580 - Cloud Infrastructure Discovery
        https://attack.mitre.org/techniques/T1580/
    #>
}