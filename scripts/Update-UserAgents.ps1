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
    $firefoxVersion = Get-VerifiedVersion (Invoke-RestMethod -Uri $firefoxSource -TimeoutSec 60).FIREFOX_VERSION
    $firefox = "$(([version]$firefoxVersion).Major).$(([version]$firefoxVersion).Minor)"
    Write-Information "Firefox stable $firefoxVersion — $firefoxSource" -InformationAction Continue

    $chrome = @{}
    foreach ($platform in @('win', 'mac', 'linux')) {
        $source = "https://versionhistory.googleapis.com/v1/chrome/platforms/$platform/channels/stable/versions/all/releases?filter=endtime=none,fraction%3E0"
        $releases = @()
        $pageToken = $null
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
            $_.ReleaseDate -and [datetimeoffset]$_.ReleaseDate -le $now
        })
    $edgeVersions = @($edgeReleases | ForEach-Object { Get-VerifiedVersion $_.ProductVersion } |
        Sort-Object { [version]$_ } -Descending)
    if (-not $edgeVersions.Count) { throw 'No released Windows x64 Edge stable version.' }
    $edge = $edgeVersions[0]
    Write-Information "Edge stable $edge — $edgeSource" -InformationAction Continue

    $platformTokens = @{
        windows = 'Windows NT 10.0; Win64; x64'
        mac = 'Macintosh; Intel Mac OS X 10_15_7'
        linux = 'X11; Linux x86_64'
    }
    $chromePlatforms = @{ windows = 'win'; mac = 'mac'; linux = 'linux' }
    foreach ($agent in $list.agents) {
        if ($agent.type -match '^(windows|mac|linux)_(chrome|firefox)$') {
            $platform = $Matches[1]
            $browser = $Matches[2]
            $token = $platformTokens[$platform]
            if ($browser -eq 'chrome') {
                $agent.value = "Mozilla/5.0 ($token) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$($chrome[$chromePlatforms[$platform]]) Safari/537.36"
            } else {
                if ($platform -eq 'mac') { $token = 'Macintosh; Intel Mac OS X 10.15' }
                $agent.value = "Mozilla/5.0 ($token; rv:$firefox) Gecko/20100101 Firefox/$firefox"
            }
        }
        elseif ($agent.type -eq 'windows_edge') {
            $agent.value = "Mozilla/5.0 ($($platformTokens.windows)) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$(([version]$edge).Major).0.0.0 Safari/537.36 Edg/$edge"
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
