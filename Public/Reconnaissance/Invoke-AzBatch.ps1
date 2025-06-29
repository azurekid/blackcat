function Invoke-AzBatch {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^Microsoft\.[A-Za-z]+(/[A-Za-z]+)+$|^$')]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceTypeCompleterAttribute()]
        [Alias('resource-type')]
        [string]$ResourceType,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias('resource-name', 'ResourceName')]
        [string]$Name,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [switch]$Silent,

        [Parameter(Mandatory = $false)]
        [string]$filter
    )

    begin {

        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {
        try {
            $allResources = @()
            $skipToken = $null
            $pageCount = 0

            do {
                $pageCount++
                Write-Verbose "Retrieving page $pageCount of resources"

                $payload = @{
                    requests = @(
                        @{
                            httpMethod = 'POST'
                            url        = $($sessionVariables.resourceGraphUri)
                            content    = @{
                                query = "resources"
                            }
                        }
                    )
                }

                if (![string]::IsNullOrEmpty($ResourceType)) {
                    $payload.requests[0].content.query = "resources | where type == '$($ResourceType.ToLower())'"
                }

                if (![string]::IsNullOrEmpty($Name)) {
                    $payload.requests[0].content.query += " | where name == '$($Name)'"
                    Write-Output "Filtering resources by name: $Name"
                }

                if (![string]::IsNullOrEmpty($filter)) {
                    $payload.requests[0].content.query += "$filter"
                    Write-Output "Filtering resources with: $($payload.requests[0].content.query)"
                }

                # Add skipToken to the request if available
                if ($skipToken) {
                    if (!$payload.requests[0].content.options) {
                        $payload.requests[0].content.options = @{}
                    }
                    $payload.requests[0].content.options.'$skipToken' = $skipToken
                    Write-Verbose "Using skipToken for pagination: $skipToken"
                }

                $requestParam = @{
                    Headers     = $script:authHeader
                    Uri         = $sessionVariables.batchUri
                    Method      = 'POST'
                    ContentType = 'application/json'
                    Body        = $payload | ConvertTo-Json -Depth 10
                    UserAgent   = $($sessionVariables.userAgent)
                }

                Write-Verbose "Making API request using User-Agent: $($sessionVariables.userAgent)"
                $response = Invoke-RestMethod @requestParam
                $pageData = $response.responses.content.data

                if ($pageData) {
                    $allResources += $pageData
                    Write-Verbose "Retrieved $($pageData.Count) resources on page $pageCount. Total count: $($allResources.Count)"
                }

                # Get skipToken for next page if it exists
                $skipToken = $response.responses.content.'$skipToken'

            } while ($skipToken)

            if ($allResources.Count -eq 0 -and -not $Silent) {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "No resources found" -Severity 'Information'
            }
            else {
                return $allResources
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
}