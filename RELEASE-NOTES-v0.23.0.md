# BlackCat v0.23.0 Release Summary

## 📋 Overview

BlackCat v0.23.0 continues our commitment to standardization, performance, and user experience by modernizing key discovery functions to follow BlackCat's established design patterns. This release focuses on enhancing the `Find-AzurePermissionHolder` function, bringing it in line with the module's best practices while improving its usability and performance.

## 📝 Release Summary

**What's New at a Glance:**
* Modernized `Find-AzurePermissionHolder` with standard BlackCat patterns
* Added new `Find-EntraPermissionHolder` for Microsoft Entra ID permission discovery
* Implemented consistent output formatting using `Format-BlackCatOutput`
* Enhanced performance through batch processing and optimized API calls
* Advanced UserAgent rotation system for improved security and stealth
* Improved user experience with better progress indicators and error handling
* Added comprehensive documentation and usage examples

**Key Benefits:**
* Faster permission discovery across both Azure resources and Entra ID
* Consistent experience across all BlackCat module functions
* Enhanced reporting capabilities with standardized output options
* Improved security posture with advanced UserAgent management
* More intelligent caching for repeated operations
* Reduced detection risk during sensitive operations

## What's New in v0.23.0

### **Enhanced Discovery Capabilities**

#### **New Find-AzurePermissionHolder Improvements**
```powershell
# Standard search for permission holders
Find-AzurePermissionHolder -Permission "Microsoft.KeyVault/vaults/accessPolicies/write"

# With performance metrics and comprehensive output
Find-AzurePermissionHolder -Permission "Microsoft.Compute/virtualMachines/start/action" -OutputFormat JSON

# Multi-permission search with batch processing
Find-AzurePermissionHolder -Permission @(
  "Microsoft.Authorization/roleAssignments/write",
  "Microsoft.Authorization/roleDefinitions/write"
) -OutputFormat Table
```

#### **New Find-EntraPermissionHolder Function**
```powershell
# Standard search for Entra ID permission holders
Find-EntraPermissionHolder -Permission "microsoft.directory/applications/appRoles/update"

```

### **Function Standardization**

The following improvements have been made to ensure consistency across the module:

- **Standardized Output Formatting**: Implemented `Format-BlackCatOutput` for all results
- **Modern Logging**: Added structured logging with `Write-BlackCatLog`
- **Consistent Parameter Patterns**: Aligned parameters with module standards
- **Enhanced Documentation**: Improved help content and examples
- **Expanded Capability Set**: Added `Find-EntraPermissionHolder` to complement Azure resource permissions with Microsoft Entra ID permissions

### ⚡ **Performance Enhancements**

- **Batch Processing**: Implemented subscription batch processing for parallel queries
- **Optimized API Calls**: Using `Invoke-AzBatch` for efficient Azure API interaction
- **Improved Caching**: Better cache key generation and management
- **Memory Optimization**: Reduced memory footprint for large queries

### **User Experience Improvements**

- **Rich Progress Indicators**: Enhanced visual feedback during operations
- **Detailed Performance Metrics**: Added execution statistics and duration reporting
- **Better Error Handling**: Improved error messages and recovery options
- **Standardized Output**: Consistent result formatting for easier consumption

### 🔒 **Advanced Security & Stealth Features**

#### **Dynamic UserAgent Rotation System**
```powershell
# Get current UserAgent configuration
Get-UserAgentStatus

# Configure rotation settings
Set-UserAgentRotation -RotationInterval 30 -RandomizeBrowsers

# View the current UserAgent in use
Get-CurrentUserAgent
```

The new UserAgent system provides:

- **Enhanced Security Posture**: Sophisticated request fingerprint management
- **Detection Avoidance**: Prevents correlation of requests across API calls
- **Natural Request Patterns**: Mimics regular browser behavior to blend with normal traffic
- **Configurable Rotation**: Adjustable timing and patterns for different scenarios
- **Integrated Management**: Automatically handles headers across all HTTP operations
- **Transparent Operation**: No additional configuration needed for standard functions

## Testing Notes

This update maintains full backward compatibility while adding new capabilities:

- All existing parameter sets continue to function as before
- Default output format standardized to `Object` for programmatic use
- Enhanced error handling maintains backward compatibility

## For Security Analysts

The enhanced discovery functions offer improved capabilities for security assessments:

- **Enhanced Azure Resource Permission Discovery**:
  - More reliable permission detection across complex hierarchies
  - Better performance for tenant-wide scans
  - Enhanced output formatting for integration with security reports
  - Improved error handling for more robust security assessments

- **New Microsoft Entra ID Permission Discovery**:
  - Comprehensive discovery of Entra ID role assignments
  - Detection of critical directory permissions
  - Identification of users with sensitive access rights
  - Cross-service permission mapping between Azure resources and Entra ID

---

For more detailed information about these changes, please see the [CHANGELOG.md](CHANGELOG.md).
