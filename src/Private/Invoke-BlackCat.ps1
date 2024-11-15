#requires -module @{ModuleName = 'Az.Accounts'; ModuleVersion = '3.0.0'}
#requires -version 7.0

function Invoke-BlackCat {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$FunctionName,

        [Parameter(Mandatory = $false, ValueFromPipeline = $false)]
        [string]$ResourceTypeName
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
    }
    else {
        Write-Message -FunctionName $MyInvocation.MyCommand.Name "Run Connect-AzAccount to login" -Severity 'Error'
        break
    }
}