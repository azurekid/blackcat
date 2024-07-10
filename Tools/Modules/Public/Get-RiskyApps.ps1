function Get-RiskyApps {

    Write-Host "   [-] Collecting Enterprise Applications" -ForegroundColor Yellow
    $applications = (Get-GraphRecursive @aadRequestHeader -Url "$($sessionVariables.graphUri)/applications")

    Write-Host "      [-] Validating [$($applications.count)] Enterprise Applications Risks" -ForegroundColor Yellow

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

    $dataHash           = New-Object System.Collections.ArrayList
    $riskyApps          = New-Object System.Collections.ArrayList
    $permissionObjects  = @()

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

            $null = $dataHash.Add($currentItem)
        }
        $permissionObjects = @()

    }

    $json = [ordered]@{}
    $null = $json.add("data", ($dataHash))

    return $json
}