function Function-Name {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9-]+[A-Za-z0-9]$', ErrorMessage = "It does not match expected pattern '{1}'")]
        [string]$Name,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroupName
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {

        try {

            Write-Verbose "Information Dialog"
            $uri = "$($SessionVariables.baseUri)/providers/Microsoft.<providerName>/<resourceType>?api-version=$($SessionVariables.apiVersion)"

            $requestParam = @{
                Headers = $authHeader
                Uri     = $uri
                Method  = 'GET'
            }
            $apiResponse = (Invoke-RestMethod @requestParam).value

        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
    <#
    .SYNOPSIS
        This function performs an API call to a specified provider and resource type.

    .DESCRIPTION
        The Function-Name function makes a GET request to a specified provider and resource type using the provided session variables and authentication headers. It handles errors and logs messages accordingly.

    .PARAMETER Name
        The name parameter is a mandatory string that must match the pattern '^[A-Za-z0-9][A-Za-z0-9-]+[A-Za-z0-9]$'. It is used to identify the resource.

    .PARAMETER ResourceGroupName
        The ResourceGroupName parameter is an optional string that specifies the name of the resource group.

    .EXAMPLE
        ```powershell
        Function-Name -Name "exampleName" -ResourceGroupName "exampleResourceGroup"
        ```
        This example calls the Function-Name function with the specified Name and ResourceGroupName.

    .EXAMPLE
        ```powershell
        Function-Name -Name "exampleName"
        ```
        This example calls the Function-Name function with only the mandatory Name parameter.

    .LINK
        For more information, see the related documentation or contact support.

    .NOTES
    Author: Rogier Dijkman
    #>
}