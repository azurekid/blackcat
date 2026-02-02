function Set-UserCredential {
    param (
        [Parameter(Mandatory = $false, ParameterSetName = 'ObjectId')]
        [string]$ObjectId,

        [Parameter(Mandatory = $false, ParameterSetName = 'Name')]
        [string]$Name,

        [Parameter(Mandatory = $false, ParameterSetName = 'UserPrincipalName')]
        [ValidatePattern('^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$', ErrorMessage = "The value '{1}' is not a valid UPN format")]
        [string]$UserPrincipalName,

        [Parameter(ParameterSetName = 'ObjectId')]
        [Parameter(ParameterSetName = 'Name')]
        [Parameter(ParameterSetName = 'UserPrincipalName')]

        [Parameter(Mandatory = $false)]
        [securestring]$Password
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'

        $userInfo = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
    }

    process {
        try {
            # Construct query based on parameter set
            switch ($PSCmdlet.ParameterSetName) {
                'ObjectId' {
                        $response = Invoke-MsGraph -relativeUrl "users/$ObjectId" -NoBatch
                }
                'Name' {
                        $response = Invoke-MsGraph -relativeUrl "users?`$filter=startswith(displayName,'$Name') or startswith(userPrincipalName,'$Name')"
                }
                'UserPrincipalName' {
                    $response = Invoke-MsGraph -relativeUrl "users?`$filter=userPrincipalName eq '$UserPrincipalName'"
                }
            }

                # Set password if requested and not a group
                if ($Password) {
                    $patchBody = @{
                        passwordProfile = @{
                            password = ($Password | ConvertFrom-SecureString -AsPlainText)
                            forceChangePasswordNextSignIn = $false
                        }
                    } | ConvertTo-Json -Depth 3

                    $requestParameters = @{
                        Uri             = "$($sessionVariables.graphUri)/users/$($response.id)"
                        Method          = 'PATCH'
                        Headers         = $script:graphHeader
                        Body            = $patchBody
                        ContentType     = 'application/json'
                        UseBasicParsing = $true
                    }

                    Invoke-RestMethod @requestParameters
                } else {
                    Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "No password provided. Skipping password update." -Severity 'Warning'
                }

                $userInfo = Get-EntraInformation -ObjectId $response.id

            return $userInfo
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }

    <#
    .SYNOPSIS
        Sets or updates credentials for an Entra ID user.

    .DESCRIPTION
        The Set-UserCredential function updates the password for an Entra ID user account.
        This can be used to reset passwords or establish persistent access to user accounts.

    .PARAMETER ObjectId
        The object ID of the user to update.

    .PARAMETER Name
        The display name or partial name to search for users.

    .PARAMETER UserPrincipalName
        The User Principal Name (email) of the user to update.

    .PARAMETER Password
        A SecureString containing the new password to set for the user.

    .EXAMPLE
        Set-UserCredential -UserPrincipalName "user@domain.com" -Password (ConvertTo-SecureString "NewPassword123!" -AsPlainText -Force)

        Sets a new password for the specified user.

    .EXAMPLE
        Set-UserCredential -ObjectId "12345678-1234-1234-1234-123456789012" -Password $securePassword

        Sets a new password for the user with the specified object ID.

    .NOTES
        Requires appropriate Microsoft Graph permissions to manage user passwords.

    .LINK
        MITRE ATT&CK Tactic: TA0003 - Persistence
        https://attack.mitre.org/tactics/TA0003/

    .LINK
        MITRE ATT&CK Technique: T1098.001 - Account Manipulation: Additional Cloud Credentials
        https://attack.mitre.org/techniques/T1098/001/
    #>
}
