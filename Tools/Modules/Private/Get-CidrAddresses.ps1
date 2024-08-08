function Get-CidrAddresses {
    param (
        [Parameter(Mandatory = $true)]
        [ValidatePattern('\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}|^([0-9A-Fa-f]{1,4}):([0-9A-Fa-f]{1,4}):')]
        [string]$CidrRange
    )

    # Check if the CIDR range is an IPv6 address
    if ($CidrRange -match '^([0-9A-Fa-f]{1,4}):([0-9A-Fa-f]{1,4}):') {
        $ipv6 = $true
    } else {
        $ipv4 = $true
    }

    # Parse the CIDR range
    $cidr = $CidrRange -split '/'
    $baseIp = [System.Net.IPAddress]::Parse($cidr[0])
    $subnetMaskLength = [int]$cidr[1]

    if ($ipv6 -and ($subnetMaskLength -lt 117)) {
        Write-Error "IPv6 subnet mask length must be at least 117"
        return
    }

    if ($ipv4 -and ($subnetMaskLength -lt 19)) {
        Write-Error "IPv4 subnet mask length must be at least 19"
        return
    }

    # Calculate the number of addresses in the subnet
    if ($ipv6) {
        $numberOfAddresses = [math]::Pow(2, 128 - $subnetMaskLength)
    } else {
        $numberOfAddresses = [math]::Pow(2, 32 - $subnetMaskLength)
    }

    # Convert base IP to a 128-bit integer for IPv6 or a 32-bit integer for IPv4
    $baseIpBytes = $baseIp.GetAddressBytes()
    [Array]::Reverse($baseIpBytes)
    if ($ipv6) {
        $baseIpInt = [System.Numerics.BigInteger]::new($baseIpBytes)
    } else {
        $baseIpInt = [BitConverter]::ToUInt32($baseIpBytes, 0)
    }

    # Generate all possible IP addresses within the subnet
    $ipAddresses = @()
    for ($i = 0; $i -lt $numberOfAddresses; $i++) {
        $currentIpInt = $baseIpInt + $i
        if ($ipv6) {
            $currentIpBytes = [System.Numerics.BigInteger]::DivRem($currentIpInt, [System.Numerics.BigInteger]::Pow(2, 64), [ref]$currentIpInt)
            $currentIpBytes = $currentIpBytes.ToByteArray()
        } else {
            $currentIpBytes = [BitConverter]::GetBytes($currentIpInt)
        }
        [Array]::Reverse($currentIpBytes)
        $currentIp = [System.Net.IPAddress]::new($currentIpBytes)
        $ipAddresses += $currentIp.ToString()
    }

    return $ipAddresses
}