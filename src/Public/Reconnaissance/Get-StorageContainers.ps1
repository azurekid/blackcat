function Get-StorageContainers {
    [cmdletbinding()]
    param (
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
        Write-Verbose "Starting function: $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat

        $result = New-Object System.Collections.ArrayList
        $totalItems = $id.Count
        $currentItemIndex = 0
        $sync = [PSCustomObject]@{ CurrentItemIndex = 0 }
    }

    process {
        try {
            Write-Verbose "Building payload for API request"

            $id | ForEach-Object -Parallel {
                $authHeader       = $using:script:authHeader
                $result           = $using:result
                $totalItems       = $using:totalItems
                $batchUri         = $using:sessionVariables.batchUri
                $currentItemIndex = [System.Threading.Interlocked]::Increment([ref]$using:sync.CurrentItemIndex)

                $payload = @{
                    requests = @(
                        @{
                            httpMethod           = "GET"
                            name                 = (New-Guid).Guid
                            requestHeaderDetails = @{
                                commandName = "Microsoft_Azure_Storage.StorageClient.ListContainers"
                            }
                            url                  = "https://management.azure.com$($_)/blobServices/default/containers?api-version=2023-05-01"
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
                $percentComplete = [math]::Round(($currentItemIndex / $totalItems) * 100)
                Write-Progress -Activity "Processing containers" -Status "$currentItemIndex of $totalItems completed" -PercentComplete $percentComplete
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
    Retrieves Azure Storage Containers information.

.DESCRIPTION
    This function retrieves information about Azure Storage Containers. It can optionally filter for containers 
    with public access enabled. The function uses parallel processing for improved performance when handling multiple storage accounts.

.PARAMETER id
    Array of Azure resource IDs for storage accounts.

.PARAMETER PublicAccess
    Switch parameter to filter for containers with public access enabled.

.PARAMETER ThrottleLimit
    Maximum number of concurrent operations. Default is 1000.

.EXAMPLE
    PS> $storageIds = (Get-AzStorageAccount).Id
    PS> Get-AzStorageContainers -id $storageIds
    Returns all containers from the specified storage accounts.

.EXAMPLE
    PS> Get-AzStorageContainers -id $storageIds -PublicAccess
    Returns only containers that have public access enabled.

.EXAMPLE
    PS> Get-AzStorageContainers -id $storageIds -ThrottleLimit 50
    Returns containers with a maximum of 50 concurrent operations.

.INPUTS
    System.Array
    You can pipe storage account resource IDs to this function.

.OUTPUTS
    System.Collections.ArrayList
    Returns an ArrayList containing container information.

.NOTES
    Dependencies:
    - Az.Accounts module
    - Az.Storage module
    - Active Azure connection (Connect-AzAccount)
    - Appropriate RBAC permissions on the storage accounts
    - BlackCat module (for Invoke-BlackCat function)

    File: Get-AzStorageContainers.ps1

.LINK
    https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blobs-introduction

.COMPONENT
    BlackCat

.FUNCTIONALITY
    Azure Storage Container Management
#>
}
