# Contributing to Blackcat

Thank you for your interest in contributing to Blackcat! We welcome contributions of all kinds, including bug fixes, new features, and documentation improvements.

## Table of Contents
- [Development Setup](#development-setup)
- [Optimization Guidelines](#optimization-guidelines)
- [Function Organization](#function-organization)
- [Coding Style](#coding-style)
- [Commit Message Format](#commit-message-format)
- [Communication](#communication)
- [Code of Conduct](#code-of-conduct)

## Development Setup

We recommend using GitHub Codespaces for developing and maintaining Blackcat. Codespaces provides a fully configured development environment in the cloud.

### Steps to Set Up Codespaces

1. Fork the repository to your GitHub account.
2. Open the forked repository in GitHub.
3. Click on the "Code" button and select "Open with Codespaces".
4. If you don't have a Codespace created, click on "New Codespace".
5. Codespaces will set up the development environment automatically.

## Optimization Guidelines

To ensure that Blackcat functions are optimized for speed, please adhere to the following guidelines:

- Use the BATCH API for operations that involve multiple requests to reduce the number of API calls.
- Implement parallel processing where applicable to improve performance.
- Avoid unnecessary loops and optimize algorithms for efficiency.
- Profile your code to identify and address performance bottlenecks.

## Function Organization

To maintain a well-organized codebase, please map all functions to the appropriate folders based on the [MITRE ATT&CK](https://attack.mitre.org/) tactics. Each folder should correspond to a specific tactic, and functions should be placed in the relevant folder.

### Example Folder Structure

```
Blackcat/
├── InitialAccess/
│   └── Get-ExampleInitialAccess.ps1
├── Execution/
│   └── Invoke-ExampleExecution.ps1
├── Persistence/
│   └── Set-ExamplePersistence.ps1
├── PrivilegeEscalation/
│   └── Invoke-ExamplePrivilegeEscalation.ps1
├── DefenseEvasion/
│   └── Invoke-ExampleDefenseEvasion.ps1
├── CredentialAccess/
│   └── Get-ExampleCredentialAccess.ps1
├── Discovery/
│   └── Get-ExampleDiscovery.ps1
├── LateralMovement/
│   └── Invoke-ExampleLateralMovement.ps1
├── Collection/
│   └── Get-ExampleCollection.ps1
├── Exfiltration/
│   └── Invoke-ExampleExfiltration.ps1
├── CommandAndControl/
│   └── Invoke-ExampleCommandAndControl.ps1
```

### MITRE ATT&CK Tactics

- **Initial Access**: Functions related to gaining initial access to Azure environments.
- **Execution**: Functions that execute malicious code or commands.
- **Persistence**: Functions that establish and maintain persistence within Azure environments.
- **Privilege Escalation**: Functions that escalate privileges within Azure environments.
- **Defense Evasion**: Functions that evade detection and defensive measures.
- **Credential Access**: Functions that obtain credentials and sensitive information.
- **Discovery**: Functions that gather information about Azure environments.
- **Lateral Movement**: Functions that move laterally within Azure environments.
- **Collection**: Functions that collect data from Azure environments.
- **Exfiltration**: Functions that exfiltrate data from Azure environments.
- **Command and Control**: Functions that establish command and control channels.


## Communication

Please use GitHub Issues for communication. You can open an issue to report bugs, request features, or ask questions. We encourage open discussions and collaboration.


## Coding Style

Please follow these coding guidelines to ensure consistency across the codebase:

- Use 4 spaces for indentation.
- Follow the [PowerShell Best Practices and Style Guide](https://poshcode.gitbook.io/powershell-practice-and-style/).
- Ensure that all public functions have comment-based help.
- Use meaningful variable and function names.
- Limit line length to 80 characters.

### Example

```powershell
function Get-Example {
    param (
        [int]$Param1,
        [string]$Param2
    )

    if ($Param1 -gt 0) {
        return $true
    }
    return $false

    <#
    .SYNOPSIS
    This is an example function.

    .DESCRIPTION
    This function demonstrates the coding style for Blackcat.

    .PARAMETER Param1
    The first parameter.

    .PARAMETER Param2
    The second parameter.

    .OUTPUTS
    [bool]

    .EXAMPLE
    Get-Example -Param1 5 -Param2 "test"
    #>

}
```

## Commit Message Format

Please use the following format for commit messages:

```
<type>(<scope>): <subject>

<body>
```

### Types

- **feat**: A new feature
- **fix**: A bug fix
- **docs**: Documentation only changes
- **style**: Changes that do not affect the meaning of the code (white-space, formatting, etc.)
- **refactor**: A code change that neither fixes a bug nor adds a feature
- **perf**: A code change that improves performance
- **test**: Adding missing or correcting existing tests
- **chore**: Changes to the build process or auxiliary tools and libraries

### Example

```
feat(authentication): add support for multi-factor authentication

Added support for multi-factor authentication using TOTP.
Updated the login flow to include a step for TOTP verification.
```

## Code of Conduct

Please note that this project is governed by a [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code. Please report unacceptable behavior to [maintainer@example.com].

Thank you for contributing to Blackcat!
