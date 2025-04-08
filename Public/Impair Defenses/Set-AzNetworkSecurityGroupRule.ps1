function Set-AzNetworkSecurityGroupRule {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceNameCompleterAttribute(
            "Microsoft.Network/networkSecurityGroups",
            "ResourceGroupName"
        )]
        [Alias('nsgName', 'networkSecurityGroupName')]
        [string[]]$Name,

        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceGroupCompleterAttribute()]
        [Alias('rg', 'resource-group')]
        [string[]]$ResourceGroupName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias('resource-id')]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceIdCompleter(
            "Microsoft.Network/networkSecurityGroups"
        )][object]$Id,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('port-numbers')]
        [int[]]$Ports = @(22, 23, 80, 443, 3389),

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('throttle-limit')]
        [int]$ThrottleLimit = 100,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('source-ip')]
        [string]$SourceIp = "*"
    )

    begin {
        [void] $ResourceGroupName # Only used to trigger the ResourceGroupCompleter

        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {
        $Ports = $Ports | Sort-Object -Unique
        $baseUri = 'https://management.azure.com'

        $id = if ($Name) {
            (Invoke-AzBatch -ResourceType 'Microsoft.Network/networkSecurityGroups' -Name $($Name)).id
        } else {
            (Invoke-AzBatch -ResourceType 'Microsoft.Network/networkSecurityGroups').id
        }

        $id | ForEach-Object -Parallel {
            try {
                $authHeader = $using:script:authHeader
                $nsgUrl = '{0}{1}?api-version={2}' -f $using:baseUri, $_, '2021-02-01'

                $requestParam = @{
                    Headers = $authHeader
                    Uri     = $nsgUrl
                    Method  = 'GET'
                }

                $nsg = Invoke-RestMethod @requestParam

                $ruleName = "remote-management"
                if ($nsg.properties.securityRules.name -notcontains $ruleName) {
                    Write-Output $nsg.properties.securityRules
                    Write-Verbose "Adding rule '$ruleName' to NSG for ports $($using:Ports -join ', ') and source IP $using:SourceIp"
                    $newRule = @{
                        name       = $ruleName
                        properties = @{
                            description              = "Allow traffic on ports $($using:Ports -join ', ') from source IP $using:SourceIp"
                            protocol                 = "Tcp"
                            sourcePortRange          = "*"
                            destinationPortRanges    = $using:Ports
                            sourceAddressPrefix      = $using:SourceIp
                            destinationAddressPrefix = "*"
                            access                   = "Allow"
                            priority                 = 100
                            direction                = "Inbound"
                        }
                    }
                    $nsg.properties.securityRules += $newRule

                    $requestParam = @{
                        Uri         = $nsgUrl
                        Method      = "Put"
                        Headers     = $authHeader
                        Body        = ($nsg | ConvertTo-Json -Depth 10)
                        ContentType = "application/json"
                    }
                    Invoke-RestMethod @requestParam
                    Write-Verbose "Updated NSG successfully."
                }
                else {
                    Write-Output "    Set-AzNetworkSecurityGroupRule: Rule '$ruleName' already exists in NSG."
                }
            }
            catch {
                Write-Error "Failed to process NSG: $($_.Exception.Message)"
            }
        } -ThrottleLimit $ThrottleLimit
    }

    end {
        Write-Verbose "Completed function $($MyInvocation.MyCommand.Name)"
    }
<#
.SYNOPSIS
Configures or updates a rule in an Azure Network Security Group (NSG).

.DESCRIPTION
The `Set-AzNetworkSecurityGroupRule` function allows you to configure or update a security rule in an Azure Network Security Group (NSG).
It supports specifying the NSG by name, resource group, or resource ID. The function ensures that a rule named "remote-management"
is added to the NSG with the specified ports and source IP address.

.PARAMETER Name
Specifies the name(s) of the Network Security Group(s) to configure. This parameter supports pipeline input.

.PARAMETER ResourceGroupName
Specifies the name(s) of the resource group(s) containing the Network Security Group(s). This parameter supports pipeline input.

.PARAMETER Id
Specifies the resource ID(s) of the Network Security Group(s). This parameter supports pipeline input.

.PARAMETER Ports
Specifies the port numbers to allow in the security rule. Defaults to 22, 23, 80, 443, and 3389. The ports are sorted and made unique.

.PARAMETER ThrottleLimit
Specifies the maximum number of concurrent operations to run. Defaults to 100.

.PARAMETER SourceIp
Specifies the source IP address or range to allow in the security rule. Defaults to "*", which allows traffic from any source.

.EXAMPLE
Set-AzNetworkSecurityGroupRule -Name "MyNSG" -ResourceGroupName "MyResourceGroup" -Ports 22, 443 -SourceIp "192.168.1.0/24"

Adds or updates a rule named "remote-management" in the NSG named "MyNSG" within the resource group "MyResourceGroup".
The rule allows traffic on ports 22 and 443 from the source IP range "192.168.1.0/24".

.EXAMPLE
Get-AzNetworkSecurityGroup | Set-AzNetworkSecurityGroupRule -Ports 3389

Pipes a list of NSGs to the function and adds or updates a rule named "remote-management" to allow traffic on port 3389 from any source IP.

.NOTES
- This function uses Azure REST APIs to interact with Network Security Groups.
- The function requires appropriate Azure authentication and permissions to modify NSGs.
- The rule name is hardcoded as "remote-management".

.INPUTS
- [string[]] Name
- [string[]] ResourceGroupName
- [object] Id

.OUTPUTS
None. The function performs actions but does not return any output.

#>
}