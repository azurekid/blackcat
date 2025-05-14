function Get-AdministrativeUnits {
    [CmdletBinding()]
    param (
        [switch]$IncludeDynamicMembershipRules,
        [switch]$IncludeMembers
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }
    process {
        try {
            $units = Invoke-MsGraph -relativeUrl "administrativeUnits"
            if (-not $units) {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "No administrative units found." -Severity Warning
                return
            }

            foreach ($unit in $units) {
                if ($IncludeDynamicMembershipRules) {
                    # Get full details for dynamic membership properties
                    $details = Invoke-MsGraph -relativeUrl "administrativeUnits/$($unit.id)?`$select=id,displayName,membershipType,membershipRule,membershipRuleProcessingState" -NoBatch
                    $output = [PSCustomObject]@{
                        Id                            = $details.id
                        DisplayName                   = $details.displayName
                        MembershipType                = $details.membershipType
                        MembershipRule                = $details.membershipRule
                        MembershipRuleProcessingState = $details.membershipRuleProcessingState
                    }
                } else {
                    $output = [PSCustomObject]@{
                        Id             = $unit.id
                        DisplayName    = $unit.displayName
                        MembershipType = $unit.membershipType
                    }
                }

                if ($IncludeMembers) {
                    $members = Invoke-MsGraph -relativeUrl "administrativeUnits/$($unit.id)/members"
                    $output | Add-Member -MemberType NoteProperty -Name Members -Value $members.userPrincipalName
                }

                $output
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $_.Exception.Message -Severity 'Error'
        }
    }
}
