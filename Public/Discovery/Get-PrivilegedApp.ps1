function Get-PrivilegedApp {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [int]$ThrottleLimit = 1000,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Object", "JSON", "CSV", "Table")]
        [Alias("output", "o")]
        [string]$OutputFormat = "Table",

        [Parameter(Mandatory = $false)]
        [Alias("include-owners", "owners")]
        [switch]$IncludeOwners
    )

    begin {
        Write-Verbose " Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName "MSGraph"

        $result = New-Object System.Collections.ArrayList
        $stats = @{ 
            StartTime         = Get-Date
            TotalApplications = 0
        }
        
        # Thread-safe counters for parallel processing
        $privilegedAppCount = [ref]0
        $credentialAppCount = [ref]0
        $keyCredentialAppCount = [ref]0
        $expiredCredentialAppCount = [ref]0
        $expiredKeyCredentialAppCount = [ref]0
    }

    process {
        try {
            Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message " Collecting Enterprise Applications" -Severity 'Information'
            $applications = Invoke-MsGraph -relativeUrl "applications"

            $stats.TotalApplications = $applications.count
            Write-Verbose " User Applications: $($applications.count)"
            Write-Verbose "     Validating [$($applications.count)] Enterprise Applications for privileged permissions"

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

            Write-Verbose "     Pre-filtering applications with privileged permissions..."
            $privilegedApps = $applications | Where-Object {
                $app = $_
                $hasPrivilegedPermissions = $false
                foreach ($riskyGrant in $riskyGrants) {
                    if ($app.requiredResourceAccess.resourceAccess.id -contains $riskyGrant.appRoleId) {
                        $hasPrivilegedPermissions = $true
                        break
                    }
                }
                $hasPrivilegedPermissions
            }

            Write-Verbose "     Found $($privilegedApps.Count) applications with privileged permissions (filtering from $($applications.count) total)"

            # Only fetch owners if explicitly requested or if output format needs detailed information
            $ownerLookup = @{}
            if ($IncludeOwners) {
                Write-Verbose "     Fetching owners for privileged applications..."
                foreach ($app in $privilegedApps) {
                    try {
                        $owners = Invoke-MsGraph -relativeUrl "applications/$($app.Id)/owners"
                        $ownerLookup[$app.Id] = $owners.userPrincipalName
                    }
                    catch {
                        Write-Verbose "     Failed to get owners for application $($app.Id): $($_.Exception.Message)"
                        $ownerLookup[$app.Id] = @()
                    }
                }
            }
            else {
                Write-Verbose "     Skipping owner lookup for better performance (use -IncludeOwners to fetch owners)"
                # Initialize empty lookup for all privileged apps
                foreach ($app in $privilegedApps) {
                    $ownerLookup[$app.Id] = @("Not fetched - use -IncludeOwners parameter")
                }
            }

            $privilegedApps | ForEach-Object -Parallel {
                $riskyGrants = $using:riskyGrants
                $result = $using:result
                $ownerLookup = $using:ownerLookup
                $privilegedAppCount = $using:privilegedAppCount
                $credentialAppCount = $using:credentialAppCount
                $keyCredentialAppCount = $using:keyCredentialAppCount
                $expiredCredentialAppCount = $using:expiredCredentialAppCount
                $expiredKeyCredentialAppCount = $using:expiredKeyCredentialAppCount

                $permissionObjects = @()

                foreach ($riskyGrant in $riskyGrants) {
                    if ($_.requiredResourceAccess.resourceAccess.id -contains $riskyGrant.appRoleId) {
                        $permissionObjects += $riskyGrant.Permission
                    }
                }

                if ($permissionObjects.Count -gt 0) {
                    # Determine severity level based on permissions (ordered by risk level)
                    $severity = "Low"  # Default for any other risky permissions
                    
                    # Critical - Permissions that provide broad administrative access or bypass security controls
                    if ($permissionObjects -contains "Directory.ReadWrite.All" -or
                        $permissionObjects -contains "PrivilegedAccess.ReadWrite.AzureAD" -or
                        $permissionObjects -contains "PrivilegedAccess.ReadWrite.AzureADGroup" -or
                        $permissionObjects -contains "PrivilegedAccess.ReadWrite.AzureResources" -or
                        $permissionObjects -contains "Policy.ReadWrite.ConditionalAccess") { 
                        $severity = "Critical" 
                    }
                    # High - Permissions that can escalate privileges or manage credentials
                    elseif ($permissionObjects -contains "RoleManagement.ReadWrite.Directory" -or
                            $permissionObjects -contains "Application.ReadWrite.All" -or
                            $permissionObjects -contains "GroupMember.ReadWrite.All" -or
                            $permissionObjects -contains "Group.ReadWrite.All") { 
                        $severity = "High" 
                    }
                    # Medium severity is now handled by the default "Low" since these are all high-risk permissions

                    $currentItem = [PSCustomObject]@{
                        DisplayName              = $_.DisplayName
                        Id                       = $_.Id
                        Severity                 = $severity
                        CreatedDateTime          = $_.CreatedDateTime
                        Permission               = $permissionObjects | Sort-Object -Unique
                        Owners                   = $ownerLookup[$_.Id]
                        HasCredentials           = $false
                        HasKeyCredentials        = $false
                        PasswordCredentialExpiry = $null
                        KeyCredentialExpiry      = $null
                    }

                    if ($_.PasswordCredentials.KeyId) {
                        $currentItem | Add-Member -MemberType NoteProperty -Name Credentials -Value $_.PasswordCredentials -Force
                        $currentItem.HasCredentials = $true
                        
                        $passwordExpiry = $_.PasswordCredentials | Where-Object { $_.EndDateTime } | 
                        Sort-Object EndDateTime | Select-Object -First 1 -ExpandProperty EndDateTime
                        if ($passwordExpiry) {
                            $currentItem.PasswordCredentialExpiry = [DateTime]$passwordExpiry

                            if ([DateTime]$passwordExpiry -lt (Get-Date)) {
                                [void][System.Threading.Interlocked]::Increment($expiredCredentialAppCount)
                            }
                        }
                        
                        [void][System.Threading.Interlocked]::Increment($credentialAppCount)
                    }

                    if ($_.KeyCredentials.Value) {
                        $currentItem | Add-Member -MemberType NoteProperty -Name KeyCredentials -Value $_.KeyCredentials -Force
                        $currentItem.HasKeyCredentials = $true
                        
                        $keyExpiry = $_.KeyCredentials | Where-Object { $_.EndDateTime } | 
                        Sort-Object EndDateTime | Select-Object -First 1 -ExpandProperty EndDateTime
                        if ($keyExpiry) {
                            $currentItem.KeyCredentialExpiry = [DateTime]$keyExpiry

                            if ([DateTime]$keyExpiry -lt (Get-Date)) {
                                [void][System.Threading.Interlocked]::Increment($expiredKeyCredentialAppCount)
                            }
                        }
                        
                        [void][System.Threading.Interlocked]::Increment($keyCredentialAppCount)
                    }

                    [void][System.Threading.Interlocked]::Increment($privilegedAppCount)
                    [void]$result.Add($currentItem)
                }
            } -ThrottleLimit $ThrottleLimit

            $json = [ordered]@{}
            [void]$json.Add("data", $result)

            Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message " Found $($result.Count) privileged applications" -Severity 'Information'
        }
        catch {
            Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message " $($_.Exception.Message)" -Severity 'Error'
        }
    }

    end {
        $Duration = (Get-Date) - $stats.StartTime
        
        # Update stats with final counts from thread-safe counters
        $stats.PrivilegedApplications = $privilegedAppCount.Value
        $stats.ApplicationsWithCredentials = $credentialAppCount.Value
        $stats.ApplicationsWithKeyCredentials = $keyCredentialAppCount.Value
        $stats.ApplicationsWithExpiredCredentials = $expiredCredentialAppCount.Value
        $stats.ApplicationsWithExpiredKeyCredentials = $expiredKeyCredentialAppCount.Value
        
        Write-Host "`n Privileged Application Discovery Summary:" -ForegroundColor Magenta
        Write-Host "   Total Applications Analyzed: $($stats.TotalApplications)" -ForegroundColor White
        Write-Host "   Privileged Applications Found: $($stats.PrivilegedApplications)" -ForegroundColor Yellow
        Write-Host "   Applications with Password Credentials: $($stats.ApplicationsWithCredentials)" -ForegroundColor Cyan
        Write-Host "   Applications with Key Credentials: $($stats.ApplicationsWithKeyCredentials)" -ForegroundColor Cyan
        Write-Host "   Applications with Expired Password Credentials: $($stats.ApplicationsWithExpiredCredentials)" -ForegroundColor Red
        Write-Host "   Applications with Expired Key Credentials: $($stats.ApplicationsWithExpiredKeyCredentials)" -ForegroundColor Red
        Write-Host "   Duration: $($Duration.TotalSeconds.ToString('F2')) seconds" -ForegroundColor White
        
        if ($result.Count -gt 0) {
            # Group by severity level for summary
            $severityLevelCounts = $result | Group-Object Severity | Sort-Object @{Expression = {
                    switch ($_.Name) {
                        "Critical" { 1 }
                        "High" { 2 }
                        "Medium" { 3 }
                        "Low" { 4 }
                    }
                }
            }
            
            Write-Host "`n   Severity Level Breakdown:" -ForegroundColor White
            foreach ($group in $severityLevelCounts) {
                $emoji = switch ($group.Name) {
                    "Critical" { "" }
                    "High" { "" }
                    "Medium" { "" }
                    "Low" { "" }
                }
                Write-Host "      $emoji $($group.Name): $($group.Count)" -ForegroundColor White
            }
            
            # Return results in requested format
            switch ($OutputFormat) {
                "JSON" { 
                    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    $jsonOutput = $result | ConvertTo-Json -Depth 3
                    $jsonFilePath = "PrivilegedApps_$timestamp.json"
                    $jsonOutput | Out-File -FilePath $jsonFilePath -Encoding UTF8
                    Write-Host " JSON output saved to: $jsonFilePath" -ForegroundColor Green
                    # File created, no console output needed
                    return
                }
                "CSV" { 
                    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    $csvOutput = $result | ConvertTo-CSV
                    $csvFilePath = "PrivilegedApps_$timestamp.csv"
                    $csvOutput | Out-File -FilePath $csvFilePath -Encoding UTF8
                    Write-Host " CSV output saved to: $csvFilePath" -ForegroundColor Green
                    # File created, no console output needed
                    return
                }
                "Object" { return $result }
                "Table" { return $result | Format-Table -AutoSize }
            }
        }
        else {
            Write-Host "`n No privileged applications found" -ForegroundColor Red
            Write-Information "No privileged applications found" -InformationAction Continue
        }
        
        Write-Verbose " Completed function $($MyInvocation.MyCommand.Name)"
    }
    <#
.SYNOPSIS
    Retrieves Entra ID applications with privileged permissions.

.DESCRIPTION
Retrieves Entra ID applications with privileged permissions. This function identifies Enterprise Applications (service principals) granted high-risk permissions that could be leveraged for privilege escalation or lateral movement.
.PARAMETER ThrottleLimit
    Specifies the maximum number of concurrent operations that can be performed in parallel.
    Default value is 1000.

.PARAMETER OutputFormat
    Optional. Specifies the output format for results. Valid values are:
    - Object: Returns PowerShell objects (default when piping)
    - JSON: Creates timestamped JSON file (PrivilegedApps_TIMESTAMP.json) with no console output
    - CSV: Creates timestamped CSV file (PrivilegedApps_TIMESTAMP.csv) with no console output
    - Table: Returns results in a formatted table (default)
    Aliases: output, o

.PARAMETER IncludeOwners
    Optional. When specified, fetches application owner information. This adds API calls and processing time
    but provides complete ownership details. Owners are automatically included for Object, JSON, and CSV formats.
    For Table format, use this switch to include owner information.
    Aliases: include-owners, owners

.OUTPUTS
    Returns an array of PSCustomObjects containing the following properties:
    - Id: The unique identifier of the application
    - DisplayName: The display name of the application
    - Severity: Risk level (Critical, High, Medium, Low) based on permissions
    - CreatedDateTime: When the application was created
    - Permission: Array of high-risk permissions granted to the application
    - Owners: List of application owners
    - HasCredentials: Boolean indicating if password credentials are present
    - HasKeyCredentials: Boolean indicating if certificate credentials are present
    - PasswordCredentialExpiry: Earliest expiry date of password credentials (if any)
    - KeyCredentialExpiry: Earliest expiry date of key/certificate credentials (if any)
    - Credentials: (Optional) If present, contains password credentials information
    - KeyCredentials: (Optional) If present, contains certificate credentials information

.EXAMPLE
    Get-PrivilegedApp
    Returns all applications with high-risk permissions using default throttle limit and table format.
    Owners are not fetched for optimal performance.

.EXAMPLE
    Get-PrivilegedApp -IncludeOwners
    Returns all applications with high-risk permissions and includes owner information.

.EXAMPLE
    Get-PrivilegedApp -ThrottleLimit 500
    Returns all applications with high-risk permissions using a custom throttle limit of 500.

.EXAMPLE
    Get-PrivilegedApp -Verbose
    Returns all applications with high-risk permissions with detailed progress information.

.EXAMPLE
    Get-PrivilegedApp -OutputFormat JSON
    Creates a timestamped JSON file (e.g., PrivilegedApps_20250629_143022.json) in the current directory.
    No console output is displayed; only file creation confirmation message is shown.

.EXAMPLE
    Get-PrivilegedApp -OutputFormat CSV -ThrottleLimit 200
    Creates a timestamped CSV file (e.g., PrivilegedApps_20250629_143022.csv) in the current directory.
    Uses a throttle limit of 200. No console output is displayed; only file creation confirmation message is shown.

.EXAMPLE
    Get-PrivilegedApp -IncludeOwners -OutputFormat Table
    Returns privileged applications in table format with owner information included.

.NOTES
    File: Get-PrivilegedApp.ps1
    Author: Script Author
    Version: 1.0
    Requires: PowerShell 7.0 or later
    Requires: Microsoft Graph API access
    Requires: Appropriate permissions to read application information

    The function checks for the following high-risk permissions and assigns severity levels:

    CRITICAL severity permissions (broad administrative access/bypass security controls):
    - Directory.ReadWrite.All
    - PrivilegedAccess.ReadWrite.AzureAD
    - PrivilegedAccess.ReadWrite.AzureADGroup
    - PrivilegedAccess.ReadWrite.AzureResources
    - Policy.ReadWrite.ConditionalAccess

    HIGH severity permissions (privilege escalation/credential management):
    - RoleManagement.ReadWrite.Directory
    - Application.ReadWrite.All
    - GroupMember.ReadWrite.All
    - Group.ReadWrite.All

.LINK
    MITRE ATT&CK Tactic: TA0007 - Discovery
    https://attack.mitre.org/tactics/TA0007/

.LINK
    MITRE ATT&CK Technique: T1087.004 - Account Discovery: Cloud Account
    https://attack.mitre.org/techniques/T1087/004/

#>
}
