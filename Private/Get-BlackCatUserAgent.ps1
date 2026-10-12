function Get-BlackCatUserAgent {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State,

        [switch]$IncrementCount,

        [switch]$ForceSelection
    )

    # Parallel runspaces share this dictionary; selection and counting must be atomic.
    [System.Threading.Monitor]::Enter($State.SyncRoot)
    try {
        if (-not $State.Contains('UserAgentRotationEnabled')) {
            $State.UserAgentRotationEnabled = $true
        }
        if (-not $State.Contains('UserAgentRequestCount')) {
            $State.UserAgentRequestCount = 0
        }

        $now = Get-Date
        if (-not $ForceSelection -and -not $State.UserAgentRotationEnabled) {
            if (-not [string]::IsNullOrWhiteSpace($State.CustomUserAgent)) {
                $State.CurrentUserAgent = $State.CustomUserAgent
            }
            elseif ([string]::IsNullOrWhiteSpace($State.CurrentUserAgent) -and
                -not [string]::IsNullOrWhiteSpace($State.UserAgent)) {
                $State.CurrentUserAgent = $State.UserAgent
                $State.UserAgentLastChanged = $now
            }
        }

        $rotate = $ForceSelection -or [string]::IsNullOrWhiteSpace($State.CurrentUserAgent) -or (
            $State.UserAgentRotationEnabled -and (
                ($State.UserAgentLastChanged -and
                    ($now - $State.UserAgentLastChanged) -ge ($State.UserAgentRotationInterval ?? [TimeSpan]::FromMinutes(30))) -or
                (($State.MaxRequestsPerAgent ?? 50) -gt 0 -and
                    $State.UserAgentRequestCount -ge ($State.MaxRequestsPerAgent ?? 50))
            )
        )

        if ($rotate) {
            $agents = @($State.userAgents.agents | Where-Object {
                $_.value -is [string] -and -not [string]::IsNullOrWhiteSpace($_.value)
            })
            $State.CurrentUserAgent = if ($agents.Count) {
                ($agents | Get-Random).value
            } else {
                'Mozilla/5.0 (BlackCat Security Tool)'
            }
            $State.UserAgentLastChanged = $now
            $State.UserAgentRequestCount = 0
        }
        $State.UserAgent = $State.CurrentUserAgent
        if ($IncrementCount) {
            $State.UserAgentRequestCount++
        }
        return $State.CurrentUserAgent
    }
    finally {
        [System.Threading.Monitor]::Exit($State.SyncRoot)
    }
}
