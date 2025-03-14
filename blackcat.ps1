
    [cmdletbinding()]
    param (

        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [Alias('vault', 'key-vault-name')]
        [string[]]$rZUGmDSfgXlo,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('throttle-limit')]
        [int]$BdAqJeZmxUtP = 1000
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'KeyVault'

        $KHrhXOsmGQMz  = New-Object System.Collections.ArrayList
    }

    process {
        try {
            Write-Verbose "Retrieving secrets from Key Vault(s): $($rZUGmDSfgXlo -join ', ')"

            if (!$rZUGmDSfgXlo) {
                $rZUGmDSfgXlo = (Invoke-AzBatch -ResourceType 'Microsoft.KeyVault/Vaults').Name
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) "processing $($Name.Count) KeyVaults" -Severity 'Information'
            }
            # First function: Get all secret URIs
            function Get-KeyVaultsecretUrls {
                param($iHVlFnYApThE, $BdAqJeZmxUtP, $ZMskKGiPSnVt)

                $lTaMdYyQnWiU = [System.Collections.Concurrent.ConcurrentBag[object]]::new()

                $iHVlFnYApThE | foreach -Parallel {
                    $gTdzuijbGacY = 'https://{0}.vault.azure.net/secrets?api-version=7.3' -f $_

                    $requestParam = @{
                        Headers = $using:ZMskKGiPSnVt
                        Uri     = $gTdzuijbGacY
                        Method  = 'GET'
                    }

                    try {
                        $AckBuDVCTNxp = irm @requestParam
                        if ($apiResponse.value.Count -gt 0) {
                            foreach ($hSpWbHUxsJAB in $apiResponse.value) {
                                ($using:lTaMdYyQnWiU).Add($hSpWbHUxsJAB)
                            }
                        }
                    }
                    catch {
                        if ($_.Exception.Message -match "NotFound") {
                            Write-Verbose "Key Vault not found: $_"
                        }
                    }
                } -ThrottleLimit $BdAqJeZmxUtP

                return $lTaMdYyQnWiU
            }

            # Second function: Get secret values
            function Get-KeyVaultSecretValues {
                param($lTaMdYyQnWiU, $BdAqJeZmxUtP, $ZMskKGiPSnVt)

                $XHuTNrMwFDki = [System.Collections.Concurrent.ConcurrentBag[object]]::new()

                $secretUrls.id | foreach -Parallel {
                    $bLmqBIQFSWMs = $_.split('.')[0].Split('https://')[1]

                    $requestParam = @{
                        Headers = $using:ZMskKGiPSnVt
                        Uri     = '{0}/?api-version=7.4' -f $_
                        Method  = 'GET'
                    }

                    try {
                        $gvTwBaNASnbX = irm @requestParam
                        $gXfSLpoVeOiw = [PSCustomObject]@{
                            "KeyVaultName" = $bLmqBIQFSWMs
                            "SecretName"   = "$($_.Split('/')[4])"
                            "Value"        = $secretResponse.value
                        }
                        ($using:XHuTNrMwFDki).Add($gXfSLpoVeOiw)
                    }
                    catch {
                        if ($_.Exception.Message -match "Forbidden") {
                            Write-Verbose "Insufficient Permissions"
                        }
                        else {
                            Write-Verbose "Error occurred while retrieving secret: $($_.Exception.Message)"
                        }
                    }
                } -ThrottleLimit $BdAqJeZmxUtP

                return $XHuTNrMwFDki
            }

            # Execute the functions
            $nXOImugAcBaE = Get-KeyVaultsecretUrls -VaultNames $rZUGmDSfgXlo -ThrottleLimit $BdAqJeZmxUtP -AuthHeader $script:keyVaultHeader
            if ($uris.Count -gt 0) {
                $XHuTNrMwFDki = @(Get-KeyVaultSecretValues -secretUrls $nXOImugAcBaE -ThrottleLimit $BdAqJeZmxUtP -AuthHeader $script:keyVaultHeader)
                $result.AddRange($XHuTNrMwFDki)
            }
            else {
                Write-Verbose -Message "No secrets found in Key Vault '$($rZUGmDSfgXlo)'"
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }

    end {
        Write-Verbose "Completed function $($MyInvocation.MyCommand.Name)"
        if (!$KHrhXOsmGQMz) {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "No secrets found" -Severity 'Information'
        } else {
            return $KHrhXOsmGQMz | Sort-Object KeyVaultName, SecretName, Value
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

