function Get-BlackCatUserAgent {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State,

        [switch]$IncrementCount
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
        $rotate = $State.UserAgentRotationEnabled -and (
            [string]::IsNullOrEmpty($State.CurrentUserAgent) -or
            ($State.UserAgentLastChanged -and
                ($now - $State.UserAgentLastChanged) -ge ($State.UserAgentRotationInterval ?? [TimeSpan]::FromMinutes(30))) -or
            (($State.MaxRequestsPerAgent ?? 50) -gt 0 -and
                $State.UserAgentRequestCount -ge ($State.MaxRequestsPerAgent ?? 50))
        )

        if ($rotate) {
            $agents = @($State.userAgents.agents | Where-Object { -not [string]::IsNullOrEmpty($_.value) })
            $State.CurrentUserAgent = if ($agents.Count) {
                ($agents | Get-Random).value
            } else {
                'Mozilla/5.0 (BlackCat Security Tool)'
            }
            $State.UserAgentLastChanged = $now
            $State.UserAgentRequestCount = 0
        }
        elseif (-not $State.UserAgentRotationEnabled -and -not [string]::IsNullOrEmpty($State.CustomUserAgent)) {
            $State.CurrentUserAgent = $State.CustomUserAgent
        }

        if ([string]::IsNullOrEmpty($State.CurrentUserAgent)) {
            $State.CurrentUserAgent = if (-not [string]::IsNullOrEmpty($State.UserAgent)) {
                $State.UserAgent
            } else {
                'Mozilla/5.0 (BlackCat Security Tool)'
            }
            $State.UserAgentLastChanged = $now
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
