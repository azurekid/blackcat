function Get-PublicStorageAccountContent {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^https://[a-z0-9]+\.blob\.core\.windows\.net/[^/?]+', ErrorMessage = "It does not match expected pattern '{1}'")]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$DownloadDirectory,


        [Parameter(Mandatory = $false)]
        [switch]$ArchivedVersions
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
    }

    process {
        try {
            # Ensure the download directory exists
            if (-not (Test-Path -Path $DownloadDirectory)) {
                New-Item -ItemType Directory -Path $DownloadDirectory -Force | Out-Null
            }

            # Get the XML content from the URI
            $params = @{
                Uri             = "$Uri&include=versions"
                Headers         = @{
                    "x-ms-version" = "2019-12-12"
                    "Accept"       = "application/xml"
                }
                UseBasicParsing = $true
            }

            $fileContent = Invoke-RestMethod @params

            # Extract service endpoint and container name from the URI
            if ($Uri -match '^(https?://[^/]+)/([^/?]+)') {
                $matchResults = $matches
                $serviceEndpoint = $matchResults[1] + "/"
                $containerName   = $matchResults[2]
            }
            else {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Invalid URI format. Expected format: https://storage.blob.core.windows.net/container" -ErrorAction Error
            }

            # Define the regex pattern to extract file names, version IDs, and their current version status
            $isCurrentVersion = '<Blob><Name>([^<]+)</Name><VersionId>([^<]+)</VersionId><IsCurrentVersion>([^<]+)</IsCurrentVersion>'
            $isNotCurrentVersion = '<Blob><Name>([^<]+)</Name><VersionId>([^<]+)</VersionId>(?!<IsCurrentVersion>true</IsCurrentVersion>)'

            # Match the pattern in the file content
            $fileMatches = [regex]::Matches($fileContent, $isCurrentVersion)

            if ($ArchivedVersions) {
                $fileMatches = [regex]::Matches($fileContent, $isNotCurrentVersion)
            }

             Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Found $($fileMatches.Count) files to download" -Severity 'Information'

            # Download each file based on the current version status
            $fileMatches | ForEach-Object -Parallel{
                $fileName         = $_.Groups[1].Value
                $versionId        = $_.Groups[2].Value
                $isCurrentVersion = $_.Groups[3].Value -eq 'true'

                $serviceEndpoint    = $using:serviceEndpoint
                $containerName      = $using:containerName
                $DownloadDirectory  = $using:DownloadDirectory

                if ($isCurrentVersion) {
                    $fileUrl = "$serviceEndpoint$containerName/$fileName"
                }
                else {
                    $fileUrl = '{0}{1}/{2}?versionId={3}' -f $serviceEndpoint, $containerName, $fileName, $versionId
                }

                $downloadPath = Join-Path -Path $DownloadDirectory -ChildPath $fileName

                # Ensure the directory exists
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
                }
                catch {
                    Write-Information "Failed to download: $fileName" -InformationAction Continue
                }
            } -ThrottleLimit 100
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }

    end {
        Write-Verbose "Ending function $($MyInvocation.MyCommand.Name)"
    }

    <#
    .SYNOPSIS
        Downloads files from a public Azure Blob Storage account.

    .DESCRIPTION
        The Get-PublicStorageAccountContent function downloads files from a specified public Azure Blob Storage account URI.
        It can also download archived versions of the files if the ArchivedVersions switch is specified.

    .PARAMETER Uri
        The URI of the Azure Blob Storage account. The URI must match the pattern 'https://[account].blob.core.windows.net/[container]'.

    .PARAMETER DownloadDirectory
        The directory where the files will be downloaded. If the directory does not exist, it will be created.

    .PARAMETER ArchivedVersions
        A switch to indicate whether to download archived versions of the files. If not specified, only the current versions will be downloaded.

    .EXAMPLE
        ```powershell
        Get-PublicStorageAccountContent -Uri "https://mystorageaccount.blob.core.windows.net/mycontainer" -DownloadDirectory "C:\Downloads"
        ```
        This example downloads the current versions of the files from the specified Azure Blob Storage account to the C:\Downloads directory.

    .EXAMPLE
        ```powershell
        Get-PublicStorageAccountContent -Uri "https://mystorageaccount.blob.core.windows.net/mycontainer" -DownloadDirectory "C:\Downloads" -ArchivedVersions
        ```
        This example downloads both the archived versions of the files from the specified Azure Blob Storage account to the C:\Downloads directory.

    .EXAMPLE
        ```powershell
        Get-PublicStorageAccounts -storageAccountName 'mystorage' | Get-PublicStorageAccountContent -DownloadDirectory "C:\Downloads"
        ```
        This example retrieves public file containers for the specified storage account and downloads the files to the C:\Downloads directory.

    .NOTES
        Author: Rogier Dijkman
    #>
}