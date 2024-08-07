function Get-AzService {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$IpAddress
    )

    begin {
        # Check if service tags are loaded
        if (($sessionVariables.serviceTags).count -le 1) {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Service tags not loaded. Please run the 'Update-ServiceTags' function." -Severity 'Error'
            return
        }

        # Create filter for the CIDR to improve performance
        if ($CidrRange -match '^([0-9A-Fa-f]{1,4}):([0-9A-Fa-f]{1,4}):') {
            $firstTwoSegments = $ipAddress.split('.')[0..1] -join ':'
          }
          else {
            $firstTwoSegments = $ipAddress.split('.')[0..1] -join '.'
          }
    }

    process {
        try {
            $SessionVariables.serviceTags | ForEach-Object {
                # Check if the IP address matches any of the service tag prefixes within the CIDR range
                Write-Verbose "Checking service tag: $($_.Name)"
                foreach ($prefix in $_.properties.addressPrefixes) {
                    if ($prefix -like "$firstTwoSegments*") {
                        $addresses = @(Get-CidrAddresses -CidrRange $prefix)

                        if ($addresses -like "*$($ipAddress)*") {
                            Write-Host "Service tag found: $($_.Name)" -ForegroundColor Green
                            # if the IP address matches the service tag prefix, set the boolean to true and break the loop of the prefixes
                            $bool = $true
                            break
                        }
                        else {
                            continue
                        }
                    }
                }
                # if the boolean is true, break the ForEach loop of the jsonContent object
                if ($bool -eq $true) {
                    # break
                }
            }

            return "No matching service tag found for the given IP address."
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
    <#
    .SYNOPSIS
        Retrieves the Azure service tag associated with a given IP address.

    .DESCRIPTION
        The Get-AzService function retrieves the Azure service tag that corresponds to a specified IP address. It checks if the IP address matches any of the service tag prefixes and returns the corresponding service tag name.

    .PARAMETER IpAddress
        Specifies the IP address for which to retrieve the Azure service tag.

    .EXAMPLE
        Get-AzService -IpAddress "192.168.1.10"
        Retrieves the Azure service tag associated with the IP address "192.168.1.10".

    .NOTES
        This function requires the 'Update-ServiceTags' function to be run before use in order to load the service tags.

    .LINK
        Update-ServiceTags
    #>
}