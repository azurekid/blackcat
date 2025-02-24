using namespace System.Management.Automation

# used for auto-generating the valid values for the ServiceName parameter
class ResourceProviders : IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        return ($script:SessionVariables.providers | Sort-Object -Unique -Descending)
    }
}

function Invoke-AzBatch {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$ResourceType
    )

    begin {
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {
        try {
            $payload = @{
                requests = @(
                    @{
                        httpMethod = 'POST'
                        url        = $($sessionVariables.resourceGraphUri)
                        content    = @{
                            query = "resources | where type == '$($ResourceType.ToLower())'"
                        }
                    }
                )
            }

            $requestParam = @{
                Headers     = $script:authHeader
                Uri         = $sessionVariables.batchUri
                Method      = 'POST'
                ContentType = 'application/json'
                Body        = $payload | ConvertTo-Json -Depth 10
            }

            $apiResponse = (Invoke-RestMethod @requestParam).responses.content.data

            if (!($apiResponse)) {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "No resources found" -Severity 'Information'
            }
            else {
                return $apiResponse
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
<#
.SYNOPSIS
    Enumerates resources of a specified type using Azure Resource Graph.

.DESCRIPTION
    The Invoke-AzBatch function queries Azure Resource Graph to enumerate resources of a specified type.
    It constructs a query based on the provided resource type and sends an API request to retrieve the resources.

.PARAMETER ResourceType
    The type of resources to enumerate. This parameter is optional and can be provided via pipeline by property name.

.EXAMPLE
    PS> Invoke-AzBatch -ResourceType "Microsoft.Compute/virtualMachines"
    Enumerates all virtual machines in the Azure subscription.

.NOTES
    This function requires appropriate authentication headers to be set in the $script:authHeader variable.
    The $sessionVariables object must contain the resourceGraphUri and batchUri properties for API requests.
#>
}