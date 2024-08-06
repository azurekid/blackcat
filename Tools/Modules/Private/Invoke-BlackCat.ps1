#requires -module @{ModuleName = 'Az.Accounts'; ModuleVersion = '2.10.0'}
#requires -version 6.2

function Invoke-BlackCat {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$FunctionName,

        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [string]$ResourceTypeName
    )

    Write-Verbose "Function Name: $($FunctionName)"
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

        if ($ResourceTypeName) {
            Write-Verbose "ResourceTypeName: $ResourceTypeName"
            $script:graphToken = Get-AzAccessToken -ResourceTypeName 'MSGraph'
        }
    }
    else {
        Write-Message -FunctionName $MyInvocation.MyCommand.Name "Run Connect-AzAccount to login" -Severity 'Error'
        break
    }
}