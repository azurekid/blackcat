function Get-FederatedAppCredential {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias('Id', 'object-id')]
        [ValidatePattern('^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$', ErrorMessage = "It does not match expected pattern '{1}'")]
        [string]$ObjectId,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias('application-id')]
        [ValidatePattern('^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$', ErrorMessage = "It does not match expected pattern '{1}'")]
        [string]$AppId,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Object", "JSON", "CSV", "Table")]
        [Alias("output", "o")]
        [string]$OutputFormat = "Table"
    )

    begin {
        Write-Verbose " Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
    }

    process {

        try {
                $results = @()
                $app = $null

                if ($AppId) {
                    Write-Host " Resolving Application ID to Object ID..." -ForegroundColor Cyan
                    Write-Verbose " Get Application with Application Id $($AppId)"
                    $app = Invoke-MsGraph -relativeUrl "applications(appId='$AppId')" -NoBatch
                    $ObjectId = $app.id
                    Write-Host "     Resolved to application: $($app.displayName)" -ForegroundColor Green
                }
                elseif ($ObjectId) {
                    Write-Host " Retrieving application details..." -ForegroundColor Cyan
                    Write-Verbose " Get Application with Object Id $($ObjectId)"
                    $app = Invoke-MsGraph -relativeUrl "applications/$ObjectId" -NoBatch
                    Write-Host "     Found application: $($app.displayName)" -ForegroundColor Green
                }

                Write-Host " Analyzing federated identity credentials..." -ForegroundColor Yellow
                Write-Verbose " Get Federated Identity Credentials for Application: $($app.displayName)"
                $federatedCreds = Invoke-MsGraph -relativeUrl "applications/$ObjectId/federatedIdentityCredentials"

                if ($federatedCreds -and $federatedCreds.Count -gt 0) {
                    Write-Host "     Found $($federatedCreds.Count) federated credential(s)" -ForegroundColor Green
                    
                    # Enhance output with application context and emojis
                    foreach ($cred in $federatedCreds) {
                        $enhancedCred = [PSCustomObject]@{
                            'App Name' = "$($app.displayName)"
                            'App ID' = $app.appId
                            'Object ID' = $app.id
                            'Credential Name' = "$($cred.name)"
                            'Subject' = $cred.subject
                            'Issuer' = $cred.issuer
                            'Audiences' = $cred.audiences -join ', '
                            'Description' = $cred.description
                        }

                        $results += $enhancedCred
                    }

                    Write-Host "`n Federated Credential Analysis Summary:" -ForegroundColor Magenta
                    Write-Host "   Application: $($app.displayName)" -ForegroundColor White
                    Write-Host "   Total Credentials: $($federatedCreds.Count)" -ForegroundColor Yellow

                    # Group by issuer for summary
                    $issuerCounts = $results | Group-Object 'Issuer' | Sort-Object Count -Descending
                    Write-Host "   Issuers:" -ForegroundColor Cyan
                    foreach ($group in $issuerCounts) {
                        $issuerName = $group.Name
                        if ($issuerName -eq 'https://token.actions.githubusercontent.com') {
                            $issuerName = " GitHub Actions"
                        } elseif ($issuerName -match 'sts\.windows\.net') {
                            $issuerName = " Azure AD"
                        } elseif ($issuerName -match 'login\.microsoftonline\.com') {
                            $issuerName = " Microsoft Identity Platform"
                        }
                        Write-Host "     $($issuerName): $($group.Count)" -ForegroundColor White
                    }
                } else {
                    Write-Host "     No federated identity credentials found" -ForegroundColor Red
                }

                # Format and return results using the standardized output formatter
                Format-BlackCatOutput -Data $results -OutputFormat $OutputFormat -FunctionName $MyInvocation.MyCommand.Name
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message " $($_.Exception.Message)" -Severity 'Error'
        }
    }

<#
.SYNOPSIS
Retrieves federated identity credentials for a specified Microsoft Entra application.

.DESCRIPTION
Retrieves federated identity credentials for Entra applications via Object or App ID.

.PARAMETER ObjectId
The Object ID (GUID) of the Microsoft Entra application. This parameter must match the pattern of a valid GUID (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx).

.PARAMETER AppId
The Application ID (GUID) of the Microsoft Entra application. This parameter must match the pattern of a valid GUID (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx). If provided, it will be resolved to the corresponding Object ID.

.PARAMETER OutputFormat
Specifies the output format for the results. Valid values are:
- Table (default): Displays results in a formatted table
- Object: Returns PowerShell objects
- JSON: Exports results to a timestamped JSON file
- CSV: Exports results to a timestamped CSV file

.EXAMPLE
Get-FederatedAppCredential -ObjectId "12345678-1234-1234-1234-123456789012"
Retrieves all federated identity credentials for the specified application using its Object ID.

.EXAMPLE
Get-FederatedAppCredential -AppId "87654321-4321-4321-4321-210987654321"
Retrieves all federated identity credentials for the specified application using its Application ID.

.EXAMPLE
Get-FederatedAppCredential -ObjectId "12345678-1234-1234-1234-123456789012" -OutputFormat JSON
Retrieves all federated identity credentials for the specified application and exports results to a JSON file.

.EXAMPLE
Get-FederatedAppCredential -AppId "87654321-4321-4321-4321-210987654321" -OutputFormat CSV
Retrieves all federated identity credentials for the specified application and exports results to a CSV file.

.EXAMPLE
Invoke-MsGraph -relativeUrl "applications" | Get-FederatedAppCredential
Retrieves all federated identity credentials for all applications returned by the `Invoke-MsGraph` command.

.EXAMPLE
Get-AzAdApplication -All $true | Get-FederatedAppCredential
Retrieves all federated identity credentials for all applications returned by the `Get-AzAdApplication` command.

.OUTPUTS
PSCustomObject with enhanced properties:
- App Name: Display name of the application (with emoji)
- App ID: Application ID (GUID)
- Object ID: Object ID (GUID)
- Credential Name: Name of the federated credential (with emoji)
- Subject: The subject claim pattern
- Issuer: The token issuer URL
- Audiences: Comma-separated list of audiences
- Description: Credential description

.LINK
https://learn.microsoft.com/en-us/graph/api/application-list-federatedidentitycredentials

.NOTES
This function requires Microsoft Graph permissions to read application configurations:
- Application.Read.All (application permission)
- Application.ReadWrite.All (application permission) 
- Directory.Read.All (application permission)

.LINK
MITRE ATT&CK Tactic: TA0007 - Discovery
https://attack.mitre.org/tactics/TA0007/

.LINK
MITRE ATT&CK Technique: T1526 - Cloud Service Discovery
https://attack.mitre.org/techniques/T1526/
#>
}