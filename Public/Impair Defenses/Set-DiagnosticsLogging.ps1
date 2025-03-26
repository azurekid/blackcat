function Set-DiagnosticsLogging {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceId,

        [Parameter(Mandatory = $false)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $false)]
        [array]$SavedSettings,

        [Parameter(Mandatory = $false)]
        [switch]$Enable
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {
        try {
            $baseUri = "https://management.azure.com"
            $apiVersion = "2021-05-01-preview"
            # Determine the resource type from the ResourceId
            $resourceType = ($ResourceId -split '/')[($ResourceId -split '/').IndexOf('providers') + 1]
            Write-Verbose "Determined resource type: $resourceType"

            if (-not $Enable) {

                # Get the current diagnostic settings
                Write-Verbose "Fetching current diagnostics settings for resource: $ResourceId"
                $uri = '{0}{1}/providers/microsoft.insights/diagnosticSettings?api-version={2}' -f $baseUri, $ResourceId, $apiVersion
                
                $requestParam = @{
                    Headers = $script:authHeader
                    Uri     = $uri
                    Method  = 'GET'
                }

                $currentSettings = Invoke-RestMethod @requestParam
            
                # Save the current settings to a variable
                $savedSettings = $currentSettings.value
                Write-Verbose "Saved current diagnostics settings"
            
                # Disable diagnostics logging by removing the settings
                Write-Verbose "Disabling diagnostics logging for resource: $ResourceId"
                foreach ($setting in $savedSettings) {
                    $uri = '{0}{1}/providers/microsoft.insights/diagnosticSettings/{3}?api-version={2}' -f $baseUri, $ResourceId, $apiVersion, $setting.name
                    
                    $requestParam = @{
                        Headers = $script:authHeader
                        Uri     = "$uri"
                        Method  = 'DELETE'
                    }

                    Invoke-RestMethod @requestParam
                }

                Write-Verbose "Diagnostics logging disabled for resource: $ResourceId"
                return $savedSettings
            }
            else {
                # Re-enable diagnostics logging using the saved settings
                Write-Verbose "Re-enabling diagnostics logging for resource: $ResourceId"
                foreach ($setting in $SavedSettings | Where-Object { $null -ne $_.id }) {
                    $uri = '{0}{1}/providers/microsoft.insights/diagnosticSettings/{3}?api-version={2}' -f $baseUri, $ResourceId, $apiVersion, $setting.name
                    
                    $body = @{ properties = $setting.properties } | ConvertTo-Json -Depth 10 -Compress
                    $requestParam = @{
                        Headers     = $script:authHeader
                        Uri         = $uri
                        Method      = 'PUT'
                        ContentType = 'application/json'
                        Body        = $body
                    }
                    
                    Invoke-RestMethod @requestParam
                }

                Write-Verbose "Diagnostics logging re-enabled for resource: $ResourceId"
            }
        }
        catch {
            Write-Error "An error occurred: $($_.Exception.Message)"
        }
    }

    end {
        Write-Verbose "Function $($MyInvocation.MyCommand.Name) completed"
    }
}