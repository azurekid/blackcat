function Connect-GraphToken {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [Alias('BearerToken', 'Token', 'JWT')]
        [string]$AccessToken,

        [Parameter(Mandatory = $false)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [Alias('Path')]
        [string]$FilePath,

        [Parameter(Mandatory = $false)]
        [switch]$asBase64,

        [Parameter(Mandatory = $false)]
        [switch]$asCompressed,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Azure', 'Batch', 'Cache', 'CosmosDB', 'DataLake', 'DevOps', 'EventGrid', 'EventHub',
                     'IoTHub', 'KeyVault', 'LogAnalytics', 'MSGraph', 'RedisCache', 'SQLDatabase',
                     'ServiceBus', 'Storage', 'Synapse', 'Other')]
        [string]$EndpointType = 'MSGraph',

        [Parameter(Mandatory = $false)]
        [ValidatePattern('^(https?)://[^\s/$.?#].[^\s]*$')]
        [string]$EndpointUri
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
    }

    process {
        try {
            # Handle file input — read content and auto-detect compressed format
            if ($FilePath) {
                Write-Verbose "Reading token from file: $FilePath"
                $AccessToken = (Get-Content -Path $FilePath -Raw).Trim()
                if (-not $asBase64) {
                    $asCompressed = $true
                }
            }

            if ([string]::IsNullOrWhiteSpace($AccessToken)) {
                throw "No token provided. Use -AccessToken or -FilePath to supply a token."
            }

            # Decode token based on encoding format
            $decodedToken = $AccessToken
            if ($asCompressed) {
                Write-Verbose "Decompressing GZip + Base64 encoded token"
                try {
                    $compressedBytes = [System.Convert]::FromBase64String($AccessToken)
                    $memoryStream    = [System.IO.MemoryStream]::new($compressedBytes)
                    $gzipStream      = [System.IO.Compression.GZipStream]::new($memoryStream, [System.IO.Compression.CompressionMode]::Decompress)
                    $reader          = [System.IO.StreamReader]::new($gzipStream)
                    $decodedToken    = $reader.ReadToEnd()
                    $reader.Close()
                }
                catch {
                    throw "Failed to decompress token. Ensure the value is a valid GZip + Base64 string: $($_.Exception.Message)"
                }
            }
            elseif ($asBase64) {
                Write-Verbose "Decoding base64-encoded token"
                try {
                    $decodedToken = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($AccessToken))
                }
                catch {
                    throw "Failed to decode base64 token: $($_.Exception.Message)"
                }
            }

            # Define endpoint mappings
            $endpoints = @{
                Azure        = 'https://management.azure.com'
                Batch        = 'https://batch.azure.com'
                Cache        = 'https://cache.azure.com'
                CosmosDB     = 'https://cosmos.azure.com'
                DataLake     = 'https://datalake.azure.net'
                DevOps       = '499b84ac-1321-427f-aa17-267ca6975798'
                EventGrid    = 'https://eventgrid.azure.net'
                EventHub     = 'https://eventhub.azure.net'
                IoTHub       = 'https://iothub.azure.net'
                KeyVault     = 'https://vault.azure.net'
                LogAnalytics = 'https://api.loganalytics.io'
                MSGraph      = 'https://graph.microsoft.com'
                RedisCache   = 'https://cache.azure.com'
                SQLDatabase  = 'https://database.windows.net'
                ServiceBus   = 'https://servicebus.azure.net'
                Storage      = 'https://storage.azure.com'
                Synapse      = 'https://dev.azuresynapse.net'
            }

            # Determine the target endpoint
            $targetEndpoint = $endpoints[$EndpointType]
            if ($EndpointType -eq 'Other') {
                if ([string]::IsNullOrWhiteSpace($EndpointUri)) {
                    throw "When 'Other' is selected as EndpointType, 'EndpointUri' parameter is required"
                }
                $targetEndpoint = $EndpointUri
            }
            elseif ($EndpointUri) {
                $targetEndpoint = $EndpointUri
            }

            # Parse the JWT to extract claims
            $tokenDetails = ConvertFrom-JWT -Base64JWT $decodedToken

            if (-not $tokenDetails) {
                throw "Failed to parse JWT token"
            }

            # Extract key information from token (ConvertFrom-JWT returns specific property names)
            $tenantId = $tokenDetails."Tenant ID"
            $appId = $tokenDetails.AppId
            $oid = $tokenDetails.ObjectId
            $displayName = $tokenDetails.AppDisplayName
            $audience = $tokenDetails.Audience
            $roles = $tokenDetails.Roles
            $expiresOn = if ($tokenDetails.Expires) {
                $tokenDetails.Expires.DateTime
            } else {
                $null
            }

            # Validate token expiration
            if (-not $expiresOn) {
                Write-Warning "Could not determine token expiration time from token claims"
            } else {
                $utcNow = [DateTime]::UtcNow
                $timeRemaining = $expiresOn - $utcNow

                if ($utcNow -gt $expiresOn) {
                    # Token has expired
                    $expiredDuration = $utcNow - $expiresOn
                    $expiredSeconds = [Math]::Round($expiredDuration.TotalSeconds)
                    throw " Token has expired. Expired $expiredSeconds seconds ago at $($expiresOn.ToString('yyyy-MM-dd HH:mm:ss')) UTC"
                }
                elseif ($timeRemaining.TotalMinutes -lt 5) {
                    # Token expiring soon
                    Write-Warning " Token will expire in $([Math]::Round($timeRemaining.TotalSeconds)) seconds at $($expiresOn.ToString('yyyy-MM-dd HH:mm:ss')) UTC"
                }
            }

            # Validate token audience matches endpoint
            $expectedAudience = if ($EndpointType -eq 'MSGraph') { 'https://graph.microsoft.com' } else { $targetEndpoint }
            if ($audience -ne $expectedAudience -and $audience -ne $targetEndpoint) {
                Write-Warning "Token audience is '$audience', expected '$expectedAudience'. This may not work with API calls to $EndpointType."
            }

            Write-Verbose "Token expires: $expiresOn UTC"
            Write-Verbose "Token for: $displayName ($appId)"
            Write-Verbose "Tenant: $tenantId"
            Write-Verbose "Roles: $($roles -join ', ')"

            # Set up the session variables for BlackCat
            if (-not $script:SessionVariables) {
                $script:SessionVariables = @{}
            }

            # Get module version
            $moduleVersion = "0.30.0" # Default fallback
            try {
                $manifestPath = Join-Path $PSScriptRoot "../../BlackCat.psd1"
                if (Test-Path $manifestPath) {
                    $moduleManifest = Import-PowerShellDataFile $manifestPath
                    $moduleVersion = $moduleManifest.ModuleVersion
                }
            }
            catch {
                Write-Verbose "Could not load module version, using default"
            }

            # Store the token and related info
            $authHeader = @{
                'Authorization' = "Bearer $decodedToken"
                'Content-Type'  = 'application/json'
            }

            # Set appropriate session variables based on endpoint type
            if ($EndpointType -eq 'MSGraph') {
                $script:graphHeader = $authHeader
                $script:SessionVariables.graphUri = "https://graph.microsoft.com/beta"
            }
            elseif ($EndpointType -eq 'Azure') {
                $script:authHeader = $authHeader
                $script:SessionVariables.baseUri = "https://management.azure.com"
            }
            else {
                # For other endpoints, store in a generic header variable
                $script:SessionVariables."${EndpointType}Header" = $authHeader
                $script:SessionVariables."${EndpointType}Uri" = $targetEndpoint
            }

            # Always set the general authentication variables
            $script:SessionVariables.graphUri = if ($EndpointType -eq 'MSGraph') { "https://graph.microsoft.com/beta" } else { $targetEndpoint }
            $script:SessionVariables.tenantId = $tenantId
            $script:SessionVariables.ExpiresOn = $expiresOn
            $script:SessionVariables.userAgent = "BlackCat/$moduleVersion PowerShell Client"
            $script:SessionVariables.accessToken = $decodedToken
            $script:SessionVariables.AccessToken = $decodedToken  # Capital A for compatibility
            $script:SessionVariables.EndpointType = $EndpointType

            # Initialize appRoleIds if not already present
            if (-not $script:SessionVariables.appRoleIds) {
                try {
                    Get-AppRolePermission -ErrorAction SilentlyContinue | Out-Null
                }
                catch {
                    Write-Verbose "Could not load appRoleIds cache"
                }
            }

            Write-Verbose "Successfully initialized BlackCat session with provided token"

            # Return connection details
            $result = [PSCustomObject]@{
                DisplayName      = $displayName
                ObjectId         = $oid
                AppId            = $appId
                TenantId         = $tenantId
                TokenExpires     = $expiresOn
                Roles            = $roles
                Audience         = $audience
                ConnectedAt      = Get-Date
            }

            Write-Host "✓ Connected to $EndpointType as $displayName" -ForegroundColor Green
            Write-Host "  Endpoint: $targetEndpoint" -ForegroundColor Cyan
            Write-Host "  Permissions: $($roles -join ', ')" -ForegroundColor Cyan
            Write-Host "  Token expires: $expiresOn UTC" -ForegroundColor Yellow

            return $result
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
            return $null
        }
    }

    end {
        Write-Verbose "Completed function $($MyInvocation.MyCommand.Name)"
    }

    <#
.SYNOPSIS
Authenticates to Azure APIs using a bearer token (JWT) for BlackCat module operations.

.DESCRIPTION
The Connect-GraphToken function allows you to authenticate to Azure APIs by providing an existing
bearer token (JWT access token). This is useful when you have obtained a token through other means,
such as from a managed identity, federated credential, or external token acquisition process.

The function parses the JWT token to extract tenant ID, application information, permissions (roles),
and expiration time. It then configures the BlackCat session to use this token for subsequent
API calls to the specified endpoint.

This function is particularly useful for:
- Using tokens from Azure Managed Identities (UAMI/System-assigned)
- Federated identity credential scenarios (GitHub OIDC, etc.)
- Token extraction from external authentication flows
- Testing with pre-acquired tokens
- Multi-cloud and multi-endpoint scenarios

.PARAMETER AccessToken
The JWT bearer token for Azure APIs. This should be a complete JWT string, base64-encoded string,
or GZip compressed + Base64 string. Can be obtained from various sources like Get-AzAccessToken,
OIDC token exchange, etc. Either this or -FilePath must be provided.

.PARAMETER FilePath
Path to a file containing the token. Typically the .gz.b64 artifact downloaded from the GitHub
Actions workflow. The file content is read automatically and treated as GZip + Base64 compressed
unless -asBase64 is specified.

.PARAMETER asBase64
Switch parameter to indicate that the AccessToken parameter contains a base64-encoded token.
When specified, the function will decode the base64 string before processing.

.PARAMETER asCompressed
Switch parameter to indicate that the AccessToken parameter contains a GZip compressed + Base64
encoded token. This is the format produced by the exploit.yml GitHub Actions workflow, which
compresses the token to avoid log truncation. The function will decompress and decode automatically.

.PARAMETER EndpointType
The type of Azure endpoint to authenticate against.
Acceptable values are: 'Azure' (ARM), 'Batch', 'Cache', 'CosmosDB', 'DataLake', 'DevOps', 'EventGrid',
'EventHub', 'IoTHub', 'KeyVault', 'LogAnalytics', 'MSGraph' (default), 'RedisCache', 'SQLDatabase',
'ServiceBus', 'Storage', 'Synapse', 'Other' (custom endpoint).

When 'Other' is selected, the EndpointUri parameter is required.

Default value is 'MSGraph'.

.PARAMETER EndpointUri
Optional custom endpoint URI. If provided, this overrides the default endpoint for the selected EndpointType.
Required when EndpointType is 'Other'.

.EXAMPLE
# Connect using a UAMI token obtained through GitHub Actions OIDC
$token = "eyJ0eXAiOiJKV1QiLCJub25jZSI6..."
Connect-GraphToken -AccessToken $token

This example connects to Microsoft Graph using a bearer token obtained from a managed identity.

.EXAMPLE
# Connect using a base64-encoded token
$b64Token = "ZXlKMGVYQWlPaUpLVjFRaUxDSnViMjVqWlNJNklt..."
Connect-GraphToken -AccessToken $b64Token -asBase64

This example decodes a base64-encoded token and uses it to connect to Microsoft Graph.

.EXAMPLE
# Connect using a GZip compressed token from the exploit.yml workflow
$compressed = "H4sIAAAAAAAAA..."
Connect-GraphToken -AccessToken $compressed -asCompressed -EndpointType MSGraph

This example decompresses a GZip + Base64 encoded token (as output by the GitHub Actions workflow) and connects to Microsoft Graph.

.EXAMPLE
# Connect using the downloaded artifact file from the GitHub Actions workflow
Connect-GraphToken -FilePath ./token.gz.b64 -EndpointType MSGraph

This example reads the compressed token from the downloaded artifact file and connects to Microsoft Graph.

.EXAMPLE
# Connect to Azure Resource Manager (ARM)
Connect-GraphToken -AccessToken $armToken -EndpointType Azure

This example connects to Azure Resource Manager using a token.

.EXAMPLE
# Connect to Key Vault
Connect-GraphToken -AccessToken $kvToken -EndpointType KeyVault

This example connects to Azure Key Vault using a token.

.EXAMPLE
# Connect with a custom endpoint
Connect-GraphToken -AccessToken $token -EndpointType 'Other' -EndpointUri 'https://custom.endpoint.com'

This example connects to a custom endpoint using the provided token.

.EXAMPLE
# Connect and immediately use BlackCat functions
Connect-GraphToken -AccessToken $uamiToken -EndpointType MSGraph
Get-ServicePrincipalsPermission -servicePrincipalId "197e935d-02a7-4ca3-98a2-a2b0ffc389f6"

This example connects with a token and immediately runs BlackCat commands using that authentication.

.NOTES
- Token must be valid and not expired
- Token audience should match the selected endpoint type
- After connecting, all BlackCat API functions will use this token for the specified endpoint
- Token expiration is checked but not automatically refreshed
- For Microsoft Graph, all BlackCat Microsoft Graph functions will use this token
- For other endpoints, token is stored in session variables for custom API calls
- Author: Rogier Dijkman
- Prerequisite: PowerShell version 7.0 or higher

.LINK
MITRE ATT&CK Tactic: TA0001 - Initial Access
https://attack.mitre.org/tactics/TA0001/

.LINK
MITRE ATT&CK Technique: T1550.001 - Use Alternate Authentication Material: Application Access Token
https://attack.mitre.org/techniques/T1550/001/
#>
}
