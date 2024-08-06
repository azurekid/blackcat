function Get-CidrAddresses {
    param (
        [Parameter(Mandatory = $true)]
        [ValidatePattern('\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}|^([0-9A-Fa-f]{1,4}):([0-9A-Fa-f]{1,4}):')]
        [string]$CidrRange
    )

    # Check if the CIDR range is an IPv6 address
    $ipv6 = $false
    if ($CidrRange -match '^([0-9A-Fa-f]{1,4}):([0-9A-Fa-f]{1,4}):') {
        $ipv6 = $true
    }

    # Parse the CIDR range
    $cidr = $CidrRange -split '/'
    $baseIp = [System.Net.IPAddress]::Parse($cidr[0])
    $subnetMaskLength = [int]$cidr[1]

    # Calculate the number of addresses in the subnet
    if ($ipv6) {
        $numberOfAddresses = [math]::Pow(2, 128 - $subnetMaskLength)
    } else {
        $numberOfAddresses = [math]::Pow(2, 32 - $subnetMaskLength)
    }

    # Convert base IP to a 32-bit integer
    $baseIpBytes = $baseIp.GetAddressBytes()
    [Array]::Reverse($baseIpBytes)
    if ($ipv6) {
        $baseIpInt = [BitConverter]::ToUInt64($baseIpBytes, 0) + ([BitConverter]::ToUInt64($baseIpBytes, 8) -shl 64)
    } else {
        $baseIpInt = [BitConverter]::ToUInt32($baseIpBytes, 0)
    }

    # Generate all possible IP addresses within the subnet
    $ipAddresses = @()
    for ($i = 0; $i -lt $numberOfAddresses; $i++) {
        $currentIpInt = $baseIpInt + $i
        if ($ipv6) {
            $currentIpBytes = [BitConverter]::GetBytes($currentIpInt -shr 64) + [BitConverter]::GetBytes($currentIpInt -band 0xFFFFFFFFFFFFFFFF)
        } else {
            $currentIpBytes = [BitConverter]::GetBytes($currentIpInt)
        }
        [Array]::Reverse($currentIpBytes)
        $currentIp = [System.Net.IPAddress]::new($currentIpBytes)
        $ipAddresses += $currentIp.ToString()
    }

    return $ipAddresses
}