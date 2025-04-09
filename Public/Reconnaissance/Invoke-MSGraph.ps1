function Invoke-MsGraph {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $false)]
        [string]$relativeUrl,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [switch]$NoBatch,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [int]$MaxRetries = 3,  # Maximum number of retries

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [int]$RetryDelaySeconds = 5 # Initial delay in seconds
    )

    begin {
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
    }

    process {
        $retries = 0
        do {
            try {
                if ($NoBatch) {
                    $uri = "$($sessionVariables.graphUri)/$relativeUrl" -replace 'applications/\(', 'applications('
                    Write-Verbose "Invoking Microsoft Graph API: $uri"
                    $requestParam = @{
                        Headers = $script:graphHeader
                        Uri     = $uri
                        Method  = 'GET'
                        UserAgent = $($sessionVariables.userAgent)
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
                        UserAgent   = $($sessionVariables.userAgent)
                    }
                }

                $initialResponse = (Invoke-RestMethod @requestParam)

                if ($NoBatch) {
                    return $initialResponse
                }

                # Check for throttling headers
                if ($initialResponse.Headers."Retry-After") {
                    $retryAfter = [int]$initialResponse.Headers."Retry-After"
                    Write-Warning "Throttled!  Waiting $($retryAfter) seconds before retrying."
                    Start-Sleep -Seconds $retryAfter
                    $retries++ # Increment retries, important to track
                    continue  # Skip the rest of the loop and retry
                }

                $allItems = Get-AllPages -ProcessLink $initialResponse
                return $allItems

            }
            catch {
                if ($_.Exception.Message -contains "*429*") { # Check for specific throttling error
                    $retries++
                    $retryAfter = $RetryDelaySeconds * ($retries) # Exponential backoff
                    Write-Warning "Throttled!  Retry $($retries) of $($MaxRetries). Waiting $($retryAfter) seconds before retrying."
                    Start-Sleep -Seconds $retryAfter
                }
                elseif ($_.Exception.Message -contains "*401") {
                    Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Unauthorized access to the Graph API." -Severity 'Error'
                    break # No point in retrying if unauthorized
                }
                 else {
                    Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
                     break # Break out of the retry loop for other errors
                }
            }
        } while ($retries -lt $MaxRetries)

        if ($retries -ge $MaxRetries) {
            Write-Error "Max retries reached.  Failed to execute request after $($MaxRetries) attempts."
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