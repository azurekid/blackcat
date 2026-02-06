function Set-AppRegistrationOwner {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory = $true)]
        [string]$AppId,

        [Parameter(ParameterSetName = 'ByObjectId', Mandatory = $true)]
        [string]$OwnerObjectId,

        [Parameter(ParameterSetName = 'UserPrincipalName', Mandatory = $true)]
        [string]$UserPrincipalName
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'UserPrincipalName') {
            $user = Invoke-MsGraph -relativeUrl "users?`$filter=startswith(displayName,'$userPrincipalName') or startswith(userPrincipalName,'$userPrincipalName')"
            if (-not $user -or $user.Count -eq 0) {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "User with UserPrincipalName '$UserPrincipalName' not found." -Severity 'Error'
            }
            $OwnerObjectId = $user.id
        }

        if ($PSCmdlet.ShouldProcess("App Registration '$AppId'", "Set owner '$OwnerObjectId'")) {
            $sp = (Invoke-MsGraph -relativeUrl 'applications' | Where-Object appId -eq $AppId)
            if (-not $sp) {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Service Principal with AppId '$AppId' not found." -Severity 'Error'
            }

            # Add the owner
            $body = @{
                "@odata.id" = "https://graph.microsoft.com/beta/directoryObjects/$OwnerObjectId"
            }

            $requestParameters = @{
                Uri         = "https://graph.microsoft.com/beta/applications/$($sp.id)/owners/`$ref"
                Method      = 'POST'
                Headers     = $script:graphHeader
                Body        = $body | ConvertTo-Json
                ContentType = 'application/json'
            }

            Invoke-RestMethod @requestParameters
            Write-Verbose "Owner '$OwnerObjectId' added to App Registration '$AppId'."
        }
    }
    <#
    .SYNOPSIS
        Sets an owner on an Azure App Registration.

    .DESCRIPTION
        Adds a user as an owner to the specified App Registration using ID or UPN.

    .PARAMETER AppId
        The Application (client) ID of the App Registration.

    .PARAMETER OwnerObjectId
        The object ID of the user to add as owner.

    .PARAMETER UserPrincipalName
        The User Principal Name (email) of the user to add as owner.

    .EXAMPLE
        Set-AppRegistrationOwner -AppId "00000000-0000-0000-0000-000000000000" -OwnerObjectId "11111111-1111-1111-1111-111111111111"

    .EXAMPLE
        Set-AppRegistrationOwner -AppId "00000000-0000-0000-0000-000000000000" -UserPrincipalName "user@domain.com"

    .NOTES
        Requires appropriate Microsoft Graph permissions to manage application owners.

    .LINK
        MITRE ATT&CK Tactic: TA0003 - Persistence
        https://attack.mitre.org/tactics/TA0003/

    .LINK
        MITRE ATT&CK Technique: T1098.001 - Account Manipulation: Additional Cloud Credentials
        https://attack.mitre.org/techniques/T1098/001/
    #>
}
