function Invoke-GraphRecursive {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^(http|https)://[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,3}(/\S*)?$')]
        [string]$Url
    )

    begin {
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName $ResourceTypeName
    }

    process {

        try {

            Write-Verbose "Starting to collect data from Graph API"

            $requestParam = @{
                Headers = $script:graphHeader
                Uri     = $Url
                Method  = 'GET'
            }

            $apiResponse = Invoke-RestMethod @requestParam

            $count        = 0
            $apiResult    = $apiResponse.value
            $userNextLink = $apiResponse."@odata.nextLink"

            while ($null -ne $userNextLink) {

                $requestParam.uri = $userNextLink

                $apiResponse    = (Invoke-RestMethod @requestParam)
                $count = $count + ($apiResponse.value).count

                Write-Host "[+] Processed objects $($count)"`r -NoNewline
                $userNextLink   = $apiResponse."@odata.nextLink"
                $apiResult      += $apiResponse.value
            }

            return $apiResult
        }
        catch {
            if ($_.Exception.Message -contains "*401") {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Unauthorized access to the Graph API. Run Update-AccessToken -MSGraph" -Severity 'Error'
            }
        }
    }
    <#
    .SYNOPSIS
    This function retrieves data from the Graph API recursively.

    .DESCRIPTION
    The Get-GraphRecursive function is used to collect data from the Graph API in a recursive manner. It takes a URL parameter as input and retrieves data from the specified URL using the Graph API. The function handles pagination by following the "@odata.nextLink" property in the API response to retrieve additional data.

    .PARAMETER Url
    The URL parameter specifies the endpoint of the Graph API from which data needs to be retrieved. The URL must be a valid HTTP or HTTPS URL.

    .EXAMPLE
    Get-GraphRecursive -Url "https://graph.microsoft.com/beta/users"

    This example retrieves all user data from the Microsoft Graph API.

    .LINK
    More information about the Graph API can be found at:
    - [Microsoft Graph API documentation](https://docs.microsoft.com/graph/overview)
    - [Microsoft Graph API reference](https://docs.microsoft.com/graph/api/overview?view=graph-rest-1.0)
#>
}