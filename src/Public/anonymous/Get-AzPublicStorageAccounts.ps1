function Get-AzPublicStorageAccounts {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet('blob', 'file', 'queue', 'table', ErrorMessage = "Type must be one of the following: Blob, File, Queue, Table")]
        [string]$Type = 'blob',

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$WordList,

        [Parameter(Mandatory = $false)]
        [int]$ThrottleLimit = 100,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeEmpty
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        # Create thread-safe collections
        $validDnsNames = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
        $publicContainers = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
        # Add progress counters
        $script:dnsProgress = 0
        $script:containerProgress = 0
    }

    process {
        try {
            # Read word list efficiently
            $permutations = [System.Collections.Generic.HashSet[string]](Get-Content $WordList)
            Write-Host "Loaded $($permutations.Count) permutations from '$WordList'" -ForegroundColor Yellow
            $permutations += $sessionVariables.permutations
            Write-Host "Loaded $($permutations.Count) permutations from session" -ForegroundColor Yellow
            
            # Generate DNS names more efficiently
            $dnsNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($item in $permutations) {
                $null = $dnsNames.Add(('{0}{1}.{2}.core.windows.net' -f $StorageAccountName, $item, $type))
                $null = $dnsNames.Add(('{1}{0}.{2}.core.windows.net' -f $StorageAccountName, $item, $type))
            }
            $null = $dnsNames.Add(('{0}.{1}.core.windows.net' -f $StorageAccountName, $type))

            $totalDns = $dnsNames.Count
            Write-Host "Starting DNS resolution for $totalDns names..." -ForegroundColor Yellow

            # Parallel DNS resolution with improved error handling and progress
            $dnsNames | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
                try {
                    $validDnsNames = $using:validDnsNames
                    $script:dnsProgress = $using:dnsProgress
                    if ([System.Net.Dns]::GetHostEntry($_)) {
                        $validDnsNames.Add($_)
                        Write-Host "Storage Account '$_' is valid" -ForegroundColor Green
                    }
                }
                catch [System.Net.Sockets.SocketException] {
                    Write-Verbose "Storage Account '$_' does not exist"
                }
            }

            # Generate and test URIs in parallel
            if ($validDnsNames.Count -gt 0) {
                $totalContainers = $validDnsNames.Count * $permutations.Count
                Write-Host "Starting container checks for $totalContainers combinations..." -ForegroundColor Yellow

                $validDnsNames | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
                    $dns = $_
                    $permutations = $using:permutations
                    $publicContainers = $using:publicContainers
                    $includeEmpty = $using:IncludeEmpty

                    foreach ($item in $permutations) {
                        $uri = "https://$dns/$item/?restype=container&comp=list"
                        try {
                            $response = Invoke-WebRequest -Uri $uri -Method GET -UseBasicParsing -SkipHttpErrorCheck
                            if ($response.StatusCode -eq 200) {
                                if ($includeEmpty -or $response.Content -match '<Blob>') {
                                    $publicContainers.Add($uri)
                                    $message = if ($response.Content -match '<Blob>') {
                                        "Storage Account Container '$uri' is public and contains data"
                                    } else {
                                        "Storage Account Container '$uri' is public but empty"
                                    }
                                    Write-Host $message -ForegroundColor Green
                                }
                            }
                        }
                        catch {
                            Write-Verbose "Storage Account Container '$uri' is not public"
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
        # Return results
        $publicContainers
    }
}
