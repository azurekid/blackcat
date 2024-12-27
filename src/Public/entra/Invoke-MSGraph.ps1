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
            $allResults = @()
            $nextLink = '/{0}?$count=true&$top=999' -f "$relativeUrl"

            do {
                $payload = @{
                    requests = @(
                        @{
                            id     = "List"
                            method = 'GET'
                            url    = $nextLink
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

                $apiResponse = (Invoke-RestMethod @requestParam)
                $allResults += $apiResponse.responses.body.value

                $nextLink = $apiResponse.responses.body.'@odata.nextLink'
            } while ($nextLink)

            return $allResults
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