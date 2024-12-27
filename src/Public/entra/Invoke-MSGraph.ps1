function Invoke-MsGraph {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$relativeUrl
    )

    begin {
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
    }

    process {

        try {

            $payload = @{
                requests = @(
                    @{
                        id     = "List"
                        method = 'GET'
                        url    = '/{0}?$count=true&$top=999' -f "$relativeUrl"
                    }
                )
            }

            $requestParam = @{
                Headers     = $script:graphHeader
                Uri         = '{0}/$batch' -f $sessionVariables.graphUri
                Method      = 'POST'
                ContentType = 'application/json'
                Body        = $payload | ConvertTo-Json -Depth 10
            }

            $initialResponse = (Invoke-RestMethod @requestParam)
            $allItems = Get-AllPages -initialResponse $initialResponse
            return $allItems

        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
    <#
    .SYNOPSIS
        Invokes a request to the Microsoft Graph API.

    .DESCRIPTION
        This function sends a request to the Microsoft Graph API using the specified parameters.
        It handles authentication and constructs the appropriate headers for the request.

    .EXAMPLE
        Invoke-MSGraph -relativeUrl "applications"

        This example sends a GET request to the Microsoft Graph API to retrieve information about the applications.
#>
}

function Get-AllPages {
    param (
        [Parameter(Mandatory = $true)]
        [object]$initialResponse
    )

    $allItems = @($initialResponse.responses.body.value)
    $nextLink = $initialResponse.responses.body.'@odata.nextLink'
    $pageCount = 1

    while ($nextLink) {
        $percentComplete = [math]::Min((($allItems.Count / 100) * 100), 100)
        Write-Progress -Activity "Fetching data from MS Graph" -Status "Processing page $pageCount" -PercentComplete $percentComplete

        $requestParam = @{
            Headers     = $script:graphHeader
            Uri         = $nextLink
            Method      = 'GET'
            ContentType = 'application/json'
        }

        $apiResponse = (Invoke-RestMethod @requestParam)
        $allItems += $apiResponse.value
        $nextLink = $apiResponse.'@odata.nextLink'
        $pageCount++
    }

    Write-Progress -Activity "Fetching data from MS Graph" -Completed
    return $allItems
}