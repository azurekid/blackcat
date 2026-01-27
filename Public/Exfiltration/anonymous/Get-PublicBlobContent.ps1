function Get-PublicBlobContent {
    [cmdletbinding(DefaultParameterSetName = "List")]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = "Download")]
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = "List")]
        [ValidatePattern('^https://[a-z0-9]+\.blob\.core\.windows\.net/[^?]+', ErrorMessage = "It does not match expected pattern '{1}'")]
        [Alias('url', 'uri')]
        [string]$BlobUrl,

        [Parameter(Mandatory = $true, ParameterSetName = "Download")]
        [Alias('path', 'out', 'dir')]
        [string]$OutputPath,

        [Parameter(Mandatory = $false, ParameterSetName = "Download")]
        [Parameter(Mandatory = $false, ParameterSetName = "List")]
        [Alias('deleted', 'archived', 'include-deleted')]
        [switch]$IncludeDeleted,

        [Parameter(Mandatory = $true, ParameterSetName = "Download")]
        [Alias('save', 'fetch')]
        [switch]$Download
    )

    begin {
        Write-Verbose "🚀 Starting function $($MyInvocation.MyCommand.Name)"
    }

    process {
        try {
            # Ensure the download directory exists if we're downloading files
            if ($Download -and -not [string]::IsNullOrEmpty($OutputPath)) {
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

            $messageType = if ($Download) { "⬇️ to download" } else { "📋 to list" }
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "🔍 Found $($fileMatches.Count) files $messageType" -Severity 'Information'

            if (-not $Download) {
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
        Lists or downloads files from a public Azure Blob Storage account, including deleted (soft-deleted) blobs.

    .DESCRIPTION
        The Get-PublicBlobContent function lists files from a specified public Azure Blob Storage account URL by default.
        Use the -Download switch along with -OutputPath to download the files.
        It can also include deleted (soft-deleted) blobs if the IncludeDeleted switch is specified.

    .PARAMETER BlobUrl
        The URL of the Azure Blob Storage account. The URL must match the pattern 'https://[account].blob.core.windows.net/[container]'.
        Aliases: url, uri

    .PARAMETER OutputPath
        The directory where the files will be downloaded. If the directory does not exist, it will be created.
        This parameter is required when using -Download.
        Aliases: path, out, dir

    .PARAMETER IncludeDeleted
        A switch to indicate whether to include soft-deleted blobs. If not specified, only the current versions will be included.
        Aliases: deleted, archived, include-deleted

    .PARAMETER Download
        When specified along with -OutputPath, the function will download the blobs instead of just listing them.
        Aliases: save, fetch

    .EXAMPLE
        Get-PublicBlobContent -BlobUrl "https://mystorageaccount.blob.core.windows.net/mycontainer"

        This example lists all current blobs in the container.

    .EXAMPLE
        Get-PublicBlobContent -BlobUrl "https://mystorageaccount.blob.core.windows.net/mycontainer" -IncludeDeleted

        This example lists both current and deleted blobs in the container.

    .EXAMPLE
        Get-PublicBlobContent -BlobUrl "https://mystorageaccount.blob.core.windows.net/mycontainer" -OutputPath "/home/user/downloads" -Download

        This example downloads the current versions of the files from the specified Azure Blob Storage account to the /home/user/downloads directory.

    .EXAMPLE
        Get-PublicBlobContent -url "https://mystorageaccount.blob.core.windows.net/mycontainer" -path "/home/user/downloads" -IncludeDeleted -Download

        This example uses aliases to download both current and deleted versions of the files.

    .EXAMPLE
        Get-PublicStorageAccounts -storageAccountName 'mystorage' | Get-PublicBlobContent

        This example retrieves public file containers for the specified storage account and lists the files.

    .NOTES
        Author: Rogier Dijkman
    #>
}