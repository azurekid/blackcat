function Get-FederatedIdentityCredential {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias('identity-name', 'user-assigned-identity')]
        [string]$Name,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias('resource-id', 'Id')]
        [string]$ResourceId,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Object", "JSON", "CSV", "Table")]
        [Alias("output", "o")]
        [string]$OutputFormat = "Table"
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {
        try {
            $results = @()
            $managedIdentities = @()

            # Determine which managed identities to query
            if ($ResourceId) {
                Write-Host "Using provided Resource ID..." -ForegroundColor Cyan
                $managedIdentities += [PSCustomObject]@{
                    id   = $ResourceId
                    name = ($ResourceId -split '/')[-1]
                }
            }
            elseif ($Name) {
                Write-Host "Looking up Managed Identity: $Name..." -ForegroundColor Cyan
                $uami = Get-ManagedIdentity -Name $Name
                if ($uami) {
                    $managedIdentities += $uami
                    Write-Host "    Found managed identity" -ForegroundColor Green
                }
                else {
                    Write-Host "    Managed identity not found: $Name" -ForegroundColor Red
                    return
                }
            }
            else {
                Write-Host "🔍 Retrieving all User Assigned Managed Identities..." -ForegroundColor Cyan
                $managedIdentities = Get-ManagedIdentity
                Write-Host "    Found $($managedIdentities.Count) managed identities" -ForegroundColor Green
            }

            $totalFics = 0

            foreach ($uami in $managedIdentities) {
                Write-Verbose "Querying federated credentials for: $($uami.name)"
                
                $ficUrl = "https://management.azure.com$($uami.id)/federatedIdentityCredentials?api-version=2023-01-31"
                
                try {
                    $fics = Invoke-RestMethod -Uri $ficUrl -Headers $script:authHeader -Method GET
                    
                    if ($fics.value -and $fics.value.Count -gt 0) {
                        $totalFics += $fics.value.Count
                        
                        foreach ($fic in $fics.value) {
                            $enhancedFic = [PSCustomObject]@{
                                'Name'    = $uami.name
                                'Credential Name'  = $fic.name
                                'Subject'          = $fic.properties.subject
                                'Issuer'           = $fic.properties.issuer
                                'Audiences'        = ($fic.properties.audiences -join ', ')
                                'ResourceGroup'    = ($uami.id -split '/')[4]
                                'ResourceId'       = $uami.id
                            }
                            $results += $enhancedFic
                        }
                    }
                }
                catch {
                    Write-Verbose "Could not retrieve federated credentials for $($uami.name): $($_.Exception.Message)"
                }
            }

            if ($results.Count -gt 0) {
                Write-Host "`nFederated Identity Credential Summary:" -ForegroundColor Magenta
                Write-Host "   Managed Identities Scanned: $($managedIdentities.Count)" -ForegroundColor White
                Write-Host "   Total Federated Credentials: $totalFics" -ForegroundColor Yellow

                # Group by issuer for summary
                $issuerCounts = $results | Group-Object 'Issuer' | Sort-Object Count -Descending
                Write-Host "   Issuers:" -ForegroundColor Cyan
                foreach ($group in $issuerCounts) {
                    $issuerName = $group.Name
                    if ($issuerName -eq 'https://token.actions.githubusercontent.com') {
                        $issuerName = "GitHub Actions"
                    }
                    elseif ($issuerName -match 'sts\.windows\.net') {
                        $issuerName = "Azure AD"
                    }
                    elseif ($issuerName -match 'login\.microsoftonline\.com') {
                        $issuerName = "Microsoft Identity Platform"
                    }
                    Write-Host "     $($issuerName): $($group.Count)" -ForegroundColor White
                }

                # Highlight potential security concerns
                $githubFics = $results | Where-Object { $_.Issuer -eq 'https://token.actions.githubusercontent.com' }
                if ($githubFics.Count -gt 0) {
                    Write-Host "`n   GitHub Actions Trust Relationships:" -ForegroundColor Yellow
                    foreach ($ghFic in $githubFics) {
                        Write-Host "     • $($ghFic.'Identity Name'): $($ghFic.Subject)" -ForegroundColor White
                    }
                }
            }
            else {
                Write-Host "`nNo federated identity credentials found" -ForegroundColor Red
            }

            # Format and return results
            Format-BlackCatOutput -Data $results -OutputFormat $OutputFormat -FunctionName $MyInvocation.MyCommand.Name
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "$($_.Exception.Message)" -Severity 'Error'
        }
    }

    <#
    .SYNOPSIS
        Retrieves federated identity credentials configured on Azure User Assigned Managed Identities.

    .DESCRIPTION
        The `Get-FederatedIdentityCredential` function queries Azure Resource Manager to retrieve
        federated identity credentials (FICs) configured on User Assigned Managed Identities (UAMIs).
        
        Federated identity credentials establish trust relationships between managed identities and
        external identity providers like GitHub Actions, enabling workload identity federation without
        storing secrets.

        This function is valuable for security assessments to identify:
        - Which managed identities have external trust relationships
        - What GitHub repositories or other OIDC providers can authenticate as the managed identity
        - Potential attack paths via federated credential abuse

    .PARAMETER Name
        The name of a specific User Assigned Managed Identity to query.
        If not specified, all UAMIs in accessible subscriptions are queried.
        Aliases: identity-name, user-assigned-identity, Name

    .PARAMETER ResourceId
        The full Azure Resource ID of the managed identity.
        Aliases: resource-id, Id

    .PARAMETER OutputFormat
        Specifies the output format. Valid values are: Object, JSON, CSV, Table.
        Default: Table
        Aliases: output, o

    .EXAMPLE
        Get-FederatedIdentityCredential

        Retrieves all federated identity credentials from all accessible managed identities.

    .EXAMPLE
        Get-FederatedIdentityCredential -Name "uami-hr-cicd-automation"

        Retrieves federated credentials for a specific managed identity by name.

    .EXAMPLE
        Get-ManagedIdentity | Get-FederatedIdentityCredential

        Pipes managed identities to retrieve their federated credentials.

    .EXAMPLE
        Get-FederatedIdentityCredential -OutputFormat JSON

        Returns results in JSON format for further processing or export.

    .NOTES
        Author: Rogier Dijkman
        
        Security Note: Federated identity credentials can be abused by attackers who have
        Contributor access to a managed identity. They can add their own GitHub repository
        as a trusted issuer, then exchange GitHub OIDC tokens for Azure access tokens.
    #>
}
