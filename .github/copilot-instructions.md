# GitHub Copilot Instructions for BlackCat Module

This document provides comprehensive guidelines for GitHub Copilot to ensure all content created for the BlackCat module maintains consistency, quality, and adherence to established patterns.

---

## 1. Module Overview

**BlackCat** is a PowerShell module designed to validate and analyze the security of Microsoft Azure and Entra ID environments. It provides tools for:
- Azure resource discovery and enumeration
- Permission analysis and privilege escalation identification
- Credential access and exfiltration testing
- Security configuration assessment

**Current Version:** 0.32.0 (as of 2026-02-06)
**Target Environment:** PowerShell 7.0 or higher
**Required Modules:** Az.Accounts (minimum 3.0.0)

---

## 2. MITRE ATT&CK Alignment

All functions must be aligned with MITRE ATT&CK tactics. Every public function MUST include:

```powershell
.LINK
MITRE ATT&CK Tactic: TA0007 - Discovery
https://attack.mitre.org/tactics/TA0007/

.LINK
MITRE ATT&CK Technique: T1087.004 - Account Discovery: Cloud Account
https://attack.mitre.org/techniques/T1087/004/
```

### Supported Categories (Folder Organization)

- **Credential Access**: Functions for obtaining credentials (e.g., `Get-KeyVaultSecret`)
- **Discovery**: Functions for resource enumeration and analysis (e.g., `Get-EntraIDPermissions`)
- **Exfiltration**: Functions for exfiltrating data (e.g., `Export-AzAccessToken`, `Get-FileShareContent`)
- **Helpers**: Utility and API interaction functions (e.g., `Invoke-MsGraph`)
- **Impair Defenses**: Functions for disabling security controls (e.g., `Set-AzNetworkSecurityGroupRule`)
- **Initial Access**: Functions for gaining initial access (e.g., `Connect-GraphToken`)
- **Persistence**: Functions for maintaining access (e.g., `Set-ServicePrincipalCredential`)
- **Reconnaissance**: Functions for external unauthenticated enumeration (e.g., `Find-PublicStorageContainer`)
- **Resource Development**: Functions for creating resources (e.g., `Add-EntraApplication`)

---

## 3. Version Management & Changelog Requirements

**CRITICAL: Every new feature or modification MUST include both version bump and changelog update.**

### Version Format

Version follows semantic versioning: `MAJOR.MINOR.PATCH` (e.g., 0.32.0)

**Update rules:**
- **MAJOR.MINOR bump**: New functions, significant features, breaking changes
- **PATCH bump**: Bug fixes, improvements to existing functions

### Location: BlackCat.psd1

```powershell
@{
    ModuleVersion = '0.32.0'  # UPDATE THIS
    # ... rest of manifest
}
```

### Changelog Update Requirements

**File:** `CHANGELOG.md`

Every update must have a changelog entry at the TOP of the file following this format:

```markdown
## v0.33.0 [2026-02-10] 🎯 Feature Category & Enhancement Type

_Brief description of what this release focuses on_

**New Function: `Get-ExampleFunction`** (if adding new functions)
* Brief description of function
* Key capability 1
* Key capability 2
* Example usage

**`ExistingFunction` Improvements:** (if modifying existing functions)
* **Breaking Change** (if applicable): Description
* Feature added: Description
* Performance improvement: Description

**Module Enhancements:**
* Enhancement 1
* Enhancement 2

**Bug Fixes:**
* Fixed issue 1
* Fixed issue 2

---
```

**Important:**
- Use emoji to categorize changes (🎯, 🚀, 🔍, 🛡️, 📁, etc.)
- Include date in format [YYYY-MM-DD]
- Document breaking changes clearly
- List all new functions with descriptions
- Explain all improvements with sufficient detail

---

## 4. Function Structure & Standards

### Naming Conventions

**Approved Verbs (following PowerShell guidelines):**
- `Get-*`: Retrieve data
- `Find-*`: Search/discover resources
- `Set-*`: Modify/establish settings or persistence
- `Add-*`: Create new resources
- `Invoke-*`: Execute operations
- `Export-*`: Output data (files, exfiltration)
- `Restore-*`: Recover deleted resources
- `Connect-*`: Establish connections
- `Clear-*`: Remove/reset cache
- `Update-*`: Refresh data
- `New-*`: Create objects
- `Select-*`: Choose/filter
- `Optimize-*`: Improve performance
- `Analyze-*`: Examine for vulnerabilities
- `Convert-*`: Transform data formats

### Function Signature Template

```powershell
function Get-ExampleFunction {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$PropertyName,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Object', 'JSON', 'CSV', 'Table')]
        [Alias('output', 'o')]
        [string]$OutputFormat = 'Object',

        [Parameter(Mandatory = $false)]
        [int]$ThrottleLimit = 10
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
        
        $startTime = Get-Date
        $stats = @{
            TotalProcessed = 0
            SuccessCount = 0
            ErrorCount = 0
        }
    }

    process {
        try {
            # Implementation details
        }
        catch {
            Write-Warning "Error: $($_.Exception.Message)"
            $stats.ErrorCount++
        }
    }

    end {
        $duration = (Get-Date) - $startTime
        
        Write-Host "`nFunction Summary:" -ForegroundColor Cyan
        Write-Host "   Total Processed: $($stats.TotalProcessed)" -ForegroundColor White
        Write-Host "   Success: $($stats.SuccessCount)" -ForegroundColor Green
        Write-Host "   Errors: $($stats.ErrorCount)" -ForegroundColor Red
        Write-Host "   Duration: $($duration.TotalSeconds.ToString('F2')) seconds" -ForegroundColor White
        
        Write-Verbose "Completed function $($MyInvocation.MyCommand.Name)"

        # Return formatted output
        Format-BlackCatOutput -Data $results -OutputFormat $OutputFormat -FunctionName $MyInvocation.MyCommand.Name
    }

    <#
    .SYNOPSIS
        Brief description (MAX 83 characters).

    .DESCRIPTION
        Comprehensive description of what the function does, its purpose,
        and when to use it. Can span multiple lines.

    .PARAMETER PropertyName
        Description of the parameter, its purpose, and accepted values.

    .PARAMETER OutputFormat
        Specifies the output format: Object, JSON, CSV, or Table.
        Default is Object.

    .PARAMETER ThrottleLimit
        Limits concurrent operations for performance tuning.
        Default is 10.

    .EXAMPLE
        Get-ExampleFunction -PropertyName "value"
        
        Description of what this example does.

    .EXAMPLE
        Get-ExampleFunction -PropertyName "value" -OutputFormat JSON
        
        Description of what this example does.

    .OUTPUTS
        [PSCustomObject]
        Returns objects with properties:
        - Property1: Description
        - Property2: Description

    .NOTES
        Author: BlackCat Security Framework
        Requires: MSGraph API permissions
        
        This function requires the following permissions:
        - Directory.Read.All
        - Application.Read.All

    .LINK
        MITRE ATT&CK Tactic: TA0007 - Discovery
        https://attack.mitre.org/tactics/TA0007/

    .LINK
        MITRE ATT&CK Technique: T1087.004 - Account Discovery: Cloud Account
        https://attack.mitre.org/techniques/T1087/004/
    #>
}
```

---

## 5. Parameter Standards

### Common Parameters

**Always include these when applicable:**

```powershell
[Parameter(Mandatory = $false)]
[ValidateSet('Object', 'JSON', 'CSV', 'Table')]
[Alias('output', 'o')]
[string]$OutputFormat = 'Object'

[Parameter(Mandatory = $false)]
[int]$ThrottleLimit = 10

[Parameter(Mandatory = $false)]
[switch]$SkipCache

[Parameter(Mandatory = $false)]
[int]$CacheExpirationMinutes = 30

[Parameter(Mandatory = $false)]
[int]$MaxCacheSize = 100

[Parameter(Mandatory = $false)]
[switch]$CompressCache
```

### Parameter Validation

Use `ValidateSet`, `ValidatePattern`, `ValidateRange`, `ValidateNotNull`, `ValidateLength` where appropriate.

Example:
```powershell
[ValidatePattern('^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$', ErrorMessage = "Invalid GUID format")]
[string]$ObjectId
```

---

## 6. Output Formatting Standards

### Required Output Function Usage

All functions must use the standardized output formatter:

```powershell
Format-BlackCatOutput -Data $results -OutputFormat $OutputFormat -FunctionName $MyInvocation.MyCommand.Name
```

### Output Format Support

Every public function with discovery/enumeration purposes MUST support:
- **Object**: Raw PowerShell objects (default)
- **JSON**: JSON formatted export with timestamp
- **CSV**: Comma-separated values with timestamp
- **Table**: Formatted table view

### Custom Objects

Return `[PSCustomObject]` with meaningful property names:

```powershell
$result = [PSCustomObject]@{
    'Id'              = $resource.id
    'DisplayName'     = $resource.displayName
    'Type'            = $resource.Type
    'CreatedDateTime' = $resource.createdDateTime
    'IsEnabled'       = $resource.accountEnabled
    'RiskLevel'       = 'High'  # Security-relevant properties
}
```

---

## 7. Authentication & Session Management

### Required Authentication Pattern

Every function MUST initialize with:

```powershell
begin {
    Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
    $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'  # or 'Azure'
}
```

### Supported ResourceTypes

- `MSGraph`: Microsoft Graph API
- `Azure`: Azure Resource Manager API
- Default: Auto-detection based on function purpose

---

## 8. Help Documentation Requirements

### Minimum Documentation Requirements

Every public function MUST have:

```powershell
<#
.SYNOPSIS
description (EXACTLY 83 characters max - MEASURE THIS!)

.DESCRIPTION
Detailed description with context and use cases.

.PARAMETER ParameterName
Clear explanation of what this parameter does.

.EXAMPLE
Real-world usage example.
This example demonstrates...

.OUTPUTS
Type and structure of returned objects.

.NOTES
Important notes about permissions, limitations, prerequisites.

.LINK
MITRE ATT&CK references (if applicable)
#>
```

**CRITICAL: SYNOPSIS MUST NOT EXCEED 83 CHARACTERS**

---

## 9. Coding Standards

### Line Length

- **Maximum line length: 80 characters** (with rare exceptions for long URLs)
- Use line continuation where needed

### Indentation

- Use 4 spaces (never tabs)
- Consistent indentation throughout

### Comments

- Use `#` for inline comments
- Use `<# ... #>` for block comments before functions
- Keep comments concise and meaningful

### Variable Naming

- Use PascalCase for function names: `Get-ExampleFunction`
- Use camelCase for variables: `$myVariable`
- Use UPPER_SNAKE_CASE for constants: `$API_VERSION = '2024-11-01'`
- Use descriptive names: `$servicePrincipals` not `$sp`

### Operators

- Use `-eq` not `==`
- Use `-ne` not `!=`
- Use `-and` not `&&`
- Use `-or` not `||`
- Use `-not` not `!`

---

## 10. Performance Best Practices

### Batch API Usage

**ALWAYS use batch processing for multiple API calls:**

```powershell
$batchRequests = @(
    @{ id = "1"; method = "GET"; url = "/users" },
    @{ id = "2"; method = "GET"; url = "/groups" }
)
$results = Invoke-MsGraph -BatchRequests $batchRequests
```

### Parallel Processing

Use `ForEach-Object -Parallel` for large datasets:

```powershell
$items | ForEach-Object -Parallel {
    # Process with proper variable scoping
} -ThrottleLimit $ThrottleLimit
```

### Caching

Leverage BlackCat's caching for repeated calls:

```powershell
$cacheKey = "Function-Key-$($PropertyName)"
$cached = Get-BlackCatCache -Key $cacheKey
if ($cached) { return $cached }

# ... perform operation ...

Set-BlackCatCache -Key $cacheKey -Data $results -ExpirationMinutes 30
```

---

## 11. Error Handling

### Standardized Error Pattern

```powershell
try {
    # Operation
    $result = Invoke-MsGraph -relativeUrl $url
}
catch {
    Write-Warning "Failed to retrieve data: $($_.Exception.Message)"
    Write-Verbose "Stack Trace: $($_.ScriptStackTrace)"
    $stats.ErrorCount++
    continue  # or handle appropriately
}
```

### Error Messages

- Always include context about what failed
- Use `Write-Warning` for recoverable errors
- Use `Write-Error` only for critical failures
- Use `Write-Verbose` for diagnostic information

---

## 12. File Organization

### Public Function Files

Location: `Public/<Category>/<Verb>-<Noun>.ps1`

Examples:
- `Public/Discovery/Get-EntraIDPermissions.ps1`
- `Public/Persistence/Set-ServicePrincipalCredential.ps1`
- `Public/Helpers/Invoke-MsGraph.ps1`

### Private Function Files

Location: `Private/<Verb>-<Noun>.ps1`

Examples:
- `Private/Invoke-BlackCat.ps1`
- `Private/Get-AccessToken.ps1`
- `Private/Use-BlackCatCache.ps1`

---

## 13. Module Manifest Updates

When adding new functions, update `BlackCat.psd1`:

### FunctionsToExport

Add new public functions to the appropriate category:

```powershell
FunctionsToExport = @(
    # Credential Access
    'Get-KeyVaultSecret',
    'Get-StorageAccountKey',
    'Get-NewFunction',  # Add here
    
    # ... more categories ...
)
```

### FileList

Add the file path:

```powershell
FileList = @(
    # Credential Access
    'Public\Credential Access\Get-KeyVaultSecret.ps1',
    'Public\Credential Access\Get-NewFunction.ps1',  # Add here
    
    # ... rest of files ...
)
```

---

## 14. Quality Checklist

Before marking code as complete, verify:

- [ ] Function has clear, concise purpose
- [ ] SYNOPSIS is ≤ 83 characters
- [ ] All parameters are documented
- [ ] All examples work correctly
- [ ] Error handling is comprehensive
- [ ] Output format options work (Object/JSON/CSV/Table)
- [ ] Performance is optimized (batch API, caching, parallel)
- [ ] Code follows 80-character line limit
- [ ] 4-space indentation throughout
- [ ] MITRE ATT&CK references included
- [ ] Version number updated in `BlackCat.psd1`
- [ ] Changelog entry added to `CHANGELOG.md` (at TOP with date)
- [ ] FileList updated in `BlackCat.psd1` (if new public function)
- [ ] FunctionsToExport updated in `BlackCat.psd1` (if new public function)
- [ ] Module manifest syntax is valid

---

## 15. Example Complete Function

```powershell
function Get-ExampleAzureUsers {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$Filter,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Object', 'JSON', 'CSV', 'Table')]
        [Alias('output', 'o')]
        [string]$OutputFormat = 'Object',

        [Parameter(Mandatory = $false)]
        [int]$ThrottleLimit = 10
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
        
        $startTime = Get-Date
        $stats = @{
            TotalRetrieved = 0
            SuccessCount = 0
            ErrorCount = 0
        }
    }

    process {
        try {
            $url = if ($Filter) { 
                "users?`$filter=$Filter&`$select=id,displayName,userPrincipalName,createdDateTime,accountEnabled"
            }
            else {
                "users?`$select=id,displayName,userPrincipalName,createdDateTime,accountEnabled"
            }
            
            $users = Invoke-MsGraph -relativeUrl $url
            $stats.TotalRetrieved = $users.Count

            $results = @()
            foreach ($user in $users) {
                $results += [PSCustomObject]@{
                    'Id'                = $user.id
                    'DisplayName'       = $user.displayName
                    'UserPrincipalName' = $user.userPrincipalName
                    'CreatedDateTime'   = $user.createdDateTime
                    'IsEnabled'         = $user.accountEnabled
                }
            }
            
            $stats.SuccessCount = $results.Count
        }
        catch {
            Write-Warning "Error retrieving users: $($_.Exception.Message)"
            Write-Verbose "Stack Trace: $($_.ScriptStackTrace)"
            $stats.ErrorCount++
        }
    }

    end {
        $duration = (Get-Date) - $startTime
        
        Write-Host "`nUser Retrieval Summary:" -ForegroundColor Cyan
        Write-Host "   Total Retrieved: $($stats.TotalRetrieved)" -ForegroundColor White
        Write-Host "   Success: $($stats.SuccessCount)" -ForegroundColor Green
        Write-Host "   Errors: $($stats.ErrorCount)" -ForegroundColor Red
        Write-Host "   Duration: $($duration.TotalSeconds.ToString('F2')) seconds" -ForegroundColor White
        
        Write-Verbose "Completed function $($MyInvocation.MyCommand.Name)"

        Format-BlackCatOutput -Data $results -OutputFormat $OutputFormat `
            -FunctionName $MyInvocation.MyCommand.Name
    }

    <#
    .SYNOPSIS
        Retrieves Azure users with optional filtering and multiple output formats.

    .DESCRIPTION
        Retrieves Entra ID users from Microsoft Graph API with support for filtering,
        parallel processing, and multiple output formats. Essential for user discovery
        and security analysis in Azure environments.

    .PARAMETER Filter
        Optional OData filter string to restrict returned users (e.g., 
        "accountEnabled eq true").

    .PARAMETER OutputFormat
        Specifies the output format: Object (default), JSON, CSV, or Table.

    .PARAMETER ThrottleLimit
        Limits concurrent operations for performance tuning. Default is 10.

    .EXAMPLE
        Get-ExampleAzureUsers
        
        Retrieves all Azure users and returns as PowerShell objects.

    .EXAMPLE
        Get-ExampleAzureUsers -Filter "accountEnabled eq true" -OutputFormat JSON
        
        Retrieves enabled users only and exports to timestamped JSON file.

    .OUTPUTS
        [PSCustomObject]
        Returns objects with properties:
        - Id: User object ID (GUID)
        - DisplayName: User display name
        - UserPrincipalName: UPN
        - CreatedDateTime: Account creation date
        - IsEnabled: Account enabled status

    .NOTES
        Author: BlackCat Security Framework
        Requires: MSGraph API access
        
        Required permissions:
        - User.Read.All
        - Directory.Read.All

    .LINK
        MITRE ATT&CK Tactic: TA0007 - Discovery
        https://attack.mitre.org/tactics/TA0007/

    .LINK
        MITRE ATT&CK Technique: T1087.003 - Account Discovery
        https://attack.mitre.org/techniques/T1087/003/
    #>
}
```

---

## 16. Changelog Entry for This Update

When creating new functions or features, ALWAYS update `CHANGELOG.md`:

```markdown
## v0.33.0 [2026-02-10] 🔍 Enhanced User Discovery

_New functions and improvements for Azure user enumeration_

**New Function: `Get-ExampleAzureUsers`**
* Retrieves Entra ID users with flexible filtering
* Supports multiple output formats (Object, JSON, CSV, Table)
* Optimized for large environments with parallel processing
* Example: `Get-ExampleAzureUsers -Filter "accountEnabled eq true"`

**Updates to Module Manifest:**
* Added `Get-ExampleAzureUsers` to FunctionsToExport
* Updated FileList with new function path

---
```

---

## Summary of Key Rules

1. **ALWAYS update version number** in `BlackCat.psd1` when making changes
2. **ALWAYS add changelog entry** to `CHANGELOG.md` (at the top with current date)
3. **SYNOPSIS must be ≤ 83 characters** - this is enforced
4. **Every function must include MITRE ATT&CK references**
5. **Use batch API** for multiple operations
6. **Support all output formats**: Object, JSON, CSV, Table
7. **80-character line limit** (use line continuation for URLs)
8. **4-space indentation** (never tabs)
9. **Update module manifest** when adding new public functions
10. **Follow PowerShell naming conventions** with approved verbs

---

**Last Updated:** 2026-02-06  
**Module Version:** 0.32.0  
**For Questions:** Refer to CONTRIBUTING.md and existing functions as examples
