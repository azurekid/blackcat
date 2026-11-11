function Set-UserAgent {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Get-BlackCatUserAgent -State $script:SessionVariables -ForceSelection

    <#
    .SYNOPSIS
    Select a random user agent from the configured list.

    .DESCRIPTION
    Every invocation makes a fresh random draw from nonblank string entries in
    the loaded userAgents.json list. A draw can repeat the previous value.
    Updates both current and legacy agent fields, the timestamp and request
    count atomically. Missing, malformed or empty lists use
    Mozilla/5.0 (BlackCat Security Tool).
    Rotation settings and custom-agent configuration are not changed. A fixed
    custom agent is restored on the next Get-CurrentUserAgent call.

    .EXAMPLE
    Set-UserAgent

    .LINK
    Get-CurrentUserAgent

    .LINK
    Set-UserAgentRotation
    #>
}
