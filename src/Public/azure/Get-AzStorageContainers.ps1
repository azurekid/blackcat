function Get-AzStorageContainers {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [array]$id,

        [Parameter(Mandatory = $false)]
        [switch]$PublicAccess,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [int]$ThrottleLimit = 10000
    )

    begin {
        Write-Verbose "Starting function: $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat

        $result = New-Object System.Collections.ArrayList
        $totalItems = $id.Count
        $currentItemIndex = 0
    }

    process {
        try {
            Write-Verbose "Building payload for API request"

            $id | ForEach-Object -Parallel {
                $authHeader       = $using:script:authHeader
                $result           = $using:result
                $totalItems       = $using:totalItems
                $batchUri         = $using:sessionVariables.batchUri
                $currentItemIndex = [System.Threading.Interlocked]::Increment([ref]$using:currentItemIndex)

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
}
