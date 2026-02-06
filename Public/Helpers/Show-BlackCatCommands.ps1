function Show-BlackCatCommands {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, Position=0)]
        [Alias("cat", "c")]
        [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            # Get the Public folder path
            $publicFolderPath = Split-Path -Parent $PSScriptRoot

            # Get immediate subdirectories of Public (excluding Helpers)
            $categories = Get-ChildItem -Path $publicFolderPath -Directory |
                         Where-Object { $_.Name -ne 'Helpers' } |
                         Where-Object {
                             # Only return directories that contain at least one PowerShell script
                             (Get-ChildItem -Path $_.FullName -Filter "*.ps1" -File).Count -gt 0
                         } |
                         Select-Object -ExpandProperty Name |
                         Where-Object { $_ -like "$wordToComplete*" }

            return $categories
        })]
        [string]$Category
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

                        /\_/\
                       ( ◣_◢ )
                        > ^ <
     __ ) ___  |  |  |          |      ___|    __ \   |      /\_/\
     __ \     /   |  |     __|  |  /  |       / _` |  __|    ( ◣_◢ )
     |   |   /   ___ __|  (       <   |      | (   |  |      > ^ <
    ____/  _/       _|   \___| _|\_\ \____| \ \__,_| \__|    (   )
                                             \____/

        $updateMessage

"@
        Write-Host $logo -ForegroundColor Blue

        $results = @()
        $fileCount = 0

        foreach ($filePath in $fileList) {
            if ($Category) {
                # Normalize path separators for comparison
                $normalizedCategory = $Category -replace '[\\/]', [IO.Path]::DirectorySeparatorChar
                if ($filePath -notlike "*$normalizedCategory*") {
                    continue
                }
            }
            $fileName = [IO.Path]::GetFileNameWithoutExtension((Split-Path -Path $filePath -Leaf))
            $fileCount++

            # Get full path to the file
            $fullFilePath = Join-Path -Path $moduleRoot -ChildPath $filePath
            $description = "No description available"

            # Try to extract description from the file
            if (Test-Path $fullFilePath) {
                # First attempt to load the function and get its help
                try {
                    # Get just the function name without path
                    $functionName = [System.IO.Path]::GetFileNameWithoutExtension($fullFilePath)
                    # Try to get help for the function (only works if loaded)
                    $helpInfo = Get-Help -Name $functionName -ErrorAction SilentlyContinue
                    
                    if ($helpInfo -and $helpInfo.Synopsis) {
                        $description = $helpInfo.Synopsis.Trim()
                    }
                }
                catch {
                    # Fallback to parsing the file directly
                    Write-Verbose "Couldn't get help for $functionName, falling back to file parsing"
                }
                
                # Always parse the file directly for more reliable extraction
                # Prioritize SYNOPSIS as the default description
                $content = Get-Content -Path $fullFilePath -Raw
                $fileDescription = "No description available"
                
                # Special handling for Export-AzAccessToken.ps1
                if ($fileName -eq "Export-AzAccessToken") {
                    $fileDescription = "The Export-AzAccessToken function retrieves access tokens."
                }
                else {
                    # Prioritize .SYNOPSIS as the default source
                    if ($content -match '\.SYNOPSIS\s*\r?\n\s*(.*?)(?:\r?\n\s*\.|\r?\n\s*\r?\n|$)') {
                        $fileDescription = $matches[1].Trim()
                    }
                    # Fall back to .DESCRIPTION if SYNOPSIS not found
                    elseif ($content -match '<#(?:.|\n)*?\.DESCRIPTION\s*\r?\n\s*(.*?)(?:\r?\n\s*\.|\r?\n\s*\r?\n|\r?\n\s*#>|$)') {
                        $fileDescription = $matches[1].Trim()
                    }
                    # Try alternative pattern for help blocks
                    elseif ($content -match '\.DESCRIPTION\s*(.*?)(?:\r?\n\s*\.|\r?\n\s*\r?\n|$)') {
                        $fileDescription = $matches[1].Trim()
                    }
                    # If neither found, try to find first comment that might serve as description
                    elseif ($content -match '#\s*(.*?)(\r?\n|$)') {
                        $fileDescription = $matches[1].Trim()
                    }
                }
                
                # Use file-parsed description
                if ($fileDescription -ne "No description available") {
                    $description = $fileDescription
                }
                
                # Clean up multi-line descriptions - replace newlines with spaces
                $description = $description -replace '\s*\r?\n\s*', ' '
                
                # Enforce 83-character limit (with "..." if truncated)
                if ($description.Length -gt 83) {
                    $description = $description.Substring(0, 80) + "..."
                }
            }

            $results += [PSCustomObject]@{
                Function = $fileName
                Description = $description
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
    <#
    .SYNOPSIS
        Displays all available BlackCat functions organized by MITRE ATT&CK category.

    .DESCRIPTION
        This function shows a comprehensive list of all public functions in the BlackCat module,
        organized by their MITRE ATT&CK tactic category. You can filter by category to show
        only functions related to specific attack phases.

    .PARAMETER Category
        Optional category to filter functions. If not specified, shows all categories.
        Auto-completion is provided for available categories (e.g., Discovery, Persistence, Credential Access).

    .EXAMPLE
        Show-BlackCatCommands
        Shows all available BlackCat functions organized by category.

    .EXAMPLE
        Show-BlackCatCommands -Category Discovery
        Shows only functions in the Discovery category.

    .ALIAS
        cat, c

    .NOTES
        This is a utility/support function and does not directly map to MITRE ATT&CK tactics.
        Use this function to explore available BlackCat capabilities and their classifications.
    #>
}