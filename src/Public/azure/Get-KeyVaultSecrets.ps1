function Get-KeyVaultSecrets {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [object]$id,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [int]$ThrottleLimit = 10000
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'KeyVault'

        $result = New-Object System.Collections.ArrayList
        # $secrets = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
        $secrets = New-Object System.Collections.ArrayList
        
        $totalItems = $id.Count
        $currentItemIndex = 0
    }

    process {
        try {
            Write-Verbose "Retrieving Key Vault secrets for $(($id).count) vaults"

            $id | ForEach-Object -Parallel {
                # try {
                    $baseUri    = $using:SessionVariables.baseUri
                    $authHeader = $using:script:keyVaultHeader
                    $result     = $using:result
                    $secrets    = $using:secrets
                    $totalItems = $using:totalItems
                    $currentItemIndex = [System.Threading.Interlocked]::Increment([ref]$using:currentItemIndex)

                    $uri = 'https://{0}.vault.azure.net/secrets?api-version=7.3' -f $_.split('/')[-1]
                    Write-Host "Retrieving secrets for keyvault $uri"
                    $requestParam = @{
                        Headers = $authHeader
                        Uri     = $uri
                        Method  = 'GET'
                    }

                    $apiResponse = Invoke-RestMethod @requestParam
                    
                    if ($apiResponse.value.Count -gt 0) {
                        [void] $secrets.Add($apiResponse.value)
                    }

                    
                # }
                # catch {
                #     Write-Information "$($MyInvocation.MyCommand.Name): Key Vault '$_' does not exist"  -InformationAction Continue
                # }
            } -ThrottleLimit $ThrottleLimit

            if ($secrets.count -gt 0) {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Found $($secrets.count) Key Vaults that contains secrets" -Severity 'Information'
                $secrets.id | ForEach-Object -Parallel {
                    $authHeader = $using:script:keyVaultHeader
                    $result     = $using:result
                    $secrets    = $using:secrets

                    $requestParam = @{
                        Headers = $authHeader
                        Uri     = "$_/?api-version=7.4"
                        Method  = 'GET'
                    }

                    try {
                        try {
                            $secretResponse = Invoke-RestMethod @requestParam
                        }
                        catch {
                            Write-Verbose "Error occurred while retrieving secret: $($_.Exception.Message)"
                            continue
                        }
                        
                        $currentItem = [PSCustomObject]@{
                            "KeyVaultName" = $_.split('.')[0].Split('https://')[1]
                            "SecretName" = "$($_.Split('/')[4])"
                            "Value" = $secretResponse.value
                        }
                        
                        [void] $result.Add($currentItem)        
                    }
                    catch {
                        if ($_.Exception.Forbidden -match "Forbidden") {
                            Write-Verbose "Insufficient Permissions"# Write-Output $_.Exception
                        }
                        }
                    $secretResponse = Invoke-RestMethod @requestParam
                    
                    $currentItem = [PSCustomObject]@{
                        "KeyVaultName" = $_.split('.')[0].Split('https://')[1]
                        "SecretName" = "$($_.Split('/')[4])"
                        "Value" = $secretResponse.value
                    }
                    
                    [void] $result.Add($currentItem)        
                }
            }
            else {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "No secrets found" -Severity 'Information'
            }
            
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }   
    }

    end {
        Write-Verbose "Completed function $($MyInvocation.MyCommand.Name)"
        return $result
    }
}
