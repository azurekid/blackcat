BeforeAll {
    . "$PSScriptRoot/../scripts/Update-UserAgents.ps1"
}

Describe 'Official stable user-agent refresh' {
    BeforeEach {
        $root = Join-Path $TestDrive 'repository'
        New-Item -ItemType Directory -Path "$root/Private/Reference", "$root/support-files" -Force | Out-Null
        $types = @('windows_chrome', 'mac_chrome', 'linux_chrome', 'windows_firefox',
            'mac_firefox', 'linux_firefox', 'windows_edge', 'mac_safari', 'chromebook',
            'windows_brave', 'windows_opera', 'windows_vivaldi')
        @{ agents = @($types | ForEach-Object { @{ type = $_; value = 'Preserved-Agent' } }) } |
            ConvertTo-Json -Depth 5 | Set-Content "$root/Private/Reference/userAgents.json"
        Set-Content "$root/support-files/userAgents.json" 'original-support-copy'
        Mock Invoke-RestMethod {
            param($Uri)
            if ($Uri -like '*firefox_versions.json') {
                @{ LATEST_FIREFOX_VERSION = '120.0.1'; FIREFOX_NIGHTLY = '999.0' }
            }

            elseif ($Uri -like '*edgeupdates*') {
                @(
                    @{ Product = 'Beta'; Releases = @(@{ Platform = 'Windows'; Architecture = 'x64'; ProductVersion = '999.0.1.1'; PublishedTime = '2020-01-01' }) }
                    @{ Product = 'Stable'; Releases = @(
                        @{ Platform = 'Windows'; Architecture = 'x64'; ProductVersion = '120.0.1.2'; PublishedTime = '2020-01-01' }
                        @{ Platform = 'MacOS'; Architecture = 'x64'; ProductVersion = '998.0.1.1'; PublishedTime = '2020-01-01' }
                        @{ Platform = 'Windows'; Architecture = 'x64'; ProductVersion = '997.0.1.1'; PublishedTime = '2099-01-01' }
                    ) }
                )
            }
            elseif ($Uri -like '*/brave-browser/releases/latest') {
                @{ tag_name = 'v1.2.3'; draft = $false; prerelease = $false; published_at = '2020-01-01' }
            }
            elseif ($Uri -like '*/brave-core/*') {
                @{ version = '1.2.3'; config = @{ projects = @{ chrome = @{ tag = '124.0.1.2' } } } }
            }
            else {
                $major = if ($Uri -like '*/mac/*') { 121 } elseif ($Uri -like '*/linux/*') { 122 } else { 120 }
                @{ releases = @(
                    @{ version = "$major.0.1.2"; fraction = 0.5; serving = @{ startTime = '2020-01-01' } }
                    @{ version = '999.0.1.2'; fraction = 0; serving = @{ startTime = '2020-01-01' } }
                    @{ version = '998.0.1.2'; fraction = 1; serving = @{ startTime = '2099-01-01' } }
                    @{ version = '997.0.1.2'; fraction = 1; serving = @{ startTime = '2020-01-01'; endTime = '2020-02-01' } }
                ) }
            }
        }
    }

    It 'synchronizes the schema and types using serving stable releases and realistic platform tokens' {
        Update-UserAgentList -RepositoryRoot $root
        $private = Get-Content "$root/Private/Reference/userAgents.json" -Raw
        $private | Should -BeExactly (Get-Content "$root/support-files/userAgents.json" -Raw)
        $list = $private | ConvertFrom-Json
        @($list.PSObject.Properties.Name) | Should -Be @('agents')
        $list.agents.type | Should -Be $types
        $list.agents[0].value | Should -Match 'Windows NT 10.0; Win64; x64.*Chrome/120.0.0.0 '
        $list.agents[1].value | Should -Match 'Intel Mac OS X 10_15_7.*Chrome/121.0.0.0 '
        $list.agents[2].value | Should -Match 'X11; Linux x86_64.*Chrome/122.0.0.0 '
        $list.agents[4].value | Should -Match 'Intel Mac OS X 10.15; rv:120.0.*Firefox/120.0$'
        $list.agents[6].value | Should -Match 'Chrome/120.0.0.0 .*Edg/120.0.0.0$'
        $list.agents[7,8,10,11].value | Should -Be @('Preserved-Agent', 'Preserved-Agent', 'Preserved-Agent', 'Preserved-Agent')
        $list.agents[9].value | Should -Match 'Chrome/124.0.0.0 '
        $list.agents[9].value | Should -Not -Match 'Brave/'
        $private | Should -Not -Match '999|998|997'
    }

    It 'follows Chrome release pagination and selects the highest released serving version' {
        Mock Invoke-RestMethod {
            param($Uri)
            if ($Uri -like '*pageToken=*') {
                @{ releases = @(@{ version = '123.0.1.2'; fraction = 0.1; serving = @{ startTime = '2020-01-01' } }) }
            } else {
                @{ releases = @(@{ version = '120.0.1.2'; fraction = 1; serving = @{ startTime = '2020-01-01' } }); nextPageToken = 'next page' }
            }
        } -ParameterFilter { $Uri -like '*versionhistory*' }
        Update-UserAgentList -RepositoryRoot $root
        (Get-Content "$root/Private/Reference/userAgents.json" -Raw | ConvertFrom-Json).agents[0].value |
            Should -Match 'Chrome/123.0.0.0 '
        Should -Invoke Invoke-RestMethod -Times 3 -Exactly -ParameterFilter { $Uri -match 'pageToken=next(%20| )page' }
    }

    It 'does not modify either copy when a provider fails or supplies invalid versions' {
        $original = Get-Content "$root/Private/Reference/userAgents.json" -Raw
        foreach ($response in @('unavailable', 'invalid-version')) {
            Mock Invoke-RestMethod {
                if ($response -eq 'unavailable') { throw 'Provider unavailable' }
                @{ LATEST_FIREFOX_VERSION = 'beta/999' }
            }
            { Update-UserAgentList -RepositoryRoot $root } | Should -Throw
            Get-Content "$root/Private/Reference/userAgents.json" -Raw | Should -BeExactly $original
            (Get-Content "$root/support-files/userAgents.json" -Raw).Trim() | Should -Be 'original-support-copy'
        }
    }

    It 'fails without writes if no Chrome release is currently serving' {
        Mock Invoke-RestMethod { @{ releases = @() } } -ParameterFilter { $Uri -like '*versionhistory*' }
        { Update-UserAgentList -RepositoryRoot $root } | Should -Throw '*No currently serving*'
        (Get-Content "$root/support-files/userAgents.json" -Raw).Trim() | Should -Be 'original-support-copy'
    }

    It 'uses official production Firefox metadata when the vendor endpoint is unavailable' {
        Mock Invoke-RestMethod { throw 'DNS unavailable' } -ParameterFilter { $Uri -like '*product-details.mozilla.org*' }
        Update-UserAgentList -RepositoryRoot $root
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Uri -like '*mozilla-releng/product-details/production/*' }
    }

    It 'falls back to recent platform-available Chrome for Testing Stable metadata' {
        Mock Invoke-RestMethod { throw 'DNS unavailable' } -ParameterFilter { $Uri -like '*versionhistory*' }
        Mock Invoke-RestMethod {
            @{ timestamp = [datetimeoffset]::UtcNow.AddMinutes(-1).ToString('o'); channels = @{
                Stable = @{ channel = 'Stable'; version = '125.0.1.2'; downloads = @{ chrome = @(
                    @{ platform = 'win64' }, @{ platform = 'mac-x64' }, @{ platform = 'linux64' }
                ) } }
                Beta = @{ version = '999.0.1.2' }
            } }
        } -ParameterFilter { $Uri -like '*chrome-for-testing*' }
        Update-UserAgentList -RepositoryRoot $root
        $list = Get-Content "$root/Private/Reference/userAgents.json" -Raw | ConvertFrom-Json
        $list.agents[0..2].value | ForEach-Object { $_ | Should -Match 'Chrome/125.0.0.0 ' }
    }

    It 'rejects stale Chrome fallback metadata before writing' {
        Mock Invoke-RestMethod { throw 'DNS unavailable' } -ParameterFilter { $Uri -like '*versionhistory*' }
        Mock Invoke-RestMethod {
            @{ timestamp = '2020-01-01'; channels = @{ Stable = @{ channel = 'Stable'; version = '120.0.1.2' } } }
        } -ParameterFilter { $Uri -like '*chrome-for-testing*' }
        { Update-UserAgentList -RepositoryRoot $root } | Should -Throw '*No recent published*'
        (Get-Content "$root/support-files/userAgents.json" -Raw).Trim() | Should -Be 'original-support-copy'
    }

    It 'rejects prerelease Brave metadata and mismatched tagged source without writes' {
        Mock Invoke-RestMethod {
            @{ tag_name = 'v1.2.3'; prerelease = $true; published_at = '2020-01-01' }
        } -ParameterFilter { $Uri -like '*/brave-browser/releases/latest' }
        { Update-UserAgentList -RepositoryRoot $root } | Should -Throw '*No published Brave stable*'
        Mock Invoke-RestMethod {
            @{ tag_name = 'v1.2.3'; prerelease = $false; published_at = '2020-01-01' }
        } -ParameterFilter { $Uri -like '*/brave-browser/releases/latest' }
        Mock Invoke-RestMethod { @{ version = '1.2.4' } } -ParameterFilter { $Uri -like '*/brave-core/*' }
        { Update-UserAgentList -RepositoryRoot $root } | Should -Throw '*does not match*'
        (Get-Content "$root/support-files/userAgents.json" -Raw).Trim() | Should -Be 'original-support-copy'
    }
}

Describe 'Packaged user-agent reference data' {
    It 'ships synchronized lists with valid browser formats' {
        $private = Get-Content "$PSScriptRoot/../Private/Reference/userAgents.json" -Raw
        $private | Should -BeExactly (Get-Content "$PSScriptRoot/../support-files/userAgents.json" -Raw)
        $agents = ($private | ConvertFrom-Json).agents
        $agents | Should -HaveCount 18
        @($agents.type | Select-Object -Unique) | Should -HaveCount 18
        $agents | ForEach-Object { $_.value | Should -Not -BeNullOrEmpty }
        ($agents | Where-Object type -EQ mac_safari).value | Should -Match 'AppleWebKit/605.1.15.*Version/\d+\.\d+ Safari/605.1.15$'
        ($agents | Where-Object type -EQ mac_firefox).value | Should -Match 'Intel Mac OS X 10.15; rv:(\d+\.\d+)\) Gecko/20100101 Firefox/\1$'
        @($agents | Where-Object type -Match '_brave$').value | ForEach-Object { $_ | Should -Not -Match 'Brave/' }
        @($agents | Where-Object type -Match '_chrome$').value | ForEach-Object { $_ | Should -Match 'Chrome/\d+\.0\.0\.0 ' }
    }

    It 'exports and packages the random setter with discoverable help' {
        $manifest = Import-PowerShellDataFile "$PSScriptRoot/../BlackCat.psd1"
        $manifest.FunctionsToExport | Should -Contain 'Set-UserAgent'
        $manifest.FileList | Should -Contain 'Public\Helpers\Set-UserAgent.ps1'
        . "$PSScriptRoot/../Public/Helpers/Set-UserAgent.ps1"
        (Get-Help Set-UserAgent).Synopsis | Should -Be 'Select a random user agent from the configured list.'
    }
}

Describe 'Scheduled refresh release metadata' {
    BeforeAll {
        $workflow = Get-Content "$PSScriptRoot/../.github/workflows/update-user-agents.yml" -Raw
        $match = [regex]::Match($workflow, '(?ms)- name: Update release metadata when the lists change\r?\n        shell: pwsh\r?\n        run: \|\r?\n(?<Script>.*?)(?=^      - name:)')
        $releaseStep = [scriptblock]::Create(($match.Groups['Script'].Value -replace '(?m)^          ', ''))
    }

    It 'bumps the module version and adds a changelog entry only when data changes' {
        $root = Join-Path $TestDrive 'release'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        Copy-Item "$PSScriptRoot/../BlackCat.psd1", "$PSScriptRoot/../CHANGELOG.md" -Destination $root
        Mock git { 'Private/Reference/userAgents.json' }
        $global:LASTEXITCODE = 0
        Push-Location $root
        try {
            $previousVersion = [version](Import-PowerShellDataFile "$root/BlackCat.psd1").ModuleVersion
            . $releaseStep
            $expected = "$($previousVersion.Major).$($previousVersion.Minor).$($previousVersion.Build + 1)"
            (Import-PowerShellDataFile "$root/BlackCat.psd1").ModuleVersion | Should -Be $expected
            Get-Content "$root/CHANGELOG.md" -Raw | Should -Match ([regex]::Escape("## v$expected"))
            $before = Get-FileHash "$root/BlackCat.psd1", "$root/CHANGELOG.md"
            Mock git {}
            . $releaseStep
            $after = Get-FileHash "$root/BlackCat.psd1", "$root/CHANGELOG.md"
            $after.Hash | Should -Be $before.Hash
        }
        finally {
            Pop-Location
        }
    }
}
