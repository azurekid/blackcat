
function Restore-DeletedIdentity {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [string]$ObjectId,

        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Application', 'Group', 'User', 'AdministrativeUnit')]
        [string]$Type = 'Application',

        [Parameter(Mandatory = $false)]
        [switch]$Restore
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'

        $directoryPath = "directory/deleteditems"

        # Map object types to their Graph API paths
        $typeMap = @{
            'Application'        = 'microsoft.graph.application'
            'Group'              = 'microsoft.graph.group'
            'User'               = 'microsoft.graph.user'
            'AdministrativeUnit' = 'microsoft.graph.administrativeUnit'
        }
    }

    process {
        Write-Verbose "Querying deleted $Type items from Microsoft Graph"
        $deletedObject = Invoke-MsGraph -relativeUrl "$directoryPath/$($typeMap[$Type])" |

        Where-Object {
            $_.deletedDateTime -gt (Get-Date).AddDays(-30) -and
                (!$ObjectId -or $_.Id -eq $ObjectId) -and
                (!$Name -or $_.DisplayName -like "*$Name*")
        } |
        Select-Object DisplayName, Id, appId, deletedDateTime

        Write-Verbose "Found $($deletedObject.Count) deleted items matching criteria"

        if ($deletedObject.id -and $Restore) {
            Write-Verbose "Attempting to restore $Type with ID: $($deletedObject.id)"
            $restoreUri = "$($SessionVariables.graphUri)/$directoryPath/$($deletedObject.id)/restore"

            $restoreParam = @{
                Headers     = $script:graphHeader
                Uri         = "$($SessionVariables.graphUri)/$directoryPath/$($deletedObject.id)/restore"
                UserAgent   = $($sessionVariables.userAgent)
                Method      = 'POST'
                Body    = '{}'
                'ContentType'  = 'application/json'
            }

            Write-Verbose "Sending restore request for $Type"
            $restoredObject = Invoke-RestMethod @restoreParam

        }

        # Handle service principal restoration only for Application type
        if ($Type -eq 'Application' -and $restoredObject) {
            Write-Verbose "Application restored successfully. Looking for associated service principal"
            $spn = Invoke-MsGraph -relativeUrl "$directoryPath/microsoft.graph.servicePrincipal" |
            Where-Object {
                $_.appId -eq $deletedObject.appId
            }

            if ($spn) {
                foreach ($sp in $spn) {
                    Write-Verbose "Found associated service principal with ID: $($sp.id)"
                    $restoreUri = "$($sessionVariables.graphUri)/$directoryPath/$($sp.id)/restore"

                    $restoreParam = @{
                        Headers     = $script:graphHeader
                        Uri     = $restoreUri
                        Method  = 'POST'
                        UserAgent   = $($sessionVariables.userAgent)
                        Body    = '{}'
                        'ContentType' = 'application/json'
                    }

                    Write-Verbose "Sending restore request for service principal"
                    $null = Invoke-RestMethod @restoreParam
                    Write-Verbose "Service principal restore completed"
                }
            }
            else {
                Write-Verbose "No associated service principal found"
            }
        }

        return $deletedObject | Select-Object DisplayName, Id, appId, deletedDateTime
    }
    <#
.SYNOPSIS
    Retrieves and optionally restores deleted identities from Microsoft Graph.

.DESCRIPTION
    Searches for and restores deleted identities from Microsoft Graph within the retention window (typically 30 days). Enables recovery of deleted users, groups, or applications. Useful for account recovery and gaining persistence through previously deleted identities.

.PARAMETER ObjectId
    The unique identifier (ObjectId) of the deleted identity to find or restore.

.PARAMETER Name
    The display name (or partial name) of the deleted identity to find or restore.

.PARAMETER Type
    The type of identity to search for. Valid values are:
    - Application (default)
    - Group
    - User
    - AdministrativeUnit

.PARAMETER Restore
    If specified, attempts to restore the found deleted identity. Otherwise, only retrieves information about deleted identities.

.EXAMPLE
    PS> Restore-DeletedIdentity -Name "TestApp" -Type Application
    Lists all deleted applications with "TestApp" in their name.

.EXAMPLE
    PS> Restore-DeletedIdentity -ObjectId "12345678-1234-1234-1234-123456789012" -Type User -Restore
    Restores a specific deleted user by their ObjectId.

.EXAMPLE
    PS> Restore-DeletedIdentity -Name "HR" -Type Group
    Lists all deleted groups with "HR" in their name.

.OUTPUTS
    If -Restore is not specified:
        PSCustomObject with properties: DisplayName, Id, appId, deletedDateTime
    If -Restore is specified:
        The restored object from Microsoft Graph

.NOTES
    - Requires appropriate Microsoft Graph permissions
    - Can only restore items deleted within the last 30 days
    - When restoring applications, automatically attempts to restore associated service principals

.LINK
    https://learn.microsoft.com/en-us/graph/api/directory-deleteditems-list

.LINK
    MITRE ATT&CK Tactic: TA0042 - Resource Development
    https://attack.mitre.org/tactics/TA0042/

.LINK
    MITRE ATT&CK Technique: T1583.006 - Acquire Infrastructure: Web Services
    https://attack.mitre.org/techniques/T1583/006/
#>
}