# Azure Service Tag Function Improvements

## Summary of Changes

The `Get-ServiceTag.ps1` function has been significantly improved and renamed to `Find-AzureServiceTag` with enhanced functionality, better parameter naming, and Linux-friendly aliases.

## Key Improvements

### 1. **Enhanced Function Name**
- **Old**: `Get-ServiceTag`
- **New**: `Find-AzureServiceTag`
- **Backward Compatibility**: Original name maintained as alias

### 2. **Linux-Friendly Aliases**
- **Function Aliases**: `Get-ServiceTag`, `Find-ServiceTag`, `azure-service-tag`, `find-service-tag`
- **Parameter Aliases**:
  - `IPAddress`: `ip`, `address`, `host`
  - `ServiceName`: `service`, `svc`, `service-name`
  - `Region`: `location`, `region-name`, `loc`
  - `AsJson`: `json`, `raw`
  - `Detailed`: `table`, `list`

### 3. **Improved Parameter Design**
- **Multiple IP Support**: Now accepts `string[]` for processing multiple IP addresses
- **Pipeline Support**: Enhanced pipeline input capabilities
- **Parameter Sets**: Clear separation between IP lookup and filtering modes
- **Better Validation**: Enhanced IP address validation with regex patterns

### 4. **Enhanced Features**
- **Multiple Output Formats**: Objects (default), JSON, detailed table
- **Better Error Handling**: Proper error messages and validation
- **Performance Optimization**: CIDR prefix filtering for faster searches
- **Dynamic Validation**: Service names and regions validated against loaded data
- **Comprehensive Logging**: Verbose output for troubleshooting

### 5. **Cross-Platform Compatibility**
- **Linux-style usage**: `azure-service-tag --ip "52.239.152.0" --json`
- **Traditional PowerShell**: `Find-AzureServiceTag -IPAddress "52.239.152.0"`
- **Short aliases**: `find-service-tag -service Storage -loc EastUS`

## Usage Examples

### Traditional PowerShell Style
```powershell
# Find service tag for specific IP
Find-AzureServiceTag -IPAddress "52.239.152.0"

# Filter by service and region
Find-AzureServiceTag -ServiceName "Storage" -Region "EastUS"

# Multiple IPs via pipeline
@("52.239.152.0", "40.77.226.0") | Find-AzureServiceTag

# Get results as JSON
Find-AzureServiceTag -IPAddress "52.239.152.0" -AsJson
```

### Linux-Friendly Style
```bash
# Using aliases for cross-platform compatibility
azure-service-tag --ip "52.239.152.0" --json
find-service-tag --service "Storage" --location "EastUS" --table
```

### Pipeline Examples
```powershell
# Process multiple IPs
"52.239.152.0", "40.77.226.0" | azure-service-tag

# Import from CSV and lookup
Import-Csv ips.csv | Find-AzureServiceTag

# Chain with other commands
Get-Content ip-list.txt | Find-AzureServiceTag | Where-Object SystemService -eq "Storage"
```

## Output Format

The function now returns structured objects with consistent property names:

```powershell
PSTypeName      : AzureServiceTag
ServiceTagName  : ServiceBus.EastUS
SystemService   : ServiceBus
Region          : EastUS
RegionId        : 12
Platform        : Azure
ChangeNumber    : 123
AddressPrefix   : 52.239.152.0/24
NetworkFeatures : API,NSG
RequiredFqdns   : *.servicebus.windows.net
```

## Error Handling Improvements

- **Validation**: Better IP address format validation
- **Dependencies**: Clear error messages when service tags not loaded
- **Graceful Failures**: Continues processing when individual IPs fail
- **Warnings**: Informative warnings for no matches found

## Performance Enhancements

- **CIDR Filtering**: Pre-filters address ranges for faster matching
- **Optimized Loops**: Reduced nested iteration complexity
- **Memory Efficient**: Processes results incrementally
- **Verbose Logging**: Optional detailed progress tracking

## Backward Compatibility

- All original functionality preserved
- `Get-ServiceTag` alias maintains existing scripts
- Same session variable dependencies
- Compatible output format (with enhancements)

## Requirements

- PowerShell 5.1 or later
- Azure service tags loaded via `Update-ServiceTag`
- System.Net.IPNetwork assembly for CIDR operations

## Migration Guide

### Minimal Migration
No changes required - use existing `Get-ServiceTag` calls.

### Recommended Migration
Update to new function name and take advantage of new features:

```powershell
# Old
Get-ServiceTag -IpAddress "52.239.152.0"

# New
Find-AzureServiceTag -IPAddress "52.239.152.0"

# New with enhancements
Find-AzureServiceTag -ip "52.239.152.0" -json
```

This enhanced function provides better cross-platform compatibility, improved performance, and more flexible usage patterns while maintaining full backward compatibility.
