#region load module variables
Write-Verbose -Message "Creating modules variables"
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$script:SessionVariables = [ordered]@{
    baseUri     = ''
    ExpiresOn   = ''
    apiVersion  = '2023-06-01-preview'
    Roles       = if (Test-Path $PSScriptRoot\Helpers\EntraRoles.csv) { Get-Content -Path $PSScriptRoot\Helpers\EntraRoles.csv | ConvertFrom-Csv }
    serviceTags = if (Test-Path $PSScriptRoot\Helpers\ServiceTags.json) { Get-Content -Path $PSScriptRoot\Helpers\ServiceTags.json | ConvertFrom-Json }
}

if (-not $script:SessionVariables.serviceTags) {
    Write-Verbose "Updating Service Tags for Azure Public"
    Write-Verbose "Getting lastest IP Ranges"
    $uri = ((Invoke-WebRequest -uri "https://www.microsoft.com/en-us/download/confirmation.aspx?id=56519").links | Where-Object outerHTML -like "*click here to download manually*").href
            (Invoke-RestMethod -uri $uri).values | ConvertTo-Json -Depth 100 | Out-File $PSScriptRoot\Helpers\ServiceTags.json -Force

    Write-Verbose "Updating Service Tags"
    $sessionVariables.serviceTags = (Get-Content $PSScriptRoot\Helpers\ServiceTags.json | ConvertFrom-Json)
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
    Import-Module $script
    try {
        . $script.FullName
        Write-Verbose -Message ("Imported function {0}" -f $script)
    }
    catch {
        Write-Error -Message ("Failed to import function {0}: {1}" -f $script, $_)
    }
}

Export-ModuleMember -Function $publicScripts.BaseName

# Import Classes
$helperPath = "$PSScriptRoot/Helpers"

# if (Test-Path "$helperPath/classes.psd1") {
#     $ClassLoadOrder = Import-PowerShellDataFile -Path "$helperPath/classes.psd1" -ErrorAction SilentlyContinue
# }
# else {
#     Write-Host "Path $helperPath/classes.psd1 not found"
#     $ClassLoadOrder = @{}
# }

# foreach ($class in $ClassLoadOrder.order) {
#     $path = '{0}/{1}.ps1' -f $helperPath, $class
#     if (Test-Path $path) {
#         # Write-Host $path
#         . $path
#     }
#     else {
#         Write-Host "Path $path not found"
#     }
# }

$manifest = Import-PowerShellDataFile "$PSScriptRoot\BlackCat.psd1"
$version = $manifest.ModuleVersion

# Set the window title
try {
    $host.UI.RawUI.WindowTitle = "BlackCat $version"
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
