function Get-AccessTokens {
    [cmdletbinding()]
    [OutputType([string])] # Declares that the function can return a string
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("MSGraph", "ResourceManager", "KeyVault", "Storage", "Synapse", "OperationalInsights", "Batch", IgnoreCase = $true)]
        [array]$ResourceTypeNames = @("MSGraph", "ResourceManager", "KeyVault", "Storage", "Synapse", "OperationalInsights", "Batch"),

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputFile = "accesstokens.json",

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [switch]$Publish
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
    }

    process {
        try {
            Write-Verbose "Requesting access tokens for specified audiences"
            $tokens = @()

            foreach ($resourceTypeName in $ResourceTypeNames) {
                try {
                    $accessToken = (Get-AzAccessToken -ResourceTypeName $resourceTypeName -AsSecureString)
                    $tokenContent = ConvertFrom-JWT -Base64JWT ($accessToken.token | ConvertFrom-SecureString -AsPlainText)

                    $tokenObject = [PSCustomObject]@{
                        Resource = $resourceTypeName
                        UPN      = $tokenContent.UPN
                        Audience = $tokenContent.Audience
                        Roles    = $tokenContent.Roles
                        Scope    = $tokenContent.Scope
                        Tenant   = $tokenContent.'Tenant ID'
                        Token    = ($accessToken.token | ConvertFrom-SecureString -AsPlainText)
                    }
                    $tokens += $tokenObject
                }
                catch {
                    Write-Error "Failed to get access token for resource type $resourceTypeName : $($_.Exception.Message)"
                }
            }

            if ($Publish) {
                $requestParam = @{
                    Uri         = 'https://us.onetimesecret.com/api/v1/share'
                    Method      = 'POST'
                    Body        = @{
                        secret = $tokens | ConvertTo-Json -Depth 10
                        ttl    = 3600
                    }
                }

                $response = Invoke-RestMethod @requestParam
                return "https://us.onetimesecret.com/secret/$($response.secret_key)"

            } else {
                Write-Verbose "Exporting tokens to file $OutputFile"
                $tokens | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputFile
            }
        }
        catch {
            Write-Error "An error occurred in function $($MyInvocation.MyCommand.Name): $($_.Exception.Message)"
        }
    }

    end {
        Write-Verbose "Function $($MyInvocation.MyCommand.Name) completed"
    }
    <#
    .SYNOPSIS
        Retrieves and exports access tokens for specified Azure resource types.

    .DESCRIPTION
        The Get-AccessTokens function retrieves access tokens for specified Azure resource types and exports them to a JSON file.
        It supports publishing the tokens to a secure sharing service or saving them locally. The function handles errors gracefully
        and provides verbose logging for better traceability.

    .PARAMETER ResourceTypeNames
        An optional array of strings specifying the Azure resource types for which to request access tokens.
        Supported values are "MSGraph", "ResourceManager", "KeyVault", "Storage", "Synapse", "OperationalInsights", and "Batch".
        The default value includes all supported resource types.

    .PARAMETER OutputFile
        An optional string specifying the path to the file where the tokens will be exported.
        The default value is "accesstokens.json".

    .PARAMETER Publish
        An optional switch parameter. If specified, the tokens will be published to a secure sharing service
        (https://us.onetimesecret.com) instead of being saved to a file. The function will return a URL to access the shared tokens.

    .EXAMPLE
        Get-AccessTokens -ResourceTypeNames @("MSGraph", "ResourceManager") -OutputFile "AccessTokens.json"
        Retrieves access tokens for "MSGraph" and "ResourceManager" resource types and saves them to "AccessTokens.json".

    .EXAMPLE
        Get-AccessTokens -Publish
        Retrieves access tokens for all default resource types and publishes them to a secure sharing service.
        Returns a URL to access the shared tokens.

    .EXAMPLE
        Get-AccessTokens -OutputFile "AccessTokens.json"
        Retrieves access tokens for all default resource types and saves them to "AccessTokens.json".

    .EXAMPLE
        $tokens = Get-Content -Path "AccessTokens.json" -Raw | ConvertFrom-Json
        Reads the exported JSON file back into a PowerShell object for further use.

    .NOTES
        This function requires the Azure PowerShell module to be installed and authenticated.

    .LINK
        For more information, refer to the Azure PowerShell documentation or contact support.
    #>
}
