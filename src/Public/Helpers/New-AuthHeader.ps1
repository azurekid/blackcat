function New-AuthHeader {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('MSGraph', 'KeyVault', 'Azure', 'LogAnalytics')]
        [string]$EndpointType
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"

        # Define endpoint resource URLs
        $endpoints = @{
            MSGraph      = 'https://graph.microsoft.com'
            KeyVault     = 'https://vault.azure.net'
            Azure        = 'https://management.azure.com'
            LogAnalytics = 'https://api.loganalytics.io'
        }
    }

    process {
        try {
            # Get the access token for the specified endpoint
            $context = Get-AzContext
            if (-not $context) {
                throw "No Azure context found. Please run Connect-AzAccount first."
            }

            $token = Get-AzAccessToken -ResourceUrl $endpoints[$EndpointType]

            # Create and return the authentication header
            $authHeader = @{
                'Authorization' = "Bearer $($token.Token)"
                'Content-Type'  = 'application/json'
            }

            return $authHeader
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }

    <#
    .SYNOPSIS
        Creates an authentication header for Azure REST API calls.

    .DESCRIPTION
        Creates an authentication header using the current Azure context for different Azure endpoints
        including Microsoft Graph, Key Vault, and Azure Management API.

    .PARAMETER EndpointType
        The type of endpoint to authenticate against. Valid values are 'MSGraph', 'KeyVault', 'Azure', 'LogAnalytics'.

    .EXAMPLE
        Create-AuthHeader -EndpointType 'MSGraph'
        Creates an authentication header for Microsoft Graph API calls.

    .EXAMPLE
        Create-AuthHeader -EndpointType 'KeyVault'
        Creates an authentication header for Key Vault API calls.

    .NOTES
        Author: Rogier Dijkman
        Requires: Az.Accounts module
    #>
}
