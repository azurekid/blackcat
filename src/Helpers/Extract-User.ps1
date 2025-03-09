function Extract-User {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9-]+[A-Za-z0-9]$', ErrorMessage = "It does not match expected pattern '{1}'")]
        [string]$UserName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$UserGroup
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {

        try {

            Write-Verbose "Extracting user information"
            $uri = "$($SessionVariables.baseUri)/users/$UserName?api-version=$($SessionVariables.apiVersion)"

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
        This function extracts user information based on the provided username.

    .DESCRIPTION
        The Extract-User function makes a GET request to retrieve user information using the provided session variables and authentication headers. It handles errors and logs messages accordingly.

    .PARAMETER UserName
        The UserName parameter is a mandatory string that must match the pattern '^[A-Za-z0-9][A-Za-z0-9-]+[A-Za-z0-9]$'. It is used to identify the user.

    .PARAMETER UserGroup
        The UserGroup parameter is an optional string that specifies the name of the user group.

    .EXAMPLE
        ```powershell
        Extract-User -UserName "exampleUser" -UserGroup "exampleGroup"
        ```
        This example calls the Extract-User function with the specified UserName and UserGroup.

    .EXAMPLE
        ```powershell
        Extract-User -UserName "exampleUser"
        ```
        This example calls the Extract-User function with only the mandatory UserName parameter.

    .LINK
        For more information, see the related documentation or contact support.

    .NOTES
    Author: Rogier Dijkman
    #>
}
