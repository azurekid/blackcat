function Set-CurrentScope {
    [cmdletbinding()]
    param (
    )

    begin {
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ChangeProfile
    }

    process {

        try {

            Write-Verbose "Getting current scope"
            ConvertFrom-JWT -Base64JWT $script:authHeader.Values

        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
    <#
    .SYNOPSIS
        Sets and retrieves information about the current authentication scope.

    .DESCRIPTION
        The Set-CurrentScope function decodes and displays the current JWT authentication scope from the stored auth header. 
        It first invokes BlackCat profile change tracking and then attempts to decode the JWT token.

    .EXAMPLE
        Set-CurrentScope
        Sets and displays the current current context and shows the JWT authentication scope information.

    .NOTES
        Uses ConvertFrom-JWT for token decoding.
        Implements error handling and verbose logging.

    .COMPONENT
        Requires BlackCat module

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        Decoded JWT token information about current scope.

    .FUNCTIONALITY
        Authentication
    #>
}