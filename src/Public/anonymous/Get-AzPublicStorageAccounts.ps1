function Get-AzPublicStorageAccounts {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet('blob', 'file', 'queue', 'table', 'dfs', ErrorMessage = "Type must be one of the following: Blob, File, Queue, Table")]
        [string]$Type = 'blob',

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$WordList,

        [Parameter(Mandatory = $false)]
        [int]$ThrottleLimit = 100,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeEmpty,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeMetadata
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"

        # Create thread-safe collections
        $validDnsNames = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
        $result = New-Object System.Collections.ArrayList
    }

    process {
        try {
            # Read word list efficiently
            if ($WordList) {
                $permutations = [System.Collections.Generic.HashSet[string]](Get-Content $WordList)
                Write-Verbose "Loaded $($permutations.Count) permutations from '$WordList'"
            }

            $permutations += $sessionVariables.permutations
            Write-Verbose "Loaded $($permutations.Count) permutations from session"

            # Generate DNS names more efficiently
            $dnsNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($item in $permutations) {
                [void] $dnsNames.Add(('{0}{1}.{2}.core.windows.net' -f $StorageAccountName, $item, $type))
                [void] $dnsNames.Add(('{1}{0}.{2}.core.windows.net' -f $StorageAccountName, $item, $type))
            }
            [void] $dnsNames.Add(('{0}.{1}.core.windows.net' -f $StorageAccountName, $type))

            $totalDns = $dnsNames.Count
            Write-Verbose "Starting DNS resolution for $totalDns names..."

            # Parallel DNS resolution with improved error handling and progress
            $dnsNames | ForEach-Object -Parallel {
                try {
                    $validDnsNames = $using:validDnsNames
                    if ([System.Net.Dns]::GetHostEntry($_)) {
                        $validDnsNames.Add($_)
                    }
                }
                catch [System.Net.Sockets.SocketException] {
                    Write-Verbose "Storage Account '$_' does not exist"
                }
            }

            # Generate and test URIs in parallel
            if ($validDnsNames.Count -gt 0) {
                $totalContainers = $validDnsNames.Count * $permutations.Count
                Write-Verbose "Get-AzPublicStorageAccounts: Starting container checks for $totalContainers combinations..."

                $validDnsNames | ForEach-Object -Parallel {
                    $dns = $_
                    $permutations = $using:permutations
                    $result = $using:result
                    $includeEmpty = $using:IncludeEmpty
                    $IncludeMetadata = $using:IncludeMetadata

                    $permutations | ForEach-Object -Parallel {
                        $dns = $using:dns
                        $result = $using:result
                        $includeEmpty = $using:IncludeEmpty
                        $IncludeMetadata = $using:IncludeMetadata

                        $uri = "https://$dns/$_/?restype=container&comp=list"
                        $response = Invoke-WebRequest -Uri $uri -Method GET -UseBasicParsing -SkipHttpErrorCheck

                        if ($response.StatusCode -eq 200) {
                            if ($includeEmpty -or $response.Content -match '<Blob>') {

                                $currentItem = [PSCustomObject]@{
                                    "StorageAccountName" = $dns.split('.')[0]
                                    "Container"          = $_
                                    "FileCount" = (Select-String -InputObject $response.Content -Pattern "/Url" -AllMatches).Matches.Count
                                }

                                if ($response.Content -match '<Blob>') {
                                    $currentItem | Add-Member -NotePropertyName IsEmpty -NotePropertyValue $false

                                }
                                else {
                                    $currentItem | Add-Member -NotePropertyName IsEmpty -NotePropertyValue $true
                                }
                            }

                            if ($IncludeMetadata) {
                                $metadataUri = "https://$dns/$_/?restype=container&comp=metadata"
                                $metaResponse = Invoke-WebRequest -Uri $metadataUri -Method GET -UseBasicParsing -SkipHttpErrorCheck

                                $metaHeaders = @{}
                                $metaResponse.Headers.GetEnumerator() | Where-Object { $_.Key -like 'x-ms-meta-*' } | ForEach-Object {
                                    $metaHeaders[$_.Key] = $_.Value
                                    if ($metaHeaders) {$currentItem | Add-Member -NotePropertyName Metadata -NotePropertyValue $metaHeaders -Force}
                                }
                            }

                            # $currentItem | Add-Member -NotePropertyName Uri -NotePropertyValue $uri

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
        return $result
    }
}