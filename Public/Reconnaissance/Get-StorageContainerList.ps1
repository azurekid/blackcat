function Get-StorageContainerList {
    [cmdletbinding()]
    [OutputType([System.Collections.Generic.List[PSObject]])]
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
        [void] $ResourceGroupName #Only used to trigger the ResourceGroupCompleter

        Write-Verbose "Starting function: $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat

        $result = [System.Collections.Generic.List[PSObject]]::new()
        $totalItems = $id.Count
    }

    process {
        try {
            Write-Verbose "Building payload for API request"

            $id | ForEach-Object -Parallel {
                $authHeader = $using:script:authHeader
                $result = $using:result
                $totalItems = $using:totalItems
                $batchUri = $using:sessionVariables.batchUri

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
}
