function Get-GraphRecursive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $false)]
        [string]$Filter,

        [Parameter(Mandatory = $false)]
        [string]$Select,

        [Parameter(Mandatory = $true)]
        [securestring]$Token,

        [Parameter(Mandatory = $false)]
        [string]$api,

        [Parameter(Mandatory = $true)]
        [string]$Method = 'GET',

        [Parameter(Mandatory = $true)]
        [string]$Authentication = 'OAuth'

        )

    if ($Filter) {
        $uri = '{0}?$Filter={1}' -f $Url, $Filter
        } else {
        $uri = $Url
    }

    if ($Select) {
         if ($uri) {
            $url = '{0}&$select={1}' -f $uri, "$select"
         } else {
            $uri = '{0}?$select={1}' -f $url, "$select"
         }
    }

    if ($api){
        $uri = '{0}?api-version={1}' -f $Url, $api
    }
    $apiResponse = Invoke-RestMethod -Uri $uri @aadRequestHeader

    $count        = 0
    $apiResult    = $apiResponse.value
    $userNextLink = $apiResponse."@odata.nextLink"

    while ($null -ne $userNextLink) {
        $apiResponse    = (Invoke-RestMethod -uri $userNextLink @aadRequestHeader)
        $count = $count + ($apiResponse.value).count

        Write-Host "[+] Processed objects $($count)"`r -NoNewline
        $userNextLink   = $apiResponse."@odata.nextLink"
        $apiResult      += $apiResponse.value
    }

    return $apiResult
}