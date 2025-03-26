function Get-KeyVaultSecrets {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceNameCompleterAttribute(
            "Microsoft.KeyVault/vaults",
            "ResourceGroupName"
        )]
        [Alias('vault', 'key-vault-name', 'KeyVaultName')]
        [string[]]$Name,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [bool]$DisableLogging,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('throttle-limit')]
        [int]$ThrottleLimit = 1000
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'KeyVault'

        $result  = New-Object System.Collections.ArrayList
    }

    process {
        try {
            Write-Verbose "Retrieving secrets from Key Vault(s): $($Name -join ', ')"

            if (!$Name) {
                $vaults = (Invoke-AzBatch -ResourceType 'Microsoft.KeyVault/Vaults')
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) "processing $($vaults.Count) KeyVaults" -Severity 'Information'
            } else {
                $vaults = Invoke-AzBatch -ResourceType 'Microsoft.KeyVault/Vaults' -filter "| where name in ('$(($Name -join "','"))')"
            }
            # First function: Get all secret URIs
            function Get-KeyVaultSecretUris {
                param($VaultNames, $ThrottleLimit, $AuthHeader)

                $secretUris = [System.Collections.Concurrent.ConcurrentBag[object]]::new()

                $VaultNames | ForEach-Object -Parallel {
                    $uri = 'https://{0}.vault.azure.net/secrets?api-version=7.3' -f $_

                    $requestParam = @{
                        Headers = $using:AuthHeader
                        Uri     = $uri
                        Method  = 'GET'
                    }

                    try {
                        $apiResponse = Invoke-RestMethod @requestParam
                        if ($apiResponse.value.Count -gt 0) {
                            foreach ($value in $apiResponse.value) {
                                ($using:secretUris).Add($value)
                            }
                        }
                    }
                    catch {
                        if ($_.Exception.Message -match "NotFound") {
                            Write-Verbose "Key Vault not found: $_"
                        }
                    }
                } -ThrottleLimit $ThrottleLimit

                return $secretUris
            }

            # Second function: Get secret values
            function Get-KeyVaultSecretValues {
                param($SecretUris, $ThrottleLimit, $AuthHeader)

                $secretValues = [System.Collections.Concurrent.ConcurrentBag[object]]::new()

                $SecretUris.id | ForEach-Object -Parallel {
                    $vault = $_.split('.')[0].Split('https://')[1]

                    $requestParam = @{
                        Headers = $using:AuthHeader
                        Uri     = '{0}/?api-version=7.4' -f $_
                        Method  = 'GET'
                    }

                    try {
                        $secretResponse = Invoke-RestMethod @requestParam
                        $currentItem = [PSCustomObject]@{
                            "KeyVaultName" = $vault
                            "SecretName"   = "$($_.Split('/')[4])"
                            "Value"        = $secretResponse.value
                        }
                        ($using:secretValues).Add($currentItem)
                    }
                    catch {
                        if ($_.Exception.Message -match "Forbidden") {
                            Write-Verbose "Insufficient Permissions"
                        }
                        else {
                            Write-Verbose "Error occurred while retrieving secret: $($_.Exception.Message)"
                        }
                    }
                } -ThrottleLimit $ThrottleLimit

                if ($DisableLogging) {
                    $vaults.id | ForEach-Object {
                        Set-DiagnosticsLogging -ResourceId $_ -Enable $true
                    }
                }

                return $secretValues
            }

            # Execute the functions
            $requestParam = @{
                VaultNames    = $vaults.name
                ThrottleLimit = $ThrottleLimit
                AuthHeader    = $script:keyVaultHeader
            }

            if ($DisableLogging) {
                $vaults.id | ForEach-Object {
                    Set-DiagnosticsLogging -ResourceId $_
                }
            }

            $uris = Get-KeyVaultSecretUris @requestParam
            if ($uris.Count -gt 0) {

                $requestParam = @{
                    AuthHeader = $script:keyVaultHeader
                    ThrottleLimit = $ThrottleLimit
                    SecretUris = $uris
                }

                $secretValues = @(Get-KeyVaultSecretValues @requestParam)
                $result.AddRange($secretValues)
            }

            else {
                Write-Verbose -Message "No secrets found in Key Vault '$($vaults.name)'"
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }

    end {
        Write-Verbose "Completed function $($MyInvocation.MyCommand.Name)"
        if (!$result) {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "No secrets found" -Severity 'Information'
        } else {
            return $result | Sort-Object KeyVaultName, SecretName, Value
        }
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
