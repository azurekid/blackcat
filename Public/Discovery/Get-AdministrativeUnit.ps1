function Get-AdministrativeUnit {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('administrative-unit', 'displayName', 'display-name', 'name')]
        [string]$AdministrativeUnit,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$ObjectId,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeMembers
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }
    process {
        $result = [System.Collections.Concurrent.ConcurrentBag[object]]::new()

        try {
            Write-Verbose "Processing parameters: ObjectId='$ObjectId', AdministrativeUnit='$AdministrativeUnit', IncludeMembers='$IncludeMembers'"

            switch ($true) {
                { $ObjectId } {
                    Write-Verbose "Querying administrative unit by ObjectId: $ObjectId"
                    $units = Invoke-MsGraph -relativeUrl "administrativeUnits/$ObjectId" -NoBatch -ErrorAction SilentlyContinue
                    if (-not $units) {
                        Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Administrative unit with ObjectId '$ObjectId' not found." -Severity Error
                        return
                    }
                    break
                }
                { $AdministrativeUnit } {
                    Write-Verbose "Querying administrative unit by name: $AdministrativeUnit"
                    $units = Invoke-MsGraph -relativeUrl  "administrativeunits?`$filter=startswith(displayName,'$AdministrativeUnit')" -ErrorAction SilentlyContinue
                    if (-not $units) {
                        Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Administrative unit '$AdministrativeUnit' not found." -Severity Error
                        return
                    }
                    break
                }
                default {
                    Write-Verbose "Querying all administrative units"
                    $units = Invoke-MsGraph -relativeUrl "administrativeUnits"
                    if (-not $units) {
                        Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "No administrative units found." -Severity Error
                        return
                    }
                }
            }

            Write-Verbose "Processing administrative units"
            $units | ForEach-Object -Parallel {

                Write-Verbose "Processing administrative unit: $($_.id)"
                $currentItem = [PSCustomObject]@{
                    Id                            = $_.id
                    DisplayName                   = $_.displayName
                    MembershipType                = $_.membershipType
                    MembershipRule                = $_.membershipRule
                    MembershipRuleProcessingState = $_.membershipRuleProcessingState
                }

                if ($using:IncludeMembers) {
                    Write-Verbose "Including members for administrative unit: $($_.id)"
                    $members = (Invoke-RestMethod -Uri "$($using:script:SessionVariables.graphUri)/administrativeUnits/$($_.id)/members" -Headers $using:script:graphHeader).value

                    Write-Verbose "Found $($members.Count) members for administrative unit: $($_.id)"
                    $currentItem | Add-Member -MemberType NoteProperty -Name Members -Value $members.userPrincipalName
                }
                ($using:result).Add($currentItem)
            }
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
        Retrieves administrative units from Entra ID.

    .DESCRIPTION
        The Get-AdministrativeUnit function retrieves administrative units from Microsoft Entra ID,
        including their membership rules and optionally their members.

    .PARAMETER AdministrativeUnit
        The display name or partial name of the administrative unit to search for.

    .PARAMETER ObjectId
        The object ID of a specific administrative unit to retrieve.

    .PARAMETER IncludeMembers
        When specified, includes the members of each administrative unit in the output.

    .EXAMPLE
        Get-AdministrativeUnit

        Retrieves all administrative units in the tenant.

    .EXAMPLE
        Get-AdministrativeUnit -AdministrativeUnit "HR" -IncludeMembers

        Retrieves administrative units with "HR" in the name and includes their members.

    .NOTES
        Requires appropriate Microsoft Graph permissions to enumerate administrative units.

    .LINK
        MITRE ATT&CK Tactic: TA0007 - Discovery
        https://attack.mitre.org/tactics/TA0007/

    .LINK
        MITRE ATT&CK Technique: T1526 - Cloud Service Discovery
        https://attack.mitre.org/techniques/T1526/
    #>
}
