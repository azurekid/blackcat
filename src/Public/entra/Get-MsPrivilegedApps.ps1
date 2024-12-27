function Get-MsPrivilegedApps {
    begin {
        Write-Verbose "Invoking BlackCat for MSGraph"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName "MSGraph"
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

            $dataHash = New-Object System.Collections.ArrayList
            $riskyApps = New-Object System.Collections.ArrayList

            foreach ($application in $applications) {
                $permissionObjects = @()

                foreach ($riskyGrant in $riskyGrants) {
                    if ($application.requiredResourceAccess.resourceAccess.id -contains $riskyGrant.id) {
                        $permissionObjects += $riskyGrant.Permission
                    }
                }

                if ($permissionObjects.Count -gt 0) {
                    $null = $riskyApps.Add($application)

                    $currentItem = [PSCustomObject]@{
                        Id              = $application.Id
                        DisplayName     = $application.DisplayName
                        CreatedDateTime = $application.CreatedDateTime
                        Permission      = $permissionObjects | Sort-Object -Unique
                        Owners          = @((Invoke-MSGraph -relativeUrl "applications/$($application.id)/owners").userPrincipalName)
                    }

                    if ($application.PasswordCredentials.KeyId) {
                        $currentItem | Add-Member -MemberType NoteProperty -Name Credentials -Value $application.PasswordCredentials -Force
                    }

                    if ($application.KeyCredentials.Value) {
                        $currentItem | Add-Member -MemberType NoteProperty -Name KeyCredentials -Value $application.KeyCredentials -Force
                    }

                    [void]$dataHash.Add($currentItem)
                }
            }

            $json = [ordered]@{}
            [void]$json.Add("data", $dataHash)

            return $json.Values
        }
        catch {
            Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message $_.Exception.Message -Severity 'Error'
        }
    }
    <#
.SYNOPSIS
Retrieves and analyzes privileged enterprise applications from Microsoft Graph.

.DESCRIPTION
The Get-MsPrivilegedApps function collects enterprise applications from Microsoft Graph and identifies those with risky permissions. It validates the applications against a predefined list of risky permissions and returns detailed information about the applications that have these permissions.

.PARAMETER None
This function does not take any parameters.

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
