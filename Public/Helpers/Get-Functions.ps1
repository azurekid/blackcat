function Get-Functions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [ArgumentCompleter({
            param($CommandName, $ParameterName, $WordToComplete, $CommandAst, $FakeBoundParameters)

            # Find all subdirectories in the Public folder
            $validPaths = @()

            if (Test-Path -Path "Public" -PathType Container) {
                $publicSubDirs = Get-ChildItem -Path "Public" -Directory

                foreach ($dir in $publicSubDirs) {
                    # Include subdirectories of Public that match the word to complete
                    if ($dir.Name -like "$WordToComplete*") {
                        $validPaths += $dir.Name
                    }
                }
            }

            return $validPaths
        })]
        [ValidateScript({
            if (Test-Path -Path "Public\$_" -PathType Container) {
                return $true
            }

            throw "Path '$_' not found. Please specify a valid category path within the Public folder."
        })]
        [string]$CategoryPath
    )

    try {
        Clear-Host
        # Always use the path inside Public folder
        $actualPath = "Public\$CategoryPath"

        # Get all PS1 files in the folder
        $scriptFiles = Get-ChildItem -Path $actualPath -Filter *.ps1 -File -ErrorAction Stop

        if ($scriptFiles.Count -eq 0) {
            Write-Warning "No PowerShell scripts found in '$CategoryPath'."
            return
        }

        $logo = `
    @"


    __ ) ___  |  |  |          |      ___|    __ \   |
    __ \     /   |  |     __|  |  /  |       / _` |  __|
    |   |   /   ___ __|  (       <   |      | (   |  |
   ____/  _/       _|   \___| _|\_\ \____| \ \__,_| \__|
                                            \____/

                 v$script:version by Rogier Dijkman

"@

Write-Host $logo -ForegroundColor Blue

        # Create an array to hold our results
        $results = @()
        $functionCount = 0
        $fileCount = 0

        foreach ($file in $scriptFiles) {
            $fileCount++
            $content = Get-Content $file.FullName -Raw -ErrorAction Continue
            $matches = [regex]::Matches($content, '(?m)^\s*function\s+([a-zA-Z0-9_\-]+)(\s*{|\s+|\r?\n)')

            foreach ($match in $matches) {
                $functionName = $match.Groups[1].Value
                # Only include functions that don't start with underscore (public functions)
                if (-not $functionName.StartsWith('_')) {
                    $functionCount++

                    # Create a custom object for this function
                    $results += [PSCustomObject]@{
                        Category = $CategoryPath
                        Function = $functionName
                    }
                }
            }
        }

        Write-Verbose "Found $functionCount public functions in $fileCount files"

        # Return the results as objects that can be formatted as a table
        Write-Output $results| Format-Table -AutoSize

        Write-Host "========== Summary ==========`n" -ForegroundColor Cyan
        Write-Host "Found $functionCount public functions`n" -ForegroundColor White
    }
    catch {
        Write-Error "Error processing category folder: $_"
    }
}