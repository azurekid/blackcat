$ResourceTypeNames = @("MSGraph", "ResourceManager", "KeyVault", "Storage", "Synapse", "OperationalInsights", "Batch")
$OutputFile = "accesstokens.json"

try {
    Write-Host "Requesting access tokens for specified audiences"
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

Write-Host "Exporting tokens to file $OutputFile"
    $tokens | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputFile
}
catch {
    Write-Error "An error occurred in function $($MyInvocation.MyCommand.Name): $($_.Exception.Message)"
}
