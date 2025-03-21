[![Mr Robot fonts](https://see.fontimg.com/api/renderfont4/g123/eyJyIjoiZnMiLCJoIjoxMjUsInciOjE1MDAsImZzIjo4MywiZmdjIjoiI0VGMDkwOSIsImJnYyI6IiMxMTAwMDAiLCJ0IjoxfQ/QiA3IDQgYyBLIEMgQCBU/mrrobot.png)](https://www.fontspace.com/category/mr-robot)

![logo](/.github/media/cateye.png?raw=true)

<div align="center">

Languages & Tools
=================

<img width="50" src="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/powershell/powershell-original.svg" alt="PowerShell" title=PowerShell />
<br>
<br>

</div>

PowerShell Module

### BlackCat Module Overview

```yaml
description: >
    BlackCat is a PowerShell module designed to validate the security of Microsoft Azure environments.
    It provides a set of functions to identify potential security risks and ensure compliance with best practices.

target_scope: >
    The module focuses on analyzing and validating configurations within Microsoft Azure environments.

note: >
    The module will be published to the PowerShell Gallery once it has been signed and is ready for release.
    Please note that the author is not responsible for any misuse of this module. It is intended solely for
    detecting security risks within the defined scope.
```

### Running from Codespaces

```yaml
running_from_codespace:
    description: >
        To run the BlackCat module from a GitHub Codespace, follow these steps:

        1. Click the `Code` button and select `Create codespace on main`.

        2. Once the Codespace is ready, open the terminal.

        3. The pwsh terminal already has the BlackCat module activated
```

![alt text](/.github/media/loaded.png)

### Installing the Module

```powershell
PS> git clone https://github.com/azurekid/blackcat.git
PS> cd blackcat
PS> import-module ./blackcat.psd1
```

### Using Help

```yaml
documentation: >
    Work in progress, but all functions have documentation in the files
    Get-Help Get-RoleAssignments
```

### Backlog

```yaml
description: >
    The backlog contains a list of planned features, enhancements, and bug fixes for the project.
    You can track the progress and upcoming tasks by visiting the project's backlog page.

    ⬇️
```

> [Project Backlog](https://github.com/users/azurekid/projects/3/views/1)

![image](https://github.com/user-attachments/assets/173b93ac-bdac-4b71-84db-07fffd4ff149)

### Feedback & Contributions

```yaml
feedback_and_contributions:
    description: >
        Support and feedback are greatly appreciated. If you would like to
        see specific features or have suggestions for improvement, please use the Issue forms 
        available in the repository.
        
        Your input helps shape the future of this project.

        Contributions are welcome! To contribute:
            - Fork the repository to your GitHub account.
            - Create a new branch for your feature or bug fix.
            - Make your changes, ensuring they align with the project's coding standards.
            - Test your changes thoroughly.
            - Submit a pull request with a clear description of your changes.

        Please ensure that your contributions adhere to the project's code of conduct. 
        For more details, refer to the CONTRIBUTING.md file in the repository.
```
