[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path $PSScriptRoot -Parent)
)

function Update-UserAgentList {
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot = (Split-Path $PSScriptRoot -Parent)
    )

    $ErrorActionPreference = 'Stop'
    $path = Join-Path $RepositoryRoot 'Private/Reference/userAgents.json'
    $list = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if (-not $list.agents -or @($list.agents | Where-Object {
        [string]::IsNullOrWhiteSpace($_.type) -or $_.value -isnot [string] -or
        [string]::IsNullOrWhiteSpace($_.value)
    }).Count) {
        throw 'The configured user-agent list is malformed.'
    }

    function Get-VerifiedVersion {
        param([string]$Value)
        if ($Value -notmatch '^\d+\.\d+(?:\.\d+){0,2}$') {
            throw "Invalid stable browser version: '$Value'."
        }
        return $Value
    }

    $now = [datetimeoffset]::UtcNow
    $firefoxSource = 'https://product-details.mozilla.org/1.0/firefox_versions.json'
    try {
        $firefoxMetadata = Invoke-RestMethod -Uri $firefoxSource -TimeoutSec 60
    }
    catch {
        $firefoxSource = 'https://raw.githubusercontent.com/mozilla-releng/product-details/production/public/1.0/firefox_versions.json'
        Write-Warning "Mozilla endpoint unavailable; using official production metadata: $firefoxSource"
        $firefoxMetadata = Invoke-RestMethod -Uri $firefoxSource -TimeoutSec 60
    }
    $firefoxVersion = Get-VerifiedVersion $firefoxMetadata.LATEST_FIREFOX_VERSION
    $firefox = "$(([version]$firefoxVersion).Major).$(([version]$firefoxVersion).Minor)"
    Write-Information "Firefox stable $firefoxVersion — $firefoxSource" -InformationAction Continue

    $chrome = @{}
    foreach ($platform in @('win64', 'mac', 'linux')) {
        $source = "https://versionhistory.googleapis.com/v1/chrome/platforms/$platform/channels/stable/versions/all/releases?filter=endtime=none,fraction%3E0"
        $releases = @()
        $pageToken = $null
        try {
            do {
                $uri = if ($pageToken) { "$source&pageToken=$([uri]::EscapeDataString($pageToken))" } else { $source }
                $page = Invoke-RestMethod -Uri $uri -TimeoutSec 60
                $releases += @($page.releases | Where-Object {
                    $_.fraction -gt 0 -and $_.serving.startTime -and
                    [datetimeoffset]$_.serving.startTime -le $now -and
                    -not $_.serving.endTime
                })
                $pageToken = $page.nextPageToken
            } while ($pageToken)
        }
        catch {
            $source = 'https://raw.githubusercontent.com/GoogleChromeLabs/chrome-for-testing/main/data/last-known-good-versions-with-downloads.json'
            Write-Warning "VersionHistory unavailable; using published Chrome for Testing Stable metadata: $source"
            $metadata = Invoke-RestMethod -Uri $source -TimeoutSec 60
            $downloadPlatform = @{ win64 = 'win64'; mac = 'mac-x64'; linux = 'linux64' }[$platform]
            $stable = $metadata.channels.Stable
            if ($stable.channel -ne 'Stable' -or -not $metadata.timestamp -or
                [datetimeoffset]$metadata.timestamp -gt $now -or
                [datetimeoffset]$metadata.timestamp -lt $now.AddDays(-7) -or
                -not @($stable.downloads.chrome | Where-Object platform -EQ $downloadPlatform).Count) {
                throw "No recent published Chrome for Testing Stable metadata for $platform."
            }
            $releases = @(@{ version = $stable.version })
        }
        $versions = @($releases | ForEach-Object { Get-VerifiedVersion $_.version } |
            Sort-Object { [version]$_ } -Descending)
        if (-not $versions.Count) { throw "No currently serving Chrome stable release for $platform." }
        $chrome[$platform] = "$(([version]$versions[0]).Major).0.0.0"
        Write-Information "Chrome $platform stable $($versions[0]) — $source" -InformationAction Continue
    }

    $edgeSource = 'https://edgeupdates.microsoft.com/api/products?view=enterprise'
    $edgeProducts = Invoke-RestMethod -Uri $edgeSource -TimeoutSec 60
    $edgeReleases = @($edgeProducts | Where-Object Product -EQ 'Stable' |
        ForEach-Object Releases | Where-Object {
            $_.Platform -eq 'Windows' -and $_.Architecture -eq 'x64' -and
            $_.PublishedTime -and [datetimeoffset]$_.PublishedTime -le $now
        })
    $edgeVersions = @($edgeReleases | ForEach-Object { Get-VerifiedVersion $_.ProductVersion } |
        Sort-Object { [version]$_ } -Descending)
    if (-not $edgeVersions.Count) { throw 'No released Windows x64 Edge stable version.' }
    $edge = $edgeVersions[0]
    Write-Information "Edge stable $edge — $edgeSource" -InformationAction Continue

    $braveSource = 'https://api.github.com/repos/brave/brave-browser/releases/latest'
    $braveRelease = Invoke-RestMethod -Uri $braveSource -UserAgent 'BlackCat-UserAgent-Refresh' -TimeoutSec 60
    if ($braveRelease.draft -or $braveRelease.prerelease -or
        $braveRelease.tag_name -notmatch '^v\d+\.\d+\.\d+$' -or
        -not $braveRelease.published_at -or [datetimeoffset]$braveRelease.published_at -gt $now) {
        throw 'No published Brave stable release.'
    }
    $braveVersion = Get-VerifiedVersion $braveRelease.tag_name.Substring(1)
    $braveCoreSource = "https://raw.githubusercontent.com/brave/brave-core/$($braveRelease.tag_name)/package.json"
    $braveCore = Invoke-RestMethod -Uri $braveCoreSource -TimeoutSec 60
    if ($braveCore.version -ne $braveVersion) { throw 'Brave tagged source does not match its stable release.' }
    $braveChromium = Get-VerifiedVersion $braveCore.config.projects.chrome.tag
    Write-Information "Brave stable $braveVersion, Chromium $braveChromium — $braveSource; $braveCoreSource" -InformationAction Continue

    $platformTokens = @{
        windows = 'Windows NT 10.0; Win64; x64'
        mac = 'Macintosh; Intel Mac OS X 10_15_7'
        linux = 'X11; Linux x86_64'
    }
    $chromePlatforms = @{ windows = 'win64'; mac = 'mac'; linux = 'linux' }
    foreach ($agent in $list.agents) {
        if ($agent.type -match '^(windows|mac|linux)_(chrome|firefox|brave)$') {
            $platform = $Matches[1]
            $browser = $Matches[2]
            $token = $platformTokens[$platform]
            if ($browser -in @('chrome', 'brave')) {
                $engine = if ($browser -eq 'brave') { "$(([version]$braveChromium).Major).0.0.0" } else { $chrome[$chromePlatforms[$platform]] }
                $agent.value = "Mozilla/5.0 ($token) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$engine Safari/537.36"
            } else {
                if ($platform -eq 'mac') { $token = 'Macintosh; Intel Mac OS X 10.15' }
                $agent.value = "Mozilla/5.0 ($token; rv:$firefox) Gecko/20100101 Firefox/$firefox"
            }
        }
        elseif ($agent.type -eq 'windows_edge') {
            $agent.value = "Mozilla/5.0 ($($platformTokens.windows)) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$(([version]$edge).Major).0.0.0 Safari/537.36 Edg/$(([version]$edge).Major).0.0.0"
        }
        else {
            # Do not substitute Chrome's release for another browser's embedded engine.
            Write-Warning "Retaining $($agent.type): no verified stable vendor metadata provider is configured."
        }
    }

    # Fetch and validate all metadata before touching either copy.
    $json = ($list | ConvertTo-Json -Depth 5) + "`n"
    foreach ($destination in @($path, (Join-Path $RepositoryRoot 'support-files/userAgents.json'))) {
        [System.IO.File]::WriteAllText($destination, $json, [System.Text.UTF8Encoding]::new($false))
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Update-UserAgentList -RepositoryRoot $RepositoryRoot
}
