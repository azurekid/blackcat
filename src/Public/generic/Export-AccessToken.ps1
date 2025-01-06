function Export-AccessToken {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [array]$ResourceTypeNames = @("MSGraph", "ResourceManager", "KeyVault", "Storage", "Synapse", "OperationalInsights", "Batch"),

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputFile = "AccessTokens.txt"
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
                    $accessToken = Get-AzAccessToken -ResourceTypeName $resourceTypeName
                    $tokenContent = ConvertFrom-JWT -Base64JWT $accessToken

                    $tokenObject = [PSCustomObject]@{
                        Resource = $resourceTypeName
                        UPN      = $tokenContent.UPN
                        Audience = $tokenContent.Audience
                        Roles    = $tokenContent.Roles
                        Tenant   = $tokenContent.Tenant
                        Token    = $accessToken
                    }
                    $tokens += $tokenObject
                }
                catch {
                    Write-Error "Failed to get access token for resource type $resourceTypeName : $($_.Exception.Message)"
                }
            }

            Write-Verbose "Exporting tokens to file $OutputFile"
            $tokens | Out-File -FilePath $OutputFile
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
        This function exports access tokens for specified resource types to a text file.

    .DESCRIPTION
        The Export-AccessToken function requests access tokens for the specified resource types and exports them to a text file. It handles errors and logs messages accordingly.

    .PARAMETER ResourceTypeNames
        The ResourceTypeNames parameter is an optional array of strings that specifies the resource types for which to request access tokens. Default values are "MSGraph", "ResourceManager", "KeyVault", "Storage", "Synapse", "OperationalInsights", and "Batch".

    .PARAMETER OutputFile
        The OutputFile parameter is an optional string that specifies the path to the file where the tokens will be exported. The default value is "AccessTokens.txt".

    .EXAMPLE
        ```powershell
        Export-AccessToken -ResourceTypeNames @("MSGraph", "ResourceManager") -OutputFile "AccessTokens.txt"
        ```
        This example calls the Export-AccessToken function with specified resource types and output file.

    .EXAMPLE
        ```powershell
        Export-AccessToken -OutputFile "AccessTokens.txt"
        ```
        This example calls the Export-AccessToken function with the default resource types and a specified output file.

    .LINK
        For more information, see the related documentation or contact support.
    #>
}
