function Test-DNSName {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$DnsName
    )

    # Load the System.Net namespace
    Add-Type -AssemblyName System.Net

    Write-Verbose "Validating DNS name: $DnsName"

    try {
        # Use the Dns.GetHostAddresses method to validate the DNS name
        $result = [System.Net.Dns]::GetHostAddresses($DnsName)
        if ($result) {
            Write-Verbose "DNS name '$DnsName' is valid. IP addresses: $($result.IPAddressToString -join ', ')"
            return $true
        } else {
            Write-Verbose "DNS name '$DnsName' is not valid."
            return $false
        }
    } catch [System.Net.Sockets.SocketException] {
        Write-Verbose "DNS name '$DnsName' is not valid. Exception: $_"
        return $false
    } catch {
        Write-Verbose "An unexpected error occurred: $_"
        return $false
    }
<#
.SYNOPSIS
    Validates a DNS name by attempting to resolve it to an IP address.

.DESCRIPTION
    The Test-DNSName function takes a DNS name as input and attempts to resolve it to an IP address using the System.Net.Dns class. 
    If the DNS name is valid and can be resolved, the function returns $true. Otherwise, it returns $false.

.PARAMETER dnsName
    The DNS name to validate. This parameter is mandatory.

.EXAMPLE
    PS C:\> Test-DNSName -dnsName "example.com"
    This command validates the DNS name "example.com".

.EXAMPLE
    PS C:\> Test-DNSName -dnsName "invalid-dns-name"
    This command attempts to validate the DNS name "invalid-dns-name" and returns $false if it cannot be resolved.

.NOTES
    Author: Your Name
    Date: Today's Date
    Version: 1.0

#>
}