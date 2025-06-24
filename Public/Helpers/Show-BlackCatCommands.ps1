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
                
                # If help didn't work, parse the file manually
                if ($description -eq "No description available") {
                    $content = Get-Content -Path $fullFilePath -Raw
                    
                    # Special handling for Export-AzAccessToken.ps1
                    if ($fileName -eq "Export-AzAccessToken") {
                        $description = "The Export-AzAccessToken function retrieves access tokens for specified Azure resource types and exports them to a JSON file or publishes them to a secure sharing service."
                    }
                    # Look for .DESCRIPTION in a comment block
                    elseif ($content -match '<#(?:.|\n)*?\.DESCRIPTION\s*\r?\n\s*(.*?)(?:\r?\n\s*\.|\r?\n\s*\r?\n|\r?\n\s*#>|$)') {
                        $description = $matches[1].Trim()
                    }
                    # Try alternative pattern for help blocks
                    elseif ($content -match '\.DESCRIPTION\s*(.*?)(?:\r?\n\s*\.|\r?\n\s*\r?\n|$)') {
                        $description = $matches[1].Trim()
                    }
                    # If no .DESCRIPTION found, try to find first comment that might serve as description
                    elseif ($content -match '#\s*(.*?)(\r?\n|$)') {
                        $description = $matches[1].Trim()
                    }
                }
                
                # Clean up multi-line descriptions - replace newlines with spaces
                $description = $description -replace '\s*\r?\n\s*', ' '
                
                # Truncate long descriptions
                if ($description.Length -gt 80) {
                    $description = $description.Substring(0, 79) + "..."
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
}