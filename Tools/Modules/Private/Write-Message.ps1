function Write-Message {
    <#
    .SYNOPSIS
    Writes an output message to the console
    .DESCRIPTION
    This function is used internally to prompt messages to the PowerShell console
    .EXAMPLE
    Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message 'This is a message' -Severity 'Information'
    .NOTES
    NAME: Write-Message
    #>

    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification='This Function is used for custom output messages')]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Error", "Information", "Debug")]
        [string]$Severity,

        [Parameter(Mandatory = $false)]
        [string]$FunctionName
    )

    $messageBody = ("**$($FunctionName): $($Message)**" | ConvertFrom-Markdown -AsVt100EncodedString).VT100EncodedString

    switch ($Severity) {
        'Error' { Write-Host -Object $messageBody -ForegroundColor Red }
        'Information' { Write-Host -Object $messageBody -ForegroundColor Green }
        'Debug' { Write-Host -Object $messageBody -ForegroundColor Blue }
        Default { Write-Host -Object $messageBody }
    }

    if ($Severity -eq 'Error') {
        break
    }
}