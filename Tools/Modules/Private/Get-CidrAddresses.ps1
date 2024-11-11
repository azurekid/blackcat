function Get-CidrAddresses {
    param (
        [Parameter(Mandatory = $true)]
        [ValidatePattern('\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}|^([0-9A-Fa-f]{1,4}):([0-9A-Fa-f]{1,4}):')]
        [string]$CidrRange
    )

    # Check if the CIDR range is an IPv6 address
    $ipv6 = $CidrRange -match '^([0-9A-Fa-f]{1,4}):([0-9A-Fa-f]{1,4}):'
    $ipv4 = !$ipv6

    # Parse the CIDR range
    $cidr = $CidrRange -split '/'
    $baseIp = [System.Net.IPAddress]::Parse($cidr[0])
    $subnetMaskLength = [int]$cidr[1]

    if ($ipv6 -and ($subnetMaskLength -lt 117)) {
        # "IPv6 subnet mask length must be at least 117"
        break
    }

    if ($ipv4 -and ($subnetMaskLength -lt 18)) {
        # throw "IPv4 subnet mask length must be at least 18"
        break
    }

    # Calculate the number of addresses in the subnet
    $numberOfAddresses = [math]::Pow(2, ($ipv6 ? 128 : 32) - $subnetMaskLength)

    # Convert base IP to a 32-bit integer
    $baseIpBytes = $baseIp.GetAddressBytes()
    [Array]::Reverse($baseIpBytes)

    # Generate all possible IP addresses within the subnet
    $ipAddresses = for ($i = 0; $i -lt $numberOfAddresses; $i++) {
        $currentIpInt = [BitConverter]::ToUInt32($baseIpBytes, 0) + $i
        $currentIpBytes = [BitConverter]::GetBytes($currentIpInt)
        [Array]::Reverse($currentIpBytes)
        $currentIp = [System.Net.IPAddress]::new($currentIpBytes)
        $currentIp.ToString()
    }

    return $ipAddresses
}