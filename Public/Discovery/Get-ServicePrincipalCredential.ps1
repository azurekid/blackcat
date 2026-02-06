function Get-ServicePrincipalCredential {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [Alias('Id', 'object-id', 'application-id')]
        [string]$ObjectId,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Password', 'Certificate', 'All')]
        [string]$CredentialType = 'All',

        [Parameter(Mandatory = $false)]
        [switch]$UseApplicationEndpoint,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeExpired
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
    }

    process {
        try {
            # Determine if we're working with an Application or Service Principal
            $entityType = if ($UseApplicationEndpoint) { "applications" } else { "servicePrincipals" }
            
            Write-Verbose "Retrieving credentials for $entityType with ObjectId: $ObjectId"
            $entity = Invoke-MsGraph -relativeUrl "$entityType/$ObjectId" -NoBatch
            
            if (-not $entity) {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "$entityType with ObjectId '$ObjectId' not found." -Severity 'Error'
                return
            }

            Write-Verbose "Found ${entityType}: $($entity.displayName)"
            
            $credentials = @()
            $currentDateTime = Get-Date

            # Process password credentials
            if ($CredentialType -eq 'All' -or $CredentialType -eq 'Password') {
                if ($entity.passwordCredentials) {
                    foreach ($passwordCred in $entity.passwordCredentials) {
                        $endDateTime = [DateTime]::Parse($passwordCred.endDateTime)
                        $isExpired = $endDateTime -lt $currentDateTime
                        
                        if ($IncludeExpired -or -not $isExpired) {
                            $credentialObject = [PSCustomObject]@{
                                EntityType = $entityType
                                EntityDisplayName = $entity.displayName
                                EntityId = $entity.id
                                CredentialType = 'Password'
                                KeyId = $passwordCred.keyId
                                DisplayName = $passwordCred.displayName
                                StartDateTime = if ($passwordCred.startDateTime) { [DateTime]::Parse($passwordCred.startDateTime) } else { $null }
                                EndDateTime = $endDateTime
                                IsExpired = $isExpired
                                DaysUntilExpiry = if (-not $isExpired) { ($endDateTime - $currentDateTime).Days } else { $null }
                                Hint = $passwordCred.hint
                                SecretText = if ($passwordCred.secretText) { "[REDACTED - Available in response]" } else { $null }
                            }
                            $credentials += $credentialObject
                        }
                    }
                }
            }

            # Process key/certificate credentials
            if ($CredentialType -eq 'All' -or $CredentialType -eq 'Certificate') {
                if ($entity.keyCredentials) {
                    foreach ($keyCred in $entity.keyCredentials) {
                        $endDateTime = [DateTime]::Parse($keyCred.endDateTime)
                        $isExpired = $endDateTime -lt $currentDateTime
                        
                        if ($IncludeExpired -or -not $isExpired) {
                            $credentialObject = [PSCustomObject]@{
                                EntityType = $entityType
                                EntityDisplayName = $entity.displayName
                                EntityId = $entity.id
                                CredentialType = 'Certificate'
                                KeyId = $keyCred.keyId
                                DisplayName = $keyCred.displayName
                                StartDateTime = if ($keyCred.startDateTime) { [DateTime]::Parse($keyCred.startDateTime) } else { $null }
                                EndDateTime = $endDateTime
                                IsExpired = $isExpired
                                DaysUntilExpiry = if (-not $isExpired) { ($endDateTime - $currentDateTime).Days } else { $null }
                                Type = $keyCred.type
                                Usage = $keyCred.usage
                                CustomKeyIdentifier = $keyCred.customKeyIdentifier
                                Thumbprint = if ($keyCred.customKeyIdentifier) { 
                                    [System.BitConverter]::ToString([System.Convert]::FromBase64String($keyCred.customKeyIdentifier)).Replace('-', '').ToLower()
                                } else { $null }
                            }
                            $credentials += $credentialObject
                        }
                    }
                }
            }

            if ($credentials.Count -eq 0) {
                $filterText = if ($IncludeExpired) { "" } else { "non-expired " }
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "No $filterText$($CredentialType.ToLower()) credentials found for $entityType '$($entity.displayName)'" -Severity 'Information'
            } else {
                Write-Verbose "Found $($credentials.Count) credentials for $entityType '$($entity.displayName)'"
            }

            return $credentials | Sort-Object CredentialType, EndDateTime
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }

    end {
        Write-Verbose "Completed function $($MyInvocation.MyCommand.Name)"
    }

<#
.SYNOPSIS
Retrieves credentials (passwords and certificates) for Microsoft Entra applications and service principals.

.DESCRIPTION
Retrieves credential information for Entra applications and service principals with expiry details.

.PARAMETER ObjectId
The Object ID (GUID) of the Microsoft Entra application or service principal. This parameter is mandatory and must match the pattern of a valid GUID.

.PARAMETER CredentialType
Specifies the type of credentials to retrieve. Valid values are:
- All: Retrieves both password and certificate credentials (default)
- Password: Retrieves only password credentials
- Certificate: Retrieves only certificate credentials

.PARAMETER UseApplicationEndpoint
When specified, uses the applications endpoint instead of servicePrincipals endpoint. Use this when working with application registrations directly.

.PARAMETER IncludeExpired
When specified, includes expired credentials in the results. By default, only active (non-expired) credentials are returned.

.OUTPUTS
Returns an array of PSCustomObjects containing credential information with the following properties:
- EntityType: The type of entity (applications or servicePrincipals)
- EntityDisplayName: The display name of the entity
- EntityId: The ID of the entity
- CredentialType: Type of credential (Password or Certificate)
- KeyId: Unique identifier for the credential
- DisplayName: Display name of the credential
- StartDateTime: When the credential becomes valid
- EndDateTime: When the credential expires
- IsExpired: Boolean indicating if the credential is expired
- DaysUntilExpiry: Number of days until expiration (null if expired)
- Additional properties specific to credential type

.EXAMPLE
Get-ServicePrincipalCredential -ObjectId "12345678-1234-1234-1234-123456789012"

Retrieves all active credentials for the specified service principal.

.EXAMPLE
Get-ServicePrincipalCredential -ObjectId "12345678-1234-1234-1234-123456789012" -CredentialType Password

Retrieves only password credentials for the specified service principal.

.EXAMPLE
Get-ServicePrincipalCredential -ObjectId "12345678-1234-1234-1234-123456789012" -IncludeExpired

Retrieves all credentials including expired ones for the specified service principal.

.EXAMPLE
Get-ServicePrincipalCredential -ObjectId "12345678-1234-1234-1234-123456789012" -UseApplicationEndpoint

Retrieves credentials using the applications endpoint instead of servicePrincipals endpoint.

.EXAMPLE
Get-ServicePrincipalCredential -ObjectId "12345678-1234-1234-1234-123456789012" | Where-Object { $_.DaysUntilExpiry -lt 30 }

Retrieves credentials that will expire within the next 30 days.

.NOTES
- This function requires authentication to the Microsoft Graph API with appropriate permissions
- Required permissions: Application.Read.All, Application.ReadWrite.All, or Directory.Read.All
- The function works with both applications and servicePrincipals endpoints
- Secret text values are redacted in the output for security
- Certificate thumbprints are calculated from the customKeyIdentifier when available

.LINK
https://learn.microsoft.com/en-us/graph/api/application-get
https://learn.microsoft.com/en-us/graph/api/serviceprincipal-get

.LINK
MITRE ATT&CK Tactic: TA0007 - Discovery
https://attack.mitre.org/tactics/TA0007/

.LINK
MITRE ATT&CK Technique: T1087.004 - Account Discovery: Cloud Account
https://attack.mitre.org/techniques/T1087/004/

#>
}
