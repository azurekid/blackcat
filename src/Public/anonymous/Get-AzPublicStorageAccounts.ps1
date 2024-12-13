function Get-AzPublicStorageAccounts {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        # [ValidatePattern('^[A-Za-z0-9]$', ErrorMessage = "It does not match expected pattern '{1}'")]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet('blob', 'file', 'queue', 'table', ErrorMessage = "Type must be one of the following: Blob, File, Queue, Table")]
        [string]$Type = 'blob',

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$WordList
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
    }

    process {
        try {
            if ($WordList){
                Get-Content $WordList| ForEach-Object {
                     $sessionVariables.permutations += $_
                }
            }
            # Create thread-safe collection to receive output
            $validDnsNames = [System.Collections.Concurrent.ConcurrentBag[psobject]]::new()


            foreach ($item in $sessionVariables.permutations) {
                $dnsNames += @(
                    '{0}{1}.{2}.core.windows.net' -f $StorageAccountName, $item, $type
                    '{1}{0}.{2}.core.windows.net' -f $StorageAccountName, $item, $type
                )
            }
            $dnsNames += '{0}.{1}.core.windows.net' -f $StorageAccountName, $type

            $dnsNames | Foreach-Object -Parallel {
                try {
                    $localResultsArray = $using:validDnsNames
                    $exists = [System.Net.Dns]::Resolve($_)

                    if ($exists) {
                        Write-Host "Storage Account '$_' is valid" -ForegroundColor Green
                        $localResultsArray.Add("$_")
                    }
                    else {
                        Write-Verbose "Storage Account '$_' does not exist"
                    }
                }
                catch {}
            }

            $uriArray = @()
            foreach ($validDnsName in $validDnsNames) {
                foreach ($item in $sessionVariables.permutations) {
                    $uri = "$validDnsName/$item"
                    $uriArray += $uri
                }
                $uri = "$validDnsName/$validDnsName"
            }

            $uriArray | Foreach-Object -Parallel {
                $statusCode = (Invoke-WebRequest -Uri "https://$($_)/?comp=list" -Method GET -UseBasicParsing -SkipHttpErrorCheck).StatusCode
                if ($statusCode -eq 200) {
                    Write-Host "Storage Account Container 'https://$($_)/?comp=list' is public" -ForegroundColor Green
                }
                else {
                    Write-Verbose "Storage Account Container 'https://$_' is not public"
                }
            } -ThrottleLimit 100
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    } end {
        Write-Verbose "Function $($MyInvocation.MyCommand.Name) completed"
    }

    <#
    .SYNOPSIS
        Retrieves and checks the validity of Azure public storage accounts based on the provided name and type.

    .DESCRIPTION
        The Get-AzPublicStorageAccounts function generates permutations of the provided storage account name and checks if they are valid DNS names for Azure storage accounts. It then tests if the storage account containers are publicly accessible.

    .PARAMETER Name
        The base name of the storage account. This parameter is mandatory.

    .PARAMETER type
        The type of Azure storage service to check. Valid values are 'blob', 'file', 'queue', and 'table'. The default value is 'blob'.

    .EXAMPLE
        Get-AzPublicStorageAccounts -Name "mystorageaccount"
        Retrieves and checks the validity of public storage accounts with the base name "mystorageaccount" for the default type 'blob'.

    .EXAMPLE
        Get-AzPublicStorageAccounts -Name "mystorageaccount" -type "file"
        Retrieves and checks the validity of public storage accounts with the base name "mystorageaccount" for the type 'file'.

    .LINK
        https://docs.microsoft.com/en-us/powershell/module/az.storage
    #>
    #>
}