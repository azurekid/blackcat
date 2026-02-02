function Get-StorageAccountKey {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceNameCompleterAttribute(
            "Microsoft.Storage/StorageAccounts",
            "ResourceGroupName"
        )]
        [Alias('storageAccount', 'storage-account-name', 'storageAccountName')]
        [string[]]$Name,

        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceGroupCompleterAttribute()]
        [Alias('rg', 'resource-group')]
        [string[]]$ResourceGroupName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias('resource-id')]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceIdCompleter(
            "Microsoft.storage/storageAccounts"
        )][object]$Id,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('kerb-key', 'kerberos-key')]
        [switch]$KerbKey,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('throttle-limit')]
        [int]$ThrottleLimit = 100,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Object", "JSON", "CSV", "Table")]
        [Alias("output", "o")]
        [string]$OutputFormat = "Table"
    )

    begin {
        [void] $ResourceGroupName #Only used to trigger the ResourceGroupCompleter

        Write-Verbose " Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat

        $result = New-Object System.Collections.ArrayList

        # Initialize stats tracking similar to Get-KeyVaultSecret
        $stats = @{
            StartTime = Get-Date
            TotalStorageAccounts = 0
            StorageAccountsWithKeys = 0
            TotalKeysRetrieved = 0
            ProcessingErrors = 0
            ForbiddenByPolicy = 0
            InsufficientPermissions = 0
            TotalAccessDenied = 0
        }

        # Debug output to verify initialization
        Write-Verbose "Stats initialized: ForbiddenByPolicy=$($stats.ForbiddenByPolicy), InsufficientPermissions=$($stats.InsufficientPermissions)"
    }

    process {
        try {
            Write-Host "Analyzing Storage Account keys..." -ForegroundColor Green

            if (!$($Name) -and !$Id) {
                $id = (Invoke-AzBatch -ResourceType 'Microsoft.Storage/storageaccounts').id
                Write-Host "  Processing all available Storage Accounts ($($id.Count) found)" -ForegroundColor Cyan
            } elseif ($($Name)) {
                $id = (Invoke-AzBatch -ResourceType 'Microsoft.Storage/storageaccounts' -Name $($Name)).id
                Write-Host "  Processing specified Storage Account(s): $($Name -join ', ')" -ForegroundColor Cyan
            } else {
                $id = $Id
                Write-Host "  Processing Storage Account(s) by Resource ID ($($id.Count) specified)" -ForegroundColor Cyan
            }

            $stats.TotalStorageAccounts = $id.Count

            if ($id.Count -eq 0) {
                Write-Host "  No Storage Accounts found to process" -ForegroundColor Yellow
                return
            }

            Write-Host "  Retrieving keys from $($id.Count) Storage Account(s)..." -ForegroundColor Yellow

            # Use concurrent collections for thread-safe operations
            $successfulKeys = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
            $policyForbiddenBag = [System.Collections.Concurrent.ConcurrentBag[int]]::new()
            $permissionForbiddenBag = [System.Collections.Concurrent.ConcurrentBag[int]]::new()
            $generalErrorBag = [System.Collections.Concurrent.ConcurrentBag[int]]::new()

            $id | ForEach-Object -Parallel {
                try {
                    $KerbKey = $using:KerbKey
                    $currentResourceId = $_
                    $storageAccountName = $currentResourceId.split('/')[-1]

                    $uri = 'https://management.azure.com{0}/listKeys?api-version=2024-01-01' -f $currentResourceId
                    if ($KerbKey) {
                        $uri += '&$expand=kerb'
                    }

                    $requestParam = @{
                        Headers = $using:script:authHeader
                        Uri     = $uri
                        Method  = 'POST'
                        UserAgent = $using:sessionVariables.userAgent
                    }

                    $apiResponse = Invoke-RestMethod @requestParam

                    $currentItem = [PSCustomObject]@{
                        "StorageAccountName" = $storageAccountName
                        "Keys"               = $apiResponse.keys
                    }

                    ($using:successfulKeys).Add($currentItem)
                }
                catch {
                    $errorMsg = $_.Exception.Message
                    # Get storage account name from the current resource ID being processed
                    $storageAccountName = $currentResourceId.split('/')[-1]

                    # Enhanced error logging for validation
                    Write-Verbose "Full error message for $storageAccountName`: $errorMsg"
                    Write-Debug "Exception type: $($_.Exception.GetType().Name)"

                    # Check HTTP status code if available
                    $statusCode = ""
                    if ($_.Exception.Response) {
                        $statusCode = $_.Exception.Response.StatusCode
                        Write-Debug "HTTP Status Code: $statusCode"
                    }

                    # Check for specific Azure error patterns based on actual responses
                    if ($errorMsg -match "Forbidden|403" -or $statusCode -eq 403) {
                        # Check for RBAC-specific errors (Storage Accounts use RBAC, not access policies)
                        if (($errorMsg -match "does not have authorization to perform action") -or
                            ($errorMsg -match "Microsoft\.Authorization/roleAssignments") -or
                            ($errorMsg -match "RBAC") -or
                            ($errorMsg -match "role assignment") -or
                            ($errorMsg -match "Microsoft\.Storage/storageAccounts/listkeys/action") -or
                            ($errorMsg -match "AuthorizationFailed") -or
                            ($errorMsg -match "InsufficientAccountPermissions")) {

                            Write-Host "    Access forbidden by RBAC role assignment for Storage Account: $storageAccountName" -ForegroundColor Red
                            ($using:policyForbiddenBag).Add(1)
                        } else {
                            Write-Host "    Insufficient permissions for Storage Account: $storageAccountName" -ForegroundColor Yellow
                            ($using:permissionForbiddenBag).Add(1)
                        }
                    }
                    elseif ($errorMsg -match "Unauthorized|401" -or $statusCode -eq 401) {
                        Write-Host "    Authentication failed for Storage Account: $storageAccountName" -ForegroundColor Yellow
                        ($using:permissionForbiddenBag).Add(1)
                    }
                    elseif ($errorMsg -match "NotFound|404|does not exist|could not be found" -or $statusCode -eq 404) {
                        Write-Host "    Storage Account not found: $storageAccountName" -ForegroundColor Red
                        ($using:generalErrorBag).Add(1)
                    }
                    elseif ($errorMsg -match "BadRequest|400" -or $statusCode -eq 400) {
                        Write-Host "    Bad request for Storage Account: $storageAccountName" -ForegroundColor Yellow
                        ($using:generalErrorBag).Add(1)
                    }
                    elseif ($errorMsg -match "TooManyRequests|429" -or $statusCode -eq 429) {
                        Write-Host "    Rate limited for Storage Account: $storageAccountName" -ForegroundColor Yellow
                        ($using:generalErrorBag).Add(1)
                    }
                    elseif ($errorMsg -match "InternalServerError|500|502|503|504" -or ($statusCode -ge 500 -and $statusCode -le 504)) {
                        Write-Host "    Server error for Storage Account: $storageAccountName" -ForegroundColor Red
                        ($using:generalErrorBag).Add(1)
                    }
                    else {
                        Write-Host "    Error retrieving keys for Storage Account $storageAccountName`: $errorMsg" -ForegroundColor Red
                        ($using:generalErrorBag).Add(1)
                    }
                }
            } -ThrottleLimit $ThrottleLimit

            # Convert concurrent bag results to regular collections and update stats
            $result.AddRange($successfulKeys)
            $stats.StorageAccountsWithKeys = $successfulKeys.Count
            $stats.TotalKeysRetrieved = ($successfulKeys | ForEach-Object { $_.Keys.Count } | Measure-Object -Sum).Sum
            $stats.ForbiddenByPolicy = $policyForbiddenBag.Count
            $stats.InsufficientPermissions = $permissionForbiddenBag.Count
            $stats.ProcessingErrors = $generalErrorBag.Count
            $stats.TotalAccessDenied = $stats.ForbiddenByPolicy + $stats.InsufficientPermissions

            Write-Host "  Retrieved keys from $($stats.StorageAccountsWithKeys) Storage Accounts, $($stats.ForbiddenByPolicy) policy denials, $($stats.InsufficientPermissions) permission denials" -ForegroundColor Cyan
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
    end {
        $Duration = (Get-Date) - $stats.StartTime

        Write-Host "`nStorage Account Key Retrieval Summary:" -ForegroundColor Magenta
        Write-Host "   Total Storage Accounts Analyzed: $($stats.TotalStorageAccounts)" -ForegroundColor White
        Write-Host "   Storage Accounts with Keys Retrieved: $($stats.StorageAccountsWithKeys)" -ForegroundColor Yellow
        Write-Host "   Total Keys Retrieved: $($stats.TotalKeysRetrieved)" -ForegroundColor Green

        # Always show access summary
        Write-Host "   Access Summary:" -ForegroundColor Cyan
        Write-Host "     • Access Forbidden by Policy: $($stats.ForbiddenByPolicy)" -ForegroundColor Red
        Write-Host "     • Insufficient Permissions: $($stats.InsufficientPermissions)" -ForegroundColor Yellow
        Write-Host "     • Total Access Denied: $($stats.TotalAccessDenied)" -ForegroundColor Red

        if ($stats.ProcessingErrors -gt 0) {
            Write-Host "   Processing Errors: $($stats.ProcessingErrors)" -ForegroundColor Red
        }
        Write-Host "   Duration: $($Duration.TotalSeconds.ToString('F2')) seconds" -ForegroundColor White

        Write-Verbose "Completed function $($MyInvocation.MyCommand.Name)"

        if (!$result -or $result.Count -eq 0) {
            # Handle case when no storage account keys found based on output format
            switch ($OutputFormat) {
                "JSON" {
                    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    $jsonOutput = @() | ConvertTo-Json
                    $jsonFilePath = "StorageAccountKeys_$timestamp.json"
                    $jsonOutput | Out-File -FilePath $jsonFilePath -Encoding UTF8
                    Write-Host "Empty JSON output saved to: $jsonFilePath" -ForegroundColor Green
                    return
                }
                "CSV" {
                    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    $csvOutput = @() | ConvertTo-CSV
                    $csvFilePath = "StorageAccountKeys_$timestamp.csv"
                    $csvOutput | Out-File -FilePath $csvFilePath -Encoding UTF8
                    Write-Host "Empty CSV output saved to: $csvFilePath" -ForegroundColor Green
                    return
                }
                "Object" {
                    Write-Host "`nNo storage account keys found" -ForegroundColor Red
                    return @()
                }
                "Table" {
                    Write-Host "`nNo storage account keys found" -ForegroundColor Red
                    return @()
                }
            }
        } else {
            # Return results in requested format
            switch ($OutputFormat) {
                "JSON" {
                    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    $jsonOutput = $result | Sort-Object StorageAccountName | ConvertTo-Json -Depth 3
                    $jsonFilePath = "StorageAccountKeys_$timestamp.json"
                    $jsonOutput | Out-File -FilePath $jsonFilePath -Encoding UTF8
                    Write-Host "JSON output saved to: $jsonFilePath" -ForegroundColor Green
                    # File created, no console output needed
                    return
                }
                "CSV" {
                    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    $csvOutput = $result | Sort-Object StorageAccountName | ConvertTo-CSV
                    $csvFilePath = "StorageAccountKeys_$timestamp.csv"
                    $csvOutput | Out-File -FilePath $csvFilePath -Encoding UTF8
                    Write-Host "CSV output saved to: $csvFilePath" -ForegroundColor Green
                    # File created, no console output needed
                    return
                }
                "Object" { return $result | Sort-Object StorageAccountName }
                "Table"  { return $result | Sort-Object StorageAccountName | Format-Table -AutoSize }
            }
        }
    }
<#
.SYNOPSIS
Retrieves the storage account keys for specified Azure Storage Accounts.

.DESCRIPTION
The `Get-StorageAccountKey` function retrieves the access keys for Azure Storage Accounts with enhanced output formatting, error tracking, and comprehensive summary statistics. It supports parallel processing to handle multiple storage accounts efficiently with beautiful emoji progress indicators and detailed access denial reporting.

.PARAMETER Name
Specifies the name(s) of the storage account(s) to retrieve keys for.
This parameter accepts an array of strings and supports pipeline input.

.PARAMETER ResourceGroupName
Specifies the name(s) of the resource group(s) containing the storage account(s).
This parameter accepts an array of strings.

.PARAMETER Id
Specifies the resource ID(s) of the storage account(s).
This parameter accepts an object and supports pipeline input by property name.

.PARAMETER KerbKey
Indicates whether to retrieve Kerberos keys for the storage account(s).
This is a switch parameter.

.PARAMETER ThrottleLimit
Specifies the maximum number of concurrent operations to run when retrieving keys.
The default value is 100.

.PARAMETER OutputFormat
Optional. Specifies the output format for results. Valid values are:
- Object: Returns PowerShell objects (default when piping)
- JSON: Creates timestamped JSON file (StorageAccountKeys_TIMESTAMP.json) with no console output
- CSV: Creates timestamped CSV file (StorageAccountKeys_TIMESTAMP.csv) with no console output
- Table: Returns results in a formatted table (default)
Aliases: output, o

.INPUTS
- [string[]] Name
- [string[]] ResourceGroupName
- [object] Id

.OUTPUTS
- [PSCustomObject] A custom object containing the storage account name and its keys.

.EXAMPLE
Get-StorageAccountKey -Name "mystorageaccount" -ResourceGroupName "myresourcegroup"

Retrieves the keys for the storage account named "mystorageaccount" in the resource group "myresourcegroup".

.EXAMPLE
Get-StorageAccountKey -Id "/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.Storage/storageAccounts/{storageAccountName}"

Retrieves the keys for the storage account specified by its resource ID.

.EXAMPLE
Get-StorageAccountKey -KerbKey

Retrieves the Kerberos keys for all storage accounts in the current subscription.

.EXAMPLE
Get-StorageAccountKey -OutputFormat JSON

Retrieves keys from all available Storage Accounts and creates a timestamped JSON file (e.g., StorageAccountKeys_20250709_143022.json) in the current directory.

.EXAMPLE
Get-StorageAccountKey -Name "mystorageaccount" -OutputFormat CSV

Retrieves keys from "mystorageaccount" and saves results to a timestamped CSV file.

.EXAMPLE
$keys = Get-StorageAccountKey -OutputFormat Object
$productionKeys = $keys | Where-Object { $_.StorageAccountName -like "*prod*" }

Stores results in a variable and filters for production-related Storage Accounts.

.NOTES
- This function uses Azure REST API to retrieve storage account keys.
- Ensure that you have the necessary permissions to access the storage accounts.

.LINK
MITRE ATT&CK Tactic: TA0006 - Credential Access
https://attack.mitre.org/tactics/TA0006/

.LINK
MITRE ATT&CK Technique: T1552.005 - Unsecured Credentials: Cloud Instance Metadata API
https://attack.mitre.org/techniques/T1552/005/

#>
}