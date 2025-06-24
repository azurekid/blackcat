function Get-PrivilegedApp {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [int]$ThrottleLimit = 1000
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
            Write-Verbose "    [-] Validating [$($applications.count)] Enterprise Applications"

            $riskyGrants = $sessionVariables.appRoleIds | Where-Object Permission -in @(
                'Directory.ReadWrite.All',
                'PrivilegedAccess.ReadWrite.AzureAD',
                'PrivilegedAccess.ReadWrite.AzureADGroup',
                'PrivilegedAccess.ReadWrite.AzureResources',
                'Policy.ReadWrite.ConditionalAccess',
                'GroupMember.ReadWrite.All',
                'Group.ReadWrite.All',
                'RoleManagement.ReadWrite.Directory',
                'Application.ReadWrite.All'
            )

            $applications | ForEach-Object -Parallel {
                $riskyGrants = $using:riskyGrants
                $result = $using:result
                $header = $using:script:graphHeader

                $permissionObjects = @()

                foreach ($riskyGrant in $riskyGrants) {
                    if ($_.requiredResourceAccess.resourceAccess.id -contains $riskyGrant.appRoleId) {
                        $permissionObjects += $riskyGrant.Permission
                    }
                }

                if ($permissionObjects.Count -gt 0) {

                    $currentItem = [PSCustomObject]@{
                        Id              = $_.Id
                        DisplayName     = $_.DisplayName
                        CreatedDateTime = $_.CreatedDateTime
                        Permission      = $permissionObjects | Sort-Object -Unique
                        Owners          = (Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/applications/$($_.Id)/owners" -Headers $header).value.UserPrincipalName
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
    Retrieves Microsoft Entra ID (Azure AD) applications with privileged permissions.

.DESCRIPTION
    The Get-PrivilegedApp function identifies and returns Enterprise Applications that have been granted high-risk
    permissions in Microsoft Entra ID. It specifically looks for applications with permissions such as Directory.ReadWrite.All,
    PrivilegedAccess.ReadWrite.AzureAD, and other sensitive permissions that could pose security risks.

.PARAMETER ThrottleLimit
    Specifies the maximum number of concurrent operations that can be performed in parallel.
    Default value is 1000.

.OUTPUTS
    Returns an array of PSCustomObjects containing the following properties:
    - Id: The unique identifier of the applicationc
    - DisplayName: The display name of the application
    - CreatedDateTime: When the application was created
    - Permission: Array of high-risk permissions granted to the application
    - Credentials: (Optional) If present, contains password credentials information
    - KeyCredentials: (Optional) If present, contains certificate credentials information

.EXAMPLE
    Get-PrivilegedApp
    Returns all applications with high-risk permissions using default throttle limit.

.EXAMPLE
    Get-PrivilegedApp -ThrottleLimit 500
    Returns all applications with high-risk permissions using a custom throttle limit of 500.

.EXAMPLE
    Get-PrivilegedApp -Verbose
    Returns all applications with high-risk permissions with detailed progress information.

.NOTES
    File: Get-PrivilegedApp.ps1
    Author: Script Author
    Version: 1.0
    Requires: PowerShell 7.0 or later
    Requires: Microsoft Graph API access
    Requires: Appropriate permissions to read application information

    The function checks for the following high-risk permissions:
    - Directory.ReadWrite.All
    - PrivilegedAccess.ReadWrite.AzureAD
    - PrivilegedAccess.ReadWrite.AzureADGroup
    - PrivilegedAccess.ReadWrite.AzureResources
    - Policy.ReadWrite.ConditionalAccess
    - GroupMember.ReadWrite.All
    - Group.ReadWrite.All
    - RoleManagement.ReadWrite.Directory

#>
}
