function Get-FileShareContent {
    [CmdletBinding(DefaultParameterSetName = "Authenticated")]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[a-z0-9]{3,24}$', ErrorMessage = "Storage account name must be 3-24 lowercase alphanumeric characters")]
        [Alias('storage', 'account', 'sa')]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias('share', 'fs')]
        [string]$FileShareName,

        [Parameter(Mandatory = $false)]
        [Alias('directory', 'folder')]
        [string]$Path = "",

        [Parameter(Mandatory = $true, ParameterSetName = "SasToken")]
        [Alias('sas', 'token')]
        [string]$SasToken,

        [Parameter(Mandatory = $false)]
        [switch]$Recurse,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [Alias('save', 'fetch')]
        [switch]$Download,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Object", "JSON", "CSV", "Table")]
        [Alias("output", "o")]
        [string]$OutputFormat = "Table"
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        
        # Clean up SAS token if provided - remove leading ? if present
        if ($SasToken) {
            $SasToken = $SasToken.TrimStart('?')
        }

        # Build base URL
        $baseUrl = "https://$StorageAccountName.file.core.windows.net"

        # Determine auth method
        if ($PSCmdlet.ParameterSetName -eq "SasToken") {
            $authMethod = "SasToken"
            Write-Verbose "[+] Using SAS token authentication"
        }
        else {
            $authMethod = "Bearer"
            Write-Verbose "[+] Using current authentication context"
            
            # Get token for Azure Storage
            try {
                $token = Get-AzAccessToken -ResourceUrl "https://storage.azure.com/" -ErrorAction Stop
                $accessToken = $token.Token
            }
            catch {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Failed to get access token. Ensure you're authenticated with Connect-ServicePrincipal or Connect-AzAccount" -Severity 'Error'
                return
            }
        }
    }

    process {
        try {
            # Handle FileShareName with path (e.g., "docs/config")
            if ($FileShareName -and $FileShareName.Contains('/')) {
                $parts = $FileShareName -split '/', 2
                $FileShareName = $parts[0]
                if ([string]::IsNullOrWhiteSpace($Path)) {
                    $Path = $parts[1]
                    Write-Verbose "[+] Split FileShareName: Share='$FileShareName', Path='$Path'"
                }
            }

            # If no FileShareName provided, list all shares
            if ([string]::IsNullOrWhiteSpace($FileShareName)) {
                Write-Verbose "[+] No FileShareName provided - listing all file shares"
                $shares = Get-FileShares -BaseUrl $baseUrl -AuthMethod $authMethod -SasToken $SasToken -AccessToken $accessToken
                return (Format-BlackCatOutput -Data $shares -OutputFormat $OutputFormat -FunctionName $MyInvocation.MyCommand.Name)
            }

            # List contents of specific share/path
            $contents = Get-DirectoryContents -BaseUrl $baseUrl -FileShareName $FileShareName -Path $Path -AuthMethod $authMethod -SasToken $SasToken -AccessToken $accessToken -Recurse:$Recurse

            # Handle download if OutputPath is specified
            if (-not [string]::IsNullOrEmpty($OutputPath)) {
                if (-not (Test-Path -Path $OutputPath)) {
                    Write-Host " Creating output directory: $OutputPath" -ForegroundColor Yellow
                    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
                }

                $files = $contents | Where-Object { $_.Type -eq 'File' }
                Write-Host "Downloading $($files.Count) files..." -ForegroundColor Cyan

                foreach ($file in $files) {
                    $fileUrl = "$baseUrl/$FileShareName$($file.Path)"
                    if ($authMethod -eq "SasToken") {
                        $fileUrl = "$fileUrl`?$SasToken"
                    }

                    $downloadPath = Join-Path -Path $OutputPath -ChildPath $file.Path
                    $downloadDir = Split-Path -Path $downloadPath -Parent

                    if (-not (Test-Path -Path $downloadDir)) {
                        New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
                    }

                    try {
                        $headers = @{}
                        if ($authMethod -eq "Bearer") {
                            $headers["Authorization"] = "Bearer $accessToken"
                            $headers["x-ms-version"] = "2021-06-08"
                        }

                        Invoke-WebRequest -Uri $fileUrl -OutFile $downloadPath -Headers $headers -UseBasicParsing
                        Write-Host "  Downloaded: $($file.Path)" -ForegroundColor Green
                    }
                    catch {
                        Write-Host "  Failed: $($file.Path) - $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
            }

            return (Format-BlackCatOutput -Data $contents -OutputFormat $OutputFormat -FunctionName $MyInvocation.MyCommand.Name)
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Error: $($_.Exception.Message)" -Severity 'Error'
        }
    }
}

function Get-FileShares {
    param (
        [string]$BaseUrl,
        [string]$AuthMethod,
        [string]$SasToken,
        [string]$AccessToken
    )

    $listUrl = "$BaseUrl/?comp=list"

    if ($AuthMethod -eq "SasToken") {
        $listUrl = "$listUrl&$SasToken"
        $headers = @{
            "x-ms-version" = "2021-06-08"
        }
    }
    else {
        $headers = @{
            "Authorization" = "Bearer $AccessToken"
            "x-ms-version"  = "2021-06-08"
        }
    }

    try {
        $rawResponse = Invoke-RestMethod -Uri $listUrl -Headers $headers -UseBasicParsing
        
        # Handle BOM in response - Azure Storage returns UTF-8 BOM which breaks XML parsing
        if ($rawResponse -is [string]) {
            $cleanResponse = $rawResponse.TrimStart([char]0xFEFF) -replace '^\xEF\xBB\xBF', ''
            $xml = New-Object System.Xml.XmlDocument
            $xml.LoadXml($cleanResponse)
            $response = $xml
        }
        else {
            $response = $rawResponse
        }
        
        $shares = @()
        
        # Parse XML response
        if ($response.EnumerationResults.Shares.Share) {
            foreach ($share in $response.EnumerationResults.Shares.Share) {
                $status = if ($share.Properties.DeletedTime) { "🗑️ Deleted" } else { "Active" }
                
                $shares += [PSCustomObject]@{
                    Name            = $share.Name
                    Type            = "FileShare"
                    Status          = $status
                    LastModified    = $share.Properties.'Last-Modified'
                    Quota           = $share.Properties.Quota
                    DeletedTime     = $share.Properties.DeletedTime
                    RemainingDays   = $share.Properties.RemainingRetentionDays
                }
            }
        }

        Write-Host "Found $($shares.Count) file shares" -ForegroundColor Green
        return $shares
    }
    catch {
        Write-Message -FunctionName "Get-FileShares" -Message "Failed to list shares: $($_.Exception.Message)" -Severity 'Error'
        throw
    }
}

function Get-DirectoryContents {
    param (
        [string]$BaseUrl,
        [string]$FileShareName,
        [string]$Path,
        [string]$AuthMethod,
        [string]$SasToken,
        [string]$AccessToken,
        [switch]$Recurse
    )

    # Clean up path
    $Path = $Path.TrimStart('/')
    
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $listUrl = "$BaseUrl/$FileShareName/?restype=directory&comp=list"
    }
    else {
        $listUrl = "$BaseUrl/$FileShareName/$Path`?restype=directory&comp=list"
    }

    if ($AuthMethod -eq "SasToken") {
        $listUrl = "$listUrl&$SasToken"
        $headers = @{
            "x-ms-version" = "2021-06-08"
        }
    }
    else {
        $headers = @{
            "Authorization" = "Bearer $AccessToken"
            "x-ms-version"  = "2021-06-08"
        }
    }

    try {
        $rawResponse = Invoke-RestMethod -Uri $listUrl -Headers $headers -UseBasicParsing
        
        # Handle BOM in response - Azure Storage returns UTF-8 BOM which breaks XML parsing
        if ($rawResponse -is [string]) {
            $cleanResponse = $rawResponse.TrimStart([char]0xFEFF) -replace '^\xEF\xBB\xBF', ''
            $xml = New-Object System.Xml.XmlDocument
            $xml.LoadXml($cleanResponse)
            $response = $xml
        }
        else {
            $response = $rawResponse
        }
        
        $contents = @()
        $currentPath = if ([string]::IsNullOrWhiteSpace($Path)) { "" } else { "/$Path" }

        # Parse directories
        if ($response.EnumerationResults.Entries.Directory) {
            $directories = @($response.EnumerationResults.Entries.Directory)
            foreach ($dir in $directories) {
                $dirPath = "$currentPath/$($dir.Name)"
                
                $contents += [PSCustomObject]@{
                    Name         = $dir.Name
                    Type         = "Directory"
                    Path         = $dirPath
                    Size         = $null
                    LastModified = $dir.Properties.'Last-Modified'
                    FullUrl      = "$BaseUrl/$FileShareName$dirPath"
                }

                # Recurse into subdirectories if requested
                if ($Recurse) {
                    $subContents = Get-DirectoryContents -BaseUrl $BaseUrl -FileShareName $FileShareName -Path $dirPath.TrimStart('/') -AuthMethod $AuthMethod -SasToken $SasToken -AccessToken $AccessToken -Recurse:$Recurse
                    $contents += $subContents
                }
            }
        }

        # Parse files
        if ($response.EnumerationResults.Entries.File) {
            $files = @($response.EnumerationResults.Entries.File)
            foreach ($file in $files) {
                $filePath = "$currentPath/$($file.Name)"
                
                $contents += [PSCustomObject]@{
                    Name         = $file.Name
                    Type         = "File"
                    Path         = $filePath
                    Size         = [int64]$file.Properties.'Content-Length'
                    LastModified = $file.Properties.'Last-Modified'
                    FullUrl      = "$BaseUrl/$FileShareName$filePath"
                }
            }
        }

        if ($currentPath -eq "") {
            Write-Host "Found $($contents.Count) items in share '$FileShareName'" -ForegroundColor Green
        }

        return $contents
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            Write-Verbose "Path not found or empty: $Path"
            return @()
        }
        Write-Message -FunctionName "Get-DirectoryContents" -Message "Failed to list contents: $($_.Exception.Message)" -Severity 'Error'
        throw
    }
}

<#
    .SYNOPSIS
        Lists file shares or contents from an Azure Storage Account using SAS token or authenticated context.

    .DESCRIPTION
        Enumerates files/directories in Azure File Shares with SAS token or auth access.

    .PARAMETER StorageAccountName
        The name of the Azure Storage Account (3-24 lowercase alphanumeric characters).
        Aliases: storage, account, sa

    .PARAMETER FileShareName
        The name of the file share to enumerate. If not provided, lists all shares in the account.
        Aliases: share, fs

    .PARAMETER Path
        The directory path within the file share to list. Defaults to root.
        Aliases: directory, folder

    .PARAMETER SasToken
        A SAS token string for authentication. Can include or exclude the leading '?'.
        Aliases: sas, token

    .PARAMETER Recurse
        When specified, recursively enumerates all subdirectories.

    .PARAMETER OutputPath
        The directory where files will be downloaded. When specified, automatically downloads all files from the share/path.

    .PARAMETER Download
        Legacy parameter. No longer required - specifying -OutputPath is sufficient to trigger download.
        Aliases: save, fetch

    .PARAMETER OutputFormat
        Specifies the output format for the results. Valid values are:
        - Table: Displays results in a formatted table (default)
        - Object: Returns PowerShell objects for pipeline usage
        - JSON: Exports results to a JSON file
        - CSV: Exports results to a CSV file
        Aliases: output, o

    .EXAMPLE
        Get-FileShareContent -StorageAccountName "bluemountaintravelsa" -SasToken $token

        Lists all file shares in the storage account using the provided SAS token.

    .EXAMPLE
        Get-FileShareContent -StorageAccountName "bluemountaintravelsa" -SasToken $token -OutputFormat Object

        Lists all file shares and returns objects for pipeline processing.

    .EXAMPLE
        Get-FileShareContent -StorageAccountName "bluemountaintravelsa" -FileShareName "docs" -SasToken $token -OutputFormat JSON

        Lists contents of the 'docs' share and exports results to a JSON file.

    .EXAMPLE

        Lists all file shares in the storage account using the provided SAS token.

    .EXAMPLE
        Get-FileShareContent -StorageAccountName "bluemountaintravelsa" -FileShareName "docs" -SasToken $token

        Lists all directories and files in the root of the 'docs' file share.

    .EXAMPLE
        Get-FileShareContent -sa "bluemountaintravelsa" -share "docs" -Path "/config" -sas $token

        Lists contents of the /config directory within the 'docs' share.

    .EXAMPLE
        Get-FileShareContent -StorageAccountName "bluemountaintravelsa" -FileShareName "docs" -SasToken $token -Recurse

        Recursively lists all directories and files in the 'docs' share.

    .EXAMPLE
        Get-FileShareContent -StorageAccountName "bluemountaintravelsa" -FileShareName "docs" -SasToken $token -OutputPath "./loot"

        Downloads all files from the 'docs' share to the ./loot directory.

    .EXAMPLE
        Get-FileShareContent -StorageAccountName "bluemountaintravelsa" -FileShareName "docs"

        Lists contents using the current authenticated context (Connect-ServicePrincipal).

    .NOTES
        Author: Rogier Dijkman
        
        The SAS token needs appropriate permissions:
        - ss=f (File service)
        - srt=sco (Service, Container, Object) for full enumeration
        - sp=rl (Read, List) minimum permissions

    .LINK
        MITRE ATT&CK Tactic: TA0010 - Exfiltration
        https://attack.mitre.org/tactics/TA0010/

    .LINK
        MITRE ATT&CK Technique: T1530 - Data from Cloud Storage
        https://attack.mitre.org/techniques/T1530/
#>
