[![Mr Robot fonts](https://see.fontimg.com/api/renderfont4/g123/eyJyIjoiZnMiLCJoIjoxMjIsInciOjE1MDAsImZzIjo4MywiZmdjIjoiI0VGMDkwOSIsImJnYyI6IiMxMTAwMDAiLCJ0IjoxfQ/QiA3IDQgYyBLIEMgQCBU/mrrobot.png)](https://www.fontspace.com/category/mr-robot)

![logo](/.github/media/cateye.png?raw=true)

# CHANGELOG

## v0.26.0 [2026-01-26] 🔧 Service Principal Support & Output Improvements

_Enhanced `-CurrentUser` functionality for Service Principal authentication_

**`Get-RoleAssignment` Improvements:**
* **Service Principal Authentication Support**: Fixed `-CurrentUser` parameter to work with Service Principal authentication
  - Previously failed with `/me request is only valid with delegated authentication flow` error
  - Now automatically detects authentication type (User vs Service Principal)
  - Uses Graph API to retrieve Service Principal's object ID when authenticated as SP
  - Retrieves group memberships for Service Principals for complete role enumeration
* **Improved Table Output**: Default table output now displays `RoleName` instead of `RoleId`
  - Table columns: `PrincipalType`, `PrincipalId`, `RoleName`, `Scope`
  - More readable output showing role names like "Contributor" instead of GUIDs

**New Function: `Get-FederatedIdentityCredential`**
* Retrieves federated identity credentials from User Assigned Managed Identities
* Supports querying all UAMIs or filtering by name/resource ID
* Highlights GitHub Actions trust relationships for security review
* Pipeline support: `Get-ManagedIdentity | Get-FederatedIdentityCredential`
* Multiple output formats: Table, JSON, CSV, Object

**`Set-FederatedIdentity` Improvements:**
* **New `-ManagedIdentityName` Parameter**: Specify managed identity by name instead of full resource ID
  - Automatically resolves the name to resource ID
  - Includes argument completer for tab-completion of available managed identities
  - Pipeline support: `Get-ManagedIdentity | Set-FederatedIdentity ...`
* Original `-Id` parameter still supported for full resource ID

**`Set-ManagedIdentityPermission` Improvements:**
* **New `-Remove` Switch**: Remove app role assignments from service principals
  - Automatically looks up existing assignments and deletes the matching one
  - Example: `Set-ManagedIdentityPermission -servicePrincipalId $id -CommonResource MicrosoftGraph -appRoleName "User.Read.All" -Remove`

**`Find-PublicStorageContainer` Improvements:**
* **`-IncludeEmpty` Now Defaults to `$true`**: Empty containers are now included by default
  - Previously required explicit `-IncludeEmpty` flag

**`Get-PublicBlobContent` Improvements:**
* **Breaking Change: Listing is Now Default Behavior**: The function now lists blobs by default
  - Replaced `-ListOnly` switch with `-Download` switch
  - Use `-Download -OutputPath <path>` to download files
  - Safer default behavior - no accidental downloads
  - Example: `Get-PublicBlobContent -BlobUrl $url` (lists files)
  - Example: `Get-PublicBlobContent -BlobUrl $url -OutputPath ./loot -Download` (downloads files)


## v0.24.0 [2025-10-15] 🚀 Performance Optimization & Usability Improvements

_Enhanced Service Principal Analysis & Permission Management_

**Optimized Service Principal Functions:**
* **`Get-ServicePrincipalsPermission` Major Enhancement**:
  - **Performance Boost**: Implemented Microsoft Graph batch API support, reducing multiple API calls to a single HTTP request
  - **Token Management**: Added intelligent token reuse to prevent unnecessary module reloads
  - **Comprehensive Data**: Now includes permission names along with IDs for better readability
  - **Complete Security Profile**: Added owned objects with type information for better attack surface analysis
  - **Enhanced Documentation**: Completely rewritten function documentation with security-focused examples.

**Improved Permission Management:**
* **`Set-ManagedIdentityPermission` Usability Enhancement**:
  - **Common Resource Support**: Added `CommonResource` parameter with predefined values for popular Azure services
  - **Simplified Syntax**: Eliminated need to manually look up resource IDs for common services
  - **Built-in Mapping**: Added support for Microsoft Graph, Azure Key Vault, Storage, and other common resources
  - **Improved Examples**: Added documentation showing simplified permission assignment patterns


## v0.23.2 [2025-09-22] 🛠️ PowerShell Compatibility & First-time Setup Fixes

_Reliability & Compatibility Enhancements_

**Compatibility Improvements:**
* **PowerShell Version Check Enhancement**: Updated version validation to execute in PowerShell 5.1
  - Modified SessionVariables hashtable format for compatibility with PowerShell 5.1
  - Added early termination with clear error message when incompatible PowerShell version is detected
  - Ensures proper version check happens before module attempts to load

**First-time Installation Fixes:**
* **Module Directory Structure**: Fixed issue with missing `Private/Reference` directory
  - Added automatic directory creation during first-time module import
  - Enhanced `Invoke-Update` function with proper path handling and error management
  - Added initialization block to ensure reference files are downloaded after functions are loaded
  - Improved error handling during first-time setup with graceful fallbacks

**Module Import Process Improvements:**
* Added more robust initialization sequence for reliable first-time setup
* Enhanced error messages with clear instructions for PowerShell version requirements
* Improved module loading flow with better directory management

## v0.23.1 [2025-09-22] 🛡️ Compatibility & Security Updates

_PowerShell 7 Compatibility Enforcement_

**Compatibility Improvements:**
* **Enhanced PowerShell Version Validation**: Fixed critical issue that prevented proper PowerShell 7+ enforcement
  - **Improved Error Handling**: Clear error messages when attempting to load in PowerShell 5.1
  - **Syntax Compatibility**: Modified module initialization to ensure PS 5.1 can parse version check
  - **Technical Debt**: Refactored hashtable declarations to maintain PS7-specific format while enabling validation
  - **Security**: Strengthened module integrity by preventing partial loading in unsupported environments

**Bug Fixes:**
* Fixed hashtable formatting issues that caused syntax errors during module import in PowerShell 5.1
* Improved exception handling for version validation to prevent cryptic error messages
* Enhanced module loading sequence to ensure proper environment validation

## v0.23.0 [2025-09-09] 🔍 Discovery & Output Enhancements

_Improvements & Function Standardization_

**Enhanced Discovery Functions:**
* **New `Find-AzurePermissionHolder` function for Microsoft Azure permission discovery**
  - **Standard Output Formatting**: Migrated to `Format-BlackCatOutput` for consistent results across all functions
  - **Enhanced Performance**: Implemented batch processing for subscription queries
  - **Intelligent Caching**: Improved cache key generation and data storage for repeated queries
  - **Improved UX**: Enhanced progress indicators and result summaries with rich formatting
  - **Robust Error Handling**: Better exception management and graceful fallbacks
  - **Performance Metrics**: Added execution statistics and analysis summaries
  - **Enhanced Documentation**: Improved help content and examples for better usability

* **New `Find-EntraPermissionHolder` function for Microsoft Entra ID permission discovery**
  - **Modern Identity Focus**: Specialized for Entra ID permission discovery and analysis
  - **Enhanced Role Analysis**: Deep inspection of Entra ID role assignments and permissions
  - **Cross-Platform Support**: Works seamlessly across all supported platforms
  - **Hierarchical Permission Mapping**: Advanced permission hierarchy understanding
  - **Directory-Wide Scanning**: Efficient scanning of entire tenant directories
  - **Rich Permission Analysis**: Detailed permission relationship mapping
  - **High-Performance Queries**: Optimized for large Entra ID tenants
  - **Standard Output Options**: Full support for all BlackCat output formats

**Enhanced Security & Stealth:**
* **Advanced UserAgent rotation system**
  - **Dynamic UserAgent Generation**: Intelligent rotation of realistic browser user-agents
  - **Platform-Aware Headers**: Customized headers that match the reported operating system
  - **Natural Patterns**: Mimics organic user behavior patterns to avoid detection
  - **Fingerprint Diversity**: Prevents correlation of requests across multiple sessions
  - **Automatic Header Management**: Seamlessly integrates with all API requests
  - **Low Detection Profile**: Reduces the risk of being blocked by security monitoring systems
  - **Enhanced Privacy**: Minimizes trackable footprints during sensitive operations
  - **Configurable Behavior**: Adjustable rotation frequency and pattern settings
=======
## v0.22.1 [2025-09-05] 🐞 Bug Fixes & Compatibility

_Bug Fixes_

* **PowerShell 5.1 Import Error:**
  - The module previously failed to import in Windows PowerShell 5.1 due to unsupported syntax. BlackCat now clearly requires PowerShell 7.0 or higher and the Az.Accounts module. Documentation and manifest have been updated to reflect this requirement. ([#70](https://github.com/azurekid/blackcat/issues/70))
  - Users on PowerShell 5.1 will see a requirement notice and should upgrade to PowerShell 7+ for full compatibility.

_Improvements_

* Updated README and module manifest to list PowerShell 7+ and Az.Accounts as prerequisites.
* Minor documentation and code cleanups for clarity and maintainability.

## v0.22.0 [2025-08-25] 🔐 Security & UX Enhancements

_Improvements & New Features_

**Enhanced Stealth Operations:**
* **Enhanced `Invoke-StealthOperation` with color output and improved timezone handling**
  - 🌈 **Colorized Status Messages**: Added colored output for improved visual feedback
  - 🌍 **Improved Timezone Handling**: Enhanced custom UTC offset support with validation
  - 🏢 **Business Hours Descriptions**: Added country/timezone descriptions to delay messages
  - ⏰ **Waiting Period Feedback**: Enhanced messages for business hours/lunch breaks with proper formatting
  - 🎭 **Emoji Context Awareness**: Dynamic emoji selection based on configuration
  - 🛡️ **Robust Error Handling**: Improved fallback behavior for invalid timezone specifications
  - 🔍 **Enhanced Verbose Logging**: Better tracking of configuration selection and timing decisions

**Azure Identity & Authentication Security:**
* **Added UAMI-based App Escalation workflow**
  - 🆔 **GitHub OIDC Integration**: Implemented secure token exchange using OIDC tokens
  - 🔄 **Two-Stage Token Exchange**: OIDC → UAMI → Application token flow
  - 🛡️ **Audience Validation**: Strict validation of token audiences for enhanced security
  - 🔐 **No-CLI Authentication**: Pure API-based authentication without Azure CLI dependency
  - 🧪 **Automated Verification**: Built-in token validation and smoke testing
  - 📝 **Detailed Documentation**: Comprehensive comments explaining the OAuth 2.0 token flow
  - ⚙️ **GitHub Actions Integration**: Ready-to-use workflow for secure token acquisition

**Module Improvements:**
* **Enhanced Security Documentation**: Added comprehensive documentation on token-based authentication techniques
* **Code Quality**: Improved error handling and parameter validation across multiple functions
* **Performance Optimization**: Enhanced parallelization and resource management

## v0.21.0 [2025-07-09] 🚀 Major Cache Analytics Release

_New Features & Major Enhancements_

**Revolutionary Cache Analytics System:**
* **Completely redesigned `Get-BlackCatCacheStats` function with enterprise-grade analytics**
  - 🎯 **Advanced Filtering Engine**: 15 new parameters including FilterExpired, FilterValid, FilterCompressed, FilterLarge, MinSize, MaxAge
  - 📊 **Sophisticated Analytics**: Performance metrics, trend analysis, distribution histograms, and predictive insights
  - 🔍 **Enhanced Sorting**: 6 sorting options (Timestamp, Size, Key, ExpirationTime, Age, TTL) for comprehensive data organization
  - 📈 **Trend Analysis**: Growth rate calculations, peak usage patterns, cache freshness metrics, and usage predictions
  - 📊 **Distribution Histograms**: Visual size and age distribution analysis with ASCII bar charts and statistical breakdowns
  - 💾 **Multi-Format Export**: 6 output formats (Summary, Table, List, JSON, CSV, XML) with automatic file export capabilities
  - 🎨 **Enhanced Visual Dashboard**: Color-coded metrics, emoji indicators, comprehensive performance visualization
  - 🧠 **Intelligent Recommendations**: Context-aware optimization suggestions, memory usage analysis, compression recommendations
  - 🔧 **Performance Optimization**: Hit rate analysis, cache utilization metrics, memory density calculations
  - 📋 **Programmatic Interface**: Quiet mode for automated scripts, structured data objects for integration
  - ⚡ **Advanced Performance Metrics**: Hit rates, cache utilization, memory efficiency, compression ratios, turnover rates
  - 🚀 **Predictive Analysis**: Cache growth predictions, usage pattern analysis, maintenance recommendations

* **Enhanced Cache Management Functions:**
  - **Universal Cache System**: Implemented LRU (Least Recently Used) eviction, compression support, configurable expiration
  - **Memory Management**: Advanced memory optimization with size-based eviction and compression ratios
  - **Cache Integration**: Seamless integration with core functions (Invoke-MSGraph, Invoke-AzBatch, Get-RoleAssignment)
  - **Parameter Standardization**: Consistent cache parameters across all functions (SkipCache, CacheExpirationMinutes, MaxCacheSize, CompressCache)

**Core Function Cache Integration:**
* **Enhanced `Get-RoleAssignment` function with comprehensive cache support**
  - Added full cache parameter support: `-SkipCache`, `-CacheExpirationMinutes`, `-MaxCacheSize`, `-CompressCache`
  - Implemented intelligent cache key generation based on subscription, filters, and PIM settings
  - Added cache-aware processing with automatic cache management and cleanup
  - Enhanced performance for repeated role assignment queries across multiple subscriptions
  - Maintains full compatibility with all existing functionality including PIM eligible assignments

* **Enhanced `Invoke-MSGraph` and `Invoke-AzBatch` functions with advanced caching**
  - Updated cache integration with new parameter support and LRU management
  - Improved cache key generation for better cache hit rates
  - Enhanced memory management with compression support
  - Optimized performance for large-scale API operations

**Module Architecture Improvements:**
* **Modular Function Organization**: Split multi-function files into individual function files for better module compatibility
* **Enhanced Module Loading**: Updated BlackCat.psd1 manifest with comprehensive function exports and file listings
* **Function Export Standardization**: All cache management functions properly exported and available after module import
* **Documentation Updates**: Comprehensive documentation for all new cache features and advanced analytics

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

**Role Assignment Discovery Enhancements:**
* **Enhanced `Get-RoleAssignment` function with duration tracking and improved performance monitoring**
  - Added comprehensive duration tracking from start to completion of role assignment analysis
  - Enhanced summary statistics to include execution time in seconds with precise formatting
  - Provides users with valuable timing information for performance optimization
  - Duration tracking works consistently across all output formats (Table, JSON, CSV, Object)
  - Helps users understand performance characteristics when dealing with multiple subscriptions or large result sets

* **Added PIM (Privileged Identity Management) eligible role assignment support**
  - Added `-IncludeEligible` parameter (aliases: `include-eligible`, `eligible`) to query PIM eligible assignments
  - Integrated Microsoft.Authorization/roleEligibilityScheduleInstances API for comprehensive PIM discovery
  - Enhanced role assignment objects with `IsEligible` property to distinguish active vs. eligible assignments
  - Added PIM-specific properties: `StartDateTime`, `EndDateTime`, and `Status` for eligible assignments
  - Improved summary statistics with breakdown of active vs. eligible assignment counts
  - Maintains full compatibility with all existing filtering options (PrincipalType, ObjectId, etc.)
  - Uses parallel processing for optimal performance when querying eligible assignments across subscriptions
  - Enhanced error handling for scenarios where PIM might not be available or accessible
  - Updated comprehensive help documentation with PIM-related examples and parameter descriptions

**Entra ID Information Discovery Enhancements:**
* **Enhanced `Get-EntraInformation` function with automatic object type detection**
  - Added intelligent automatic fallback for ObjectId queries
  - When querying by ObjectId without the -Group switch, automatically attempts group query if user query fails
  - Eliminates need to manually specify -Group switch when uncertain about object type
  - Enhanced verbose logging to track query attempts and results
  - Improved error handling with detailed error message classification
  - Distinguishes between "resource not found" errors vs. permission/access errors
  - Only attempts automatic group fallback for genuine "not found" scenarios
  - Provides specific error messages when ObjectId doesn't exist in Azure AD
  - Enhanced error pattern matching to catch various forms of "does not exist" messages
  - Updated help documentation with examples demonstrating automatic fallback behavior
  - Maintains backward compatibility with existing explicit -Group parameter usage

**Microsoft Graph API Core Enhancements:**
* **Enhanced `Invoke-MsGraph` function with robust retry logic and throttling management**
  - Added configurable retry mechanism with `-MaxRetries` parameter (default: 3 attempts)
  - Implemented intelligent exponential backoff with `-RetryDelaySeconds` parameter (default: 5 seconds)
  - Enhanced throttling detection and automatic retry handling for HTTP 429 responses
  - Added support for Microsoft Graph "Retry-After" header compliance
  - Improved error handling with specific detection for unauthorized (401) errors
  - Enhanced verbose logging for API calls and retry attempts
  - Robust error message extraction from Graph API JSON error responses
  - Graceful handling of batch vs. non-batch requests with consistent retry behavior
  - Prevents unnecessary retries for authorization failures while maintaining resilience for transient errors
  - Maintains backward compatibility with existing Graph API call patterns
  - Added `OutputFormat` parameter with support for Object, JSON, CSV, and Table formats
  - JSON and CSV outputs are automatically saved to timestamped files (MSGraphResult_YYYYMMDD_HHMMSS.json/csv)
  - Table format provides formatted output using Format-Table -AutoSize for improved readability
  - Object format maintains default behavior returning raw PowerShell objects
  - Includes parameter aliases ("output", "o") for convenient command-line usage
  - Enhanced function documentation with comprehensive parameter descriptions and usage examples
  - Maintains full compatibility with all existing functionality including batch processing and retry logic

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