function ConvertTo-ObfuscatedCommand {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock
    )

    # Get the script block content and any parameter values
    $scriptText = $ScriptBlock.ToString()

    # Extract function name if the script block calls a function
    if ($scriptText -match '(?<function>\w+-\w+)\s*(?<params>.*)') {
        $functionName = $Matches.function
        $functionParams = $Matches.params
        # Get the function content
        $functionContent = (Get-Command $functionName -ErrorAction SilentlyContinue).ScriptBlock.ToString()

        if ($functionContent) {
            $scriptText = $functionContent
        }
    }

    # Create mapping for common PowerShell commands to their aliases
    $aliasMapping = @{}
    Get-Alias | ForEach-Object {
        if ($_.Definition -notlike "*-*") { return }
        $aliasMapping[$_.Definition] = $_.Name
    }

    # Generate random variable names
    $varMapping = @{}
    # Modified regex to better handle foreach loop context
    $variables = [regex]::Matches($scriptText, '\$(?!script:|using:)\w+') |
                Where-Object { 
                    $_.Value -notin @('$true', '$false') -and
                    # Additional check for foreach loop context
                    $_.Value -notmatch '^\$using:' -and
                    $_.Value -notmatch '^\$MyInvocation' -and
                    $_.Value -notmatch '^\$_' -and
                    $_.Value -notmatch '^\$filter' -and
                    $_.Value -notmatch '^\$roleAssignmentsRequestParam' -and
                    $_.Value -notmatch '^\$roleDefinitionsRequestParam' -and
                    $_.Value -notmatch '^\$requestParam'
                } |
                Select-Object -ExpandProperty Value -Unique

    foreach ($var in $variables) {
        $newVarName = '$' + -join ((65..90) + (97..122) | Get-Random -Count 12 | ForEach-Object { [char]$_ })
        $value = $var.Substring(1)
        $varMapping[$value] = $newVarName
    }

    # Replace commands with aliases
    $obfuscatedScript = $scriptText
    foreach ($command in $aliasMapping.Keys) {
        $obfuscatedScript = $obfuscatedScript -replace "\b$command\b", $aliasMapping[$command]
    }

   # Replace variables with random names
foreach ($var in $varMapping.Keys | ForEach-Object { $_.TrimStart('$') }) {
    # Handle $using: variables separately
    $obfuscatedScript = $obfuscatedScript -replace "\`$using:$var\b", ('$using:' + $varMapping[$var].TrimStart('$'))
    # Handle regular variables
    $obfuscatedScript = $obfuscatedScript -replace "(?<!script:|using:)\`$$var\b(?!\.|\[)", $varMapping[$var]
    $obfuscatedScript = $obfuscatedScript -replace "\`$$var(?=\s*=)", $varMapping[$var]
}

    $obfuscatedScript.Replace('$$', '$') | Out-File blackcat.ps1

    # Append the extracted function parameters to the paramValues
    if ($functionParams) {
        $paramValues = ""
        foreach ($param in $functionParams.Split()) {
            if ($param.StartsWith('-')) {
                $currentParam = $param.Substring(1)
                if ($varMapping.ContainsKey($currentParam)) {
                    $paramValues += " -" + ($varMapping[$currentParam]).Substring(1)
                } else {
                    $paramValues += " " + $param
                }
            } else {
                $paramValues += " " + $param
            }
        }
    }

    # Construct the command string
    $commandString = ".\blackcat.ps1 $paramValues"
    Write-Host $commandString
    # Run the newly generated file with the parameter values provided in the scriptblock
    Invoke-Expression -Command $commandString
}
