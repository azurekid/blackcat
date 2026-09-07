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

            function ConvertTo-KqlStringLiteral {
                param ([string]$Value)
                return "'$($Value.Replace("'", "''"))'"
            }

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
                $uami = Get-ManagedIdentity -Name $Name -OutputFormat Object
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
                Write-Host " Retrieving all User Assigned Managed Identities..." -ForegroundColor Cyan
                $managedIdentities = Get-ManagedIdentity -OutputFormat Object
                Write-Host "    Found $($managedIdentities.Count) managed identities" -ForegroundColor Green
            }

            $totalFics = 0

            $ficQueryParts = @(
                'resources'
                "| where type =~ 'microsoft.managedidentity/userassignedidentities/federatedidentitycredentials'"
                "| extend ParentResourceId = tostring(split(tolower(id), '/federatedidentitycredentials/')[0])"
            )

            if ($managedIdentities.Count -gt 0) {
                $parentIds = ($managedIdentities | ForEach-Object { ConvertTo-KqlStringLiteral -Value $_.id.ToLower() }) -join ', '
                $ficQueryParts += "| where ParentResourceId in~ ($parentIds)"
            }

            $ficQueryParts += @(
                '| extend Subject = tostring(properties.subject), Issuer = tostring(properties.issuer), Audiences = properties.audiences'
                '| project id, name, ParentResourceId, Subject, Issuer, Audiences, resourceGroup, subscriptionId'
            )

            $ficQuery = $ficQueryParts -join "`n"
            $ficResources = Invoke-AzBatch -Query $ficQuery -Silent
            if ($null -eq $ficResources) {
                $ficResources = @()
            }

            if ($ficResources.Count -gt 0) {
                $identityNameById = @{}
                foreach ($uami in $managedIdentities) {
                    $identityNameById[$uami.id.ToLower()] = $uami.name
                }

                foreach ($fic in $ficResources) {
                    $parentId = $fic.ParentResourceId.ToLower()
                    $identityName = $identityNameById[$parentId]
                    if (-not $identityName) {
                        $identityName = ($parentId -split '/')[-1]
                    }

                    $audiences = if ($fic.Audiences -is [array]) {
                        $fic.Audiences -join ', '
                    }
                    elseif ($fic.Audiences) {
                        [string]$fic.Audiences
                    }
                    else {
                        ''
                    }

                    $results += [PSCustomObject]@{
                        'Name'             = $identityName
                        'Identity Name'    = $identityName
                        'Credential Name'  = $fic.name
                        'Subject'          = $fic.Subject
                        'Issuer'           = $fic.Issuer
                        'Audiences'        = $audiences
                        'ResourceGroup'    = $fic.resourceGroup
                        'ResourceId'       = $parentId
                    }
                }

                $totalFics = $results.Count
            }

            foreach ($uami in $managedIdentities) {
                if ($ficResources.Count -gt 0) {
                    continue
                }

                Write-Verbose "Querying federated credentials for: $($uami.name)"
                
                $ficUrl = "https://management.azure.com$($uami.id)/federatedIdentityCredentials?api-version=2023-01-31"
                
                try {
                    $fics = Invoke-RestMethod -Uri $ficUrl -Headers $script:authHeader -Method GET
                    
                    if ($fics.value -and $fics.value.Count -gt 0) {
                        $totalFics += $fics.value.Count
                        
                        foreach ($fic in $fics.value) {
                            $enhancedFic = [PSCustomObject]@{
                                'Name'             = $uami.name
                                'Identity Name'    = $uami.name
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
        Retrieves federated identity credentials on managed identities.

    .DESCRIPTION
Retrieves federated identity credentials on managed identities via Azure Resource Manager. These credentials enable workloads running outside Azure to obtain access tokens without storing secrets.
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

    .LINK
        MITRE ATT&CK Tactic: TA0007 - Discovery
        https://attack.mitre.org/tactics/TA0007/

    .LINK
        MITRE ATT&CK Technique: T1526 - Cloud Service Discovery
        https://attack.mitre.org/techniques/T1526/
    #>
}
