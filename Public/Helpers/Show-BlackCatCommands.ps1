function Show-BlackCatCommands {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, Position=0)]
        [string]$CategoryPath
    )

    try {
        Clear-Host

        # The module root is two levels up from the Helpers folder (since Helpers is inside Public)
        $moduleRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
        $psd1Path = Join-Path -Path $moduleRoot -ChildPath "BlackCat.psd1"
        Write-Verbose "Looking for BlackCat.psd1 at $psd1Path"
        if (-not (Test-Path $psd1Path)) {
            throw "BlackCat.psd1 not found at $psd1Path"
        }

        $moduleManifest = Import-PowerShellDataFile -Path $psd1Path


        if (-not $moduleManifest.ContainsKey('FileList')) {
            throw "No 'FileList' key found in BlackCat.psd1"
        }

        $fileList = $moduleManifest['FileList']

        $logo = @"
    __ ) ___  |  |  |          |      ___|    __ \   |
    __ \     /   |  |     __|  |  /  |       / _` |  __|
    |   |   /   ___ __|  (       <   |      | (   |  |
   ____/  _/       _|   \___| _|\_\ \____| \ \__,_| \__|
                                            \____/

                 v$script:version by Rogier Dijkman

"@
        Write-Host $logo -ForegroundColor Blue

        $results = @()
        $fileCount = 0

        foreach ($filePath in $fileList) {
            if ($CategoryPath) {
                # Normalize path separators for comparison
                $normalizedCategory = $CategoryPath -replace '[\\/]', [IO.Path]::DirectorySeparatorChar
                if ($filePath -notlike "*$normalizedCategory*") {
                    continue
                }
            }
            $fileName = [IO.Path]::GetFileNameWithoutExtension((Split-Path -Path $filePath -Leaf))
            $fileCount++
            $results += [PSCustomObject]@{
                Function = $fileName
            }
        }

        Write-Verbose "Found $fileCount public functions"

        $results | Format-Table -AutoSize

        Write-Host "========== Summary ==========`n" -ForegroundColor Cyan
        Write-Host "Found $fileCount public functions`n" -ForegroundColor White
    }
    catch {
        Write-Error "Error processing BlackCat.psd1: $_"
    }
}