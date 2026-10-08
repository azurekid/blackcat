function Get-CurrentUserAgent {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$IncrementCount
    )

    Get-BlackCatUserAgent -State $script:SessionVariables -IncrementCount:$IncrementCount

    <#
    .SYNOPSIS
    Gets the current user agent string for HTTP requests based on rotation settings.

    .DESCRIPTION
    Manages user agent rotation for BlackCat requests based on time and request counts.
    An explicitly disabled rotation remains disabled, including before the first request.

    .PARAMETER IncrementCount
    When specified, increments the request counter for the current user agent.
    Module HTTP call sites use this immediately before each outgoing request.

    .EXAMPLE
    # Get the current user agent without incrementing the counter
    $userAgent = Get-CurrentUserAgent

    .EXAMPLE
    # Get current user agent and increment the request counter
    $userAgent = Get-CurrentUserAgent -IncrementCount

    .NOTES
    The function's behavior is controlled by settings configured via Set-UserAgentRotation.

    .LINK
        MITRE ATT&CK Tactic: TA0007 - Discovery
        https://attack.mitre.org/tactics/TA0007/

    .LINK
        MITRE ATT&CK Technique: T1016 - System Network Configuration Discovery
        https://attack.mitre.org/techniques/T1016/

    #>
}
