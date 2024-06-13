# Import private and public scripts and expose the public ones
$privateScripts = @(Get-ChildItem -Path "$PSScriptRoot\private" -Recurse -Filter "*.ps1" | Sort-Object Name )
$publicScripts = @(Get-ChildItem -Path "$PSScriptRoot\public" -Recurse -Filter "*.ps1" | Sort-Object Name )

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