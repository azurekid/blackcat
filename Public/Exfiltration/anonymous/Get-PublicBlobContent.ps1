function Get-PublicBlobContent {
    [cmdletbinding(DefaultParameterSetName = "Download")]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = "Download")]
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = "ListOnly")]
        [ValidatePattern('^https://[a-z0-9]+\.blob\.core\.windows\.net/[^?]+', ErrorMessage = "It does not match expected pattern '{1}'")]
        [Alias('url', 'uri')]
        [string]$BlobUrl,

        [Parameter(Mandatory = $true, ParameterSetName = "Download")]
        [Alias('path', 'out', 'dir')]
        [string]$OutputPath,

        [Parameter(Mandatory = $false, ParameterSetName = "Download")]
        [Parameter(Mandatory = $false, ParameterSetName = "ListOnly")]
        [Alias('deleted', 'archived', 'include-deleted')]
        [switch]$IncludeDeleted,

        [Parameter(Mandatory = $true, ParameterSetName = "ListOnly")]
        [Alias('list-only', 'show', 'preview')]
        [switch]$ListOnly
    )

    begin {
        Write-Verbose "🚀 Starting function $($MyInvocation.MyCommand.Name)"
    }

    process {
        try {
            # Ensure the download directory exists if we're downloading files
            if (-not $ListOnly -and -not [string]::IsNullOrEmpty($OutputPath)) {
                if (-not (Test-Path -Path $OutputPath)) {
                    Write-Host "📁 Creating output directory: $OutputPath" -ForegroundColor Yellow
                    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
                }
            }

            # Check if the URL already contains the container list parameters
            if ($BlobUrl -notlike "*restype=container&comp=list*") {
                $separator = if ($BlobUrl -like "*`?*") { "?" } else { "?" }
                $requestUrl = "$BlobUrl$separator" + "restype=container&comp=list"
            }
            else {
                $requestUrl = $BlobUrl
            }

            # Add the versions parameter if it's not already there
            if ($requestUrl -notlike "*include=versions*") {
                $requestUrl = "$requestUrl&include=versions"
            }

            $params = @{
                Uri             = $requestUrl
                Headers         = @{
                    "x-ms-version" = "2019-12-12"
                    "Accept"       = "application/xml"
                }
                UseBasicParsing = $true
            }

            $fileContent = Invoke-RestMethod @params

            if ($BlobUrl -match '^(https?://[^/]+)/([^/?]+)') {
                $matchResults = $matches
                $serviceEndpoint = $matchResults[1] + "/"
                $containerName = $matchResults[2]
            }
            else {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "❌ Invalid URI format. Expected format: https://storage.blob.core.windows.net/container" -ErrorAction Error
            }

            # Define the regex pattern to extract file names, version IDs, and their current version status
            $isCurrentVersion = '<Blob><Name>([^<]+)</Name><VersionId>([^<]+)</VersionId><IsCurrentVersion>([^<]+)</IsCurrentVersion>'
            $isNotCurrentVersion = '<Blob><Name>([^<]+)</Name><VersionId>([^<]+)</VersionId>(?!<IsCurrentVersion>true</IsCurrentVersion>)'

            # Match the pattern in the file content
            $fileMatches = [regex]::Matches($fileContent, $isCurrentVersion)

            if ($IncludeDeleted) {
                $fileMatches = [regex]::Matches($fileContent, $isNotCurrentVersion)
            }

            $messageType = if ($ListOnly) { "📋 to list" } else { "⬇️ to download" }
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "🔍 Found $($fileMatches.Count) files $messageType" -Severity 'Information'

            if ($ListOnly) {
                $fileList = @()
                foreach ($match in $fileMatches) {
                    $fileName  = $match.Groups[1].Value
                    $versionId = $match.Groups[2].Value
                    $isCurrentVersion = $match.Groups.Count -gt 3 -and $match.Groups[3].Value -eq 'true'
                    $status = if ($isCurrentVersion) { "✅ Current" } else { "🗑️  Deleted" }

                    $fileList += [PSCustomObject]@{
                        Name      = "📄 $fileName"
                        Status    = $status
                        VersionId = $versionId
                        FullPath  = "$serviceEndpoint$containerName/$fileName"
                    }
                }
                Write-Host "📋 Blob listing complete! Found $($fileList.Count) files." -ForegroundColor Green
                return $fileList
            }

            # Add progress message before starting downloads
            Write-Host "🚀 Starting parallel downloads with throttle limit of 100..." -ForegroundColor Cyan
            
            $fileMatches | ForEach-Object -Parallel {
                $fileName         = $_.Groups[1].Value
                $versionId        = $_.Groups[2].Value
                $isCurrentVersion = $_.Groups[3].Value -eq 'true'

                $serviceEndpoint = $using:serviceEndpoint
                $containerName   = $using:containerName
                $OutputPath      = $using:OutputPath

                if ($isCurrentVersion) {
                    $fileUrl = "$serviceEndpoint$containerName/$fileName"
                }
                else {
                    $fileUrl = '{0}{1}/{2}?versionId={3}' -f $serviceEndpoint, $containerName, $fileName, $versionId
                }

                $downloadPath = Join-Path -Path $OutputPath -ChildPath $fileName
                $downloadDirPath = Split-Path -Path $downloadPath

                if (-not (Test-Path -Path $downloadDirPath)) {

                    New-Item -ItemType Directory -Path $downloadDirPath -Force | Out-Null
                }

                # Download the file
                $params = @{
                    Uri             = $fileUrl
                    OutFile         = $downloadPath
                    UseBasicParsing = $true
                    Headers         = @{"x-ms-version" = "2019-12-12" }
                }

                try {
                    Invoke-RestMethod @params
                    Write-Information "✅ Downloaded: $fileName" -InformationAction Continue
                }
                catch {
                    Write-Information "❌ Failed to download: $fileName - $($_.Exception.Message)" -InformationAction Continue
                }
            } -ThrottleLimit 100
            
            Write-Host "🎉 Download process completed!" -ForegroundColor Green
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "💥 $($_.Exception.Message)" -Severity 'Error'
        }
    }

    end {
        Write-Verbose "✅ Ending function $($MyInvocation.MyCommand.Name)"
    }

    <#
    .SYNOPSIS
        Downloads or lists files from a public Azure Blob Storage account, including deleted (soft-deleted) blobs.

    .DESCRIPTION
        The Get-PublicBlobContent function downloads files from a specified public Azure Blob Storage account URL.
        It can also download deleted (soft-deleted) blobs if the IncludeDeleted switch is specified.
        Use the ListOnly parameter to preview the blobs before downloading them.

    .PARAMETER BlobUrl
        The URL of the Azure Blob Storage account. The URL must match the pattern 'https://[account].blob.core.windows.net/[container]'.
        Aliases: url, uri

    .PARAMETER OutputPath
        The directory where the files will be downloaded. If the directory does not exist, it will be created.
        This parameter is not required when using -ListOnly (ListOnly parameter set).
        Aliases: path, out, dir

    .PARAMETER IncludeDeleted
        A switch to indicate whether to download or list soft-deleted blobs. If not specified, only the current versions will be included.
        Aliases: deleted, archived, include-deleted

    .PARAMETER ListOnly
        When specified, the function will only list the blobs without downloading them. This is useful for previewing what would be downloaded.
        When using this parameter, -OutputPath is not required.
        Aliases: list-only, show, preview

    .EXAMPLE
        Get-PublicBlobContent -BlobUrl "https://mystorageaccount.blob.core.windows.net/mycontainer" -OutputPath "/home/user/downloads"

        This example downloads the current versions of the files from the specified Azure Blob Storage account to the /home/user/downloads directory.

    .EXAMPLE
        Get-PublicBlobContent -url "https://mystorageaccount.blob.core.windows.net/mycontainer" -path "/home/user/downloads" -IncludeDeleted

        This example uses aliases to download both current and deleted versions of the files.

    .EXAMPLE
        Get-PublicBlobContent -BlobUrl "https://mystorageaccount.blob.core.windows.net/mycontainer" -ListOnly

        This example lists all current blobs in the container without downloading them.

    .EXAMPLE
        Get-PublicBlobContent -url "https://mystorageaccount.blob.core.windows.net/mycontainer" -IncludeDeleted -ListOnly

        This example lists both current and deleted blobs in the container without downloading them.

    .EXAMPLE
        Get-PublicStorageAccounts -storageAccountName 'mystorage' | Get-PublicBlobContent -OutputPath "/home/user/downloads"

        This example retrieves public file containers for the specified storage account and downloads the files to the /home/user/downloads directory.

    .NOTES
        Author: Rogier Dijkman
    #>
}