function Get-StorageAccountKeys {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('resource-id')]
        [object]$id,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('kerb-key', 'kerberos-key')]
        [switch]$KerbKey,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('throttle-limit')]
        [int]$ThrottleLimit = 100
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat

        $result = New-Object System.Collections.ArrayList
        $secrets = [System.Collections.Concurrent.ConcurrentBag[string]]::new()

        $totalItems = $id.Count
        $currentItemIndex = 0
    }

    process {
        try {
            Write-Verbose "Retrieving storage account keys for $(($id).count)"

            $id | ForEach-Object -Parallel {
                try {
                    $baseUri    = $using:SessionVariables.baseUri
                    $authHeader = $using:script:authHeader
                    $result     = $using:result
                    $KerbKey    = $using:KerbKey
                    $totalItems = $using:totalItems
                    $currentItemIndex = [System.Threading.Interlocked]::Increment([ref]$using:currentItemIndex)

                    $uri = 'https://management.azure.com{0}/listKeys?api-version=2024-01-01' -f $_
                    if ($KerbKey) {
                        $uri += '&$expand=kerb'
                    }

                    $requestParam = @{
                        Headers = $authHeader
                        Uri     = $uri
                        Method  = 'POST'
                    }

                    $apiResponse = Invoke-RestMethod @requestParam

                    $currentItem = [PSCustomObject]@{
                        "StorageAccountName" = $_.split('/')[-1]
                        "Keys"               = $apiResponse.keys
                    }

                    [void] $result.Add($currentItem)

                    $percentComplete = [math]::Round(($currentItemIndex / $totalItems) * 100)
                    Write-Progress -Activity "Retrieving Storage Account Keys" -Status "$percentComplete% Complete" -PercentComplete $percentComplete

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
}