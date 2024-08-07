function Get-RiskyApps {

    begin {
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName "MSGraph"
    }

    process {

        try {

            Write-Host "   [-] Collecting Enterprise Applications" -ForegroundColor Yellow
            $applications = (Invoke-GraphRecursive -Url "$($sessionVariables.graphUri)/applications")

            Write-Host "User Applications: $($applications.count)"
            Write-Verbose "      [-] Validating [$($applications.count)] Enterprise Applications" -ForegroundColor Yellow

            $permissionList = (Invoke-WebRequest 'https://raw.githubusercontent.com/SecureHats/SecureHacks/main/documentation/AppRegistrationPermissions.csv').content | ConvertFrom-Csv
            $riskyGrants = $permissionList | Where-Object Permission -in `
            (`
                    'Directory.ReadWrite.All', `
                    'PrivilegedAccess.ReadWrite.AzureAD', `
                    'PrivilegedAccess.ReadWrite.AzureADGroup', `
                    'PrivilegedAccess.ReadWrite.AzureResources', `
                    'Policy.ReadWrite.ConditionalAccess', `
                    'GroupMember.ReadWrite.All' `
            )

            $dataHash = New-Object System.Collections.ArrayList
            $riskyApps = New-Object System.Collections.ArrayList
            $permissionObjects = @()

            foreach ($application in $applications) {
                foreach ($riskyGrant in $riskyGrants) {
                    if ($application.requiredResourceAccess.resourceaccess.id -contains $riskyGrant.id) {
                        $permissionObjects += ($riskyGrant.Permission)
                    }

                    if ($permissionObjects.count -gt 0) {
                        $null = $riskyApps.add($application)
                    }
                }

                if ($permissionObjects.count -gt 0) {

                    $currentItem = [PSCustomObject]@{
                        Id              = $application.Id
                        DisplayName     = $application.displayname
                        createdDateTime = $application.createdDateTime
                        Permission      = $permissionObjects | Sort-Object -Unique
                    }

                    if ($application.passwordCredentials.keyId) {
                        $currentItem | Add-Member `
                            -MemberType NoteProperty `
                            -Name Credentials `
                            -Value $application.passwordCredentials `
                            -Force
                    }

                    if ($application.keyCredentials.value) {
                        $currentItem | Add-Member `
                            -MemberType NoteProperty `
                            -Name keyCredentials `
                            -Value $application.keyCredentials `
                            -Force
                    }

                    [void]$dataHash.Add($currentItem)
                }
                $permissionObjects = @()
            }

            $json = [ordered]@{}
            [void]$json.add("data", ($dataHash))

            return $json.values
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
}