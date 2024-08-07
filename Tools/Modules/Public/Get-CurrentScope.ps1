function Get-CurrentScope {
    [cmdletbinding()]
    param (
    )

    begin {
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {

        try {

            Write-Verbose "Information Dialog"
            ConvertFrom-JWT -Base64JWT $script:authHeader.Values

        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
    <#
    .SYNOPSIS
        This function retrieves the current scope.
    .DESCRIPTION
        The Get-CurrentScope function is used to retrieve the current scope. It is designed to be used within a PowerShell script or module.
    .EXAMPLE
        Get-CurrentScope
        Retrieves the current scope.
    .LINK
        More information can be found at: <link>
    #>
}