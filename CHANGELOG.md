[![Mr Robot fonts](https://see.fontimg.com/api/renderfont4/g123/eyJyIjoiZnMiLCJoIjoxMjUsInciOjE1MDAsImZzIjo4MywiZmdjIjoiI0VGMDkwOSIsImJnYyI6IiMxMTAwMDAiLCJ0IjoxfQ/QiA3IDQgYyBLIEMgQCBU/mrrobot.png)](https://www.fontspace.com/category/mr-robot)

![logo](/.github/media/cateye.png?raw=true)

# CHANGELOG

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

- Resolved mismatching on custom roles ([#20](https://github.com/azurekid/blackcat/issues/24)).

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
