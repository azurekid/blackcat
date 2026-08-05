function Invoke-ConnectorProxy {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true
        )]
        [string]$ResourceId,

        [Parameter(
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true
        )]
        [string]$Token,

        [Parameter(
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true
        )]
        [string]$RuntimeUrl,

        [Parameter(
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true
        )]
        [string]$DynamicInvokeUrl,

        [Parameter(Mandatory = $false)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$OperationId,

        [Parameter(Mandatory = $false)]
        [ValidateSet(
            'GET', 'POST', 'PUT', 'PATCH', 'DELETE'
        )]
        [string]$Method = 'GET',

        [Parameter(Mandatory = $false)]
        [hashtable]$Body,

        [Parameter(Mandatory = $false)]
        [hashtable]$Queries,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Object', 'JSON', 'CSV', 'Table')]
        [Alias('output', 'o')]
        [string]$OutputFormat = 'Object'
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name |
            Invoke-BlackCat -ResourceTypeName 'Azure'

        $startTime = Get-Date
        $stats = @{
            TotalProcessed = 0
            Succeeded      = 0
            ErrorCount     = 0
        }
        $results = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
    }

    process {
        $stats.TotalProcessed++

        # Resolve connection identifier for display
        $connLabel = if ($ResourceId) {
            ($ResourceId -split '/')[-1]
        } elseif ($DynamicInvokeUrl) {
            # Extract connection name from URL segment
            $DynamicInvokeUrl -replace '.*\/connections\/([^\/\?]+).*', '$1'
        } else {
            '(unknown)'
        }

        try {
            # -------------------------------------------------------
            # Mode 1 — Direct: call the connector runtime using a
            # Bearer token retrieved via Get-ApiConnectionToken.
            # Requires both $Token and $RuntimeUrl.
            # -------------------------------------------------------
            if ($Token -and $RuntimeUrl) {
                Write-Host (
                    "  [*] $connLabel — Mode 1 (Direct)" +
                    " — $Method $Path"
                ) -ForegroundColor Cyan

                $callUri = $RuntimeUrl.TrimEnd('/') + $Path

                if ($Queries -and $Queries.Count -gt 0) {
                    $qs = ($Queries.GetEnumerator() |
                        ForEach-Object {
                            "$([uri]::EscapeDataString($_.Key))" +
                            "=$([uri]::EscapeDataString($_.Value))"
                        }) -join '&'
                    $callUri = "$callUri`?$qs"
                }

                $invokeParams = @{
                    Uri     = $callUri
                    Method  = $Method
                    Headers = @{ Authorization = "Bearer $Token" }
                }
                if ($Body -and $Body.Count -gt 0) {
                    $invokeParams['Body'] = (
                        $Body | ConvertTo-Json -Depth 10 -Compress
                    )
                    $invokeParams['ContentType'] = 'application/json'
                }

                $response = Invoke-RestMethod @invokeParams

                # Unwrap OData envelope: connectors that return a
                # list use the standard { value: [...] } wrapper.
                $data     = if ($null -ne $response.value) {
                    $response.value
                } else { $response }
                $nextLink = $response.'@odata.nextLink'
                $count    = if ($data -is [array]) {
                    $data.Count
                } elseif ($null -ne $data) { 1 } else { 0 }

                $item = [PSCustomObject]@{
                    'Mode'         = 'Direct'
                    'Connection'   = $connLabel
                    'Path'         = $Path
                    'Method'       = $Method
                    'ConnectionId' = $ResourceId
                    'StatusCode'   = 200
                    'Count'        = $count
                    'NextLink'     = $nextLink
                    'Data'         = $data
                }
                [void]$results.Add($item)
                $stats.Succeeded++

                Write-Host (
                    "  [+] $connLabel — $count item(s) received"
                ) -ForegroundColor Green
            }
            # -------------------------------------------------------
            # Mode 2 — DynamicInvoke: ARM-authenticated proxy call.
            # Azure forwards the request as the consenting user.
            # Works for OAuth-User connections where the raw token
            # is not accessible.  Requires either $DynamicInvokeUrl
            # (piped from Get-ApiConnection / Get-ApiConnectionToken)
            # or $ResourceId from which the URL is auto-constructed.
            # -------------------------------------------------------
            else {
                $sv   = $script:SessionVariables
                $auth = $script:authHeader

                # Auto-build DynamicInvokeUrl from ResourceId when not
                # piped from an upstream function
                if (-not $DynamicInvokeUrl) {
                    if (-not $ResourceId) {
                        throw (
                            'Provide -ResourceId or -DynamicInvokeUrl,' +
                            ' or pipe from Get-ApiConnection /' +
                            ' Get-ApiConnectionToken'
                        )
                    }
                    $dynSub  = ($ResourceId -split '/')[2]
                    $dynRg   = ($ResourceId -split '/')[4]
                    $dynName = ($ResourceId -split '/')[-1]
                    $DynamicInvokeUrl = (
                        '{0}/subscriptions/{1}' +
                        '/resourceGroups/{2}' +
                        '/providers/Microsoft.Web' +
                        '/connections/{3}/dynamicInvoke' +
                        '?api-version=2018-07-01-preview'
                    ) -f $sv.armUri, $dynSub, $dynRg, $dynName
                }

                Write-Host (
                    "  [*] $connLabel — Mode 2 (DynamicInvoke)" +
                    " — $Method $Path"
                ) -ForegroundColor Cyan

                # CloudManagedApiConnectionDynamicInvokeDefinition schema:
                # top-level key is 'request', containing the HTTP
                # request details as a nested object.  The ARM RP
                # injects the /{connectionId}/ path prefix itself.
                $invokeBody = [ordered]@{
                    request = [ordered]@{
                        method  = $Method.ToLower()
                        path    = $Path
                        queries = if ($Queries -and $Queries.Count -gt 0) {
                            $Queries
                        } else { @{} }
                        headers = @{}
                        body    = if ($Body -and $Body.Count -gt 0) {
                            $Body
                        } else { $null }
                    }
                }

                $response = Invoke-RestMethod `
                    -Uri         $DynamicInvokeUrl `
                    -Headers     $auth `
                    -Method      'POST' `
                    -Body        (
                        $invokeBody | ConvertTo-Json -Depth 10 -Compress
                    ) `
                    -ContentType 'application/json' `
                    -UserAgent   $sv.userAgent

                # Unwrap the ARM dynamicInvoke envelope:
                #   $response.response.statusCode  — HTTP status
                #   $response.response.body        — connector payload
                # Then unwrap OData { value: [...] } if present.
                $armResp  = $response.response
                $rawBody  = $armResp.body
                $data     = if ($null -ne $rawBody.value) {
                    $rawBody.value
                } elseif ($null -ne $rawBody) {
                    $rawBody
                } else { $null }
                $nextLink = $rawBody.'@odata.nextLink'
                $count    = if ($data -is [array]) {
                    $data.Count
                } elseif ($null -ne $data) { 1 } else { 0 }

                $item = [PSCustomObject]@{
                    'Mode'         = 'DynamicInvoke'
                    'Connection'   = $connLabel
                    'Path'         = $Path
                    'Method'       = $Method
                    'ConnectionId' = $ResourceId
                    'StatusCode'   = $armResp.statusCode
                    'Count'        = $count
                    'NextLink'     = $nextLink
                    'Data'         = $data
                }
                [void]$results.Add($item)
                $stats.Succeeded++

                Write-Host (
                    "  [+] $connLabel — $count item(s) received"
                ) -ForegroundColor Green
            }
        }
        catch {
            $errMsg = $_.Exception.Message
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

            Write-Warning "Failed on $connLabel`: $displayMsg"
            $stats.ErrorCount++
        }
    }

    end {
        $duration = (Get-Date) - $startTime

        Write-Host "`nConnector Proxy Summary:" -ForegroundColor Cyan
        Write-Host (
            "   Total Processed: $($stats.TotalProcessed)"
        ) -ForegroundColor White
        Write-Host (
            "   Succeeded: $($stats.Succeeded)"
        ) -ForegroundColor Green
        Write-Host (
            "   Errors: $($stats.ErrorCount)"
        ) -ForegroundColor Red
        Write-Host (
            "   Duration: $($duration.TotalSeconds.ToString('F2'))" +
            ' seconds'
        ) -ForegroundColor White

        Write-Verbose "Completed function $($MyInvocation.MyCommand.Name)"

        Format-BlackCatOutput `
            -Data       $results `
            -OutputFormat $OutputFormat `
            -FunctionName $MyInvocation.MyCommand.Name
    }

    <#
    .SYNOPSIS
        Invokes actions through an existing API connection resource.

    .DESCRIPTION
        Proxies API calls through Microsoft.Web/connections resources
        using one of two modes:

        Mode 1 — Direct: Uses a Bearer token (from Get-ApiConnectionToken)
        to call the connector runtime URL directly.  Fast but requires a
        token, which is only available for non-OAuth-User connections.

        Mode 2 — DynamicInvoke (default): Posts to the ARM dynamicInvoke
        endpoint using the current ARM session token.  Azure transparently
        forwards the request acting as the consenting user.  Works for ALL
        connection types including OAuth-User (office365, teams, sharepoint)
        where the raw refresh token is stored in Azure's internal vault and
        is not directly accessible.

        The function accepts pipeline input from Get-ApiConnection or
        Get-ApiConnectionToken so connections can be enumerated and
        immediately acted on without storing credentials.

    .PARAMETER ResourceId
        ARM resource ID of the connection
        (/subscriptions/{sub}/resourceGroups/{rg}/providers/
        Microsoft.Web/connections/{name}).
        Piped automatically from Get-ApiConnection /
        Get-ApiConnectionToken.

    .PARAMETER Token
        Short-lived JWT from Get-ApiConnectionToken.
        When combined with RuntimeUrl, enables Mode 1 (Direct).

    .PARAMETER RuntimeUrl
        Connector runtime base URL from Get-ApiConnectionToken.
        When combined with Token, enables Mode 1 (Direct).

    .PARAMETER DynamicInvokeUrl
        Fully-qualified ARM dynamicInvoke URL.
        Piped automatically from Get-ApiConnection /
        Get-ApiConnectionToken.  If omitted and ResourceId is set,
        the URL is auto-constructed.

    .PARAMETER Path
        Connector API path to invoke, relative to the connector
        runtime root (strip the leading /{connectionId}/ segment
        from swagger paths).  Examples:
          Swagger: /{connectionId}/v2/Mail  →  Path: /v2/Mail
          Swagger: /{connectionId}/datasets/{dataset}/tables/{table}/items
                    → Path: /datasets/default/tables/default/items
        Used by both Mode 1 (Direct) and Mode 2 (DynamicInvoke).

    .PARAMETER OperationId
        Reserved for future use.  Not sent in the request body;
        keep for pipeline compatibility.

    .PARAMETER Method
        HTTP method for the connector action.
        Accepted: GET, POST, PUT, PATCH, DELETE.  Default: GET.

    .PARAMETER Body
        Optional hashtable forwarded as the request body.

    .PARAMETER Queries
        Optional hashtable of query-string parameters appended to
        the connector path.

    .PARAMETER OutputFormat
        Output format: Object (default), JSON, CSV, or Table.

    .EXAMPLE
        Get-ApiConnection |
            Where-Object ConnectorId -eq 'office365' |
            Invoke-ConnectorProxy -Path '/v2/Mail' `
                -Queries @{ top = 10; fetchOnlyUnread = $false }

        List the 10 most recent emails via all Office 365 connections
        using Mode 2 (DynamicInvoke).  Path is the swagger path minus
        the /{connectionId}/ prefix.  No token extraction required.

    .EXAMPLE
        Get-ApiConnectionToken |
            Where-Object Token |
            Invoke-ConnectorProxy `
                -Path '/v2/datasets/default/tables/default/items' `
                -Queries @{ '$top' = '50' }

        Query SharePoint list items (Mode 1 Direct) for all
        connections that returned a runtime token.

    .EXAMPLE
        Invoke-ConnectorProxy `
            -ResourceId (
                '/subscriptions/cc826ab7-e046-4422-8e68' +
                '-ba57b6d48165/resourceGroups/rg-prod' +
                '/providers/Microsoft.Web/connections/office365'
            ) `
            -Path '/v2/Mail' `
            -Method POST `
            -Body @{
                emailMessage = @{
                    To      = 'target@contoso.com'
                    Subject = 'Security Test'
                    Body    = 'Automated notification'
                }
            }

        Send an email as the consenting user via DynamicInvoke.

    .OUTPUTS
        [PSCustomObject]
        Returns objects with properties:
        - Mode:         'Direct' or 'DynamicInvoke'
        - Connection:   Connection resource name
        - Path:         Connector action path that was invoked
        - Method:       HTTP method used
        - ConnectionId: ARM resource ID of the connection
        - StatusCode:   HTTP status code from the connector response
        - Count:        Number of items in Data (1 for single objects)
        - NextLink:     OData nextLink URL for paging, or $null
        - Data:         Unwrapped response payload.  List endpoints
                        return an array directly; single-object
                        endpoints return a PSCustomObject

    .NOTES
        Author: BlackCat Security Framework
        Requires: Azure ARM session (Invoke-BlackCat -ResourceTypeName Azure)

        DynamicInvoke requires:
        - Microsoft.Web/connections/read
        - Microsoft.Web/connections/dynamicInvoke/action

        Mode 1 (Direct) additionally requires:
        - Microsoft.Web/connections/listConnectionKeys/action

        OAuth-User connections (office365, teams, sharepoint, etc.)
        will always use Mode 2 — the OAuth refresh token is held in
        Azure's internal vault and cannot be extracted via the ARM API.

    .LINK
        MITRE ATT&CK Tactic: TA0009 - Collection
        https://attack.mitre.org/tactics/TA0009/

    .LINK
        MITRE ATT&CK Technique: T1530 - Data from Cloud Storage
        https://attack.mitre.org/techniques/T1530/
    #>
}
