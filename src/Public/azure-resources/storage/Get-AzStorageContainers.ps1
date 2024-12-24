function Get-AzStorageContainers {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [array]$id,

        [Parameter(Mandatory = $false)]
        [switch]$PublicAccess
    )

    begin {
        Write-Verbose "Starting function: $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {
        try {
            Write-Verbose "Building payload for API request"
            $payload = @{
                requests = @(
                    @{
                        httpMethod           = "GET"
                        name                 = (New-Guid).Guid
                        requestHeaderDetails = @{
                            commandName = "Microsoft_Azure_Storage.StorageClient.ListContainers"
                        }
                        url                  = "https://management.azure.com$($Id)/blobServices/default/containers?api-version=2023-05-01"
                    }
                )
            }

            Write-Verbose "Preparing request parameters"
            $requestParam = @{
                Headers     = $script:authHeader
                Uri         = $sessionVariables.batchUri
                Method      = 'POST'
                ContentType = 'application/json'
                Body        = $payload | ConvertTo-Json -Depth 10
            }

            Write-Verbose "Sending API request"
            $apiResponse = (Invoke-RestMethod @requestParam).responses.content.value
            Write-Verbose "API request completed successfully"

            if ($PublicAccess) {
                Write-Verbose "Filtering containers with public access"
                $apiResponse = $apiResponse | Where-Object { $_.properties.publicAccess -ne 'None' }
            }

            Write-Verbose "Returning API response"
            $apiResponse | ForEach-Object {
                $_ | Add-Member -MemberType NoteProperty -Name "storageAccountName" -Value ($Id -split "/")[8]
                $_ | Add-Member -MemberType NoteProperty -Name "uri" -Value $('https://{0}.blob.core.windows.net/{1}/?restype=container&comp=list' -f (($Id -split "/")[8]), $_.name)
            }
            return $apiResponse
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
            Write-Verbose "An error occurred: $($_.Exception.Message)"
        }
    }
    <#
.SYNOPSIS
    Retrieves Azure Storage Containers.

.DESCRIPTION
    The Get-AzStorageContainers function retrieves a list of storage containers from Azure Storage accounts.
    It constructs a query based on the provided parameters and sends an API request to retrieve the containers.

.PARAMETER id
    An array of resource IDs for the storage accounts. This parameter is optional and can be provided via pipeline by property name.

.PARAMETER PublicAccess
    A switch parameter to filter containers that have public access enabled. If specified, only containers with public access will be returned.

.EXAMPLE
    PS> Get-AzStorageContainers -id "/subscriptions/{subscription-id}/resourceGroups/{resource-group-name}/providers/Microsoft.Storage/storageAccounts/{storage-account-name}"
    Retrieves all storage containers for the specified storage account.

.EXAMPLE
    PS> Get-AzStorageContainers -id "/subscriptions/{subscription-id}/resourceGroups/{resource-group-name}/providers/Microsoft.Storage/storageAccounts/{storage-account-name}" -PublicAccess
    Retrieves all storage containers with public access enabled for the specified storage account.

.NOTES
    This function requires appropriate authentication headers to be set in the $script:authHeader variable.
    The $sessionVariables object must contain the batchUri property for API requests.
#>
}