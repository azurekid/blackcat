function Get-ManagedIdentity {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceNameCompleterAttribute(
            "Microsoft.ManagedIdentity/userAssignedIdentities",
            "ResourceGroupName"
        )]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9-]+[A-Za-z0-9]$', ErrorMessage = "It does not match expected pattern '{1}'")]
        [Alias('identity-name', 'user-assigned-identity')]
        [string]$Name,

        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceGroupCompleterAttribute()]
        [Alias('rg', 'resource-group')]
        [string[]]$ResourceGroupName,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Table', 'List', 'Json', 'Object')]
        [string]$OutputFormat = 'Table'
    )

    begin {
        [void] $ResourceGroupName #Only used to trigger the ResourceGroupCompleter

        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {
        try {

            Write-Verbose "Get Managed Identity"

            if ($Name) {
                $results = Invoke-AzBatch -ResourceType 'Microsoft.ManagedIdentity/userAssignedIdentities' -Name $($Name)
            } else {
                $results = Invoke-AzBatch -ResourceType 'Microsoft.ManagedIdentity/userAssignedIdentities'
            }

            # Format output based on OutputFormat parameter
            switch ($OutputFormat) {
                'Object' {
                    return $results
                }
                'Table' {
                    return $results | Select-Object -Property Name, 
                        @{Name='ServicePrincipalId'; Expression={$_.properties.principalId}},
                        @{Name='ResourceGroup'; Expression={$_.id.Split('/')[4]}} |
                        Format-Table -AutoSize
                }
                'List' {
                    return $results | Select-Object -Property Name, 
                        @{Name='ServicePrincipalId'; Expression={$_.properties.principalId}},
                        @{Name='ResourceGroup'; Expression={$_.id.Split('/')[4]}} |
                        Format-List
                }
                'Json' {
                    return $results | ConvertTo-Json -Depth 10
                }
                default {
                    return $results
                }
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
<#
.SYNOPSIS
Retrieves Azure Managed Identities.

.DESCRIPTION
Retrieves user-assigned managed identities from Azure with optional name filtering.

.PARAMETER Name
The name of the managed identity to retrieve. This parameter is optional and can be provided from the pipeline by property name.

.PARAMETER OutputFormat
Specifies the output format for the results. Valid values are 'Table' (default), 'List', or 'Json'.
- Table: Displays results in a formatted table with Name, ServicePrincipalId, and ResourceGroup columns
- List: Displays results in a list format
- Json: Returns the raw JSON response

.EXAMPLE
# Example 1: Retrieve all managed identities
Get-AzManagedIdentity

.EXAMPLE
# Example 2: Retrieve a specific managed identity by name
Get-AzManagedIdentity -Name "myManagedIdentity"

.EXAMPLE
# Example 3: Retrieve all managed identities in JSON format
Get-AzManagedIdentity -OutputFormat Json

.EXAMPLE
# Example 4: Retrieve all managed identities in list format
Get-AzManagedIdentity -OutputFormat List

.DEPENDENCIES
- `Invoke-BlackCat`: This function is invoked at the beginning of the script.
- `Invoke-RestMethod`: This cmdlet is used to make REST API calls to Azure.
- `Write-Message`: This function is used to log error messages.

.NOTES
- The function requires the `Microsoft.ManagedIdentity` provider and the `2023-01-31` API version.

.LINK
MITRE ATT&CK Tactic: TA0007 - Discovery
https://attack.mitre.org/tactics/TA0007/

.LINK
MITRE ATT&CK Technique: T1526 - Cloud Service Discovery
https://attack.mitre.org/techniques/T1526/
#>
}