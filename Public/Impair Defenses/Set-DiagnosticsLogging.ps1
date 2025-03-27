function Set-DiagnosticsLogging {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceId,

        [Parameter(Mandatory = $false)]
        [array]$SavedSettings,

        [Parameter(Mandatory = $false)]
        [bool]$Disable
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

            if (-not $Disable) {

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
                foreach ($setting in $savedSettings) {
                    $uri = '{0}{1}/providers/microsoft.insights/diagnosticSettings/{3}?api-version={2}' -f $baseUri, $ResourceId, $apiVersion, $setting.name
                    
                    $requestParam = @{
                        Headers = $script:authHeader
                        Uri     = "$uri"
                        Method  = 'DELETE'
                    }

                    Invoke-RestMethod @requestParam
                }
            }
        }
        catch {
            Write-Error "An error occurred: $($_.Exception.Message)"
        }
    }

    end {
        Write-Verbose "Function $($MyInvocation.MyCommand.Name) completed"
    }
<#
.SYNOPSIS
Configures or disables diagnostics logging for a specified Azure resource.

.DESCRIPTION
The Set-DiagnosticsLogging function allows you to enable or disable diagnostics logging for a specified Azure resource. 
If diagnostics logging is being disabled, the current settings are saved before being removed.

.PARAMETER ResourceId
The Resource ID of the Azure resource for which diagnostics logging is being configured. This parameter is mandatory.

.PARAMETER SavedSettings
An optional parameter to store the current diagnostics settings before disabling them. This parameter is used when disabling diagnostics logging.

.PARAMETER Disable
A boolean flag indicating whether to enable or disable diagnostics logging. If set to $true, diagnostics logging will be disabled.

.EXAMPLE
Set-DiagnosticsLogging -ResourceId "/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/{resourceProvider}/{resourceType}/{resourceName}" -Enable $false

Disables diagnostics logging for the specified Azure resource and saves the current settings.

.EXAMPLE
Set-DiagnosticsLogging -ResourceId "/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/{resourceProvider}/{resourceType}/{resourceName}" -Enable $true

Enables diagnostics logging for the specified Azure resource.

.NOTES
- This function uses Azure REST API to manage diagnostics settings.
- Ensure that the $script:authHeader variable is properly configured with the required authentication header before using this function.

#>
}