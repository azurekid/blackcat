function Format-BlackCatOutput {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Data,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Object', 'JSON', 'CSV', 'Table')]
        [string]$OutputFormat,

        [Parameter(Mandatory = $true)]
        [string]$FunctionName,

        [Parameter(Mandatory = $false)]
        [string]$FilePrefix,

        [Parameter(Mandatory = $false)]
        [switch]$Silent
    )

    if ($null -eq $Data -or ($Data -is [array] -and $Data.Count -eq 0)) {
        return $null
    }

    if (-not $FilePrefix) {
        $FilePrefix = $FunctionName -replace '^(Get-|Invoke-|Find-)', ''
    }

    switch ($OutputFormat) {
        'JSON' {
            try {
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $fileName = "${FilePrefix}Result_$timestamp.json"
                $Data | ConvertTo-Json -Depth 10 | Out-File -FilePath $fileName -Encoding UTF8
                
                if (-not $Silent) {
                    Write-Host " Results exported to: $fileName" -ForegroundColor Green
                }
            }
            catch {
                Write-Warning "  Failed to export JSON: $($_.Exception.Message)"
                return $Data
            }
        }
        'CSV' {
            try {
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $fileName = "${FilePrefix}Result_$timestamp.csv"
                $Data | Export-Csv -Path $fileName -NoTypeInformation -Encoding UTF8
                
                if (-not $Silent) {
                    Write-Host " Results exported to: $fileName" -ForegroundColor Green
                }
            }
            catch {
                Write-Warning "  Failed to export CSV: $($_.Exception.Message)"
                return $Data
            }
        }
        'Table' {
            try {
                $Data | Format-Table -AutoSize
            }
            catch {
                Write-Warning "  Failed to format table: $($_.Exception.Message)"
                return $Data
            }
        }
        'Object' {
            return $Data
        }
        default {
            return $Data
        }
    }
<#
    .SYNOPSIS
        Formats and outputs data according to the specified output format.

    .DESCRIPTION
        This private function handles output formatting for BlackCat module functions.
        It supports Object, JSON, CSV, and Table formats with consistent behavior
        across all module functions.

    .PARAMETER Data
        The data to format and output.

    .PARAMETER OutputFormat
        The output format to use (Object, JSON, CSV, Table).

    .PARAMETER FunctionName
        The name of the calling function, used for file naming.

    .PARAMETER FilePrefix
        Optional prefix for exported files. If not specified, uses the function name.

    .PARAMETER Silent
        When specified, suppresses file export messages.

    .EXAMPLE
        Format-BlackCatOutput -Data $results -OutputFormat 'JSON' -FunctionName 'Get-RoleAssignment'

    .EXAMPLE
        Format-BlackCatOutput -Data $results -OutputFormat 'CSV' -FunctionName 'Invoke-AzBatch' -FilePrefix 'AzBatch'
    #>
}