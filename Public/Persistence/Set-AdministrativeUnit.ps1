function Set-AdministrativeUnit {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('administrative-unit', 'displayName', 'display-name', 'name')]
        [string]$AdministrativeUnit,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$ObjectId,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeMembers,

        [Parameter(Mandatory = $false)]
        [string]$NewDisplayName,

        [Parameter(Mandatory = $false)]
        [string]$MembershipType,

        [Parameter(Mandatory = $false)]
        [string]$MembershipRule,

        [Parameter(Mandatory = $false)]
        [string[]]$AddUserIds
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }
    process {
        $result = [System.Collections.Concurrent.ConcurrentBag[object]]::new()

        try {
            Write-Verbose "Processing parameters: ObjectId='$ObjectId', AdministrativeUnit='$AdministrativeUnit', IncludeMembers='$IncludeMembers', AddUserIds='$AddUserIds'"

            # Find the administrative unit
            if ($ObjectId) {
                Write-Verbose "Querying administrative unit by ObjectId: $ObjectId"
                $unit = Invoke-MsGraph -relativeUrl "administrativeUnits/$ObjectId" -NoBatch -ErrorAction SilentlyContinue
                if (-not $unit) {
                    Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Administrative unit with ObjectId '$ObjectId' not found." -Severity Error
                    return
                }
            }
            elseif ($AdministrativeUnit) {
                Write-Verbose "Querying administrative unit by name: $AdministrativeUnit"
                $unit = Invoke-MsGraph -relativeUrl "administrativeUnits" -ErrorAction SilentlyContinue | Where-Object { $_.displayName -eq $AdministrativeUnit }
                if (-not $unit) {
                    Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Administrative unit '$AdministrativeUnit' not found." -Severity Error
                    return
                }
            }
            else {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "No administrative unit identifier provided." -Severity Error
                return
            }

            # Prepare update body
            $updateBody = @{}
            if ($PSBoundParameters.ContainsKey('NewDisplayName')) { $updateBody.displayName = $NewDisplayName }
            if ($PSBoundParameters.ContainsKey('MembershipType')) { $updateBody.membershipType = $MembershipType }
            if ($PSBoundParameters.ContainsKey('MembershipRule')) { $updateBody.membershipRule = $MembershipRule }

            if ($updateBody.Count -gt 0) {
                Write-Verbose "Updating administrative unit $($unit.id) with $($updateBody | Out-String)"
                $requestParams = @{
                    Uri     = "$($sessionVariables.graphUri)/administrativeUnits/$($unit.id)"
                    Method  = 'PATCH'
                    Headers = $script:graphHeader
                    Body    = ($updateBody | ConvertTo-Json -Depth 5)
                    ContentType = 'application/json'
                }
                Invoke-RestMethod @requestParams
            } else {
                Write-Verbose "No update parameters provided. Skipping update."
            }

            # Add users to administrative unit if specified
            if ($AddUserIds) {
                foreach ($userId in $AddUserIds) {
                    Write-Verbose "Adding user $userId to administrative unit $($unit.id)"
                    $addMemberBody = @{
                        "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$userId"
                    }
                    $addMemberParams = @{
                        Uri         = "$($sessionVariables.graphUri)/administrativeUnits/$($unit.id)/members/`$ref"
                        Method      = 'POST'
                        Headers     = $script:graphHeader
                        Body        = ($addMemberBody | ConvertTo-Json)
                        ContentType = 'application/json'
                        ErrorAction = 'Stop'
                    }
                    try {
                        Invoke-RestMethod @addMemberParams
                    } catch {
                        Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Failed to add user $userId $($_.Exception.Message)" -Severity 'Error'
                    }
                }
            }

            # Get updated unit
            $updatedUnit = Invoke-MsGraph -relativeUrl "administrativeUnits/$($unit.id)" -NoBatch

            $currentItem = [PSCustomObject]@{
                Id                            = $updatedUnit.id
                DisplayName                   = $updatedUnit.displayName
                MembershipType                = $updatedUnit.membershipType
                MembershipRule                = $updatedUnit.membershipRule
                MembershipRuleProcessingState = $updatedUnit.membershipRuleProcessingState
            }

            if ($IncludeMembers) {
                Write-Verbose "Including members for administrative unit: $($updatedUnit.id)"
                $members = Invoke-MsGraph -relativeUrl "/administrativeUnits/$($updatedUnit.id)/members"
                $currentItem | Add-Member -MemberType NoteProperty -Name Members -Value $members
            }

            $result.Add($currentItem)
            Write-Verbose "Returning result"
            return $result
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $_.Exception.Message -Severity 'Error'
            Write-Verbose "Exception occurred: $($_.Exception.Message)"
        }
    }
<#
.SYNOPSIS
Updates properties of an Azure Active Directory Administrative Unit.

.DESCRIPTION
Updates Azure AD Administrative Unit properties including name, membership type, rules.

.PARAMETER AdministrativeUnit
The display name or alias of the administrative unit to update. Can also be specified as 'administrative-unit', 'displayName', 'display-name', or 'name'.

.PARAMETER ObjectId
The unique ObjectId of the administrative unit to update.

.PARAMETER IncludeMembers
Switch parameter. If specified, includes the members of the administrative unit in the output.

.PARAMETER NewDisplayName
The new display name to assign to the administrative unit.

.PARAMETER MembershipType
The membership type to assign to the administrative unit.

.PARAMETER MembershipRule
The membership rule to assign to the administrative unit.

.PARAMETER AddUserIds
An array of user ObjectIds to add as members to the administrative unit.

.EXAMPLE
Set-AdministrativeUnit -ObjectId "12345678-90ab-cdef-1234-567890abcdef" -NewDisplayName "New AU Name"

Updates the display name of the administrative unit with the specified ObjectId.

.EXAMPLE
Set-AdministrativeUnit -AdministrativeUnit "HR Department" -MembershipType "Dynamic" -MembershipRule "(user.department -eq 'HR')" -IncludeMembers

Updates the membership type and rule for the "HR Department" administrative unit and includes its members in the output.

.EXAMPLE
Set-AdministrativeUnit -ObjectId "12345678-90ab-cdef-1234-567890abcdef" -AddUserIds "user-object-id-1","user-object-id-2"

Adds the specified users to the administrative unit.

.NOTES
Requires appropriate permissions to update administrative units in Azure Active Directory.

.LINK
MITRE ATT&CK Tactic: TA0003 - Persistence
https://attack.mitre.org/tactics/TA0003/

.LINK
MITRE ATT&CK Technique: T1098.003 - Account Manipulation: Additional Cloud Roles
https://attack.mitre.org/techniques/T1098/003/
#>
}