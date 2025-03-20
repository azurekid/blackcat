function Get-AccessTokens {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
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
                        Token    = $accessToken
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
    This function exports access tokens for specified resource types to a JSON file.

.DESCRIPTION
    The Export-AccessToken function requests access tokens for the specified resource types and exports them to a JSON file. It handles errors and logs messages accordingly.

.PARAMETER ResourceTypeNames
    The ResourceTypeNames parameter is an optional array of strings that specifies the resource types for which to request access tokens. Default values are "MSGraph", "ResourceManager", "KeyVault", "Storage", "Synapse", "OperationalInsights", and "Batch".

.PARAMETER OutputFile
    The OutputFile parameter is an optional string that specifies the path to the file where the tokens will be exported. The default value is "AccessTokens.json".

.EXAMPLE
    Export-AccessToken -ResourceTypeNames @("MSGraph", "ResourceManager") -OutputFile "AccessTokens.json"
    This example calls the Export-AccessToken function with specified resource types and output file.

.EXAMPLE
    Export-AccessToken -OutputFile "AccessTokens.json"
    This example calls the Export-AccessToken function with the default resource types and a specified output file.

.EXAMPLE
    $tokens = Get-Content -Path "AccessTokens.json" -Raw | ConvertFrom-Json
    This example shows how to read the exported JSON file back into a PowerShell object for further use.

.LINK
    For more information, see the related documentation or contact support.
#>
}
