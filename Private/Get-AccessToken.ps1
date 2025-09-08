#requires -module @{ModuleName = 'Az.Accounts'; ModuleVersion = '2.10.0'}
#requires -version 6.2

function Get-AccessToken {
    [CmdletBinding()]
    param (
    )

    try {
        $azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile

        Write-Verbose "Current Subscription: $($azProfile.DefaultContext.Subscription.Name) in tenant $($azProfile.DefaultContext.Tenant.Id)"

        $script:SessionVariables.subscriptionId = $azProfile.DefaultContext.Subscription.Id
        $script:SessionVariables.tenantId = $azProfile.DefaultContext.Tenant.Id

        $profileClient = [Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient]::new($azProfile)

        try {
            $script:SessionVariables.accessToken = ([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(($profileClient.AcquireAccessToken($script:SessionVariables.tenantId)).accessToken)))
            $script:SessionVariables.ExpiresOn = ($profileClient.AcquireAccessToken($script:SessionVariables.tenantId)).ExpiresOn.DateTime
            Write-Verbose "Access Token expires on: $($script:SessionVariables.ExpiresOn)"
        }
        catch {
            Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message 'Run Connect-AzAccount to login' -Severity 'Error'
            break
        }
    }
    catch {
        Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message 'An error has occured requesting the Access Token' -Severity 'Error'
        break
    }
    <#
    .SYNOPSIS
    Get an Access Token

    .DESCRIPTION
    This function is used to get an access token for the Microsoft Azure API. It retrieves the current Azure profile and acquires an access token for the specified tenant.

    .PARAMETERS
    This function does not take any parameters.

    .EXAMPLE
    Get-AccessToken
    This example retrieves an access token for the current Azure profile.

    .NOTES
    NAME: Get-AccessToken
    AUTHOR: Rogier Dijkman
    REQUIRES: Az.Accounts module version 2.10.0 or higher
    REQUIRES: PowerShell version 6.2 or higher

    .DEPENDENCIES
    - Az.Accounts module version 2.10.0 or higher
    - Microsoft.Azure.Commands.Common.Authentication.Abstractions
    - Microsoft.Azure.Commands.ResourceManager.Common

    .OUTPUTS
    - Base64 encoded access token
    - Expiration date and time of the access token

    #>
}
