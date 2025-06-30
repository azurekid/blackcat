#requires -module @{ModuleName = 'Az.Accounts'; ModuleVersion = '3.0.0'}
#requires -version 7.0

function Invoke-BlackCat {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$FunctionName,

        [Parameter(Mandatory = $false, ValueFromPipeline = $false)]
        [string]$ResourceTypeName,

        [Switch]
        $ChangeProfile = $False
    )

    $azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile

    try {
        # Select a random user agent
        $randomUserAgent = ($sessionVariables.userAgents.agents | Get-Random).value
        Write-Verbose -Message "Using user agent: $randomUserAgent"

        if ($azProfile.Contexts.Count -ne 0) {
            if ([string]::IsNullOrEmpty($SessionVariables.AccessToken)) {
                try {
                    Get-AccessToken
                }
                catch {
                    Write-Error -Exception $_.Exception.Message
                    break
                }
            }
            elseif ($SessionVariables.ExpiresOn - [datetime]::UtcNow.AddMinutes(-5) -le 0) {
                # if token expires within 5 minutes, request a new access token
                try {
                    Get-AccessToken
                }
                catch {
                    Write-Error -Exception $_.Exception.Message
                    break
                }
            }
            elseif ($ChangeProfile) {
                try {
                    Get-AccessToken
                }
                catch {
                    Write-Error -Exception $_.Exception.Message
                    break
                }
            }

            # Set the subscription from AzContext
            $SessionVariables.baseUri = "https://management.azure.com/subscriptions/$($SessionVariables.subscriptionId)"
            $SessionVariables.UserAgent = $randomUserAgent

            $script:authHeader = @{
                'Authorization' = 'Bearer ' + [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($($SessionVariables.AccessToken)))
            }

            if ($ResourceTypeName -eq "MSGraph") {
                try {
                    $script:graphToken = Get-AzAccessToken -ResourceTypeName 'MSGraph'
                    $tokenValue = ConvertFrom-AzAccessToken -Token $script:graphToken.Token
                    
                    if ([string]::IsNullOrEmpty($tokenValue)) {
                        throw "Failed to retrieve valid MSGraph token"
                    }
                    $script:graphHeader = @{
                        'Authorization' = 'Bearer ' + $tokenValue
                    }
                }
                catch {
                    if ($_.Exception.Message -like "*User interaction is required*") {
                        Write-Error "Authentication failed for MSGraph. MFA or conditional access policy may be required. Please run 'Connect-AzAccount -AuthScope MicrosoftGraphEndpointResourceId'"
                    }
                    else {
                        Write-Error $_.Exception.Message
                    }
                    break
                }
            }

            if ($ResourceTypeName -eq "KeyVault") {
                try {
                    $script:keyVaultToken = Get-AzAccessToken -ResourceTypeName 'KeyVault'
                    $tokenValue = ConvertFrom-AzAccessToken -Token $script:keyVaultToken.Token
                    
                    if ([string]::IsNullOrEmpty($tokenValue)) {
                        throw "Failed to retrieve valid KeyVault token"
                    }
                    $script:keyVaultHeader = @{
                        'Authorization' = 'Bearer ' + $tokenValue
                    }
                }
                catch {
                    if ($_.Exception.Message -like "*User interaction is required*") {
                        Write-Error "Authentication failed for KeyVault. MFA or conditional access policy may be required. Please run 'Connect-AzAccount -AuthScope KeyVaultEndpointResourceId'"
                    }
                    else {
                        Write-Error $_.Exception.Message
                    }
                    break
                }
            }
        }
        else {
            Write-Message -FunctionName $MyInvocation.MyCommand.Name "Run Connect-AzAccount -UseDeviceAuthentication to login" -Severity 'Error'
            break
        }
    }
    catch {
        Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message "Please run Connect-AzAccount" -Severity 'Error'
    }
    <#
    .SYNOPSIS
        Invokes the BlackCat function to manage Azure resources.

    .DESCRIPTION
        The Invoke-BlackCat function is used to manage Azure resources by obtaining access tokens and setting the appropriate headers for API requests. It supports different resource types such as MSGraph and KeyVault.

    .PARAMETER FunctionName
        The name of the function to be invoked. This parameter is mandatory and accepts pipeline input.

    .PARAMETER ResourceTypeName
        The type of resource for which the access token is required. This parameter is optional and does not accept pipeline input. Supported values are "MSGraph" and "KeyVault".

    .PARAMETER ChangeProfile
        A switch parameter that indicates whether to change the Azure profile. If specified, a new access token will be requested.

    .DEPENDENCIES
        - Az.Accounts module version 3.0.0 or higher.
        - PowerShell version 7.0 or higher.

    .EXAMPLE
        ```powershell
        # Example 1: Invoke the BlackCat function for a specific function name
        Invoke-BlackCat -FunctionName "MyFunction"

        # Example 2: Invoke the BlackCat function for a specific function name and resource type
        Invoke-BlackCat -FunctionName "MyFunction" -ResourceTypeName "MSGraph"

        # Example 3: Invoke the BlackCat function and change the Azure profile
        Invoke-BlackCat -FunctionName "MyFunction" -ChangeProfile
        ```

    .NOTES
        Ensure that you are logged in to Azure using Connect-AzAccount before invoking this function.
#>
}