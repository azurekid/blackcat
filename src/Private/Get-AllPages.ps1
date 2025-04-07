function Get-AllPages {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [object]$ProcessLink
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
    }

    process {
        try {
            Write-Verbose "Fetching data from MS Graph"
            $allItems = @($ProcessLink.responses.body.value)
            $nextLink = $ProcessLink.responses.body.'@odata.nextLink'
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
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
    <#
    .SYNOPSIS
        Retrieves all pages of data from Microsoft Graph API.

    .DESCRIPTION
        The Get-AllPages function fetches data from the Microsoft Graph API, handling pagination by following the '@odata.nextLink' property until all pages are retrieved. It returns all items from the paginated response.

    .PARAMETER NextLink
        The initial response object containing the '@odata.nextLink' property to start fetching data from Microsoft Graph API.

    .EXAMPLE
        $initialResponse = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/me/messages" -Headers $headers
        $allMessages = $initialResponse | Get-AllPages

        This example demonstrates how to use the Get-AllPages function to retrieve all messages from the Microsoft Graph API.

    .EXAMPLE
        $initialResponse = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users" -Headers $headers
        $allUsers = $initialResponse | Get-AllPages

        This example demonstrates how to use the Get-AllPages function to retrieve all users from the Microsoft Graph API.

    .LINK
        https://docs.microsoft.com/en-us/graph/api/overview
    #>
}