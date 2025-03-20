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
    
    <#
    .SYNOPSIS
    Generates all possible IP addresses within a given CIDR range.

    .DESCRIPTION
    The `Get-CidrAddresses` function takes a CIDR range as input and generates all possible IP addresses within that range. It supports both IPv4 and IPv6 addresses.

    .PARAMETER CidrRange
    The CIDR range to generate IP addresses for. This parameter is mandatory and must be a valid CIDR notation for either IPv4 or IPv6.

    .DEPENDENCIES
    - System.Net.IPAddress
    - System.BitConverter
    - System.Math

    .EXAMPLES
    # Example 1
    # Generate all IP addresses within the IPv4 CIDR range 192.168.1.0/24
    $ipv4Addresses = Get-CidrAddresses -CidrRange '192.168.1.0/24'
    $ipv4Addresses

    # Example 2
    # Generate all IP addresses within the IPv6 CIDR range 2001:db8::/64
    $ipv6Addresses = Get-CidrAddresses -CidrRange '2001:db8::/64'
    $ipv6Addresses

    .NOTES
    IPv4 subnet mask length must be at least 18.
    IPv6 subnet mask length must be at least 117.
    #>
}