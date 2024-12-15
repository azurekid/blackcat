function Get-MsPrivilegedApps {
    begin {
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName "MSGraph"
    }

    process {
        try {
            Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message "Collecting Enterprise Applications" -Severity 'Information'
            $applications = Invoke-GraphRecursive -Url "$($sessionVariables.graphUri)/applications"

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
                        Owners          = @((Invoke-GraphRecursive -Url "$($sessionVariables.graphUri)/applications/$($application.id)/owners").userPrincipalName)
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
}
