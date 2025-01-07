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
        } elseif ($ChangeProfile) {
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
        $script:authHeader = @{
            'Authorization' = 'Bearer ' + [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($($SessionVariables.AccessToken)))
        }

        if ($ResourceTypeName -eq "MSGraph") {
            $script:graphToken = Get-AzAccessToken -ResourceTypeName 'MSGraph'
            $script:graphHeader = @{
                'Authorization' = 'Bearer ' + ($script:graphToken).Token
            }
        }

        if ($ResourceTypeName -eq "KeyVault") {
            $script:keyVaultToken = Get-AzAccessToken -ResourceTypeName 'KeyVault'
            $script:keyVaultHeader = @{
                'Authorization' = 'Bearer ' + ($script:keyVaultToken).Token
            }
        }
    }
    else {
        Write-Message -FunctionName $MyInvocation.MyCommand.Name "Run Connect-AzAccount to login" -Severity 'Error'
        break
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