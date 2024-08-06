function GetServiceTagNameByIP($ipAddress) {
  $jsonContent = Get-Content -Raw -Path '/workspaces/blackcat/Tools/Modules/Helpers/ServiceTags.json' | ConvertFrom-Json

  $jsonContent | ForEach-Object {
    Write-Output "Checking service tag: $($_.Name)"
    foreach ($prefix in $_.properties.addressPrefixes | where { $_.name -notlike "*.*" }) {
      $addresses = @()
      $addresses = @(Get-CidrAddresses -CidrRange $prefix)
      Write-Verbose "Checking IP: $($ipAddress) in range $($addresses)"
      Write-Verbose "Checking in $(($addresses).count): Addresses"
      if ($addresses -like "*$($ipAddress)*") {
        Write-Host "Service tag found: $($_.Name)" -ForegroundColor Green
        $bool = $true
      }
      else {
        continue
      }
    }
    if ($bool -eq $true) {
      break
    }
  }

  return "No matching service tag found for the given IP address."
}
