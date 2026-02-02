function Find-PublicStorageContainer {
    [cmdletbinding()]
    [OutputType([System.Collections.ArrayList])] # Updated OutputType
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
        [Alias("word-list", "w")]
        [string]$WordList,

        [Parameter(Mandatory = $false)]
        [Alias("throttle-limit", "t", "threads")]
        [int]$ThrottleLimit = 50,

        [Parameter(Mandatory = $false)]
        [Alias("include-empty")]
        [switch]$IncludeEmpty = $true,

        [Parameter(Mandatory = $false)]
        [Alias("include-metadata")]
        [switch]$IncludeMetadata,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Object", "JSON", "CSV")]
        [Alias("output", "o")]
        [string]$OutputFormat
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        Write-Host "Analyzing Azure Storage for: $StorageAccountName ($Type)" -ForegroundColor Green

        $validDnsNames = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
        $userAgent = ($sessionVariables.userAgents.agents | Get-Random).value
        $result = New-Object System.Collections.ArrayList
        
        $foundContainers = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
    }

    process {
        try {
            if ($WordList) {
                Write-Host "  Loading permutations from word list..." -ForegroundColor Cyan
                $permutations = [System.Collections.Generic.HashSet[string]](Get-Content $WordList)
                Write-Host "    Loaded $($permutations.Count) permutations from '$WordList'" -ForegroundColor Green
            }

            $permutations += $sessionVariables.permutations
            Write-Host "  Loaded total of $($permutations.Count) permutations" -ForegroundColor Green

            $dnsNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($item in $permutations) {
                [void] $dnsNames.Add(('{0}{1}.{2}.core.windows.net' -f $StorageAccountName, $($item), $type))
                [void] $dnsNames.Add(('{1}{0}.{2}.core.windows.net' -f $StorageAccountName, $($item), $type))
            }
            [void] $dnsNames.Add(('{0}.{1}.core.windows.net' -f $StorageAccountName, $type))

            $totalDns = $dnsNames.Count
            Write-Host "    Testing $totalDns DNS name candidates..." -ForegroundColor Yellow
            Write-Host "  Starting DNS resolution with $ThrottleLimit concurrent threads..." -ForegroundColor Cyan

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
                }
            } -ThrottleLimit $ThrottleLimit

            if ($validDnsNames.Count -gt 0) {
                Write-Host "    Found $($validDnsNames.Count) valid storage accounts" -ForegroundColor Green
                $totalContainers = $validDnsNames.Count * $permutations.Count
                Write-Host "   Starting container enumeration for $totalContainers combinations..." -ForegroundColor Cyan

                $validDnsNames | ForEach-Object -Parallel {
                    $dns = $_
                    $permutations = $using:permutations
                    $result = $using:result
                    $includeEmpty = $using:IncludeEmpty
                    $IncludeMetadata = $using:IncludeMetadata
                    $userAgent = $using:userAgent
                    $foundContainers = $using:foundContainers

                    $permutations | ForEach-Object -Parallel {
                        $dns = $using:dns
                        $result = $using:result
                        $includeEmpty = $using:IncludeEmpty
                        $IncludeMetadata = $using:IncludeMetadata
                        $userAgent = $using:userAgent
                        $foundContainers = $using:foundContainers

                        $uri = "https://$dns/$_/?restype=container&comp=list"
                        $response = Invoke-WebRequest -Uri $uri -Method GET -UserAgent $userAgent -UseBasicParsing -SkipHttpErrorCheck

                        if ($response.StatusCode -eq 200) {
                            $hasContent = $response.Content -match '<Blob>'
                            $shouldProcess = $includeEmpty -or $hasContent
                            
                            if ($shouldProcess) {
                                $currentItem = [PSCustomObject]@{
                                    "StorageAccountName" = $dns.split('.')[0]
                                    "Container"          = $_
                                    "FileCount"          = (Select-String -InputObject $response.Content -Pattern "/Name" -AllMatches).Matches.Count
                                }
                                
                                $subfolders = @()
                                $subfolderDetails = @{}
                                if ($response.Content -match '<Blob>') {
                                    $blobNames = [regex]::Matches($response.Content, '<Name>(.*?)</Name>') | ForEach-Object { $_.Groups[1].Value }
                                    $subfolders = $blobNames | Where-Object { $_ -like '*/*' } | ForEach-Object { 
                                        ($_ -split '/')[0] 
                                    } | Sort-Object -Unique
                                    
                                    foreach ($subfolder in $subfolders) {
                                        $filesInSubfolder = ($blobNames | Where-Object { $_ -like "$subfolder/*" }).Count
                                        $subfolderDetails[$subfolder] = $filesInSubfolder
                                    }
                                }


                                    # Normal processing - show all containers
                                    if ($subfolders.Count -gt 0) {
                                        $currentItem | Add-Member -NotePropertyName Subfolders -NotePropertyValue $subfolders
                                        $currentItem | Add-Member -NotePropertyName SubfolderCount -NotePropertyValue $subfolders.Count
                                        $currentItem | Add-Member -NotePropertyName SubfolderDetails -NotePropertyValue $subfolderDetails
                                        
                                        $fileCounts = $subfolders | ForEach-Object { $subfolderDetails[$_] }
                                        $foundMessage = "      $($dns.split('.')[0])/$_ -> $($currentItem.FileCount) files, $($subfolders.Count) subfolders: $($fileCounts -join ', ')"
                                    } else {
                                        if ($hasContent) {
                                            $currentItem | Add-Member -NotePropertyName IsEmpty -NotePropertyValue $false
                                            $foundMessage = "      $($dns.split('.')[0])/$_ -> $($currentItem.FileCount) files [$(if($currentItem.IsEmpty){'Empty'}else{'HasContent'})]"
                                        }
                                        else {
                                            $currentItem | Add-Member -NotePropertyName IsEmpty -NotePropertyValue $true
                                            $foundMessage = "      $($dns.split('.')[0])/$_ -> Empty container"
                                        }
                                    }
                                    $currentItem | Add-Member -NotePropertyName Uri -NotePropertyValue $uri
                                    $foundContainers.Add($foundMessage)
                                    [void] $result.Add($currentItem)
                            }

                            if ($shouldProcess -and $IncludeMetadata) {
                                $metadataUri = "https://$dns/$_/?restype=container&comp=metadata"
                                $metaResponse = Invoke-WebRequest -Uri $metadataUri -Method GET -UserAgent $userAgent -UseBasicParsing -SkipHttpErrorCheck

                                $metaHeaders = @{}
                                $metadataText = ""
                                
                                $metaResponse.Headers.GetEnumerator() | Where-Object { $_.Key -like 'x-ms-meta-*' } | ForEach-Object {
                                    $cleanKey = $_.Key -replace 'x-ms-meta-', ''
                                    $metaHeaders[$cleanKey] = $_.Value
                                    $metadataText += "$cleanKey=$($_.Value); "
                                }
                                
                                if ($metaHeaders.Count -gt 0) {
                                    $metadataText = $metadataText.TrimEnd('; ')
                                    
                                    $currentItem | Add-Member -NotePropertyName MetadataText -NotePropertyValue $metadataText -Force
                                    $currentItem | Add-Member -NotePropertyName Metadata -NotePropertyValue $metaHeaders -Force
                                    
                                    $metadataMessage = "$foundMessage [Metadata: $metadataText]"
                                    $foundContainers.Add($metadataMessage)
                                }
                            }

                        }
                    }
                } -ThrottleLimit $ThrottleLimit
                
                if ($foundContainers.Count -gt 0) {
                    foreach ($message in $foundContainers) {
                        Write-Host $message -ForegroundColor Green
                    }
                }
            }
            else {
                Write-Host "    No valid storage accounts found" -ForegroundColor Red
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
            Write-Host "`nNo public storage containers found" -ForegroundColor Red
            Write-Information -MessageData "No public storage account containers found" -InformationAction Continue
        }
        else {
            Write-Host "`nAzure Storage Container Discovery Summary:" -ForegroundColor Magenta
            Write-Host "   Total Containers Found: $($result.Count)" -ForegroundColor Yellow
            
            $accountGroups = $result | Group-Object StorageAccountName | Sort-Object Count -Descending
            foreach ($group in $accountGroups) {
                $emptyCount = ($group.Group | Where-Object { $_.IsEmpty }).Count
                $nonEmptyCount = $group.Count - $emptyCount
                Write-Host "   $($group.Name): $($group.Count) containers ($nonEmptyCount with content, $emptyCount empty)" -ForegroundColor White
            }

            switch ($OutputFormat) {
                "JSON" { return $result | ConvertTo-Json -Depth 3 }
                "CSV" { return $result | ConvertTo-CSV }
                "Object" { return $result }
                default { return $result | Format-Table -AutoSize }
            }
        }
    }
<#
.SYNOPSIS
    Finds publicly accessible Azure Storage containers for a given storage account name and type.

.DESCRIPTION
    The Find-PublicStorageContainer function attempts to discover public Azure Storage containers (blob, file, queue, table, or dfs) by generating permutations of storage account names and checking their DNS resolution and accessibility.
    It supports parallel processing for both DNS resolution and container enumeration, and can optionally include empty containers and container metadata in the results.

.PARAMETER StorageAccountName
    The base name of the Azure Storage account to check. Permutations will be generated based on this value.

.PARAMETER Type
    The type of Azure Storage service to check. Valid values are 'blob', 'file', 'queue', 'table', or 'dfs'. Defaults to 'blob'.

.PARAMETER WordList
    Path to a file containing additional words or permutations to use when generating storage account names.

.PARAMETER ThrottleLimit
    The maximum number of parallel operations to run during DNS resolution and container checks. Defaults to 50.

.PARAMETER IncludeEmpty
    Switch to include empty containers in the results. By default, only containers with blobs/files are included.

.PARAMETER IncludeMetadata
    Switch to include container metadata in the results by making an additional metadata request for each discovered container.

.PARAMETER OutputFormat
    Optional. Specifies the output format for results. Valid values are:
    - Object: Returns PowerShell objects (default when piping)
    - JSON: Returns results in JSON format
    - CSV: Returns results in CSV format
    Aliases: output, o

.OUTPUTS
    System.Collections.ArrayList
    Returns an array list of PSCustomObject items, each representing a discovered public storage container with properties such as StorageAccountName, Container, FileCount, IsEmpty, Uri, and optionally Metadata.

.EXAMPLE
    Find-PublicStorageContainer -StorageAccountName "examplestorage" -Type "blob" -WordList "permutations.txt" -IncludeEmpty -IncludeMetadata

    Attempts to find public blob containers for the storage account "examplestorage" using permutations from "permutations.txt", including empty containers and their metadata.

.EXAMPLE
    Find-PublicStorageContainer -StorageAccountName "contoso" -Type "blob" -OutputFormat JSON

    Searches for public blob containers using "contoso" as the base name and returns results in JSON format.

.EXAMPLE
    Find-PublicStorageContainer -StorageAccountName "company" -Type "file" -ThrottleLimit 100 -OutputFormat CSV

    Searches for public file storage containers using 100 concurrent threads and returns results in CSV format.

.NOTES
    - Requires appropriate permissions to perform DNS resolution and HTTP requests.
    - Uses parallel processing for improved performance; adjust ThrottleLimit based on system resources.
    - Designed for reconnaissance and security assessment purposes.

.LINK
    MITRE ATT&CK Tactic: TA0043 - Reconnaissance
    https://attack.mitre.org/tactics/TA0043/

.LINK
    MITRE ATT&CK Technique: T1593.003 - Search Open Websites/Domains: Code Repositories
    https://attack.mitre.org/techniques/T1593/003/
#>
}