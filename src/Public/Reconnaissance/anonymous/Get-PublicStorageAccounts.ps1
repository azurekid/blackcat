function Get-PublicStorageAccounts {
    [cmdletbinding()]
    [Alias("bl cli public storage accounts")]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias("storage-account-name")]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet('blob', 'file', 'queue', 'table', 'dfs', ErrorMessage = "Type must be one of the following: Blob, File, Queue, Table")]
        [Alias("storage-type")]
        [string]$Type = 'blob',

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias("word-list")]
        [string]$WordList,

        [Parameter(Mandatory = $false)]
        [Alias("throttle-limit")]
        [int]$ThrottleLimit = 1000,

        [Parameter(Mandatory = $false)]
        [Alias("include-empty")]
        [switch]$IncludeEmpty,

        [Parameter(Mandatory = $false)]
        [Alias("include-metadata")]
        [switch]$IncludeMetadata
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"

        # Create thread-safe collections
        $validDnsNames = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
        $userAgents = $sessionVariables.userAgents.agents
        $result = New-Object System.Collections.ArrayList
    }

    process {
        try {
            # Read word list efficiently
            if ($WordList) {
                $permutations = [System.Collections.Generic.HashSet[string]](Get-Content $WordList)
                Write-Information "$($MyInvocation.MyCommand.Name): Loaded $($permutations.Count) permutations from '$WordList'" -InformationAction Continue
            }

            $permutations += $sessionVariables.permutations
            Write-Information "$($MyInvocation.MyCommand.Name): Loaded $($permutations.Count) permutations from session"  -InformationAction Continue

            # Generate DNS names more efficiently
            $dnsNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($item in $permutations) {
                [void] $dnsNames.Add(('{0}{1}.{2}.core.windows.net' -f $StorageAccountName, $($item), $type))
                [void] $dnsNames.Add(('{1}{0}.{2}.core.windows.net' -f $StorageAccountName, $($item), $type))
            }
            [void] $dnsNames.Add(('{0}.{1}.core.windows.net' -f $StorageAccountName, $type))

            $totalDns = $dnsNames.Count
            Write-Information "$($MyInvocation.MyCommand.Name): Starting DNS resolution for $totalDns names..."  -InformationAction Continue

            # Parallel DNS resolution with improved error handling and progress
            $dnsNames | ForEach-Object -Parallel {
                try {
                    $validDnsNames = $using:validDnsNames
                    $permutations = $using:permutations

                    if ([System.Net.Dns]::GetHostEntry($_)) {
                        $validDnsNames.Add($_)
                        $permutations += $($_).split('.')[0]
                    }
                }
                catch [System.Net.Sockets.SocketException] {
                    Write-Information "$($MyInvocation.MyCommand.Name): Storage Account '$_' does not exist"  -InformationAction Continue
                }
            } -ThrottleLimit $ThrottleLimit

            # Generate and test URIs in parallel
            if ($validDnsNames.Count -gt 0) {
                Write-Information "$($MyInvocation.MyCommand.Name): Found $($validDnsNames.Count) valid DNS names"  -InformationAction Continue
                $totalContainers = $validDnsNames.Count * $permutations.Count
                Write-Information "$($MyInvocation.MyCommand.Name): Starting container checks for $totalContainers combinations..."  -InformationAction Continue

                $validDnsNames | ForEach-Object -Parallel {
                    $dns             = $_
                    $permutations    = $using:permutations
                    $result          = $using:result
                    $includeEmpty    = $using:IncludeEmpty
                    $IncludeMetadata = $using:IncludeMetadata
                    $userAgents      = $using:userAgents

                    $permutations | ForEach-Object -Parallel {
                        $dns             = $using:dns
                        $result          = $using:result
                        $includeEmpty    = $using:IncludeEmpty
                        $IncludeMetadata = $using:IncludeMetadata
                        $userAgents      = $using:userAgents

                        $uri = "https://$dns/$_/?restype=container&comp=list"
                        $response = Invoke-WebRequest -Uri $uri -Method GET -UserAgent $($userAgents.value | Get-Random) -UseBasicParsing -SkipHttpErrorCheck

                        if ($response.StatusCode -eq 200) {
                            if ($includeEmpty -or $response.Content -match '<Blob>') {
                                $currentItem = [PSCustomObject]@{
                                    "StorageAccountName" = $dns.split('.')[0]
                                    "Container"          = $_
                                    "FileCount" = (Select-String -InputObject $response.Content -Pattern "/Name" -AllMatches).Matches.Count
                                }
                                if ($response.Content -match '<Blob>') {
                                    $currentItem | Add-Member -NotePropertyName IsEmpty -NotePropertyValue $false
                                }
                                else {
                                    $currentItem | Add-Member -NotePropertyName IsEmpty -NotePropertyValue $true
                                }
                                $currentItem | Add-Member -NotePropertyName Uri -NotePropertyValue $uri

                            }

                            if ($IncludeMetadata) {
                                $metadataUri = "https://$dns/$_/?restype=container&comp=metadata"
                                $metaResponse = Invoke-WebRequest -Uri $metadataUri -Method GET -UserAgent $($userAgents.value | Get-Random) -UseBasicParsing -SkipHttpErrorCheck

                                $metaHeaders = @{}
                                $metaResponse.Headers.GetEnumerator() | Where-Object { $_.Key -like 'x-ms-meta-*' } | ForEach-Object {
                                    $metaHeaders[$_.Key] = $_.Value
                                    if ($metaHeaders) {$currentItem | Add-Member -NotePropertyName Metadata -NotePropertyValue $metaHeaders -Force}
                                }
                            }

                            [void] $result.Add($currentItem)
                        }
                    }
                }
            }
        }
        catch {
            Write-Error -Message $_.Exception.Message -ErrorAction Continue
        }
    }

    end {
        Write-Progress -Activity "Resolving DNS Names" -Completed
        Write-Progress -Activity "Checking Containers" -Completed
        Write-Verbose "Function $($MyInvocation.MyCommand.Name) completed"
        if (-not($result) -or $result.Count -eq 0) {
            Write-Information -MessageData "No public storage account containers found" -InformationAction Continue
        } else {
            return $result
        }
    }
<#
.SYNOPSIS
Retrieves public Azure Storage Accounts and their containers.

.DESCRIPTION
The Get-AzPublicStorageAccounts function retrieves public Azure Storage Accounts and their containers by performing DNS resolution and container checks. It supports parallel processing for efficient DNS resolution and container checks.

.PARAMETER StorageAccountName
The name of the Azure Storage Account to check. This parameter is optional.

.PARAMETER Type
The type of storage service to check. Valid values are 'blob', 'file', 'queue', 'table', 'dfs'. The default value is 'blob'.

.PARAMETER WordList
A file path to a list of words to use for generating permutations of DNS names. This parameter is optional.

.PARAMETER ThrottleLimit
The maximum number of concurrent operations for parallel processing. The default value is 1000.

.PARAMETER IncludeEmpty
A switch to include empty containers in the results. This parameter is optional.

.PARAMETER IncludeMetadata
A switch to include metadata of the containers in the results. This parameter is optional.

.EXAMPLE
PS> Get-AzPublicStorageAccounts -StorageAccountName "mystorageaccount"

Retrieves public containers for the specified storage account.

.EXAMPLE
PS> Get-AzPublicStorageAccounts -StorageAccountName "mystorageaccount" -Type "file" -IncludeEmpty

Retrieves public file containers for the specified storage account, including empty containers.

.EXAMPLE
PS> Get-AzPublicStorageAccounts -WordList "C:\wordlist.txt" -ThrottleLimit 500

.NOTES
Author: Rogier Dijkman
#>
}