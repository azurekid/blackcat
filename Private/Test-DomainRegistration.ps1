function Test-DomainRegistration {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    try {
        $url = "https://rdap.org/domain/$Domain"
        $response = Invoke-RestMethod -Uri $url -ErrorAction Stop

        if ($response.objectClassName -eq "domain") {
            # Extract important dates
            $creationDate = ($response.events | Where-Object { $_.eventAction -eq "registration" }).eventDate
            $expiryDate = ($response.events | Where-Object { $_.eventAction -eq "expiration" }).eventDate
            $lastUpdateDate = ($response.events | Where-Object { $_.eventAction -like "*last update*" }).eventDate
            
            # Extract name servers
            $nameServers = $response.nameservers | ForEach-Object { $_.ldhName }

            # Extract registrar information
            $registrarName = ($response.entities | Where-Object { $_.roles -contains "registrar" }).vcardArray[1] |
            Where-Object { $_[0] -eq "fn" } | Select-Object -ExpandProperty 3 -ErrorAction SilentlyContinue

            # Create user-friendly output object
            [PSCustomObject]@{
                Status      = "Registered"
                Domain      = $Domain
                Registrar   = $registrarName
                Created     = $creationDate
                Expires     = $expiryDate
                LastUpdated = $lastUpdateDate
                NameServers = $nameServers -join ", "
                FullInfo    = $response  # Include full response for reference if needed
            }
        }
        else {
            [PSCustomObject]@{
                Status   = "Unknown"
                Domain   = $Domain
                Message  = "Unexpected response format"
                FullInfo = $response
            }
        }
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 404) {
            [PSCustomObject]@{
                Status  = "Available"
                Domain  = $Domain
                Message = "Domain appears to be available for registration"
            }
        }
        else {
            [PSCustomObject]@{
                Status  = "Error"
                Domain  = $Domain
                Message = $_.Exception.Message
            }
        }
    }
}
