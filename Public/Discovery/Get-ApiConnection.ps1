function Get-ApiConnection {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true
        )]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceGroupCompleterAttribute()]
        [Alias('rg', 'resource-group')]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $false)]
        [Alias('orphaned-only')]
        [switch]$OrphanedOnly,

        [Parameter(Mandatory = $false)]
        [ValidateSet('High', 'Medium', 'Low')]
        [Alias('min-risk')]
        [string]$MinRiskLevel,

        [Parameter(Mandatory = $false)]
        [Alias('throttle-limit')]
        [ValidateRange(1, 1000)]
        [int]$ThrottleLimit = 100,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Object', 'JSON', 'CSV', 'Table')]
        [Alias('output', 'o')]
        [string]$OutputFormat = 'Table'
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat

        $rawResults = `
            [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()

        $stats = @{
            StartTime     = Get-Date
            Total         = 0
            HighRisk      = 0
            MediumRisk    = 0
            LowRisk       = 0
            Orphaned      = 0
            Errors        = 0
        }

        # Connectors with broad or sensitive data access
        $HIGH_RISK_CONNECTORS = @(
            'office365', 'office365users', 'office365groups',
            'sharepointonline', 'onedrive', 'onedriveforbusiness',
            'microsoftgraphconnector', 'azuread', 'aad',
            'sql', 'sqlazure',
            'azurekeyvault', 'keyvault',
            'salesforce', 'dynamicscrmonline', 'cds',
            'azureblob', 'azureblobstorage',
            'azuredatalake', 'adls'
        )

        # Connectors that can leak data or enable lateral movement
        $MEDIUM_RISK_CONNECTORS = @(
            'servicebus', 'azureservicebus',
            'eventhubs', 'azureeventhubs',
            'teams', 'slack', 'twilio', 'sendgrid',
            'documentdb', 'azurecosmosdb',
            'github', 'bitbucketserver',
            'azuretables', 'azurequeues'
        )
    }

    process {
        try {
            Write-Host ' Enumerating API Connections...' `
                -ForegroundColor Green

            # -- 1. Collect API Connection resource IDs via ARG ----------
            $filter = ''
            if ($ResourceGroupName) {
                $filter = `
                    "| where resourceGroup == '$ResourceGroupName'"
            }

            $connections = if ($filter) {
                Invoke-AzBatch `
                    -ResourceType 'Microsoft.Web/connections' `
                    -filter $filter
            }
            else {
                Invoke-AzBatch -ResourceType 'Microsoft.Web/connections'
            }

            if (-not $connections -or $connections.Count -eq 0) {
                Write-Host '  No API Connections found in scope' `
                    -ForegroundColor Yellow
                return
            }

            $stats.Total = $connections.Count
            Write-Host "  Found $($connections.Count) API Connection(s)" `
                -ForegroundColor Cyan

            # -- 2. Build connection → Logic App reference map via ARG ---
            Write-Host '  Mapping Logic App connection references...' `
                -ForegroundColor Cyan

            $logicApps = Invoke-AzBatch `
                -ResourceType 'Microsoft.Logic/workflows'

            # Thread-safe bag of (connectionId, logicAppName) pairs
            $refPairs = `
                [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()

            if ($logicApps -and $logicApps.Count -gt 0) {

                $logicApps | ForEach-Object -Parallel {
                    $sv      = $using:script:SessionVariables
                    $auth    = $using:script:authHeader
                    $bag     = $using:refPairs
                    $laName  = $_.name
                    $laId    = $_.id

                    $uri = '{0}{1}?api-version=2019-05-01' -f `
                        $sv.armUri, $laId

                    try {
                        $la = Invoke-RestMethod `
                            -Uri       $uri `
                            -Headers   $auth `
                            -Method    'GET' `
                            -UserAgent $sv.userAgent `
                            -ErrorAction SilentlyContinue

                        $refs = $la.properties.parameters.`
                            '$connections'.value

                        if ($refs) {
                            foreach ($key in `
                                $refs.PSObject.Properties.Name) {
                                $connId = $refs.$key.connectionId
                                if ($connId) {
                                    $bag.Add([PSCustomObject]@{
                                        ConnectionId = `
                                            $connId.ToLower()
                                        LogicAppName = $laName
                                    })
                                }
                            }
                        }
                    }
                    catch {
                        Write-Verbose `
                            "Skipped LA $laName`: $($_.Exception.Message)"
                    }
                } -ThrottleLimit $ThrottleLimit
            }

            # Collapse pairs into a lookup hashtable (sequential, safe)
            $connectionMap = @{}
            foreach ($pair in $refPairs) {
                if (-not $connectionMap.ContainsKey($pair.ConnectionId)) {
                    $connectionMap[$pair.ConnectionId] = `
                        [System.Collections.Generic.List[string]]::new()
                }
                [void]$connectionMap[$pair.ConnectionId].Add(
                    $pair.LogicAppName
                )
            }

            Write-Host (
                "  Built reference map from $($logicApps.Count) " +
                "Logic App(s)"
            ) -ForegroundColor Cyan

            # -- 3. Enrich each connection in parallel -------------------
            Write-Host '  Profiling connections (risk scoring)...' `
                -ForegroundColor Cyan

            $highRisk   = $HIGH_RISK_CONNECTORS
            $mediumRisk = $MEDIUM_RISK_CONNECTORS
            $connMap    = $connectionMap

            $connections | ForEach-Object -Parallel {
                $sv         = $using:script:SessionVariables
                $auth       = $using:script:authHeader
                $results    = $using:rawResults
                $highRisk   = $using:highRisk
                $mediumRisk = $using:mediumRisk
                $connMap    = $using:connMap
                $resource   = $_

                $uri = '{0}{1}?api-version=2016-06-01' -f `
                    $sv.armUri, $resource.id

                try {
                    $conn  = Invoke-RestMethod `
                        -Uri       $uri `
                        -Headers   $auth `
                        -Method    'GET' `
                        -UserAgent $sv.userAgent

                    $props       = $conn.properties
                    $connectorId = $props.api.name

                    # --- Determine auth type ----------------------------
                    $authType = 'Unknown'
                    if ($props.parameterValueType -eq 'Alternative') {
                        $authType = 'ManagedIdentity'
                    }
                    elseif ($props.authenticatedUser.name) {
                        $authType = 'OAuth-User'
                    }
                    elseif ($props.parameterValues) {
                        $pKeys = `
                            $props.parameterValues.PSObject.Properties.Name
                        if ($pKeys -match 'api.?key|apiKey|apikey') {
                            $authType = 'ApiKey'
                        }
                        elseif ($pKeys -match 'password|passwd') {
                            $authType = 'BasicAuth'
                        }
                    }
                    elseif (
                        $props.statuses -and
                        $props.statuses[0].status -eq 'Connected'
                    ) {
                        # Connected but no user identity → likely SP OAuth
                        $authType = 'OAuth-SP'
                    }

                    # --- Logic App cross-reference ----------------------
                    $normalId   = $conn.id.ToLower()
                    $linkedApps = $connMap[$normalId]
                    $isOrphaned = (
                        -not $linkedApps -or $linkedApps.Count -eq 0
                    )

                    # --- Risk score (0–10 scale) ------------------------
                    $riskScore = 0

                    # Connector sensitivity
                    if ($connectorId -in $highRisk) {
                        $riskScore += 4
                    }
                    elseif ($connectorId -in $mediumRisk) {
                        $riskScore += 2
                    }
                    else {
                        $riskScore += 1
                    }

                    # Auth type (delegated user = highest risk)
                    switch ($authType) {
                        'OAuth-User'       { $riskScore += 3 }
                        'OAuth-SP'         { $riskScore += 2 }
                        'ApiKey'           { $riskScore += 2 }
                        'BasicAuth'        { $riskScore += 2 }
                        'ManagedIdentity'  { $riskScore += 1 }
                        default            { $riskScore += 2 }
                    }

                    # Orphaned connections are high risk (not monitored)
                    if ($isOrphaned) { $riskScore += 2 }

                    $riskLevel = switch ($true) {
                        ($riskScore -ge 6) { 'High' }
                        ($riskScore -ge 4) { 'Medium' }
                        default            { 'Low' }
                    }

                    $status    = $props.statuses |
                        Select-Object -First 1 -ExpandProperty status
                    $authUser  = $props.authenticatedUser.name

                    $connDynSub = ($conn.id -split '/')[2]
                    $connDynRg  = ($conn.id -split '/')[4]
                    $connDynUrl = (
                        '{0}/subscriptions/{1}/resourceGroups/{2}' +
                        '/providers/Microsoft.Web/connections/{3}' +
                        '/dynamicInvoke?api-version=2018-07-01-preview'
                    ) -f $sv.armUri, $connDynSub, $connDynRg, $conn.name

                    $results.Add([PSCustomObject]@{
                        'Name'             = $conn.name
                        'ResourceGroup'    = $resource.resourceGroup
                        'Connector'        = $props.api.displayName
                        'ConnectorId'      = $connectorId
                        'AuthType'         = $authType
                        'AuthorizedAs'     = $authUser
                        'Status'           = $status
                        'LinkedApps'       = (
                            $linkedApps -join '; '
                        )
                        'IsOrphaned'       = $isOrphaned
                        'RiskScore'        = $riskScore
                        'RiskLevel'        = $riskLevel
                        'ResourceId'       = $conn.id
                        'DynamicInvokeUrl' = $connDynUrl
                        'CreatedTime'      = $props.createdTime
                        'ChangedTime'      = $props.changedTime
                    })
                }
                catch {
                    Write-Verbose (
                        "Error on $($resource.id): " +
                        $_.Exception.Message
                    )
                }
            } -ThrottleLimit $ThrottleLimit
        }
        catch {
            Write-Message `
                -FunctionName $($MyInvocation.MyCommand.Name) `
                -Message      $($_.Exception.Message) `
                -Severity     'Error'
        }
    }

    end {
        $duration   = (Get-Date) - $stats.StartTime
        $allResults = $rawResults.ToArray()

        # Apply post-process filters
        if ($OrphanedOnly) {
            $allResults = $allResults |
                Where-Object { $_.IsOrphaned -eq $true }
        }

        if ($MinRiskLevel) {
            $minScore = switch ($MinRiskLevel) {
                'High'   { 6 }
                'Medium' { 4 }
                'Low'    { 0 }
            }
            $allResults = $allResults |
                Where-Object { $_.RiskScore -ge $minScore }
        }

        $stats.HighRisk   = (
            $allResults | Where-Object RiskLevel -eq 'High'
        ).Count
        $stats.MediumRisk = (
            $allResults | Where-Object RiskLevel -eq 'Medium'
        ).Count
        $stats.LowRisk    = (
            $allResults | Where-Object RiskLevel -eq 'Low'
        ).Count
        $stats.Orphaned   = (
            $allResults | Where-Object IsOrphaned -eq $true
        ).Count

        Write-Host "`n API Connection Risk Summary:" -ForegroundColor Magenta
        Write-Host "   Total Connections : $($stats.Total)" `
            -ForegroundColor White
        Write-Host "   High Risk         : $($stats.HighRisk)" `
            -ForegroundColor Red
        Write-Host "   Medium Risk       : $($stats.MediumRisk)" `
            -ForegroundColor Yellow
        Write-Host "   Low Risk          : $($stats.LowRisk)" `
            -ForegroundColor Green
        Write-Host "   Orphaned          : $($stats.Orphaned)" `
            -ForegroundColor DarkYellow
        Write-Host (
            "   Duration          : " +
            "$($duration.TotalSeconds.ToString('F2'))s"
        ) -ForegroundColor White

        Write-Verbose "Completed function $($MyInvocation.MyCommand.Name)"

        Format-BlackCatOutput `
            -Data         $allResults `
            -OutputFormat $OutputFormat `
            -FunctionName $MyInvocation.MyCommand.Name
    }

    <#
    .SYNOPSIS
        Enumerates API Connections and scores their security risk.

    .DESCRIPTION
        Discovers all Microsoft.Web/connections in scope, correlates each
        to its consuming Logic App(s), determines the auth type and
        consenting identity, and produces a risk-scored inventory.

        Risk factors considered:
        - Connector sensitivity (Office 365, SQL, Key Vault = high)
        - Auth type (OAuth delegated user > SP > API Key > MI)
        - Orphaned status (no Logic App references = overlooked risk)

        This helps identify: over-privileged connections, connections
        authorized by high-privilege accounts, and dormant connections
        that are still active but unmonitored.

    .PARAMETER ResourceGroupName
        Limits the search to a specific resource group.
        If omitted, all accessible resource groups are searched.

    .PARAMETER OrphanedOnly
        Returns only connections that have no Logic App references.
        These are the highest-risk dormant-trust objects.

    .PARAMETER MinRiskLevel
        Filters results to connections at or above the specified risk
        level. Accepted values: High, Medium, Low.

    .PARAMETER ThrottleLimit
        Controls parallel thread count. Default is 100.

    .PARAMETER OutputFormat
        Output format: Object (default sorted table), JSON, CSV, Table.

    .EXAMPLE
        Get-ApiConnection

        Enumerates all API Connections in the current subscription and
        returns a risk-scored table.

    .EXAMPLE
        Get-ApiConnection -MinRiskLevel High -OutputFormat JSON

        Returns only high-risk connections and exports to a JSON file.

    .EXAMPLE
        Get-ApiConnection -OrphanedOnly

        Returns connections with no referencing Logic Apps — these are
        dormant trust grants that are often forgotten but still active.

    .EXAMPLE
        Get-ApiConnection -ResourceGroupName 'rg-integrations'

        Scopes the search to a single resource group.

    .OUTPUTS
        [PSCustomObject]
        Each object contains:
        - Name: Connection resource name
        - ResourceGroup: Containing resource group
        - Connector: Connector display name (e.g. "Office 365 Outlook")
        - ConnectorId: API name (e.g. "office365")
        - AuthType: OAuth-User | OAuth-SP | ApiKey | BasicAuth |
                    ManagedIdentity | Unknown
        - AuthorizedAs: UPN or display name of consenting identity
        - Status: Connected | Error | Unauthenticated
        - LinkedApps: Semicolon-separated Logic App names using this
                      connection
        - IsOrphaned: True if no Logic Apps reference this connection
        - RiskScore: Numeric score 0–10
        - RiskLevel: High | Medium | Low
        - ResourceId: Full ARM resource ID
        - CreatedTime / ChangedTime: Lifecycle timestamps

    .NOTES
        Author: BlackCat Security Framework
        Requires: ARM API access (Az.Accounts)

        Required RBAC actions:
        - Microsoft.Web/connections/read
        - Microsoft.Logic/workflows/read

    .LINK
        MITRE ATT&CK Tactic: TA0007 - Discovery
        https://attack.mitre.org/tactics/TA0007/

    .LINK
        MITRE ATT&CK Technique: T1526 - Cloud Service Discovery
        https://attack.mitre.org/techniques/T1526/
    #>
}
