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
        [int]$ThrottleLimit = 100
    )

    begin {
        [void] $ResourceGroupName #Only used to trigger the ResourceGroupCompleter

        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat

        $result = New-Object System.Collections.ArrayList
    }

    process {
        try {
            Write-Verbose "Retrieving storage account keys for $(($id).count)"

            if (!$($Name) -and !$Id) {
                $id = (Invoke-AzBatch -ResourceType 'Microsoft.Storage/storageaccounts').id
            } elseif ($($Name)) {
                $id = (Invoke-AzBatch -ResourceType 'Microsoft.Storage/storageaccounts' -Name $($Name)).id
            } else {
                $id = $Id
            }

            $id | ForEach-Object -Parallel {
                try {
                    $result     = $using:result
                    $KerbKey    = $using:KerbKey

                    $uri = 'https://management.azure.com{0}/listKeys?api-version=2024-01-01' -f $_
                    if ($KerbKey) {
                        $uri += '&$expand=kerb'
                    }

                    $requestParam = @{
                        Headers = $using:script:authHeader
                        Uri     = $uri
                        Method  = 'POST'
                    }

                    $apiResponse = Invoke-RestMethod @requestParam

                    $currentItem = [PSCustomObject]@{
                        "StorageAccountName" = $_.split('/')[-1]
                        "Keys"               = $apiResponse.keys
                    }

                    [void] $result.Add($currentItem)
                }
                catch {
                    Write-Information "$($MyInvocation.MyCommand.Name): Storage Account '$_' does not exist"  -InformationAction Continue
                }
            } -ThrottleLimit $ThrottleLimit
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
    end {
        Write-Verbose "Completed function $($MyInvocation.MyCommand.Name)"
        return $result
    }
<#
.SYNOPSIS
Retrieves the storage account keys for specified Azure Storage Accounts.

.DESCRIPTION
The `Get-StorageAccountKey` function retrieves the access keys for Azure Storage Accounts.
It supports retrieving keys by storage account name, resource group name, or resource ID.
The function also supports retrieving Kerberos keys if specified.

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

.NOTES
- This function uses Azure REST API to retrieve storage account keys.
- Ensure that you have the necessary permissions to access the storage accounts.

#>
}