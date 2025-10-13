
#region PowerShell version check
# Ensure the module runs only in PowerShell 7+
$minPSVersion = [Version]'7.0'
if ($PSVersionTable.PSVersion -lt $minPSVersion) {
    throw "BlackCat module requires PowerShell 7.0 or higher. Current version: $($PSVersionTable.PSVersion)"
    # Exit the script
    return
}

Write-Verbose -Message "Creating modules variables"

$OnRemoveScript = {
    Remove-Variable -Name SessionVariables -Scope Script -Force
    Remove-Variable -Name Guid -Scope Script -Force
}

$ExecutionContext.SessionState.Module.OnRemove += $OnRemoveScript
Register-EngineEvent -SourceIdentifier ([System.Management.Automation.PsEngineEvent]::Exiting) -Action $OnRemoveScript

$ModuleName = $ExecutionContext.SessionState.Module
Write-Verbose -Message "Loading module $ModuleName"

if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Write-Verbose -Message "Az.Accounts module not found. Installing the latest version..."
    Install-Module -Name Az.Accounts -Force -Scope CurrentUser
}

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

$helperPath = "$PSScriptRoot/Private/Reference"
if (-not(Test-Path -Path $helperPath)) {
    Write-Verbose -Message "Creating Private/Reference directory"
    New-Item -Path $helperPath -ItemType Directory -Force | Out-Null

    Write-Verbose -Message "Fetching latest helper files for first-time setup"
}
elseif (-not(Get-ChildItem -Path $helperPath -ErrorAction SilentlyContinue)) {
    Write-Verbose -Message "Private/Reference directory exists but is empty. Fetching helper files"
}

[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$script:SessionVariables = [ordered]@{
    baseUri                   = '';
    graphUri                  = 'https://graph.microsoft.com/beta';
    batchUri                  = 'https://management.azure.com/batch?api-version=2020-06-01';
    resourceGraphUri          = 'https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01';
    ExpiresOn                 = '';
    apiVersion                = '2023-06-01-preview';
    AccessToken               = '';
    UserAgent                 = '';
    Roles                     = if (Test-Path $helperPath\EntraRoles.csv) { Get-Content -Path $helperPath\EntraRoles.csv | ConvertFrom-Csv };
    AzureRoles                = if (Test-Path $helperPath\AzureRoles.csv) { Get-Content -Path $helperPath\AzureRoles.csv | ConvertFrom-Csv };
    serviceTags               = if (Test-Path $helperPath\ServiceTags.json) { Get-Content -Path $helperPath\ServiceTags.json | ConvertFrom-Json };
    appRoleIds                = if (Test-Path $helperPath\appRoleIds.csv) { Get-Content -Path $helperPath\appRoleIds.csv | ConvertFrom-Csv };
    permutations              = if (Test-Path $helperPath\permutations.txt) { Get-Content -Path $helperPath\permutations.txt };
    subdomains                = if (Test-Path $helperPath\subdomains.json) { Get-Content -Path $helperPath\subdomains.json | ConvertFrom-Json -AsHashtable };
    userAgents                = if (Test-Path $helperPath\userAgents.json) { Get-Content -Path $helperPath\userAgents.json | ConvertFrom-Json };
    privilegedRoles           = if (Test-Path $helperPath\privileged-roles.json) { Get-Content -Path $helperPath\privileged-roles.json | ConvertFrom-Json };

    # User agent rotation tracking
    CurrentUserAgent          = $null;
    UserAgentLastChanged      = $null;
    UserAgentRequestCount     = 0;
    UserAgentRotationInterval = [TimeSpan]::FromMinutes(30);
    MaxRequestsPerAgent       = 50;
    default                   = 'N2gzQmw0Y2tDNDdXNDVIM3IzNG5kMTVOMDdQbDRubjFuZzcwTDM0djM==';
}

New-Variable -Name Guid -Value (New-Guid).Guid -Scope Script -Force
New-Variable -Name SessionVariables -Value $SessionVariables -Scope Script -Force

$manifest = Import-PowerShellDataFile "$PSScriptRoot\BlackCat.psd1"
$version = $manifest.ModuleVersion

# Check for updates
try {
    $latestVersionUrl = "https://raw.githubusercontent.com/azurekid/blackcat/refs/heads/main/BlackCat.psd1"
    $latestManifestContent = Invoke-RestMethod -Uri $latestVersionUrl -UseBasicParsing
    $latestVersionLine = $latestManifestContent -split "`n" | Where-Object { $_ -match 'ModuleVersion' }
    $latestVersion = ($latestVersionLine -split '=' | Select-Object -Last 1).Trim().Trim("'")

    if ($latestVersion -gt $version) {
        $updateMessage = "A newer version of the module ($latestVersion) is available."
    }
    else {
        $updateMessage = "             v$version by Rogier Dijkman"
    }
}
catch {
    Write-Verbose -Message "Failed to check for module updates: $_"
}

#Disable Messages and WAM
Write-Verbose -Message "Disabling LoginExperienceV2..."
Update-AzConfig -LoginExperienceV2 Off

Write-Verbose -Message "Disabling BreakingChangeWarning..."
Update-AzConfig -DisplayBreakingChangeWarning $false

# Safely import module manifest
try {
	$ModuleInfo = Import-PowerShellDataFile -Path "$PsScriptRoot/blackcat.psd1" -ErrorAction Stop
} catch {
	Write-Warning "Failed to load module manifest: $($_.Exception.Message)"
	$ModuleInfo = $null
}

# Set the window title
try {
    $host.UI.RawUI.WindowTitle = "BlackCat $version"
}
catch {}

$logo = `
    @"
                        /\_/\
                       ( o.o )
     __ ) ___  |  |  |  > ^ <   |      ___|    __ \   |
     __ \     /   |  |     __|  |  /  |       / _` |  __|
     |   |   /   ___ __|  (       <   |      | (   |  |
    ____/  _/       _|   \___| _|\_\ \____| \ \__,_| \__|
                                             \____/

    $updateMessage

"@

Write-Host $logo -ForegroundColor Blue