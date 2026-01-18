function Connect-EntraApplication {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [Alias('ApplicationId', 'AppId')]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string[]]$Scopes,

        [Parameter(Mandatory = $false)]
        [switch]$UseDeviceCode,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        
        # Check if already connected and Force is not specified
        if ($script:EntraAppContext -and -not $Force) {
            Write-Verbose "Already connected to Microsoft Graph"
            Write-Verbose "Current Account: $($script:EntraAppContext.Account)"
            
            $continueConnection = Read-Host "You are already connected. Do you want to disconnect and reconnect? (Y/N)"
            if ($continueConnection -ne 'Y') {
                Write-Verbose "Connection cancelled by user"
                return $script:EntraAppContext
            }
        }
    }

    process {
        try {
            if ($PSCmdlet.ShouldProcess("Enterprise Application '$ClientId'", "Connect with delegated permissions")) {
                Write-Verbose "Authenticating with Enterprise Application: $ClientId"
                Write-Verbose "Tenant ID: $TenantId"
                Write-Verbose "Requested Scopes: $($Scopes -join ', ')"

                # Build scope string for OAuth2
                $scopeString = ($Scopes | ForEach-Object { 
                    if ($_ -notmatch '^https://') { 
                        "https://graph.microsoft.com/$_" 
                    } else { 
                        $_ 
                    }
                }) -join ' '

                $redirectUri = "http://localhost"
                $authorizationEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/authorize"
                $tokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

                if ($UseDeviceCode) {
                    # Device Code Flow
                    Write-Verbose "Using device code authentication flow"
                    
                    Write-Host "`n" -NoNewline
                    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
                    Write-Host "  Device Code Authentication" -ForegroundColor Yellow
                    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
                    Write-Host ""

                    # Request device code
                    $deviceCodeEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/devicecode"
                    $deviceCodeBody = @{
                        client_id = $ClientId
                        scope     = $scopeString
                    }

                    Write-Verbose "Requesting device code from: $deviceCodeEndpoint"
                    $deviceCodeResponse = Invoke-RestMethod -Uri $deviceCodeEndpoint -Method Post -Body $deviceCodeBody -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop

                    Write-Host "🔐 To sign in, use a web browser to open the page:" -ForegroundColor Yellow
                    Write-Host "   $($deviceCodeResponse.verification_uri)" -ForegroundColor Cyan
                    Write-Host ""
                    Write-Host "📝 And enter the code:" -ForegroundColor Yellow
                    Write-Host "   $($deviceCodeResponse.user_code)" -ForegroundColor Green
                    Write-Host ""
                    Write-Host "⏳ Waiting for authentication..." -ForegroundColor Gray
                    Write-Host ""

                    # Poll for token
                    # Note: For public clients, we should not include client_secret
                    # The app must have "Allow public client flows" enabled
                    $tokenBody = @{
                        client_id   = $ClientId
                        grant_type  = "urn:ietf:params:oauth:grant-type:device_code"
                        device_code = $deviceCodeResponse.device_code
                        scope       = $scopeString
                    }

                    $interval = $deviceCodeResponse.interval
                    $expiresIn = $deviceCodeResponse.expires_in
                    $startTime = Get-Date

                    $tokenResponse = $null
                    while ($null -eq $tokenResponse) {
                        if (((Get-Date) - $startTime).TotalSeconds -gt $expiresIn) {
                            throw "Device code expired. Please try again."
                        }

                        Start-Sleep -Seconds $interval

                        try {
                            $tokenResponse = Invoke-RestMethod -Uri $tokenEndpoint -Method Post -Body $tokenBody -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
                        }
                        catch {
                            if ($_.Exception.Response.StatusCode -eq 400) {
                                $errorResponse = $_.ErrorDetails.Message | ConvertFrom-Json
                                if ($errorResponse.error -eq "authorization_pending") {
                                    # Still waiting for user to authenticate
                                    continue
                                }
                                elseif ($errorResponse.error -eq "authorization_declined") {
                                    throw "User declined the authentication request."
                                }
                                elseif ($errorResponse.error -eq "expired_token") {
                                    throw "Device code expired. Please try again."
                                }
                                else {
                                    throw $errorResponse.error_description
                                }
                            }
                            else {
                                throw
                            }
                        }
                    }
                }
                else {
                    # Interactive Authorization Code Flow with PKCE
                    Write-Verbose "Using interactive browser authentication flow"
                    
                    Write-Host "`n" -NoNewline
                    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
                    Write-Host "  Interactive Authentication" -ForegroundColor Yellow
                    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
                    Write-Host ""
                    Write-Host "🌐 A browser window will open for authentication." -ForegroundColor Yellow
                    Write-Host "   Please complete the sign-in process." -ForegroundColor Yellow
                    Write-Host ""

                    # Generate PKCE code verifier and challenge
                    $codeVerifier = -join ((65..90) + (97..122) + (48..57) + @(45, 46, 95, 126) | Get-Random -Count 128 | ForEach-Object { [char]$_ })
                    $codeChallenge = [Convert]::ToBase64String(
                        [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                            [System.Text.Encoding]::ASCII.GetBytes($codeVerifier)
                        )
                    ).TrimEnd('=').Replace('+', '-').Replace('/', '_')

                    # Start local HTTP listener
                    $listener = New-Object System.Net.HttpListener
                    $listener.Prefixes.Add("$redirectUri/")
                    $listener.Start()

                    # Build authorization URL
                    $state = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 32 | ForEach-Object { [char]$_ })
                    $authUrl = "$authorizationEndpoint`?client_id=$ClientId&response_type=code&redirect_uri=$([Uri]::EscapeDataString($redirectUri))&response_mode=query&scope=$([Uri]::EscapeDataString($scopeString))&state=$state&code_challenge=$codeChallenge&code_challenge_method=S256"

                    # Open browser
                    Start-Process $authUrl

                    Write-Verbose "Waiting for authorization code..."

                    # Wait for callback
                    $context = $listener.GetContext()
                    $request = $context.Request
                    $response = $context.Response

                    # Extract authorization code
                    $queryParams = [System.Web.HttpUtility]::ParseQueryString($request.Url.Query)
                    $code = $queryParams['code']
                    $returnedState = $queryParams['state']
                    $authError = $queryParams['error']

                    # Send response to browser
                    $responseString = if ($authError) {
                        "<html><body><h1>Authentication Failed</h1><p>Error: $authError</p><p>You can close this window.</p></body></html>"
                    }
                    else {
                        "<html><body><h1>Authentication Successful</h1><p>You can close this window and return to PowerShell.</p></body></html>"
                    }
                    
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseString)
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    $response.Close()
                    $listener.Stop()

                    if ($authError) {
                        throw "Authorization failed: $authError"
                    }

                    if ($returnedState -ne $state) {
                        throw "State mismatch. Possible CSRF attack detected."
                    }

                    # Exchange authorization code for token
                    $tokenBody = @{
                        client_id     = $ClientId
                        scope         = $scopeString
                        code          = $code
                        redirect_uri  = $redirectUri
                        grant_type    = "authorization_code"
                        code_verifier = $codeVerifier
                    }

                    $tokenResponse = Invoke-RestMethod -Uri $tokenEndpoint -Method Post -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
                }

                Write-Verbose "Token received successfully"

                # Decode access token to get user info
                try {
                    $tokenParts = $tokenResponse.access_token -split '\.'
                    if ($tokenParts.Count -lt 2) {
                        throw "Invalid token format"
                    }

                    # Decode the payload (second part of JWT)
                    $base64 = $tokenParts[1].Replace('-', '+').Replace('_', '/')
                    # Add padding if needed
                    switch ($base64.Length % 4) {
                        2 { $base64 += '==' }
                        3 { $base64 += '=' }
                    }
                    
                    $tokenPayload = [System.Text.Encoding]::UTF8.GetString(
                        [Convert]::FromBase64String($base64)
                    ) | ConvertFrom-Json

                    Write-Verbose "Token decoded successfully"
                }
                catch {
                    Write-Verbose "Failed to decode token payload: $_"
                    # If we can't decode, create a basic payload
                    $tokenPayload = @{
                        upn = "unknown"
                        scp = ($Scopes -join ' ')
                    }
                }

                # Extract account information
                $accountName = if ($tokenPayload.upn) { 
                    $tokenPayload.upn 
                } 
                elseif ($tokenPayload.unique_name) { 
                    $tokenPayload.unique_name 
                }
                elseif ($tokenPayload.preferred_username) {
                    $tokenPayload.preferred_username
                }
                elseif ($tokenPayload.email) {
                    $tokenPayload.email
                }
                else { 
                    $tokenPayload.sub ?? "unknown"
                }

                # Extract scopes
                $grantedScopes = if ($tokenPayload.scp) {
                    $tokenPayload.scp -split ' '
                }
                else {
                    $Scopes
                }

                Write-Verbose "Successfully authenticated to Microsoft Graph"
                
                Write-Host ""
                Write-Host "✅ Successfully authenticated!" -ForegroundColor Green
                Write-Host ""
                Write-Host "Connection Details:" -ForegroundColor Cyan
                Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Gray
                
                $result = [PSCustomObject]@{
                    ClientId         = $ClientId
                    TenantId         = $TenantId
                    Account          = $accountName
                    Scopes           = $grantedScopes
                    AuthType         = "Delegated"
                    AccessToken      = $tokenResponse.access_token
                    RefreshToken     = $tokenResponse.refresh_token
                    TokenExpiry      = (Get-Date).AddSeconds($tokenResponse.expires_in)
                    ConnectedAt      = Get-Date
                }

                # Store in script scope
                $script:EntraAppContext = $result

                Write-Host "  Client ID       : $($result.ClientId)" -ForegroundColor White
                Write-Host "  Tenant ID       : $($result.TenantId)" -ForegroundColor White
                Write-Host "  User Account    : $($result.Account)" -ForegroundColor White
                Write-Host "  Auth Type       : $($result.AuthType)" -ForegroundColor White
                Write-Host "  Granted Scopes  : $($result.Scopes -join ', ')" -ForegroundColor White
                Write-Host "  Token Expires   : $($result.TokenExpiry)" -ForegroundColor White
                Write-Host "  Connected At    : $($result.ConnectedAt)" -ForegroundColor White
                Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Gray
                Write-Host ""
                
                Write-Host "ℹ️  Using delegated permissions - operations run as: $($result.Account)" -ForegroundColor Cyan
                Write-Host ""

                return $result
            }
        }
        catch {
            # Get detailed error information
            $exceptionMessage = $_.Exception.Message
            $errorDetails = if ($_.ErrorDetails.Message) {
                try {
                    ($_.ErrorDetails.Message | ConvertFrom-Json).error_description
                }
                catch {
                    $_.ErrorDetails.Message
                }
            }
            else {
                $exceptionMessage
            }

            Write-Verbose "Error caught: $exceptionMessage"
            Write-Verbose "Error details: $errorDetails"
            Write-Verbose "Full error: $($_ | Out-String)"

            $errorMessage = switch -Wildcard ($exceptionMessage) {
                "*AADSTS65001*"   { "User cancelled the authentication flow." }
                "*AADSTS50058*"   { "Silent sign-in request failed. This typically requires interactive authentication." }
                "*AADSTS50076*"   { "Multi-factor authentication is required. Please complete MFA in the browser." }
                "*AADSTS700016*"  { "Application with identifier '$ClientId' was not found in the directory. Please verify the Client ID." }
                "*AADSTS90002*"   { "Invalid tenant ID. Please verify the Tenant ID is correct." }
                "*AADSTS650052*"  { "The app needs access to a service that your organization hasn't subscribed to or enabled." }
                "*AADSTS65004*"   { "User declined to consent to access the app. Please grant consent to the requested permissions." }
                "*authorization_declined*" { "User declined the authentication request." }
                "*expired_token*" { "Device code expired. Please try again." }
                "*redirect_uri*"  { "Invalid redirect URI. Please ensure the app registration has the correct redirect URIs configured (http://localhost or https://localhost)." }
                "*public client*" { "For device code flow, please enable 'Allow public client flows' in the app registration Authentication settings." }
                "*AADSTS7000218*" { "The app requires 'Allow public client flows' to be enabled. Go to Azure Portal > App registrations > Your App > Authentication > Advanced settings > Enable 'Allow public client flows'." }
                "*client_secret*" { "The app is configured to require client authentication. For device code or interactive flows, enable 'Allow public client flows' in the app registration (Authentication > Advanced settings)." }
                "*client_assertion*" { "The app is configured to require client authentication. For device code or interactive flows, enable 'Allow public client flows' in the app registration (Authentication > Advanced settings)." }
                default           { 
                    if ($errorDetails -and $errorDetails -ne $exceptionMessage) {
                        "Authentication failed: $errorDetails"
                    }
                    else {
                        "Authentication failed: $exceptionMessage"
                    }
                }
            }
            
            Write-Host ""
            Write-Host "❌ Authentication Failed" -ForegroundColor Red
            Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Gray
            Write-Host $errorMessage -ForegroundColor Red
            
            # Show additional error details in verbose mode
            if ($VerbosePreference -eq 'Continue') {
                Write-Host ""
                Write-Host "Detailed Error Information:" -ForegroundColor Yellow
                Write-Host "  Exception: $exceptionMessage" -ForegroundColor Gray
                if ($errorDetails) {
                    Write-Host "  Details: $errorDetails" -ForegroundColor Gray
                }
            }
            
            Write-Host ""
            Write-Host "🔧 Troubleshooting Steps:" -ForegroundColor Yellow
            Write-Host "  1. Verify the Client ID and Tenant ID are correct" -ForegroundColor Gray
            Write-Host "  2. Ensure delegated permissions are granted in the app registration" -ForegroundColor Gray
            Write-Host "  3. Check that admin consent has been granted (if required)" -ForegroundColor Gray
            
            if ($UseDeviceCode) {
                Write-Host "  4. Verify 'Allow public client flows' is enabled in app authentication settings" -ForegroundColor Gray
            }
            else {
                Write-Host "  4. Ensure redirect URIs are configured (http://localhost or https://localhost)" -ForegroundColor Gray
            }
            
            Write-Host "  5. Check if the user has permission to consent to the requested scopes" -ForegroundColor Gray
            Write-Host "  6. Run with -Verbose to see detailed error information" -ForegroundColor Gray
            Write-Host ""
            
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $errorMessage -Severity 'Error'
            return $null
        }
    }

    end {
        Write-Verbose "Completed function $($MyInvocation.MyCommand.Name)"
    }

    <#
.SYNOPSIS
Authenticates to Microsoft Graph using an Enterprise Application with delegated permissions.

.DESCRIPTION
The Connect-EntraApplication function provides an interactive way to authenticate to Microsoft Graph using delegated permissions of an Enterprise Application (App Registration). This function works similarly to Connect-MgGraph but specifically uses an application's delegated permissions, allowing operations to run in the context of the authenticated user.

This is ideal for scenarios where you need:
- Interactive user authentication
- Operations that run with user's permissions and identity
- User context for auditing and compliance
- Conditional Access and MFA policies to apply

The function supports both interactive browser-based authentication and device code flow for headless/remote environments.

.PARAMETER ClientId
The Application (Client) ID of the Enterprise Application. This parameter is mandatory and must be a valid GUID format. This is the ID of the app registration that has delegated permissions configured.

.PARAMETER TenantId
The Tenant ID where the application is registered. This parameter is mandatory and must be a valid GUID format.

.PARAMETER Scopes
An array of Microsoft Graph permission scopes to request. These should match the delegated permissions configured in the app registration. Common examples include:
- "User.Read" - Read user profile
- "User.ReadBasic.All" - Read all users' basic profiles
- "Directory.Read.All" - Read directory data
- "Group.Read.All" - Read all groups

Multiple scopes can be specified as an array: @("User.Read", "Directory.Read.All")

.PARAMETER UseDeviceCode
Switch parameter to use device code authentication flow instead of interactive browser authentication. This is useful for:
- Remote PowerShell sessions
- SSH sessions without browser access
- Azure Cloud Shell
- Headless Linux environments

.PARAMETER Force
Forces a new connection even if there's already an active Microsoft Graph session. This will disconnect the current session and create a new one.

.EXAMPLE
Connect-EntraApplication -ClientId "12345678-1234-1234-1234-123456789012" -TenantId "87654321-4321-4321-4321-210987654321" -Scopes @("User.Read", "Directory.Read.All")

Connects to Microsoft Graph using interactive browser authentication with the specified scopes.

.EXAMPLE
Connect-EntraApplication -ClientId "12345678-1234-1234-1234-123456789012" -TenantId "87654321-4321-4321-4321-210987654321" -Scopes @("User.Read") -UseDeviceCode

Connects using device code flow, which is useful for remote sessions or environments without browser access.

.EXAMPLE
$connection = Connect-EntraApplication -ClientId $appId -TenantId $tenantId -Scopes @("User.Read", "Group.Read.All") -Force

Forces a new connection and stores the connection details in a variable.

.EXAMPLE
# Read current user profile
Connect-EntraApplication -ClientId $appId -TenantId $tenantId -Scopes @("User.Read")
Get-MgUser -UserId "me"

.EXAMPLE
# Read directory data
Connect-EntraApplication -ClientId $appId -TenantId $tenantId -Scopes @("Directory.Read.All", "User.Read")
Get-MgUser -All

.NOTES
Prerequisites:
- PowerShell 7.0 or higher (for proper OAuth2 support)
- The Enterprise Application must have delegated permissions configured
- For interactive flow: Redirect URIs must be configured (http://localhost or https://localhost)
- For device code flow: "Allow public client flows" must be enabled
- User or admin consent must be granted for the requested permissions

Permission Types:
- This function uses DELEGATED permissions, not application permissions
- Operations run in the user's context with user's identity
- User's permissions and restrictions apply
- Conditional Access policies and MFA are enforced

Security Considerations:
- All operations are performed with the authenticated user's identity
- Audit logs will show the user's account, not the application
- User must have appropriate permissions for the requested operations
- MFA and Conditional Access policies apply to the user
- Access tokens are stored in $script:EntraAppContext for use by other functions
- Tokens expire after the specified time and may need refresh

Return Object:
- The function returns a connection object with AccessToken and RefreshToken
- Use $script:EntraAppContext.AccessToken to access the bearer token
- The token can be used with Invoke-RestMethod for Microsoft Graph API calls

.LINK
https://learn.microsoft.com/en-us/graph/auth-v2-user

.LINK
https://learn.microsoft.com/en-us/graph/permissions-reference
#>
}
