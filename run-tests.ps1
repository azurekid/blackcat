#!/usr/bin/env pwsh
# Run the Pester tests for the Get-AzBlobContent function

# Ensure Pester is installed
if (-not (Get-Module -ListAvailable -Name Pester)) {
    Write-Host "Installing Pester module..." -ForegroundColor Yellow
    Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
}

# Import Pester
Import-Module Pester

# Run the tests
$config = New-PesterConfiguration
$config.Run.Path = "$PSScriptRoot/Tests"
$config.TestResult.Enabled = $true
$config.Output.Verbosity = "Detailed"

# In Pester 5.x we can't specify individual test files with TestFile property,
# so we'll filter by file name in the Container property
$config.Run.Container = @(
    New-PesterContainer -Path "$PSScriptRoot/Tests/Get-AzBlobContent.Tests.ps1"
    New-PesterContainer -Path "$PSScriptRoot/Tests/Get-AzBlobContentRegex.Tests.ps1" 
    New-PesterContainer -Path "$PSScriptRoot/Tests/Find-PublicStorageContainer.Tests.ps1"
)

Invoke-Pester -Configuration $config
