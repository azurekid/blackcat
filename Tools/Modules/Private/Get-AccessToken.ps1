#requires -module @{ModuleName = 'Az.Accounts'; ModuleVersion = '2.10.0'}
#requires -version 6.2

function Get-AccessToken {
    <#
    .SYNOPSIS
    Get an Access Token
    .DESCRIPTION
    This function is used to get an access token for the Microsoft Azure API
    .EXAMPLE
    Get-AuthToken
    .NOTES
    NAME: Get-AccessToken
    #>

    [CmdletBinding()]
    param (
    )

    try {
        $azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile

        Write-Verbose "Current Subscription: $($azProfile.DefaultContext.Subscription.Name) in tenant $($azProfile.DefaultContext.Tenant.Id)"

        $SessionVariables.subscriptionId = $azProfile.DefaultContext.Subscription.Id
        $SessionVariables.tenantId = $azProfile.DefaultContext.Tenant.Id

        $profileClient = [Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient]::new($azProfile)

        try {
            $SessionVariables.accessToken = ([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(($profileClient.AcquireAccessToken($SessionVariables.tenantId)).accessToken)))
            $SessionVariables.ExpiresOn = ($profileClient.AcquireAccessToken($SessionVariables.tenantId)).ExpiresOn.DateTime
            Write-Verbose "Access Token expires on: $($SessionVariables.ExpiresOn)"
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
}
