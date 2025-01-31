function Get-MsPrivilegedApps {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [int]$ThrottleLimit = 100
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName "MSGraph"

        $result = New-Object System.Collections.ArrayList
    }

    process {
        try {
            Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message "Collecting Enterprise Applications" -Severity 'Information'
            $applications = Invoke-MsGraph -relativeUrl "applications"

            Write-Verbose "User Applications: $($applications.count)"
            Write-Verbose "      [-] Validating [$($applications.count)] Enterprise Applications"

            $permissionList = (Invoke-WebRequest 'https://raw.githubusercontent.com/SecureHats/SecureHacks/main/documentation/AppRegistrationPermissions.csv').Content | ConvertFrom-Csv
            $riskyGrants = $permissionList | Where-Object Permission -in @(
                'Directory.ReadWrite.All',
                'PrivilegedAccess.ReadWrite.AzureAD',
                'PrivilegedAccess.ReadWrite.AzureADGroup',
                'PrivilegedAccess.ReadWrite.AzureResources',
                'Policy.ReadWrite.ConditionalAccess',
                'GroupMember.ReadWrite.All'
            )

            $applications | ForEach-Object -Parallel {
                $riskyGrants = $using:riskyGrants
                $result = $using:result

                $permissionObjects = @()

                foreach ($riskyGrant in $riskyGrants) {
                    if ($_.requiredResourceAccess.resourceAccess.id -contains $riskyGrant.id) {
                        $permissionObjects += $riskyGrant.Permission
                    }
                }

                if ($permissionObjects.Count -gt 0) {
                    
                    $currentItem = [PSCustomObject]@{
                        Id              = $_.Id
                        DisplayName     = $_.DisplayName
                        CreatedDateTime = $_.CreatedDateTime
                        Permission      = $permissionObjects | Sort-Object -Unique
                    }

                    if ($_.PasswordCredentials.KeyId) {
                        $currentItem | Add-Member -MemberType NoteProperty -Name Credentials -Value $_.PasswordCredentials -Force
                    }

                    if ($_.KeyCredentials.Value) {
                        $currentItem | Add-Member -MemberType NoteProperty -Name KeyCredentials -Value $_.KeyCredentials -Force
                    }

                    [void]$result.Add($currentItem)
                }
            } -ThrottleLimit $ThrottleLimit

            $json = [ordered]@{}
            [void]$json.Add("data", $result)

            return $json.Values
        }
        catch {
            Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message $_.Exception.Message -Severity 'Error'
        }
    }

    end {
        Write-Verbose "Completed function $($MyInvocation.MyCommand.Name)"
    }
    <#
    .SYNOPSIS
    Retrieves and analyzes privileged enterprise applications from Microsoft Graph.

    .DESCRIPTION
    The Get-MsPrivilegedApps function collects enterprise applications from Microsoft Graph and identifies those with risky permissions. It validates the applications against a predefined list of risky permissions and returns detailed information about the applications that have these permissions.

    .PARAMETER ThrottleLimit
    Maximum number of concurrent operations. Default is 10.

    .OUTPUTS
    System.Collections.ArrayList
    Returns an array list of PSCustomObjects containing details of the applications with risky permissions.

    .NOTES
    Author: Rogier Dijkman
    FilePath: /c:/Users/RogierDijkman/GitHub/blackcat/src/Public/entra/Get-MsPrivilegedApps.ps1

    .EXAMPLE
    PS> Get-MsPrivilegedApps
    This command retrieves and analyzes privileged enterprise applications from Microsoft Graph and returns detailed information about those with risky permissions.

    #>
}
