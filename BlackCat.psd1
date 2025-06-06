#
# Module manifest for module 'BlackCat'
#
# Generated by: Rogier Dijkman
#
# Generated on: 2024/06/13
#

@{

    # Script module or binary module file associated with this manifest.
    RootModule        = 'BlackCat.psm1'

    # Version number of this module.
    ModuleVersion     = '0.13.2'

    # ID used to uniquely identify this module
    GUID              = '767ce24a-f027-4e34-891f-f6246489dd61'

    # Author of this module
    Author            = 'Rogier Dijkman'

    # Company or vendor of this module
    CompanyName       = ''

    # Copyright statement for this module
    Copyright         = '(c) Rogier Dijkman. All rights reserved.'

    # Description of the functionality provided by this module
    Description       = 'Helper module to validate Azure Security'

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = @(
        'Add-EntraApplication',
        'Add-StorageAccountSasToken',
        'Add-GroupObject',
        'ConvertFrom-JWT',
        'Get-AccessTokens',
        'Get-AdministrativeUnits',
        'Get-AppRolePermission',
        'Get-AzResourceSecretList',
        'Get-Functions',
        'Get-ResourcePermission',
        'Get-EntraInformation',
        'Get-EntraIDPermissions',
        'Get-FederatedAppCredential',
        'Get-KeyVaultSecret',
        'Get-ManagedIdentity',
        'Get-PrivilegedApp',
        'Get-PublicResourceList',
        'Get-PublicStorageAccountContent',
        'Get-PublicStorageAccountList',
        'Get-RoleAssignment',
        'Get-ServicePrincipalsPermission',
        'Get-ServiceTag',
        'Get-StorageAccountKey',
        'Get-StorageContainerList',
        'Invoke-AzBatch',
        'Invoke-MsGraph',
        'Invoke-Update',
        'New-AuthHeader',
        'New-JWT',
        'Read-SASToken',
        'Restore-DeletedIdentity',
        'Set-AdministrativeUnit',
        'Set-AppRegistrationOwner',
        'Set-AzNetworkSecurityGroupRule',
        'Set-Context',
        'Set-FederatedIdentity',
        'Set-FunctionAppSecret',
        'Set-ManagedIdentityPermission',
        'Set-UserCredential',
        'Switch-Context',
        'Update-ServiceTag'
    )

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport   = '*'

    # Variables to export from this module
    VariablesToExport = '*'

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport   = '*'

    # List of all files packaged with this module
    FileList = @(
        'Private\Invoke-BlackCat.ps1',
        'Private\Get-AccessToken.ps1',
        'Private\Get-CidrAddresses.ps1',
        'Private\Invoke-SplitJWT.ps1',
        'Private\Write-Message.ps1',
        'Private\Test-DnsName.ps1',
        'Private\Get-AllPages.ps1',
        'Public\Credential Access\Get-KeyVaultSecret.ps1',
        'Public\Credential Access\Get-StorageAccountKey.ps1',
        'Public\Discovery\Get-AppRolePermission.ps1',
        'Public\Discovery\Get-FederatedAppCredential.ps1',
        'Public\Discovery\Get-PrivilegedApp.ps1',
        'Public\Discovery\Get-ServicePrincipalsPermission.ps1',
        'Public\Discovery\Get-ResourcePermission.ps1',
        'Public\Exfiltration\Get-AccessTokens.ps1',
        'Public\Exfiltration\anonymous\Get-PublicStorageAccountContent.ps1',
        'Public\Helpers\ConvertFrom-JWT.ps1',
        'Public\Helpers\Get-Functions.ps1',
        'Public\Helpers\Get-ServiceTag.ps1',
        'Public\Helpers\Invoke-Update.ps1',
        'Public\Helpers\New-AuthHeader.ps1',
        'Public\Helpers\New-JWT.ps1',
        'Public\Helpers\Read-SASToken.ps1',
        'Public\Helpers\Switch-Context.ps1',
        'Public\Helpers\Update-ServiceTag.ps1',
        'Public\Impair Defenses\Set-AzNetworkSecurityGroupRule.ps1',
        'Public\Persistence\Add-StorageAccountSasToken.ps1',
        'Public\Persistence\Add-GroupObject.ps1',
        'Public\Persistence\Set-AdministrativeUnit.ps1',
        'Public\Persistence\Set-AppRegistrationOwner.ps1',
        'Public\Persistence\Set-FederatedIdentity.ps1',
        'Public\Persistence\Set-ManagedIdentityPermission.ps1',
        'Public\Persistence\Set-FunctionAppSecret.ps1',
        'Public\Persistence\Set-UserCredential.ps1',
        'Public\Reconnaissance\Get-AdministrativeUnits.Ps1',
        'Public\Reconnaissance\Get-EntraInformation.ps1',
        'Public\Reconnaissance\Get-EntraIdPermissions.ps1',
        'Public\Reconnaissance\Get-ManagedIdentity.ps1',
        'Public\Reconnaissance\Get-StorageContainerList.ps1',
        'Public\Reconnaissance\Invoke-AzBatch.ps1',
        'Public\Reconnaissance\Invoke-MsGraph.ps1',
        'Public\Reconnaissance\anonymous\Get-PublicResourceList.ps1',
        'Public\Reconnaissance\anonymous\Get-PublicStorageAccountList.ps1',
        'Public\Resource Development\Add-EntraApplication.ps1',
        'Public\Resource Development\Restore-DeletedIdentity.ps1',
        'BlackCat.psd1'
        'BlackCat.psm1'
    )

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData       = @{

        PSData = @{

            # Tags applied to this module. These help with module discovery in online galleries.
            Tags       = @("Azure", "Pentesting", "Security")

            # A URL to the license for this module.
            LicenseUri = 'https://github.com/azurekid/blackcat/blob/2078bf641cf680fe41ccdb0f1ea98ce696e58384/LICENSE.md'

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/azurekid/BlackCat'

            # A URL to an icon representing this module.
            # IconUri = ''

            # ReleaseNotes of this module
            # ReleaseNotes = ''

            # Prerelease string of this module
            # Prerelease = 'beta'

            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            RequireLicenseAcceptance = $false

            # External dependent modules of this module
            # ExternalModuleDependencies = @()

        } # End of PSData hashtable

    } # End of PrivateData hashtable

    # HelpInfo URI of this module
    HelpInfoURI = 'https://github.com/azurekid/blackcat/blob/2078bf641cf680fe41ccdb0f1ea98ce696e58384/README.md'

    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
    # DefaultCommandPrefix = ''
}