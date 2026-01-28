function Get-UserAgentStatus {
    [CmdletBinding()]
    param()

    # Get the actual current user agent that's in use via the getter function if rotation is enabled
    # This ensures we display the real user agent, not just the stored value
    $currentUserAgent = if ($script:SessionVariables.UserAgentRotationEnabled -and 
                            [string]::IsNullOrEmpty($script:SessionVariables.CustomUserAgent)) {
        # Get the current user agent without incrementing the counter
        (Get-CurrentUserAgent)
    } else {
        # If rotation is disabled or custom agent is set, use the stored value
        $script:SessionVariables.CurrentUserAgent
    }

    $status = [PSCustomObject]@{
        CurrentAgent = $currentUserAgent ?? "(Not Set)"
        LastChanged = $script:SessionVariables.UserAgentLastChanged ?? "(Not Set)"
        RequestCount = $script:SessionVariables.UserAgentRequestCount ?? 0
        RotationEnabled = $script:SessionVariables.UserAgentRotationEnabled ?? $true
        RotationInterval = $script:SessionVariables.UserAgentRotationInterval ?? [TimeSpan]::FromMinutes(30)
        MaxRequestsPerAgent = $script:SessionVariables.MaxRequestsPerAgent ?? 50
        CustomUserAgent = $script:SessionVariables.CustomUserAgent ?? "(Not Set)"
        NextRotationAt = if ($script:SessionVariables.UserAgentLastChanged -and $script:SessionVariables.UserAgentRotationEnabled) {
            $script:SessionVariables.UserAgentLastChanged + $script:SessionVariables.UserAgentRotationInterval
        } else { "(Not Set)" }
        RequestsUntilRotation = if ($script:SessionVariables.UserAgentRotationEnabled -and $script:SessionVariables.MaxRequestsPerAgent) {
            $script:SessionVariables.MaxRequestsPerAgent - ($script:SessionVariables.UserAgentRequestCount ?? 0)
        } else { "(Not Set)" }
    }

    # Format the output nicely
    Write-Output " User Agent Status:"
    Write-Output "  Current User Agent: $($status.CurrentAgent)"
    Write-Output "  Last Changed: $($status.LastChanged)"
    Write-Output "  Request Count: $($status.RequestCount)"
    Write-Output "  Rotation Enabled: $($status.RotationEnabled)"
    Write-Output "  Rotation Interval: $($status.RotationInterval)"
    Write-Output "  Max Requests Per Agent: $($status.MaxRequestsPerAgent)"
    if ($status.CustomUserAgent -ne "(Not Set)") {
        Write-Output "  Custom User Agent: $($status.CustomUserAgent)"
    }
    if ($status.RotationEnabled) {
        Write-Output "  Next Rotation At: $($status.NextRotationAt)"
        Write-Output "  Requests Until Rotation: $($status.RequestsUntilRotation)"
    }

    return $status

    <#
    .SYNOPSIS
    Get the current status of user agent rotation.

    .DESCRIPTION
    This function returns information about the current user agent rotation status,
    including the current user agent in use, when it was last changed, and when the
    next rotation is expected to occur.

    .EXAMPLE
    # Display user agent rotation status
    Get-UserAgentStatus

    .NOTES
    Use this function to monitor the state of user agent rotation and verify your
    rotation settings are working as expected.
    #>
}
