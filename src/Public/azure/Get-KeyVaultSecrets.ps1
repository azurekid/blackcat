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

        $result  = New-Object System.Collections.ArrayList
        $secrets = New-Object System.Collections.ArrayList

        $totalItems = $id.Count
        $currentItemIndex = 0
    }

    process {
        try {
            Write-Verbose "Retrieving Key Vault secrets for $(($id).count) vaults"

            $id | ForEach-Object -Parallel {
                $authHeader       = $using:script:keyVaultHeader
                $result           = $using:result
                $secrets          = $using:secrets
                $totalItems       = $using:totalItems
                $currentItemIndex = [System.Threading.Interlocked]::Increment([ref]$using:currentItemIndex)

                $uri = 'https://{0}.vault.azure.net/secrets?api-version=7.3' -f $_.split('/')[-1]
                Write-Verbose "Retrieving secrets from $uri"
                $requestParam = @{
                    Headers = $authHeader
                    Uri     = $uri
                    Method  = 'GET'
                }

                $apiResponse = Invoke-RestMethod @requestParam

                if ($apiResponse.value.Count -gt 0) {
                    [void] $secrets.Add($apiResponse.value)
                }
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
                        $secretResponse = Invoke-RestMethod @requestParam

                        $currentItem = [PSCustomObject]@{
                            "KeyVaultName" = $_.split('.')[0].Split('https://')[1]
                            "SecretName"   = "$($_.Split('/')[4])"
                            "Value"        = $secretResponse.value
                        }

                        [void] $result.Add($currentItem) | Sort-Object -Unique
                    }
                    catch {
                        if ($_.Exception.Message -match "Forbidden") {
                            Write-Verbose "Insufficient Permissions"
                        }
                        else {
                            Write-Verbose "Error occurred while retrieving secret: $($_.Exception.Message)"
                        }
                    }
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
