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
        [string]$OutputFormat,

        [Parameter(Mandatory = $false)]
        [Alias("no-cache", "bypass-cache")]
        [switch]$SkipCache,

        [Parameter(Mandatory = $false)]
        [Alias("cache-expiration", "expiration")]
        [int]$CacheExpirationMinutes = 30,

        [Parameter(Mandatory = $false)]
        [Alias("max-cache")]
        [int]$MaxCacheSize = 100,

        [Parameter(Mandatory = $false)]
        [Alias("compress")]
        [switch]$CompressCache
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
            # Generate cache key and check for cached results
            $cacheParams = @{
                StorageAccountName = $StorageAccountName
                Type               = $Type
            }
            $cacheKey = ConvertTo-CacheKey `
                -BaseIdentifier "Find-PublicStorageContainer" `
                -Parameters $cacheParams

            if (-not $SkipCache) {
                try {
                    $cachedResult = Get-BlackCatCache `
                        -Key $cacheKey -CacheType 'General'
                    if ($null -ne $cachedResult) {
                        Write-Verbose "Retrieved results from cache for: $StorageAccountName"
                        foreach ($item in $cachedResult) { [void]$result.Add($item) }
                        return
                    }
                }
                catch {
                    Write-Verbose "Error retrieving from cache: $($_.Exception.Message). Proceeding with fresh queries."
                }
            }

            if ($WordList) {
                Write-Host "  Loading permutations from word list..." -ForegroundColor Cyan
                $permutations = [System.Collections.Generic.HashSet[string]](Get-Content $WordList)
                Write-Host "    Loaded $($permutations.Count) permutations from '$WordList'" -ForegroundColor Green
            } else {
                $permutations = [System.Collections.Generic.HashSet[string]]::new()
            }

            if ($sessionVariables.permutations) {
                Write-Host "  Loading session permutations..." -ForegroundColor Cyan
                foreach ($item in $sessionVariables.permutations) { [void]$permutations.Add($item) }
            }

            # Always include the base name without any suffix
            if (-not $permutations.Contains('')) { [void]$permutations.Add('') }

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

            # Cache results if any were found
            if (-not $SkipCache -and $result -and $result.Count -gt 0) {
                try {
                    Set-BlackCatCache -Key $cacheKey -Data $result `
                        -ExpirationMinutes $CacheExpirationMinutes `
                        -CacheType 'General' -MaxCacheSize $MaxCacheSize `
                        -CompressData:$CompressCache
                    Write-Verbose "Cached results for: $StorageAccountName (expires in $CacheExpirationMinutes minutes)"
                }
                catch {
                    Write-Verbose "Failed to cache results: $($_.Exception.Message)"
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
    Finds publicly accessible Azure Storage containers.

.DESCRIPTION
    Discovers public Azure Storage containers through account name enumeration and accessibility testing. Tests various storage account naming patterns and verifies public access. Useful for finding exposed data in storage services.

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

.PARAMETER SkipCache
    Bypasses the cache and forces a fresh scan.
    Default: False (cache is used if available)

.PARAMETER CacheExpirationMinutes
    Number of minutes to store results in cache before expiry.
    Default: 30 minutes

.PARAMETER MaxCacheSize
    Maximum number of entries to keep in the cache (LRU eviction).
    Default: 100

.PARAMETER CompressCache
    Enables compression of cached data to reduce memory usage.
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