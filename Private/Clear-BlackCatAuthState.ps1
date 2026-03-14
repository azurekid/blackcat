function Clear-BlackCatAuthState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [switch]$ClearLastAccountId
    )

    if (-not $script:SessionVariables) {
        return
    }

    $script:SessionVariables.AccessToken = $null
    $script:SessionVariables.accessToken = $null
    $script:SessionVariables.ExpiresOn   = $null

    if ($ClearLastAccountId) {
        $script:SessionVariables.lastAccountId = $null
    }

    $script:graphHeader = $null
    $script:authHeader  = $null
}
