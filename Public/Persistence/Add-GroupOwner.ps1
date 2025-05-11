<#
.SYNOPSIS
    Adds an owner to an Azure AD group using Microsoft Graph API.

.DESCRIPTION
    The Add-GroupOwner function assigns an owner to an Azure AD group.
    The group can be specified by its ObjectId or display name.
    The owner can be specified by ObjectId, display name, user principal name, service principal name, service principal ID, or application ID.
    The function resolves the necessary identifiers and adds the specified owner to the group using the Microsoft Graph API.

.PARAMETER GroupObjectId
    The ObjectId of the Azure AD group to which the owner will be added. Mandatory if using the 'ObjectId' parameter set.

.PARAMETER GroupName
    The display name of the Azure AD group to which the owner will be added. Mandatory if using the 'Name' parameter set.

.PARAMETER OwnerName
    The display name of the user to be added as an owner. Optional.

.PARAMETER OwnerObjectId
    The ObjectId of the user or service principal to be added as an owner. Optional.

.PARAMETER UserPrincipalName
    The User Principal Name (UPN) of the user to be added as an owner. Optional.

.PARAMETER ServicePrincipalName
    The display name of the service principal to be added as an owner. Optional.

.PARAMETER ServicePrincipalId
    The ObjectId of the service principal to be added as an owner. Optional.

.PARAMETER ApplicationId
    The Application ID (appId) of the service principal to be added as an owner. Optional.

.EXAMPLE
    Add-GroupOwner -GroupObjectId "12345678-90ab-cdef-1234-567890abcdef" -UserPrincipalName "user@domain.com"

    Adds the user with the specified UPN as an owner to the group with the given ObjectId.

.EXAMPLE
    Add-GroupOwner -GroupName "Marketing Team" -ServicePrincipalName "MyApp"

    Adds the service principal with the specified display name as an owner to the group with the given display name.

.NOTES
    Requires the Invoke-MsGraph function and appropriate permissions to call Microsoft Graph API.
    The function uses the beta endpoint of Microsoft Graph API.
    The $script:graphHeader variable must be set with valid authentication headers.

#>
function Add-GroupOwner {
    [CmdletBinding(DefaultParameterSetName = 'ObjectId')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'ObjectId')]
        [string]$GroupObjectId,

        [Parameter(Mandatory = $true, ParameterSetName = 'Name')]
        [string]$GroupName,

        [Parameter(Mandatory = $false)]
        [string]$OwnerName,

        [Parameter(Mandatory = $false)]
        [string]$OwnerObjectId,

        [Parameter(Mandatory = $false)]
        [string]$UserPrincipalName,

        [Parameter(Mandatory = $false)]
        [string]$ServicePrincipalName,

        [Parameter(Mandatory = $false)]
        [string]$ServicePrincipalId,

        [Parameter(Mandatory = $false)]
        [string]$ApplicationId
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
    }

    process {
        try {
            # Resolve group ObjectId if Name is provided
            if ($PSCmdlet.ParameterSetName -eq 'Name') {
                $group = Invoke-MsGraph -relativeUrl "groups?`$filter=startswith(displayName,'$GroupName')" | Select-Object -First 1
                if (-not $group) {
                    throw "No group found with display name starting with '$GroupName'."
                }
                $GroupObjectId = $group.id
            }

            # Resolve OwnerObjectId if not provided, using a switch statement
            if (-not $OwnerObjectId) {
                switch ($true) {
                    { $OwnerName } {
                        $user = Invoke-MsGraph -relativeUrl "users?`$filter=startswith(displayName,'$OwnerName')"
                        if (-not $user) { throw "No user found with name '$UserPrincipalName'." }
                        $OwnerObjectId = $user.id
                        break
                    }
                    { $UserPrincipalName } {
                        $user = Invoke-MsGraph -relativeUrl "users?`$filter=userPrincipalName eq '$UserPrincipalName'" | Select-Object -First 1
                        if (-not $user) { throw "No user found with userPrincipalName '$UserPrincipalName'." }
                        $OwnerObjectId = $user.id
                        break
                    }
                    { $ServicePrincipalId } {
                        $sp = Invoke-MsGraph -relativeUrl "servicePrincipals/$ServicePrincipalId"
                        if (-not $sp) { throw "No service principal found with id '$ServicePrincipalId'." }
                        $OwnerObjectId = $sp.id
                        break
                    }
                    { $ServicePrincipalName } {
                        $sp = Invoke-MsGraph -relativeUrl "servicePrincipals?`$filter=displayName eq '$ServicePrincipalName'" | Select-Object -First 1
                        if (-not $sp) { throw "No service principal found with displayName '$ServicePrincipalName'." }
                        $OwnerObjectId = $sp.id
                        break
                    }
                    { $ApplicationId } {
                        $sp = Invoke-MsGraph -relativeUrl "servicePrincipals?`$filter=appId eq '$ApplicationId'" | Select-Object -First 1
                        if (-not $sp) { throw "No service principal found with applicationId '$ApplicationId'." }
                        $OwnerObjectId = $sp.id
                        break
                    }
                    default {
                        throw "You must provide OwnerObjectId, UserPrincipalName, ServicePrincipalId, ServicePrincipalName, or ApplicationId."
                    }
                }
            }

            # Prepare the request body for adding owner
            $body = @{
                "@odata.id" = "https://graph.microsoft.com/beta/directoryObjects/$OwnerObjectId"
            } | ConvertTo-Json

            # Add the owner to the group using Graph API
            $url = "https://graph.microsoft.com/beta/groups/$GroupObjectId/owners/`$ref"

            $requestParameters = @{
                Uri         = $url
                Headers     = $script:graphHeader
                Method      = 'POST'
                Body        = $body
                ContentType = 'application/json'
                ErrorAction = 'SilentlyContinue'
            }

            # Check if the owner is already assigned to the group
            $existingOwners = Invoke-MsGraph -relativeUrl "groups/$GroupObjectId/owners"
            if ($existingOwners | Where-Object { $_.id -eq $OwnerObjectId }) {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Identity is already owner of the group."
                return
            }

            $response = Invoke-RestMethod @requestParameters

            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Owner $OwnerObjectId added to group $GroupObjectId." -Severity Information
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $_.Exception.Message -Severity 'Error'
        }
    }
}
