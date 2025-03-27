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

        [Parameter(Mandatory = $false)]
        [string]$filter
    )

    begin {
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {
        try {
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

            $requestParam = @{
                Headers     = $script:authHeader
                Uri         = $sessionVariables.batchUri
                Method      = 'POST'
                ContentType = 'application/json'
                Body        = $payload | ConvertTo-Json -Depth 10
            }

            $apiResponse = (Invoke-RestMethod @requestParam).responses.content.data

            if (!($apiResponse)) {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "No resources found" -Severity 'Information'
            }
            else {
                return $apiResponse
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
}
