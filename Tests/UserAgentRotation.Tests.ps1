BeforeAll {
    Import-Module Az.Accounts -MinimumVersion 3.0.0
    . "$PSScriptRoot/../Private/Get-BlackCatUserAgent.ps1"
    . "$PSScriptRoot/../Private/Invoke-BlackCat.ps1"
    . "$PSScriptRoot/../Private/Get-AllPages.ps1"
    . "$PSScriptRoot/../Private/Write-Message.ps1"
    . "$PSScriptRoot/../Private/Use-BlackCatCache.ps1"
    . "$PSScriptRoot/../Private/Format-BlackCatOutput.ps1"
    . "$PSScriptRoot/../Public/Helpers/Get-CurrentUserAgent.ps1"
    . "$PSScriptRoot/../Public/Helpers/Get-UserAgentStatus.ps1"
    . "$PSScriptRoot/../Public/Helpers/Set-UserAgentRotation.ps1"
    . "$PSScriptRoot/../Public/Helpers/Invoke-MSGraph.ps1"
    . "$PSScriptRoot/../Public/Initial Access/Connect-EntraApplication.ps1"
    . "$PSScriptRoot/../Public/Reconnaissance/Test-DomainRegistration.ps1"
}

Describe 'Shared user agent rotation' {
    BeforeEach {
        $script:SessionVariables = [ordered]@{
            UserAgent = ''
            CurrentUserAgent = $null
            UserAgentLastChanged = $null
            UserAgentRequestCount = 0
            UserAgentRotationEnabled = $true
            UserAgentRotationInterval = [TimeSpan]::FromMinutes(30)
            MaxRequestsPerAgent = 50
            userAgents = @{ agents = @(@{ value = 'Rotated-Agent' }) }
            graphUri = 'https://graph.microsoft.com/beta'
        }
        $script:graphHeader = @{ Authorization = '******' }
        $script:EntraAppContext = $null
        Mock Write-Message {}
        Mock Start-Sleep {}
        Mock Invoke-RestMethod { throw 'Unexpected HTTP request' }
        Mock Invoke-WebRequest { throw 'Unexpected HTTP request' }
    }

    It 'preserves disabled rotation before initialization and after clearing a custom agent' {
        Set-UserAgentRotation -Disable | Out-Null
        $agent = Get-CurrentUserAgent -IncrementCount
        $script:SessionVariables.UserAgentRotationEnabled | Should -BeFalse
        $script:SessionVariables.UserAgentLastChanged = (Get-Date).AddDays(-400)
        Set-UserAgentRotation -Disable -CustomUserAgent '' | Out-Null
        Get-CurrentUserAgent -IncrementCount | Should -Be $agent
        $script:SessionVariables.UserAgentRotationEnabled | Should -BeFalse
        $script:SessionVariables.UserAgentRequestCount | Should -Be 1
    }

    It 'uses a fixed custom agent and keeps the shared legacy field in sync' {
        Set-UserAgentRotation -Disable -CustomUserAgent 'Configured-Agent' | Out-Null
        1..3 | ForEach-Object { Get-CurrentUserAgent -IncrementCount | Should -Be 'Configured-Agent' }
        $script:SessionVariables.UserAgent | Should -Be 'Configured-Agent'
        $script:SessionVariables.UserAgentRequestCount | Should -Be 3
    }

    It 'clears both agent fields without restoring a stale disabled custom agent' {
        Set-UserAgentRotation -Disable -CustomUserAgent 'Stale-Agent' | Out-Null
        Set-UserAgentRotation -Disable -CustomUserAgent '' | Out-Null
        $script:SessionVariables.CurrentUserAgent | Should -BeNullOrEmpty
        $script:SessionVariables.UserAgent | Should -BeNullOrEmpty
        Get-CurrentUserAgent -IncrementCount | Should -Not -Be 'Stale-Agent'
        $script:SessionVariables.UserAgentRotationEnabled | Should -BeFalse
    }

    It 'does not replace a custom rotating agent during a status lookup' {
        Set-UserAgentRotation -CustomUserAgent 'Initial-Agent' -MaxRequests 1 | Out-Null
        Get-CurrentUserAgent -IncrementCount | Should -Be 'Initial-Agent'
        $script:SessionVariables.UserAgentLastChanged = (Get-Date).AddHours(-1)
        $status = @(Get-UserAgentStatus)[-1]
        $status.CurrentAgent | Should -Be 'Initial-Agent'
        $script:SessionVariables.UserAgentRequestCount | Should -Be 1
        Get-CurrentUserAgent -IncrementCount | Should -Be 'Rotated-Agent'
    }

    It 'uses the fallback when the agent list is <Name>' -TestCases @(
        @{ Name = 'missing'; Agents = $null }
        @{ Name = 'empty'; Agents = @{ agents = @() } }
        @{ Name = 'invalid'; Agents = @{ agents = @(@{ value = '' }) } }
    ) {
        param($Name, $Agents)
        $script:SessionVariables.userAgents = $Agents
        Get-CurrentUserAgent -IncrementCount | Should -Be 'Mozilla/5.0 (BlackCat Security Tool)'
        $script:SessionVariables.UserAgent | Should -Be $script:SessionVariables.CurrentUserAgent
        $script:SessionVariables.UserAgentRequestCount | Should -Be 1
    }

    It 'counts requests, not configuration or status reads, and rotates before request N+1' {
        Set-UserAgentRotation -CustomUserAgent 'Initial-Agent' -MaxRequests 2 | Out-Null
        Get-UserAgentStatus | Out-Null
        $script:SessionVariables.UserAgentRequestCount | Should -Be 0
        Get-CurrentUserAgent -IncrementCount | Should -Be 'Initial-Agent'
        Get-CurrentUserAgent -IncrementCount | Should -Be 'Initial-Agent'
        Get-CurrentUserAgent -IncrementCount | Should -Be 'Rotated-Agent'
        $script:SessionVariables.UserAgentRequestCount | Should -Be 1
    }

    It 'rotates an expired agent immediately before an outgoing request' {
        Set-UserAgentRotation -CustomUserAgent 'Initial-Agent' -Interval ([TimeSpan]::FromMinutes(1)) | Out-Null
        $script:SessionVariables.UserAgentLastChanged = (Get-Date).AddMinutes(-2)
        Get-CurrentUserAgent -IncrementCount | Should -Be 'Rotated-Agent'
        $script:SessionVariables.UserAgentRequestCount | Should -Be 1
    }

    It 'initializes missing tracking keys without overriding an explicit disable' {
        $script:SessionVariables = @{ UserAgentRotationEnabled = $false; CustomUserAgent = 'Fixed' }
        Get-CurrentUserAgent -IncrementCount | Should -Be 'Fixed'
        $script:SessionVariables.UserAgentRotationEnabled | Should -BeFalse
        $script:SessionVariables.UserAgentRequestCount | Should -Be 1
    }

    It 'does not reset the agent or count while preparing an existing Graph token' {
        Set-UserAgentRotation -Disable -CustomUserAgent 'Configured-Agent' | Out-Null
        $script:SessionVariables.AccessToken = 'test-only'
        Invoke-BlackCat -FunctionName 'test' -ResourceTypeName MSGraph
        $script:SessionVariables.UserAgent | Should -Be 'Configured-Agent'
        $script:SessionVariables.UserAgentRequestCount | Should -Be 0
    }

    It 'preserves configuration through ARM authentication setup with a cached token' {
        Set-UserAgentRotation -Disable -CustomUserAgent 'Configured-Agent' | Out-Null
        $script:SessionVariables.AccessToken = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('test-only'))
        $script:SessionVariables.ExpiresOn = [datetime]::UtcNow.AddHours(1)
        $script:SessionVariables.subscriptionId = 'test'
        # Substitute only the profile lookup to avoid modifying any real Az context.
        $source = (Get-Content "$PSScriptRoot/../Private/Invoke-BlackCat.ps1" -Raw).Replace(
            'function Invoke-BlackCat {', 'function Invoke-BlackCatContextTest {').Replace(
            '$azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile',
            '$azProfile = [pscustomobject]@{ Contexts = @{ test = 1 }; DefaultContext = @{ Account = @{ Id = "test" } } }')
        . ([scriptblock]::Create($source))
        Invoke-BlackCatContextTest -FunctionName test
        $script:SessionVariables.UserAgent | Should -Be 'Configured-Agent'
        $script:SessionVariables.UserAgentRequestCount | Should -Be 0
    }

    It 'does not change HTTP defaults for callers outside the module' {
        $defaults = $PSDefaultParameterValues.Clone()
        Set-UserAgentRotation -Disable -CustomUserAgent 'Configured-Agent' | Out-Null
        Mock Invoke-RestMethod {}
        Invoke-RestMethod -Uri 'https://example.invalid'
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { -not $UserAgent }
        $PSDefaultParameterValues.Count | Should -Be $defaults.Count
        $script:SessionVariables.UserAgentRequestCount | Should -Be 0
    }

    It 'propagates and counts every Graph pagination request' {
        Mock Invoke-BlackCat {}
        Set-UserAgentRotation -CustomUserAgent 'Initial-Agent' -MaxRequests 1 | Out-Null
        Mock Invoke-RestMethod {
            if ($Uri -eq 'https://graph.microsoft.com/page2') {
                @{ value = @('second'); '@odata.nextLink' = 'https://graph.microsoft.com/page3' }
            } else {
                @{ value = @('third') }
            }
        }
        $pages = Get-AllPages -ProcessLink @{ responses = @{ body = @{
            value = @('first'); '@odata.nextLink' = 'https://graph.microsoft.com/page2'
        } } }
        $pages | Should -HaveCount 3
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $UserAgent -eq 'Initial-Agent' }
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $UserAgent -eq 'Rotated-Agent' }
    }

    It 'propagates a fixed agent through an authenticated Graph request' {
        Mock Invoke-BlackCat {}
        Mock Set-BlackCatCache {}
        Mock Format-BlackCatOutput { $Data }
        Set-UserAgentRotation -Disable -CustomUserAgent 'Configured-Agent' | Out-Null
        Mock Invoke-RestMethod { @{ value = @(@{ id = 'test' }) } }
        Invoke-MsGraph -relativeUrl users -NoBatch -SkipCache | Out-Null
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $UserAgent -eq 'Configured-Agent' }
        $script:SessionVariables.UserAgentRequestCount | Should -Be 1
    }

    It 'counts retries of an anonymous request and selects the agent at each attempt' {
        Set-UserAgentRotation -CustomUserAgent 'Initial-Agent' -MaxRequests 1 | Out-Null
        $script:attempts = 0
        Mock Invoke-RestMethod {
            $script:attempts++
            if ($script:attempts -eq 1) { throw 'First provider unavailable' }
            @{ ldhName = 'example.com'; status = @('active') }
        }
        Test-DomainRegistration -Domain example.com -Method rdap | Out-Null
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $UserAgent -eq 'Initial-Agent' }
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $UserAgent -eq 'Rotated-Agent' }
    }

    It 'propagates the agent to unauthenticated device-code and token requests' {
        Set-UserAgentRotation -Disable -CustomUserAgent 'Configured-Agent' | Out-Null
        Mock Invoke-RestMethod {
            if ($Uri -like '*/devicecode') {
                @{ verification_uri = 'https://example.invalid'; user_code = 'test'; device_code = 'test'; interval = 0; expires_in = 60 }
            } else {
                @{ access_token = 'test-only'; expires_in = 3600; token_type = 'Bearer' }
            }
        }
        Connect-EntraApplication -ClientId test -TenantId test -Scopes User.Read -UseDeviceCode -Confirm:$false | Out-Null
        Should -Invoke Invoke-RestMethod -Times 2 -Exactly -ParameterFilter { $UserAgent -eq 'Configured-Agent' }
        $script:SessionVariables.UserAgentRequestCount | Should -Be 2
    }

    It 'shares fixed selection and atomic counting across actual parallel HTTP workers' {
        Set-UserAgentRotation -Disable -CustomUserAgent 'Configured-Agent' | Out-Null
        $blackCatUserAgentState = $script:SessionVariables
        $blackCatUserAgentProvider = ${function:Get-BlackCatUserAgent}.ToString()
        $IncludeMembers = $true
        [void]$blackCatUserAgentState
        [void]$blackCatUserAgentProvider
        [void]$IncludeMembers
        $result = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            "$PSScriptRoot/../Public/Discovery/Get-AdministrativeUnit.ps1", [ref]$null, [ref]$null)
        $worker = $ast.Find({ param($node)
            $node -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -and
            $node.Parent -is [System.Management.Automation.Language.CommandAst] -and
            $node.Parent.Extent.Text -like '*ForEach-Object -Parallel*'
        }, $true).ScriptBlock.Extent.Text
        # Pester mocks do not cross runspaces; install a network-free stub in each worker.
        $stub = 'function Invoke-RestMethod { param($Uri, $Headers, $UserAgent) @{ value = @(@{ userPrincipalName = $UserAgent }) } }'
        $worker = [scriptblock]::Create($stub + $worker.Substring(1, $worker.Length - 2))
        1..40 | ForEach-Object { @{ id = $_; displayName = "Unit $_" } } |
            ForEach-Object -Parallel $worker -ThrottleLimit 8
        $result.Count | Should -Be 40
        @($result | ForEach-Object { $_.Members } | Select-Object -Unique) | Should -Be @('Configured-Agent')
        $script:SessionVariables.UserAgentRequestCount | Should -Be 40
    }

    It 'rotates with a single shared request budget across parallel runspaces' {
        Set-UserAgentRotation -CustomUserAgent 'Initial-Agent' -MaxRequests 7 | Out-Null
        $state = $script:SessionVariables
        $provider = ${function:Get-BlackCatUserAgent}.ToString()
        $agents = 1..40 | ForEach-Object -Parallel {
            Set-Item Function:Get-BlackCatUserAgent ([scriptblock]::Create($using:provider))
            Get-BlackCatUserAgent -State $using:state -IncrementCount
        } -ThrottleLimit 8
        @($agents | Where-Object { $_ -eq 'Initial-Agent' }).Count | Should -Be 7
        @($agents | Where-Object { $_ -eq 'Rotated-Agent' }).Count | Should -Be 33
        $state.UserAgentRequestCount | Should -Be 5
    }

    It 'uses the same agent in nested anonymous storage workers and metadata requests' {
        Set-UserAgentRotation -Disable -CustomUserAgent 'Configured-Agent' | Out-Null
        $blackCatUserAgentState = $script:SessionVariables
        $blackCatUserAgentProvider = ${function:Get-BlackCatUserAgent}.ToString()
        $permutations = @('first', 'second')
        $result = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
        $IncludeEmpty = $true
        $IncludeMetadata = $true
        $foundContainers = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
        $requests = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
        [void]$blackCatUserAgentState
        [void]$blackCatUserAgentProvider
        [void]$permutations
        [void]$IncludeEmpty
        [void]$IncludeMetadata
        [void]$foundContainers
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            "$PSScriptRoot/../Public/Reconnaissance/Find-PublicStorageContainer.ps1", [ref]$null, [ref]$null)
        $worker = $ast.Find({ param($node)
            $node -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -and
            $node.Parent -is [System.Management.Automation.Language.CommandAst] -and
            $node.Parent.Extent.Text -like '*ForEach-Object -Parallel*' -and
            $node.ScriptBlock.Extent.Text -like '*$dns = $_*'
        }, $true).ScriptBlock.Extent.Text
        $stub = @'
function Invoke-WebRequest {
    param($Uri, $Method, $UserAgent, [switch]$UseBasicParsing, [switch]$SkipHttpErrorCheck)
    ($using:requests).Add($UserAgent)
    @{ StatusCode = 200; Content = '<EnumerationResults></EnumerationResults>'; Headers = @{} }
}
'@
        $worker = $worker.Substring(1, $worker.Length - 2).Replace(
            '$permutations | ForEach-Object -Parallel {',
            ('$requests = $using:requests; $permutations | ForEach-Object -Parallel {' + $stub))
        'storage.example.invalid' | ForEach-Object -Parallel ([scriptblock]::Create($worker))
        $requests.Count | Should -Be 4
        $result.Count | Should -Be 2
        @($requests | Select-Object -Unique) | Should -Be @('Configured-Agent')
        $blackCatUserAgentState.UserAgentRequestCount | Should -Be 4
    }
}

Describe 'Module HTTP call-site coverage' {
    It 'selects a shared agent immediately at every HTTP invocation, not in a reusable splat' {
        $files = @(Get-ChildItem "$PSScriptRoot/../Private", "$PSScriptRoot/../Public" -Recurse -Filter *.ps1) +
            @(Get-Item "$PSScriptRoot/../BlackCat.psm1")
        $calls = 0
        foreach ($file in $files) {
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errors)
            $errors | Should -BeNullOrEmpty -Because $file.Name
            foreach ($command in $ast.FindAll({ param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -in @('Invoke-RestMethod', 'Invoke-WebRequest', 'irm', 'iwr')
            }, $true)) {
                $calls++
                $command.Extent.Text | Should -Match '-UserAgent \(Get-(CurrentUserAgent|BlackCatUserAgent).*?-IncrementCount\)' -Because "$($file.Name):$($command.Extent.StartLineNumber)"
            }
            $ast.FindAll({ param($node)
                $node -is [System.Management.Automation.Language.HashtableAst] -and
                @($node.KeyValuePairs | Where-Object {
                    $_.Item1.Extent.Text -match "^['`"]?User-?Agent['`"]?$" -and $_.Item2.Extent.Text -ne "''"
                }).Count -gt 0
            }, $true) | Should -BeNullOrEmpty -Because "HTTP splats or headers in $($file.Name) must not retain stale agents"
        }
        $calls | Should -BeGreaterThan 100
    }
}
