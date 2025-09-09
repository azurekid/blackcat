function Get-CurrentUserAgent {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$IncrementCount
    )

    Write-Verbose -Message "Starting function Get-CurrentUserAgent"
    
    try {
        # Initialize user agent tracking if not exists
        if ($null -eq $script:SessionVariables.CurrentUserAgent) {
            Write-Verbose -Message "Initializing user agent tracking variables"
            $script:SessionVariables.CurrentUserAgent = $null
            $script:SessionVariables.UserAgentLastChanged = $null
            $script:SessionVariables.UserAgentRequestCount = 0
            $script:SessionVariables.UserAgentRotationEnabled = $true # Enable by default
        }

        # If a custom user agent is set and no rotation, always return that
        if (-not [string]::IsNullOrEmpty($script:SessionVariables.CustomUserAgent) -and 
            -not $script:SessionVariables.UserAgentRotationEnabled) {
            Write-Verbose -Message "Using fixed custom user agent: $($script:SessionVariables.CustomUserAgent)"
            if ($IncrementCount) {
                $script:SessionVariables.UserAgentRequestCount++
            }
            return $script:SessionVariables.CustomUserAgent
        }

        # Only do rotation logic if enabled
        if ($script:SessionVariables.UserAgentRotationEnabled) {
            $currentTime = Get-Date
            $userAgentRotationInterval = $script:SessionVariables.UserAgentRotationInterval ?? [TimeSpan]::FromMinutes(30)
            $maxRequestsPerAgent = $script:SessionVariables.MaxRequestsPerAgent ?? 50
            $shouldRotateUserAgent = $false

            # Check if we need to rotate
            if ($null -eq $script:SessionVariables.CurrentUserAgent) {
                # First time - select initial user agent
                $shouldRotateUserAgent = $true
                Write-Verbose -Message "First time initialization - selecting initial user agent"
            }
            elseif ($script:SessionVariables.UserAgentLastChanged -and 
                ($currentTime - $script:SessionVariables.UserAgentLastChanged) -gt $userAgentRotationInterval) {
                # Time-based rotation
                $shouldRotateUserAgent = $true
                Write-Verbose -Message "Rotating user agent due to time interval ($userAgentRotationInterval)"
            }
            elseif ($maxRequestsPerAgent -and 
                    $script:SessionVariables.UserAgentRequestCount -ge $maxRequestsPerAgent) {
                # Request count-based rotation
                $shouldRotateUserAgent = $true
                Write-Verbose -Message "Rotating user agent due to request count limit ($maxRequestsPerAgent)"
            }

            if ($shouldRotateUserAgent) {
                try {
                    # Select a new random user agent or default to a BlackCat one if no userAgents available
                    if ($script:SessionVariables.userAgents -and 
                        $script:SessionVariables.userAgents.agents -and 
                        $script:SessionVariables.userAgents.agents.Count -gt 0) {
                        $userAgent = ($script:SessionVariables.userAgents.agents | Get-Random).value
                    }
                    else {
                        $userAgent = "Mozilla/5.0 (BlackCat Security Tool)"
                    }
                    
                    $script:SessionVariables.CurrentUserAgent = $userAgent
                    $script:SessionVariables.UserAgentLastChanged = $currentTime
                    $script:SessionVariables.UserAgentRequestCount = 0
                    $script:SessionVariables.UserAgent = $userAgent
                    Write-Verbose -Message "Selected new user agent: $userAgent"
                }
                catch {
                    # Fallback to default user agent if there's an error
                    $defaultUA = "Mozilla/5.0 (BlackCat Security Tool)"
                    $script:SessionVariables.CurrentUserAgent = $defaultUA
                    $script:SessionVariables.UserAgent = $defaultUA
                    
                    Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message "Error selecting user agent: $_" -Severity 'Warning'
                    Write-Verbose -Message "Using default user agent: $defaultUA"
                    
                    return $defaultUA
                }
            }
        }

        # Increment the request counter if needed
        if ($IncrementCount) {
            $script:SessionVariables.UserAgentRequestCount++
            Write-Verbose -Message "Incremented request count to: $($script:SessionVariables.UserAgentRequestCount)"
        }

        # Make sure the current user agent is set in the main SessionVariables
        if (-not [string]::IsNullOrEmpty($script:SessionVariables.CurrentUserAgent)) {
            $script:SessionVariables.UserAgent = $script:SessionVariables.CurrentUserAgent
            return $script:SessionVariables.CurrentUserAgent
        }
        else {
            # Fallback if everything fails
            $defaultUA = "Mozilla/5.0 (BlackCat Security Tool)"
            $script:SessionVariables.UserAgent = $defaultUA
            Write-Verbose -Message "Using fallback default user agent: $defaultUA"
            return $defaultUA
        }
    }
    catch {
        $defaultUA = "Mozilla/5.0 (BlackCat Security Tool)"
        $script:SessionVariables.CurrentUserAgent = $defaultUA
        $script:SessionVariables.UserAgent = $defaultUA
        
        Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message "Error in Get-CurrentUserAgent: $_" -Severity 'Error'
        Write-Verbose -Message "Returning emergency default user agent due to error"
        
        return $defaultUA
    }
    <#
    .SYNOPSIS
    Gets the current user agent string to use for HTTP requests based on rotation settings.

    .DESCRIPTION
    This function manages user agent rotation for BlackCat module requests. It tracks when and how
    often to rotate user agents based on configured time intervals and request counts to avoid detection.
    It can use a fixed custom user agent or rotate through a pool of realistic browser user agents.

    .PARAMETER IncrementCount
    When specified, increments the request counter for the current user agent.
    This should be used when a request is actually being made.

    .EXAMPLE
    # Get the current user agent without incrementing the counter
    $userAgent = Get-CurrentUserAgent
    
    .EXAMPLE
    # Get current user agent and increment the request counter
    $userAgent = Get-CurrentUserAgent -IncrementCount
    
    .NOTES
    The function's behavior is controlled by settings configured via Set-UserAgentRotation.
    #>
}