function Get-AdministrativeUnits {
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

            if ($ObjectId) {
                Write-Verbose "Querying administrative unit by ObjectId: $ObjectId"
                $units = Invoke-MsGraph -relativeUrl "administrativeUnits/$ObjectId" -NoBatch -ErrorAction SilentlyContinue
                if (-not $units) {
                    Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Administrative unit with ObjectId '$ObjectId' not found." -Severity Error
                    return
                }
            }
            if ($AdministrativeUnit) {
                Write-Verbose "Querying administrative unit by name: $AdministrativeUnit"
                $units = Invoke-MsGraph -relativeUrl "administrativeUnits/$AdministrativeUnit" -ErrorAction SilentlyContinue

                if (-not $units) {
                    Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Administrative unit '$AdministrativeUnit' not found." -Severity Error
                    return
                }
            } else {
                Write-Verbose "Querying all administrative units"
                $units = Invoke-MsGraph -relativeUrl "administrativeUnits"

                if (-not $units) {
                    Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "No administrative units found." -Severity Error
                    return
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
}
