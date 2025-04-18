[![Mr Robot fonts](https://see.fontimg.com/api/renderfont4/g123/eyJyIjoiZnMiLCJoIjoxMjUsInciOjE1MDAsImZzIjo4MywiZmdjIjoiI0VGMDkwOSIsImJnYyI6IiMxMTAwMDAiLCJ0IjoxfQ/QiA3IDQgYyBLIEMgQCBU/mrrobot.png)](https://www.fontspace.com/category/mr-robot)

![logo](/.github/media/cateye.png?raw=true)

# CHANGELOG

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