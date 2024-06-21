#region load module variables
Write-Verbose -Message "Creating modules variables"
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$SessionVariables = [ordered]@{
    baseUri    = ''
    ExpiresOn  = ''
    apiVersion = '2023-06-01-preview'
    Roles = (Invoke-RestMethod 'https://raw.githubusercontent.com/azurekid/blackcat/0x316A1/roles.csv' | ConvertFrom-Csv)
}
New-Variable -Name Guid -Value (New-Guid).Guid -Scope Script -Force
New-Variable -Name SessionVariables -Value $SessionVariables -Scope Script -Force

#region Handle Module Removal
$OnRemoveScript = {
    Remove-Variable -Name SessionVariables -Scope Script -Force
    Remove-Variable -Name Guid -Scope Script -Force
}
$ExecutionContext.SessionState.Module.OnRemove += $OnRemoveScript
Register-EngineEvent -SourceIdentifier ([System.Management.Automation.PsEngineEvent]::Exiting) -Action $OnRemoveScript
#endregion Handle Module Removal

#region discover module name
$ModuleName = $ExecutionContext.SessionState.Module
Write-Verbose -Message "Loading module $ModuleName"
#endregion discover module name

# Import private and public scripts and expose the public ones
$privateScripts = @(Get-ChildItem -Path "$PSScriptRoot\Private" -Recurse -Filter "*.ps1" | Sort-Object Name )
$publicScripts = @(Get-ChildItem -Path "$PSScriptRoot\Public" -Recurse -Filter "*.ps1" | Sort-Object Name )

foreach ($script in @($privateScripts + $publicScripts)) {
    Write-Verbose $script
    try {
        . $script.FullName
        Write-Verbose -Message ("Imported function {0}" -f $script)
    } catch {
        Write-Error -Message ("Failed to import function {0}: {1}" -f $script, $_)
    }
}

Export-ModuleMember -Function $publicScripts.BaseName

$manifest = Import-PowerShellDataFile "$PSScriptRoot\BlackCat.psd1"
$version = $manifest.ModuleVersion

# Set the window title
try
{
    $host.UI.RawUI.WindowTitle="BlackCat $version"
}
catch {}

$logo = `
@"


     __ ) ___  |  |  |          |      ___|    __ \   |
     __ \     /   |  |     __|  |  /  |       / _` |  __|
     |   |   /   ___ __|  (       <   |      | (   |  |
    ____/  _/       _|   \___| _|\_\ \____| \ \__,_| \__|
                                             \____/

                 v$version by Rogier Dijkman

"@

Write-Host $logo -ForegroundColor "Blue"
