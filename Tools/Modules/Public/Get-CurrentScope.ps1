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
    .DESCRIPTION
    .PARAMETER Name
    .PARAMETER ResourceGroupName
    .EXAMPLE
    .EXAMPLE
    .LINK
#>
}