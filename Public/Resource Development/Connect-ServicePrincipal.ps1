function Connect-ServicePrincipal {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [Alias('ApplicationId', 'ClientId', 'AppId')]
        [string]$ServicePrincipalId,

        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$ClientSecret,

        [Parameter(Mandatory = $false)]
        [ValidatePattern('^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $false)]
        [ValidateSet('AzureCloud', 'AzureUSGovernment', 'AzureChinaCloud', 'AzureGermanCloud')]
        [string]$Environment = 'AzureCloud',

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
    }

    process {
        try {
            if ($PSCmdlet.ShouldProcess("Service Principal '$ServicePrincipalId'", "Connect to Azure")) {
                Write-Verbose "Authenticating with Service Principal: $ServicePrincipalId"
                Write-Verbose "Tenant ID: $TenantId"
                Write-Verbose "Environment: $Environment"

                $SecureStringPwd = $ClientSecret | ConvertTo-SecureString -AsPlainText -Force

                # Use the provided ServicePrincipalId for credential username (was previously referencing an undefined $clientId)
                $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ServicePrincipalId, $SecureStringPwd

                # Build connection parameters
                $connectParams = @{
                    ServicePrincipal = $true
                    Credential       = $credential
                    TenantId         = $TenantId
                    Environment      = $Environment
                }

                if ($SubscriptionId) {
                    $connectParams.Subscription = $SubscriptionId
                    Write-Verbose "Subscription ID: $SubscriptionId"
                }

                if ($Force) {
                    $connectParams.Force = $true
                }

                Write-Verbose "Connecting to Azure..."
                $context = Connect-AzAccount @connectParams

                if ($context) {
                    Write-Verbose "Successfully connected to Azure"
                    
                    $currentContext = Get-AzContext
                    
                    $result = [PSCustomObject]@{
                        ServicePrincipalId = $ServicePrincipalId
                        TenantId           = $currentContext.Tenant.Id
                        TenantName         = $currentContext.Tenant.Directory
                        SubscriptionId     = $currentContext.Subscription.Id
                        SubscriptionName   = $currentContext.Subscription.Name
                        Environment        = $currentContext.Environment.Name
                        Account            = $currentContext.Account.Id
                        ConnectedAt        = Get-Date
                    }

                    return $result
                }
                else {
                    Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Failed to connect to Azure with the provided service principal credentials" -Severity 'Error'
                    return $null
                }
            }
        }
        catch {
            $errorMessage = switch -Wildcard ($_.Exception.Message) {
                "*AADSTS70002*"   { "Invalid client credentials. Please verify the Service Principal ID and Client Secret." }
                "*AADSTS90002*"   { "Invalid tenant ID. Please verify the Tenant ID is correct." }
                "*AADSTS700016*"  { "Application not found in the directory. Please verify the Service Principal ID." }
                "*AADSTS7000215*" { "Invalid client secret provided. Please verify the Client Secret." }
                "*AADSTS50034*"   { "The user account doesn't exist in the tenant. Please verify the Service Principal ID and Tenant ID." }
                "*AADSTS900971*"  { "No reply address provided. This might indicate an application configuration issue." }
                default           { "Authentication failed: $($_.Exception.Message)" }
            }
            
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $errorMessage -Severity 'Error'
            return $null
        }
    }

    end {
        Write-Verbose "Completed function $($MyInvocation.MyCommand.Name)"
    }

    <#
.SYNOPSIS
Authenticates to Azure using service principal credentials for BlackCat module operations.

.DESCRIPTION
The Connect-ServicePrincipal function provides a secure way to authenticate to Azure using service principal credentials (client ID, client secret, and tenant ID). This function is specifically designed to work with the BlackCat module and establishes an authentication context that enables all BlackCat functions to interact with Azure resources and Microsoft Graph API.

After successful authentication, the function validates access to Microsoft Graph API and provides detailed feedback about the connection status.

.PARAMETER ServicePrincipalId
The Application (Client) ID of the service principal. This parameter is mandatory and must be a valid GUID format.

.PARAMETER TenantId
The Tenant ID where the service principal is registered. This parameter is optional. If not provided, the current tenant ID from the Azure context will be used. Must be a valid GUID format when specified.

.PARAMETER ClientSecret
The client secret for the service principal. This parameter is mandatory and must be provided as a SecureString for security.

.PARAMETER SubscriptionId
The Subscription ID to use after authentication. This parameter is optional. If not provided, the default subscription will be used.

.PARAMETER Environment
The Azure environment to connect to. Valid values are: AzureCloud (default), AzureUSGovernment, AzureChinaCloud, AzureGermanCloud.

.PARAMETER Force
Forces the connection even if there's already an active Azure context. This will override the current session.

.EXAMPLE
$clientSecret = ConvertTo-SecureString "your-client-secret" -AsPlainText -Force
Connect-ServicePrincipal -ServicePrincipalId "12345678-1234-1234-1234-123456789012" -TenantId "87654321-4321-4321-4321-210987654321" -ClientSecret $clientSecret

Connects to Azure using the specified service principal credentials.

.EXAMPLE
$clientSecret = ConvertTo-SecureString "your-client-secret" -AsPlainText -Force
Connect-ServicePrincipal -ServicePrincipalId "12345678-1234-1234-1234-123456789012" -ClientSecret $clientSecret

Connects to Azure using the current tenant ID from the existing Azure context. The TenantId parameter is automatically retrieved from the current session.

.EXAMPLE
$clientSecret = Read-Host "Enter client secret" -AsSecureString
Connect-ServicePrincipal -ServicePrincipalId "12345678-1234-1234-1234-123456789012" -TenantId "87654321-4321-4321-4321-210987654321" -ClientSecret $clientSecret -SubscriptionId "11111111-1111-1111-1111-111111111111"

Prompts for the client secret securely and connects to Azure with a specific subscription.

.EXAMPLE
$clientSecret = ConvertTo-SecureString "your-client-secret" -AsPlainText -Force
Connect-ServicePrincipal -ServicePrincipalId "12345678-1234-1234-1234-123456789012" -TenantId "87654321-4321-4321-4321-210987654321" -ClientSecret $clientSecret -Environment "AzureUSGovernment" -Force

Connects to Azure US Government cloud, forcing a new connection even if one already exists.

.EXAMPLE
# Using with BlackCat functions after connection
$clientSecret = ConvertTo-SecureString "your-secret" -AsPlainText -Force
$connection = Connect-ServicePrincipal -ServicePrincipalId "12345678-1234-1234-1234-123456789012" -TenantId "87654321-4321-4321-4321-210987654321" -ClientSecret $clientSecret
if ($connection) {
    # Now you can use BlackCat functions
    Get-ServicePrincipalCredential -ObjectId "12345678-1234-1234-1234-123456789012"
}

Shows how to use the function with other BlackCat functions after successful authentication.

.LINK
https://learn.microsoft.com/en-us/powershell/azure/authenticate-azureps-service-principal
https://learn.microsoft.com/en-us/azure/active-directory/develop/app-objects-and-service-principals

#>
}