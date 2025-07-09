[![Mr Robot fonts](https://see.fontimg.com/api/renderfont4/g123/eyJyIjoiZnMiLCJoIjoxMjUsInciOjE1MDAsImZzIjo4MywiZmdjIjoiI0VGMDkwOSIsImJnYyI6IiMxMTAwMDAiLCJ0IjoxfQ/QiA3IDQgYyBLIEMgQCBU/mrrobot.png)](https://www.fontspace.com/category/mr-robot)

![logo](/.github/media/cateye.png?raw=true)

# CHANGELOG

## v0.20.6 [2025-07-09]

_Improvements_

**App Role Permission Discovery Enhancements:**
* **Enhanced `Get-AppRolePermission` function with emoji output and improved user experience**
  - Added emoji-enhanced progress indicators and status messages for better visual feedback
  - Implemented color-coded output for easy identification of results (✅ success, ❌ errors, 🔍 search)
  - Enhanced search feedback showing permission details (📋 Permission, 🏷️ Type, 🆔 App Role ID)
  - Improved error handling with clear visual indicators for not found scenarios
  - Added detailed function documentation highlighting the enhanced output capabilities
  - Maintains full compatibility with pipeline input and all existing functionality

**Storage Account Key Retrieval Enhancements:**
* **Enhanced `Get-StorageAccountKey` function with comprehensive output and statistics**
  - Added emoji-enhanced progress indicators and colored output similar to Get-KeyVaultSecret
  - Implemented comprehensive summary statistics including access denial tracking
  - Enhanced error categorization for RBAC vs. permission based access denials
  - **FIXED**: Corrected error handling to use RBAC terminology instead of Key Vault "access policy" references
  - Storage Accounts use Role-Based Access Control (RBAC) for management operations like listKeys, not access policies
  - Updated error patterns to specifically detect Azure RBAC role assignment and permission errors
  - Improved accuracy of error classification for Storage Account access scenarios
  - Added parallel processing with ConcurrentBag for thread-safe result and error aggregation
  - Implemented OutputFormat parameter (Object, JSON, CSV, Table) with file output for JSON/CSV
  - Added detailed error categorization and summary (RBAC denied, permission denied, not found, bad request, etc.)
  - Added verbose/debug output for error messages and HTTP status codes

## v0.20.5 [2025-07-09]

_Bug Fixes & Improvements_

**Key Vault Secret Discovery Improvements:**
* **Fixed `Get-KeyVaultSecret` function's access summary statistics**
  - Corrected counting logic for "Secrets Forbidden by Policy" in the summary output
  - Enhanced error detection to properly categorize and count policy vs. permission errors
  - Improved error pattern matching for various Azure Key Vault access denied scenarios
  - Added improved debug and verbose output for troubleshooting access issues
  - Fixed access summary always showing 0 counts even when access was denied
  - Enhanced fault tolerance and readability of summary statistics

## v0.20.2 [2025-07-08]

_Improvements_

**Enhanced Storage Container Discovery:**
* **Significant refactoring of `Find-PublicStorageContainer` function** for improved efficiency and error handling
  - Optimized DNS resolution process with better concurrent thread management
  - Enhanced container enumeration with improved parallel processing
  - Added more robust error handling for DNS resolution failures
  - Improved metadata handling with cleaner key-value formatting
  - Enhanced output formatting with better display of found containers and metadata
  - Optimized memory usage and performance for large-scale container discovery operations
  - Better handling of empty containers and content detection logic
  - Improved summary reporting with detailed statistics per storage account

**Code Quality & Cleanup:**
* Removed unnecessary system files (.DS_Store) from repository
* Streamlined code structure in storage container discovery functions
* Enhanced inline documentation and code readability

## v0.20.1 [2025-06-30]

_Bug Fixes_

* **Azure Token Compatibility**: Fixed authentication failures caused by newer Az.Accounts module versions returning SecureString tokens instead of plain strings
  - Added `ConvertFrom-AzAccessToken` helper function to handle both old (string) and new (SecureString) token formats
  - Updated `Invoke-BlackCat` and `New-AuthHeader` functions to use the new token conversion utility
  - Ensures backwards compatibility across all Az.Accounts module versions
  - Properly handles memory cleanup for SecureString tokens to prevent memory leaks
  - Resolves authentication issues with `Invoke-MsGraph` and other functions that depend on these core authentication functions

## v0.20.0 [2025-06-30]

**Major Release**

This major release represents a significant evolution of the BlackCat module with extensive enhancements to reconnaissance capabilities, new Azure service management functions, and substantial improvements to DNS analysis functionality. This version includes breaking changes and major feature additions that justify the version jump to 0.20.0.

_What's New_

**Enhanced DNS Reconnaissance Framework:**
* Completely redesigned `Find-DnsRecords` function with advanced DNS-over-HTTPS (DoH) support using multiple global providers
* Added support for 15+ DNS providers including Cloudflare, Google, Quad9, OpenDNS, and regional providers
* Implemented intelligent provider rotation and load balancing with reliability scoring
* Added comprehensive subdomain enumeration with categories (common, security, infrastructure, corporate, etc.)
* Enhanced CNAME detection with DNSSEC support and proxied CNAME resolution
* Added deep subdomain search capabilities with throttling controls
* Implemented detailed statistics and performance metrics

**Advanced Azure Service Tag Management:**
* Enhanced `Find-AzureServiceTag` function with significant improvements over the legacy `Get-ServiceTag`
* Implemented multiple IP address processing with pipeline support
* Added dynamic validation for service names and regions against loaded data
* Enhanced output formats including JSON, detailed tables, and structured objects
* Improved CIDR filtering and performance optimization for faster searches
* Added comprehensive parameter aliases for better CLI experience

**New Helper Functions:**
* Added `Update-AzureServiceTag` function for dynamic service tag updates from Microsoft APIs
* Enhanced `Select-AzureContext` function with improved Azure context management and tab completion
* Added `Show-BlackCatCommands` function to display all available BlackCat functions organized by MITRE ATT&CK categories

**Anonymous Reconnaissance Enhancements:**
* Improved `Get-PublicBlobContent` function with better parameter validation and error handling
* Added comprehensive test coverage for blob content functionality
* Enhanced URL parsing and validation with strict regex patterns
* Added `Find-SubDomain` function for automated subdomain enumeration with multiple category support
* Enhanced `Find-AzurePublicResource` function with additional Azure service domains and resource type mappings
* Added `Find-PublicStorageContainer` function for discovering publicly accessible Azure Storage containers

**Domain Security & Validation:**
* Added `Test-DomainRegistration` function for comprehensive domain validation and registration status checking
* Implemented support for multiple validation methods (RDAP, WHOIS, DNS)
* Added retry logic and rate limiting for RDAP service calls
* Enhanced domain validation with improved error handling and logging

**Function Renaming & Consolidation:**
* Renamed `Get-AccessTokens` to `Export-AzAccessToken` for better PowerShell naming conventions
* Renamed `Switch-Context` to `Select-AzureContext` for consistency with Azure cmdlets
* Renamed `Get-Functions` to `Show-BlackCatCommands` for clearer functionality indication
* Consolidated and removed deprecated functions for streamlined codebase

_Improvements_

**Performance & Reliability:**
* Implemented intelligent rate limiting and provider fallback mechanisms
* Added CIDR prefix filtering for faster IP address matching
* Enhanced error handling with graceful degradation
* Optimized memory usage for large-scale operations

**User Experience:**
* Added extensive Linux-friendly aliases throughout the module
* Improved parameter naming consistency across functions
* Enhanced verbose logging and debugging capabilities
* Added comprehensive help documentation and examples

**Module Organization & Structure:**
* Reorganized module manifest with categorized function exports (Credential Access, Discovery, Reconnaissance, etc.)
* Updated file list structure for better maintainability and organization
* Enhanced module version management and dependency handling
* Improved session variable management for subdomains and service tags

**Code Quality & Cleanup:**
* Removed deprecated functions: `Get-Functions`, `Get-PublicResourceList`, `Get-PublicStorageAccountList`, `Invoke-EnumSubDomains`
* Streamlined codebase by removing redundant functionality
* Enhanced function documentation and help examples
* Improved parameter aliases throughout the module for better usability

**Backward Compatibility:**
* Maintained aliases for renamed functions to ensure existing scripts continue working
* Preserved original functionality while adding enhancements
* Compatible output formats with additional properties

_Breaking Changes_

* `Get-ServiceTag` function has been superseded by `Find-AzureServiceTag` (alias maintained for backward compatibility)
* `Get-AccessTokens` renamed to `Export-AzAccessToken` (improved functionality and naming)
* `Switch-Context` renamed to `Select-AzureContext` (enhanced context management)
* `Get-Functions` renamed to `Show-BlackCatCommands` (better categorization and display)
* `Get-AzBlobContent` renamed to `Get-PublicBlobContent` (clearer functionality scope)
* Removed deprecated functions: `Get-PublicResourceList`, `Get-PublicStorageAccountList`, `Invoke-EnumSubDomains`
* Some function parameters have been renamed for consistency (aliases provided where possible)
* Enhanced validation may reject previously accepted invalid inputs (improved security)
* Module manifest structure reorganized (functions now categorized by MITRE ATT&CK tactics)

_Technical Enhancements_

* Integration with BlackCat session variables for user agent rotation
* Dynamic class-based parameter validation with `IValidateSetValuesGenerator`
* Enhanced pipeline processing capabilities across multiple functions
* Improved cross-platform PowerShell compatibility (Windows, Linux, macOS)
* Advanced DNS-over-HTTPS implementation with provider diversity and failover
* Intelligent service tag caching and dynamic updates from Microsoft APIs
* Enhanced subdomain enumeration with category-based filtering and throttling
* Improved Azure resource discovery with expanded service domain mapping

_Migration Guide_

**For users upgrading from versions 0.13.4 and earlier:**

1. **Function Renaming**: Update any scripts using renamed functions or use the provided aliases
2. **Parameter Changes**: Review parameter usage - aliases are provided for most changes
3. **New Functionality**: Take advantage of enhanced DNS reconnaissance and service tag features
4. **Testing**: Leverage the new comprehensive test coverage for validation
5. **Configuration**: Review module manifest changes if using custom imports

**Recommended immediate actions:**
```powershell
# Update function calls
Export-AzAccessToken  # instead of Get-AccessTokens
Select-AzureContext   # instead of Switch-Context
Show-BlackCatCommands # instead of Get-Functions
Find-AzureServiceTag  # instead of Get-ServiceTag

# New powerful features to explore
Find-DnsRecords -Domain "target.com" -EnumerateSubdomains
Find-SubDomain -Domain "target.com" -Category "all"
Test-DomainRegistration -Domain "suspicious.com"
```

## v0.13.5 [2025-06-17]

_What's New_

This update introduces several new functions for enhanced domain security assessment, Azure context management, and service tag lookups, plus improvements to existing functionality.

_New Functions_

* Added `Test-DomainRegistration` function for checking domain registration status using multiple methods (RDAP, WHOIS, DNS)
* Added `Get-PublicBlobContent` function to download or list files from public Azure Blob Storage accounts, including soft-deleted blobs
* Added `Find-AzureServiceTag` function to find and lookup Azure service tags by IP address, service name, or region with enhanced filtering
* Added `Select-AzureContext` function for improved Azure context management with tab completion and user-friendly display
* Added `Show-BlackCatCommands` function to display all available BlackCat functions with descriptions organized by category

_Improvements_

* Updated `subdomains.json` with expanded subdomain lists for enhanced reconnaissance capabilities, including new categories for security, media, education, infrastructure, and corporate subdomains
* Enhanced domain registration checking with support for multiple RDAP services, rate limiting handling, and fallback mechanisms
* Improved Azure service tag lookup with dynamic validation and better error handling
* Added comprehensive parameter validation and tab completion support across new functions
* Enhanced error handling and verbose logging throughout new functions

## v0.13.4 [2025-06-10]

_What's New_

This update introduces a new function `Test-DnsTwistDomain` that helps identify potential typosquatting domains that could be used in phishing attacks.

_Improvements_

* Added `Test-DnsTwistDomain` function to detect and assess typosquatting domains
* Implemented ten different typosquatting techniques including character omission, homoglyph attacks, and TLD variations
* Added risk scoring algorithm to prioritize potentially malicious domain registrations
* Created custom formatting to improve readability of results with color-coded risk levels
* Added comprehensive unit tests for the new functionality

## v0.13.3 [2025-06-07]

_What's New_

This update renames the `Get-AccessTokens` function to `Export-AzAccessToken` for improved user experience and better consistency with PowerShell naming conventions. The function now uses a more accurate verb (`Export`) and includes the standard Azure prefix (`Az`).

_Improvements_

* Renamed `Get-AccessTokens` to `Export-AzAccessToken` to better reflect its purpose of exporting tokens to a file or secure sharing service.
* Updated function documentation to use the new name in examples and descriptions.
* Updated module manifest to reference the new function name and file.

## v0.13.0 [2025-05-13]

_What's New_

This pull request introduces significant updates to the `BlackCat` module, including new functionality for managing Entra ID administrative units, enhancements to group management, and improved logging. The most notable changes are the addition of new cmdlets, the renaming and extension of an existing cmdlet, and the inclusion of verbose logging for better traceability.

### Administrative Unit Management:

* Added `Set-AdministrativeUnit` cmdlet to update properties (e.g., display name, membership type) of Entra ID administrative units and optionally include members in the output.
* Added `Get-AdministrativeUnits` cmdlet to retrieve administrative units by name or ObjectId, with support for including members in the output.


_Improvements_

### Group Management Enhancements:

* Renamed `Add-GroupOwner` to `Add-GroupObject` and extended functionality to allow adding both owners and members to Entra ID groups. Added a new `ObjectType` parameter to specify the role (`Owner` or `Member`).

### Logging Improvements:
* Enhanced verbose logging in `Invoke-BlackCat` to include the selected user agent for better debugging.

These changes improve the module's functionality and usability, particularly for managing Entra ID resources and debugging scripts.

## v0.12.7 [2025-05-11]

_What's New_

This pull request introduces a new PowerShell function, `Add-GroupOwner`, to add owners to Entra ID groups using the Microsoft Graph API. It also updates the module metadata and exports the new function. Below is a summary of the most important changes:

* Added the `Add-GroupOwner` function in `Public/Persistence/Add-GroupOwner.ps1`. This function allows users to add an owner to an Entra ID group by specifying various identifiers (e.g., ObjectId, display name, User Principal Name, etc.) and uses the Microsoft Graph API for execution. It includes robust parameter handling, error checking, and examples for usage.

## v0.12.6 [2025-04-18]

_What's New_

This update introduces several changes to the BlackCat PowerShell module, including a function rename, parameter enhancements, and improved filtering logic. The most significant changes involve renaming the `Get-AzureResourcePermission` function to `Lookup-ResourcePermission` and enhancing its parameters for better usability.

_Improvements_

* Renamed the `Get-AzureResourcePermission` function to `Get-ResourcePermission`
* Added new parameter attributes to `Get-ResourcePermission` for auto-completion, including `ResourceGroupCompleter`, `ResourceTypeCompleter`.
Additionally, renamed `ResourceGroup` to `ResourceGroupName` for clarity.

* Added a default value to the parameter set (`Other`) to the `Get-EntraInformation` function for additional use cases.
This improvements makes it possible to easily retrieve information about the current user context without parameters

## v0.12.5 [2025-04-14]

_Improvements_

* Improved processing of Graph requests from the `Invoke-MsGraph` function, and added aditional error handling.

## v0.12.4 [2025-04-10]

_Improvements_

- Enrichment of the `Get-EntraInformation` function, which now includes a flag if the user has a privileged role assigned.([#21](https://github.com/azurekid/blackcat/issues/21))

## v0.12.2 [2025-04-10]

_What's New_

This version introduces a new function `Get-EntraIDPermissions`
The changes improve the functionality for retrieving permissions and information from Microsoft Entra ID.

* [`Public/Reconnaissance/Get-EntraIDPermissions.ps1`](diffhunk://#diff-38586cd0181e130cae82c08363f103378100397dd69a5e6c79889f5bdd4f6854R1-R147):
Added the `Get-EntraIDPermissions` function to retrieve and list all permissions a user or group has in Microsoft Entra ID.
The function supports querying by `ObjectId`, `Name`, or `UserPrincipalName`, and can optionally display only the actions a user can perform using the `ShowActions` switch.

_Improvements_

* [`Public/Reconnaissance/Get-EntraInformation.ps1`](diffhunk://#diff-4f5cf40731d4b799069e33bf6122dd0477072c8d9e0d4ebfb24100f7b9ad5222R10-R16): Added support for querying by `UserPrincipalName` with validation for the UPN format.
- The function now includes additional details in the response, such as `RoleIds` and `AccountEnabled`. [[1]](diffhunk://#diff-4f5cf40731d4b799069e33bf6122dd0477072c8d9e0d4ebfb24100f7b9ad5222R10-R16) [[2]](diffhunk://#diff-4f5cf40731d4b799069e33bf6122dd0477072c8d9e0d4ebfb24100f7b9ad5222R47-R53) [[3]](diffhunk://#diff-4f5cf40731d4b799069e33bf6122dd0477072c8d9e0d4ebfb24100f7b9ad5222R90-R91)


## v0.12.1 [2025-04-10]

This version introduces new functionality to enhance the BlackCat module's capabilities and improve user experience. Several new functions have been added to extend the toolkit's feature set.

_What's New_

- Added `Get-AzureResourcePermissions` function to retrieve the current permissions a user has on Azure resources

_Improvements_

- Implemented caching mechanisms to reduce API calls and improve speed
- Added detailed help documentation for all new functions
- Updated parameter validation across multiple commands

## v0.12.0 [2025-04-09]

This version includes several significant changes to the BlackCat module, primarily focusing on enhancing the module's functionality and cleaning up outdated references. The most important changes include specifying the functions and files to export, removing outdated role definitions, and cleaning up unused references.

_Improvements_

#### Enhancements to module functionality:

- `BlackCat.psd1`: Updated FunctionsToExport to list specific functions instead of using wildcards, improving performance and clarity.
- `BlackCat.psd1`: Updated FileList to include specific files, ensuring all necessary scripts are packaged with the module.

#### Cleanup of outdated references:

`Private/Reference/AppRoleIds.csv`: Removed outdated role definitions to maintain current and relevant role information.
`Private/Reference/AzureRoles.csv`: Removed outdated role definitions to maintain current and relevant role information.
`Private/Reference/EntraRoles.csv`: Removed outdated role definitions to maintain current and relevant role information.
`Private/Reference/permutations.txt`: Removed unused permutations, cleaning up the file for better maintainability.
`Private/Reference/userAgents.json`: Removed outdated user agent strings to keep the file up-to-date with current user agents.
`Private/Reference/ServiceTags.json`: Removed outdated servicetags, latest version in installed when module is imported.

_What's New_

- Added aliasses to the function parameters for a more native cli / linux user experience.

## v0.11.0 [2025-04-09]

_Improvements_

- Updated functions to use `Invoke-AzBatch` and `Invoke-MsGraph` for consistency faster processing.
- Renamed functions for more clarity.
- Resolved `PSScriptAnalyzer` findings.
- Enhanced rotating User Agent to all Web Requests.
- Added documentation to several functions.
- Extended parameters and filtering.

## v0.10.5 [2025-04-07]

_Improvements_

- Simplified the `Update-AzConfig`.
- Added **PSGallery deployment**
- Enhanced the installation instructions in `README.md` by adding a section for installing from **PSGallery**.… in README

_Bug fixes_

- Removed the redundant update step for the `Az.Accounts` module in `BlackCat.psm1`. 

_Bug fixes_

- BlackCat is now available from the PSGallery

```powershell
Install-Module -Name BlackCat
Import-Module -Name BlackCat
```

## v0.10.4 [2025-04-06]

_Bug fixes_

- Resolved mismatching on custom roles ([#20](https://github.com/azurekid/blackcat/issues/20)).

_What's new?_

- Added `SkipCustom` to the `Get-RoleAssignments` function to improve performance in large environments. 

## v0.10.3 [2025-04-05]

_Improvements_

- Enhanced logging for better debugging ([#22](https://github.com/azurekid/blackcat/issues/22)).
- Updated dependencies to improve performance and security.

_Bug fixes_

- Resolved crash issue when loading large datasets ([#20](https://github.com/azurekid/blackcat/issues/20)).

## v0.10.2 [2025-04-02]

_Bug fixes_

- Fixed issue with user authentication ([#18](https://github.com/azurekid/blackcat/issues/18)).

_What's new?_

- Disable New logon experience Az.Accounts ([Login experience](https://learn.microsoft.com/en-us/powershell/azure/authenticate-interactive?view=azps-13.4.0#login-experience?wt.mc_id=SEC-MVP-5005184)).

## v0.10.1 [2025-03-31]

_Initial release_

## v0.0.1  [2024-12-24]

_Pre release_