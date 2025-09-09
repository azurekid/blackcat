function Set-UserAgentRotation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [TimeSpan]$Interval,

        [Parameter(Mandatory = $false)]
        [int]$MaxRequests,

        [Parameter(Mandatory = $false)]
        [Switch]$Disable,

        [Parameter(Mandatory = $false)]
        [string]$CustomUserAgent
    )

    if ($Disable) {
        # Disable rotation by setting very high values
        $script:SessionVariables.UserAgentRotationInterval = [TimeSpan]::FromDays(365)
        $script:SessionVariables.MaxRequestsPerAgent = [int]::MaxValue
        $script:SessionVariables.UserAgentRotationEnabled = $false
        Write-Output "User agent rotation has been disabled"
    }
    else {
        # Enable rotation
        $script:SessionVariables.UserAgentRotationEnabled = $true
    }

    if ($PSBoundParameters.ContainsKey('Interval')) {
        $script:SessionVariables.UserAgentRotationInterval = $Interval
    }

    if ($PSBoundParameters.ContainsKey('MaxRequests')) {
        $script:SessionVariables.MaxRequestsPerAgent = $MaxRequests
    }

    # Set a custom user agent if specified
    if ($PSBoundParameters.ContainsKey('CustomUserAgent')) {
        $script:SessionVariables.CustomUserAgent = $CustomUserAgent
        
        # If custom user agent is null or empty, reset the current user agent so it will be regenerated
        if ([string]::IsNullOrEmpty($CustomUserAgent)) {
            $script:SessionVariables.CurrentUserAgent = $null
            # We'll force a new agent selection on next Get-CurrentUserAgent call
            Write-Output "Custom user agent cleared"
        } else {
            # Set both current agent and user agent to the custom value
            $script:SessionVariables.CurrentUserAgent = $CustomUserAgent
            $script:SessionVariables.UserAgent = $CustomUserAgent
            Write-Output "Custom user agent set: $CustomUserAgent"
        }
        
        # Reset counter and update timestamp
        $script:SessionVariables.UserAgentLastChanged = Get-Date
        $script:SessionVariables.UserAgentRequestCount = 0
    }

    # Return current settings
    Get-UserAgentStatus

    <#
    .SYNOPSIS
    Configure user agent rotation settings to reduce SIEM visibility.

    .DESCRIPTION
    This function allows you to configure how the BlackCat module rotates user agents
    to avoid detection by security monitoring systems. You can set the time interval
    between rotations, the maximum number of requests per user agent, or disable
    rotation entirely.

    .PARAMETER Interval
    The time interval between user agent rotations (TimeSpan). Default is 30 minutes.

    .PARAMETER MaxRequests
    The maximum number of requests to make with a single user agent before rotating.
    Default is 50 requests.

    .PARAMETER Disable
    Switch to disable user agent rotation. When specified, the module will use
    a single user agent indefinitely.

    .PARAMETER CustomUserAgent
    Set a specific custom user agent string to be used instead of random rotation.

    .EXAMPLE
    # Set user agent to rotate every 2 hours
    Set-UserAgentRotation -Interval (New-TimeSpan -Hours 2)

    .EXAMPLE
    # Set user agent to rotate after 100 requests
    Set-UserAgentRotation -MaxRequests 100

    .EXAMPLE
    # Set both interval and request count limits
    Set-UserAgentRotation -Interval (New-TimeSpan -Minutes 45) -MaxRequests 75

    .EXAMPLE
    # Disable user agent rotation
    Set-UserAgentRotation -Disable

    .EXAMPLE
    # Set a custom user agent
    Set-UserAgentRotation -CustomUserAgent "Mozilla/5.0 BlackCat Security Tool"

    .NOTES
    Rotating user agents helps avoid detection by SIEM solutions that might
    flag rapid changes in user agents from the same source as suspicious behavior.
    #>
}