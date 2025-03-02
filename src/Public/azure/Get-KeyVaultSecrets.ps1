function Get-KeyVaultSecrets {
    [cmdletbinding()]
    param (

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceNameCompleterAttribute(
            "Microsoft.KeyVault/vaults",
            "ResourceGroupName"
        )]
        [Alias('vault', 'key-vault-name')]
        [array]$Name,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('throttle-limit')]
        [int]$ThrottleLimit = 1000
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'KeyVault'

        $result  = New-Object System.Collections.ArrayList
        $secrets = New-Object System.Collections.ArrayList
        $secretsUri = New-Object System.Collections.ArrayList

        $totalItems = $Name.Count
        $currentItemIndex = 0
    }

    process {
        try {
            Write-Verbose "Retrieving Key Vault secrets for $(($Name).count) vaults"

            $Name | ForEach-Object -Parallel {
                $authHeader       = $using:script:keyVaultHeader
                $result           = $using:result
                $secrets          = $using:secrets
                $secretsUri       = $using:secretsUri
                $totalItems       = $using:totalItems
                $currentItemIndex = [System.Threading.Interlocked]::Increment([ref]$using:currentItemIndex)

                $uri = 'https://{0}.vault.azure.net/secrets?api-version=7.3' -f $_

                $requestParam = @{
                    Headers = $authHeader
                    Uri     = $uri
                    Method  = 'GET'
                }

                    try {
                        $apiResponse = Invoke-RestMethod @requestParam
                    }
                    catch {
                        if ($_.Exception.Message -match "NotFound") {
                            Write-Verbose "Key Vault not found: $_"
                        }
                    }

                if ($apiResponse.value.Count -gt 0) {
                    [void] $secretsUri.Add($apiResponse.value)
                }
            } -ThrottleLimit $ThrottleLimit

            if ($secretsUri.count -gt 0) {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Found $($secretsUri.count) Key Vaults that contains secrets" -Severity 'Information'

                $secretsUri.id | ForEach-Object -Parallel {
                    $authHeader = $using:script:keyVaultHeader
                    $result     = $using:result


                    $requestParam = @{
                        Headers = $authHeader
                        Uri     = '{0}/?api-version=7.4' -f $_
                        Method  = 'GET'
                    }

                    try {
                        $secretResponse = Invoke-RestMethod @requestParam

                        $currentItem = [PSCustomObject]@{
                            "KeyVaultName" = $_.split('.')[0].Split('https://')[1]
                            "SecretName"   = "$($_.Split('/')[4])"
                            "Value"        = $secretResponse.value
                        }

                        [void] $result.Add($currentItem)
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
        return $result | Sort-Object KeyVaultName, SecretName, Value -Unique
    }
<#
.SYNOPSIS
Retrieves secrets from specified Azure Key Vaults.

.DESCRIPTION
The Get-KeyVaultSecrets function retrieves secrets from the specified Azure Key Vaults. It supports parallel processing to handle multiple vaults and secrets efficiently.

.PARAMETER Name
An array of Key Vault names from which to retrieve secrets. This parameter is mandatory and accepts pipeline input by property name.

.PARAMETER ThrottleLimit
An optional parameter that specifies the maximum number of concurrent threads to use for parallel processing. The default value is 1000.

.EXAMPLE
PS C:\> Get-KeyVaultSecrets -Name "MyKeyVault1", "MyKeyVault2"

This command retrieves secrets from the specified Key Vaults "MyKeyVault1" and "MyKeyVault2".

.EXAMPLE
PS C:\> "MyKeyVault1", "MyKeyVault2" | Get-KeyVaultSecrets

This command retrieves secrets from the specified Key Vaults "MyKeyVault1" and "MyKeyVault2" using pipeline input.

.NOTES
This function requires the Azure Key Vault REST API and appropriate permissions to access the secrets in the specified Key Vaults.

#>
}
