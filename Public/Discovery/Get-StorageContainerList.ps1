function Get-StorageContainerList {
    [cmdletbinding()]
    [OutputType([System.Collections.Generic.List[PSObject]])]
    param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceNameCompleterAttribute(
            "Microsoft.Storage/StorageAccounts",
            "ResourceGroupName"
        )]
        [Alias('storageAccount', 'storage-account-name', 'storageAccountName')]
        [string[]]$Name,

    [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias('resource-id')]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceIdCompleter(
            "Microsoft.storage/storageAccounts"
        )][object]$Id,


        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceGroupCompleterAttribute()]
        [Alias('rg', 'resource-group')]
        [string[]]$ResourceGroupName,

        [Parameter(Mandatory = $false)]
        [Alias('public-access')]
        [switch]$PublicAccess,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('throttle-limit')]
        [int]$ThrottleLimit = 10
    )

    begin {
        [void] $ResourceGroupName #Only used to trigger the ResourceGroupCompleter

        Write-Verbose "Starting function: $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat

        $result = [System.Collections.Generic.List[PSObject]]::new()
        $totalItems = $id.Count
    }

    process {
        try {
            Write-Verbose "Building payload for API request"

            if (!$($Name) -and !$Id) {
                $id = (Invoke-AzBatch -ResourceType 'Microsoft.Storage/storageaccounts').id
            } elseif ($($Name)) {
                $id = (Invoke-AzBatch -ResourceType 'Microsoft.Storage/storageaccounts' -Name $($Name)).id
            } else {
                $id = $Id
            }


            $id | ForEach-Object -Parallel {
                $authHeader = $using:script:authHeader
                $result     = $using:result
                $totalItems = $using:totalItems
                $batchUri   = $using:sessionVariables.batchUri

                $payload = @{
                    requests = @(
                        @{
                            httpMethod           = "GET"
                            name                 = (New-Guid).Guid
                            requestHeaderDetails = @{
                                commandName = "Microsoft_Azure_Storage.StorageClient.ListContainers"
                            }
                            url = "https://management.azure.com$($_)/blobServices/default/containers?api-version=2023-05-01"
                        }
                    )
                }

                $requestParam = @{
                    Headers     = $authHeader
                    Uri         = $batchUri
                    Method      = 'POST'
                    ContentType = 'application/json'
                    Body        = $payload | ConvertTo-Json -Depth 10
                }

                Write-Verbose "Sending API request"
                $apiResponse = (Invoke-RestMethod @requestParam).responses.content.value
                Write-Verbose "API request completed successfully"

                if ($using:PublicAccess) {
                    Write-Verbose "Filtering containers with public access"
                    $apiResponse = $apiResponse | Where-Object { $_.properties.publicAccess -ne 'None' }
                }

                Write-Verbose "Returning API response"
                [void]$result.Add($apiResponse)

                # Update progress bar
            } -ThrottleLimit $ThrottleLimit
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
            Write-Verbose "An error occurred: $($_.Exception.Message)"
        }
    }

    end {
        Write-Verbose "Completed function $($MyInvocation.MyCommand.Name)"
        return $result
    }
<#
.SYNOPSIS
Retrieves a list of storage containers from Azure Storage Accounts.

.DESCRIPTION
The `Get-StorageContainerList` function retrieves a list of storage containers from Azure Storage Accounts.
It supports filtering by resource group and public access level. The function uses Azure REST API to fetch
the container details and supports parallel processing for improved performance.

.PARAMETER Id
Specifies the resource ID of the storage account(s). If not provided, the function will retrieve all storage
accounts in the current Azure context.

.PARAMETER ResourceGroupName
Specifies the name(s) of the resource group(s) to filter the storage accounts. This parameter is optional.

.PARAMETER PublicAccess
A switch parameter that, when specified, filters the containers to include only those with public access enabled.

.PARAMETER ThrottleLimit
Specifies the maximum number of parallel threads to use for processing. The default value is 10.

.INPUTS
None directly. Accepts pipeline input for the `Id` parameter.

.OUTPUTS
System.Collections.Generic.List[PSObject]
Returns a list of storage containers as PSObject instances.

.EXAMPLE
# Example 1: Retrieve all storage containers in the current Azure context
Get-StorageContainerList

.EXAMPLE
# Example 2: Retrieve storage containers with public access enabled
Get-StorageContainerList -PublicAccess

.EXAMPLE
# Example 3: Retrieve storage containers with a custom throttle limit
Get-StorageContainerList -ThrottleLimit 5

.NOTES
- This function requires the Azure PowerShell module to be installed and authenticated.
- The function uses Azure REST API to fetch container details and requires appropriate permissions.

.LINK
https://learn.microsoft.com/en-us/powershell/azure/

.LINK
MITRE ATT&CK Tactic: TA0007 - Discovery
https://attack.mitre.org/tactics/TA0007/

.LINK
MITRE ATT&CK Technique: T1526 - Cloud Service Discovery
https://attack.mitre.org/techniques/T1526/
#>
}