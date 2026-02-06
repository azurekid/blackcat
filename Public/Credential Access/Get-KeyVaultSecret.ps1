function Get-KeyVaultSecret {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceNameCompleterAttribute(
            "Microsoft.KeyVault/vaults",
            "ResourceGroupName"
        )]
        [Alias('vault', 'key-vault-name', 'KeyVaultName')]
        [string[]]$Name,

        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceGroupCompleterAttribute()]
        [Alias('rg', 'resource-group')]
        [string[]]$ResourceGroupName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('throttle-limit')]
        [int]$ThrottleLimit = 1000,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Object", "JSON", "CSV", "Table")]
        [Alias("output", "o")]
        [string]$OutputFormat = "Table"
    )

    begin {
        Write-Verbose " Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'KeyVault'

        $result  = New-Object System.Collections.ArrayList

        $stats = @{
            StartTime = Get-Date
            TotalVaults = 0
            VaultsWithSecrets = 0
            TotalSecrets = 0
            ProcessingErrors = 0
            ForbiddenByPolicy = 0
            InsufficientPermissions = 0
            TotalAccessDenied = 0
        }
    }

    process {
        try {
            function Get-KeyVaultSecretUris {
                param($VaultNames, $ThrottleLimit, $AuthHeader)

                $secretUris = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
                $policyForbiddenBag = [System.Collections.Concurrent.ConcurrentBag[int]]::new()
                $permissionForbiddenBag = [System.Collections.Concurrent.ConcurrentBag[int]]::new()
                $generalErrorsBag = [System.Collections.Concurrent.ConcurrentBag[int]]::new()
                
                $VaultNames | ForEach-Object -Parallel {
                    $vaultName = $_
                    $uri = 'https://{0}.vault.azure.net/secrets?api-version=7.3' -f $vaultName

                    $requestParam = @{
                        Headers = $using:AuthHeader
                        Uri     = $uri
                        Method  = 'GET'
                        UserAgent = $using:sessionVariables.userAgent
                    }

                    try {
                        $apiResponse = Invoke-RestMethod @requestParam
                        if ($apiResponse.value.Count -gt 0) {
                            Write-Host "    Found $($apiResponse.value.Count) secrets in vault: $vaultName" -ForegroundColor Green
                            foreach ($value in $apiResponse.value) {
                                ($using:secretUris).Add($value)
                            }
                        } else {
                            Write-Host "    No secrets found in vault: $vaultName" -ForegroundColor Gray
                        }
                    }
                    catch {
                        $errorMsg = $_.Exception.Message
                        Write-Verbose "Full vault access error: $errorMsg"
                        
                        if ($errorMsg -match "NotFound") {
                            Write-Host "    Key Vault not found: $vaultName" -ForegroundColor Red
                            ($using:generalErrorsBag).Add(1)
                        } 
                        elseif ($errorMsg -match "Forbidden|AccessDenied|Unauthorized") {
                            # Check for policy-related errors
                            if (($errorMsg -match "ForbiddenByPolicy") -or
                                ($errorMsg -match "[Pp]olicy") -or 
                                ($errorMsg -match "RBAC") -or
                                ($errorMsg -match "AccessPolicy")) {
                                
                                ($using:policyForbiddenBag).Add(1)
                            } else {
                                ($using:permissionForbiddenBag).Add(1)
                            }
                        }
                        else {
                            ($using:generalErrorsBag).Add(1)
                        }
                    }
                } -ThrottleLimit $ThrottleLimit
                
                # Count the results from concurrent bags
                $policyForbidden = $policyForbiddenBag.Count
                $permissionForbidden = $permissionForbiddenBag.Count
                $generalErrors = $generalErrorsBag.Count
                
                Write-Host "    Vault access summary: $policyForbidden policy denials, $permissionForbidden permission denials" -ForegroundColor Cyan
                
                return @{
                    SecretUris = $secretUris
                    PolicyForbidden = $policyForbidden
                    PermissionForbidden = $permissionForbidden
                    GeneralErrors = $generalErrors
                }
            }

            function Get-KeyVaultSecretValue {
                param($SecretUris, $ThrottleLimit, $AuthHeader)

                $secretValues = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
                $policyForbiddenBag = [System.Collections.Concurrent.ConcurrentBag[int]]::new()
                $permissionForbiddenBag = [System.Collections.Concurrent.ConcurrentBag[int]]::new()
                $generalErrorBag = [System.Collections.Concurrent.ConcurrentBag[int]]::new()

                $SecretUris.id | ForEach-Object -Parallel {
                    $currentUri = $_
                    $vault = $currentUri.split('.')[0].Split('https://')[1]
                    $secretName = $currentUri.Split('/')[4]

                    $requestParam = @{
                        Headers = $using:AuthHeader
                        Uri     = '{0}/?api-version=7.4' -f $currentUri
                        Method  = 'GET'
                        UserAgent = $using:sessionVariables.userAgent
                    }

                    try {
                        $secretResponse = Invoke-RestMethod @requestParam
                        $currentItem = [PSCustomObject]@{
                            "KeyVaultName" = $vault
                            "SecretName"   = $secretName
                            "Value"        = $secretResponse.value
                        }
                        ($using:secretValues).Add($currentItem)
                    }
                    catch {
                        $errorMsg = $_.Exception.Message
                        Write-Verbose "Exception message: $errorMsg"
                        
                        if ($errorMsg -match "Forbidden|AccessDenied|Unauthorized") {
                            if (($errorMsg -match "ForbiddenByPolicy") -or
                                ($errorMsg -match "[Pp]olicy") -or 
                                ($errorMsg -match "RBAC") -or
                                ($errorMsg -match "AccessPolicy")) {
                                    
                                ($using:policyForbiddenBag).Add(1)
                            } else {
                                ($using:permissionForbiddenBag).Add(1)
                            }
                        }
                        else {
                            ($using:generalErrorBag).Add(1)
                        }
                    }
                } -ThrottleLimit $ThrottleLimit

                # Count the results from concurrent bags
                $policyForbiddenCount = $policyForbiddenBag.Count
                $permissionForbiddenCount = $permissionForbiddenBag.Count
                $generalErrorCount = $generalErrorBag.Count
                
                return @{
                    SecretValues = $secretValues
                    ForbiddenByPolicyCount = $policyForbiddenCount
                    InsufficientPermissionsCount = $permissionForbiddenCount
                    GeneralErrorCount = $generalErrorCount
                }
            }

            Write-Host "Analyzing Key Vault secrets..." -ForegroundColor Green

            if ($Name) {
                $vaults = (Invoke-AzBatch -ResourceType 'Microsoft.KeyVault/Vaults' | Where-Object Name -in $Name)
                Write-Host "  Processing specified Key Vault(s): $($Name -join ', ')" -ForegroundColor Cyan
            } else {
                $vaults = (Invoke-AzBatch -ResourceType 'Microsoft.KeyVault/Vaults')
                Write-Host "  Processing all available Key Vaults ($($vaults.Count) found)" -ForegroundColor Cyan
            }

            $stats.TotalVaults = $vaults.Count

            if ($vaults.Count -eq 0) {
                Write-Host "  No Key Vaults found to process" -ForegroundColor Yellow
                return
            }

            Write-Host "  Discovering secrets in $($vaults.Count) Key Vault(s)..." -ForegroundColor Yellow

            $requestParam = @{
                VaultNames    = $vaults.name
                ThrottleLimit = $ThrottleLimit
                AuthHeader    = $script:keyVaultHeader
            }

            $urisResult = Get-KeyVaultSecretUris @requestParam
            $uris = $urisResult.SecretUris
            
            $stats.ForbiddenByPolicy = $urisResult.PolicyForbidden
            $stats.InsufficientPermissions = $urisResult.PermissionForbidden
            $stats.ProcessingErrors = $urisResult.GeneralErrors
            $stats.TotalAccessDenied = $stats.ForbiddenByPolicy + $stats.InsufficientPermissions
            
            Write-Verbose "Stats after vault processing:"
            Write-Verbose "  ForbiddenByPolicy: $($stats.ForbiddenByPolicy)"
            Write-Verbose "  InsufficientPermissions: $($stats.InsufficientPermissions)"
            Write-Verbose "  TotalAccessDenied: $($stats.TotalAccessDenied)"

            if ($uris.Count -gt 0) {
                Write-Host "  Retrieving $($uris.Count) secret value(s)..." -ForegroundColor Yellow

                $requestParam = @{
                    AuthHeader = $script:keyVaultHeader
                    ThrottleLimit = $ThrottleLimit
                    SecretUris = $uris
                }

                $secretResult = Get-KeyVaultSecretValue @requestParam
                $secretValues = @($secretResult.SecretValues)
                $result.AddRange($secretValues)
                $stats.TotalSecrets = $secretValues.Count
                $stats.VaultsWithSecrets = ($secretValues | Group-Object KeyVaultName).Count

                $stats.ForbiddenByPolicy += $secretResult.ForbiddenByPolicyCount
                $stats.InsufficientPermissions += $secretResult.InsufficientPermissionsCount
                $stats.ProcessingErrors += $secretResult.GeneralErrorCount
                $stats.TotalAccessDenied = $stats.ForbiddenByPolicy + $stats.InsufficientPermissions
            }
            else {
                Write-Host "  No secrets found in Key Vault(s): $($vaults.name -join ', ')" -ForegroundColor Gray
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }

    end {
        $Duration = (Get-Date) - $stats.StartTime

        Write-Host "`nKey Vault Secret Discovery Summary:" -ForegroundColor Magenta
        Write-Host "   Total Key Vaults Analyzed: $($stats.TotalVaults)" -ForegroundColor White
        Write-Host "   Key Vaults with Secrets: $($stats.VaultsWithSecrets)" -ForegroundColor Yellow
        Write-Host "   Total Secrets Retrieved: $($stats.TotalSecrets)" -ForegroundColor Green
        
        Write-Host "   Access Summary:" -ForegroundColor Cyan
        Write-Host "     • Secrets Forbidden by Policy: $($stats.ForbiddenByPolicy)" -ForegroundColor Red 
        Write-Host "     • Insufficient Permissions: $($stats.InsufficientPermissions)" -ForegroundColor Yellow
        Write-Host "     • Total Access Denied: $($stats.TotalAccessDenied)" -ForegroundColor Red
        
        if ($stats.ProcessingErrors -gt 0) {
            Write-Host "   Processing Errors: $($stats.ProcessingErrors)" -ForegroundColor Red
        }
        Write-Host "   Duration: $($Duration.TotalSeconds.ToString('F2')) seconds" -ForegroundColor White

        Write-Verbose "Completed function $($MyInvocation.MyCommand.Name)"

        if (!$result -or $result.Count -eq 0) {
            switch ($OutputFormat) {
                "JSON" {
                    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    $jsonOutput = @() | ConvertTo-Json
                    $jsonFilePath = "KeyVaultSecrets_$timestamp.json"
                    $jsonOutput | Out-File -FilePath $jsonFilePath -Encoding UTF8
                    Write-Host "Empty JSON output saved to: $jsonFilePath" -ForegroundColor Green
                    return
                }
                "CSV" {
                    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    $csvOutput = @() | ConvertTo-CSV
                    $csvFilePath = "KeyVaultSecrets_$timestamp.csv"
                    $csvOutput | Out-File -FilePath $csvFilePath -Encoding UTF8
                    Write-Host "Empty CSV output saved to: $csvFilePath" -ForegroundColor Green
                    return
                }
                "Object" {
                    Write-Host "`nNo secrets found" -ForegroundColor Red
                    return @()
                }
                "Table" {
                    Write-Host "`nNo secrets found" -ForegroundColor Red
                    return @()
                }
            }
        } else {
            switch ($OutputFormat) {
                "JSON" {
                    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    $jsonOutput = $result | Sort-Object KeyVaultName, SecretName, Value | ConvertTo-Json -Depth 3
                    $jsonFilePath = "KeyVaultSecrets_$timestamp.json"
                    $jsonOutput | Out-File -FilePath $jsonFilePath -Encoding UTF8
                    Write-Host "JSON output saved to: $jsonFilePath" -ForegroundColor Green
                    return
                }
                "CSV" {
                    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    $csvOutput = $result | Sort-Object KeyVaultName, SecretName, Value | ConvertTo-CSV
                    $csvFilePath = "KeyVaultSecrets_$timestamp.csv"
                    $csvOutput | Out-File -FilePath $csvFilePath -Encoding UTF8
                    Write-Host "CSV output saved to: $csvFilePath" -ForegroundColor Green
                    return
                }
                "Object" { return $result | Sort-Object KeyVaultName, SecretName, Value }
                "Table"  { return $result | Sort-Object KeyVaultName, SecretName, Value | Format-Table -AutoSize }
            }
        }
    }
    <#
.SYNOPSIS
Retrieves secrets from specified Azure Key Vaults.

.DESCRIPTION
Retrieves secrets from specified Azure Key Vaults with parallel processing and formatted output. This function enumerates secrets from Key Vaults and extracts their current values. Critical for discovering and exfiltrating sensitive data stored in Key Vaults.

.PARAMETER Name
An array of Key Vault names from which to retrieve secrets. This parameter is optional and accepts pipeline input by property name. If not specified, all available Key Vaults will be processed.

.PARAMETER ResourceGroupName
An optional array of resource group names to filter Key Vaults. This parameter accepts pipeline input and helps narrow down the search scope.

.PARAMETER ThrottleLimit
An optional parameter that specifies the maximum number of concurrent threads to use for parallel processing. The default value is 1000.

.PARAMETER OutputFormat
Optional. Specifies the output format for results. Valid values are:
- Object: Returns PowerShell objects (default when piping)
- JSON: Creates timestamped JSON file (KeyVaultSecrets_TIMESTAMP.json) with no console output
- CSV: Creates timestamped CSV file (KeyVaultSecrets_TIMESTAMP.csv) with no console output
- Table: Returns results in a formatted table (default)
Aliases: output, o

.EXAMPLE
PS C:\> Get-KeyVaultSecret -Name "MyKeyVault1", "MyKeyVault2"

This command retrieves secrets from the specified Key Vaults "MyKeyVault1" and "MyKeyVault2" using the default table format.

.EXAMPLE
PS C:\> "MyKeyVault1", "MyKeyVault2" | Get-KeyVaultSecret

This command retrieves secrets from the specified Key Vaults "MyKeyVault1" and "MyKeyVault2" using pipeline input.

.EXAMPLE
PS C:\> Get-KeyVaultSecret -OutputFormat JSON

This command retrieves secrets from all available Key Vaults and creates a timestamped JSON file (e.g., KeyVaultSecrets_20250629_143022.json) in the current directory.

.EXAMPLE
PS C:\> Get-KeyVaultSecret -Name "ProductionVault" -OutputFormat CSV -ThrottleLimit 500

This command retrieves secrets from "ProductionVault" using a custom throttle limit and saves results to a timestamped CSV file.

.EXAMPLE
PS C:\> $secrets = Get-KeyVaultSecret -OutputFormat Object
PS C:\> $productionSecrets = $secrets | Where-Object { $_.KeyVaultName -like "*prod*" }

This command stores results in a variable and filters for production-related Key Vaults.

.NOTES
This function requires the Azure Key Vault REST API and appropriate permissions to access the secrets in the specified Key Vaults.
File: Get-KeyVaultSecret.ps1
Author: Rogier Dijkman
Version: 2.0
Requires: PowerShell 7.0 or later for parallel processing

.LINK
MITRE ATT&CK Tactic: TA0006 - Credential Access
https://attack.mitre.org/tactics/TA0006/

.LINK
MITRE ATT&CK Technique: T1555.006 - Credentials from Password Stores: Cloud Secrets Management Stores
https://attack.mitre.org/techniques/T1555/006/

#>
}
