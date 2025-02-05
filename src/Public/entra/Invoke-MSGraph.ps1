function Invoke-MsGraph {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $false)]
        [string]$relativeUrl,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [switch]$NoBatch
    )

    begin {
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
    }

    process {

        try {
            if ($NoBatch) {
                $uri = "$($sessionVariables.graphUri)/$relativeUrl"
                $requestParam = @{
                    Headers = $script:graphHeader
                    Uri     = $uri
                    Method  = 'GET'
                }
            } 
            else {
            
            $payload = @{
                requests = @(
                    @{
                        id     = "List"
                        method = 'GET'
                        url    = '/{0}' -f "$relativeUrl"
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
        }

            $initialResponse = (Invoke-RestMethod @requestParam)
            $allItems = Get-AllPages -ProcessLink $initialResponse
            return $allItems

        }
        catch {
            if ($_.Exception.Message -contains "*401") {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Unauthorized access to the Graph API." -Severity 'Error'
            } else {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
            }
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