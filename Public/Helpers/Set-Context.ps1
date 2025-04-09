function Set-Context {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ArgumentCompleter({
                param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)

                $contexts = Get-AzContext -ListAvailable
                $index = 1
                $contexts | ForEach-Object {
                    $friendlyName = "[$($_.Account.Id.Split('@')[0])] $(($_.Subscription.Name -replace '^\s+', ''))"
                    $indexedName = "$index - $friendlyName"

                    # Return matches for index, indexed name, or friendly name
                    if ($WordToComplete -eq '' -or
                        $index.ToString() -like "*$WordToComplete*") {
                        $index.ToString()
                        """$indexedName"""
                    }

                    $index++
                }
            })]
        [string]$SwitchTo
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {
        try {
            # Get all available contexts
            $contexts = Get-AzContext -ListAvailable

            if (!$SwitchTo) {
                # Display available contexts in a friendly format with added friendly names
                $index = 1
                $contexts | ForEach-Object {
                    # Create friendly name from subscription and account
                    $friendlyName = "[$($_.Account.Id.Split('@')[0])] $(($_.Subscription.Name -replace '^\s+', ''))"

                    [PSCustomObject]@{
                        Index        = $index++
                        FriendlyName = $friendlyName
                        Name         = $_.Name
                        Account      = $_.Account.Id
                        Subscription = $_.Subscription.Name
                        Tenant       = $_.Tenant.Id
                        Environment  = $_.Environment.Name
                        IsDefault    = $_.IsDefault
                    }
                } | Format-Table -AutoSize
                return
            } else {
                # Check if SwitchTo is an index number
                if ($SwitchTo -match '^\d+$') {
                    $indexNumber = [int]$SwitchTo
                    if ($indexNumber -gt 0 -and $indexNumber -le $contexts.Count) {
                        $targetContext = $contexts[$indexNumber - 1]
                    }
                    else {
                        Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Index '$SwitchTo' is out of range (1-$($contexts.Count))" -Severity 'Error'
                        return
                    }
                }
                else {
                    # Enhance context search to include friendly name pattern
                    $targetContext = $contexts | Where-Object {
                        $friendlyName = "$($_.Subscription.Name) [$($_.Account.Id.Split('@')[0])]"
                        $_.Name -contains $SwitchTo -or
                        $_.Account.Id -contains $SwitchTo -or
                        $_.Subscription.Name -contains $SwitchTo -or
                        $friendlyName -eq $SwitchTo
                    }
                }

                if ($targetContext) {
                    Select-AzContext -InputObject $targetContext
                    $MyInvocation.MyCommand.Name | Invoke-BlackCat -ChangeProfile
                    Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Switched to context: $SwitchTo" -Severity 'Information'

                    $currentContext = Get-AzContext
                    $userDetails = ConvertFrom-JWT -Base64JWT $script:authHeader.Values

                    [PSCustomObject]@{
                        Context      = "$($currentContext.Subscription.Name) [$($currentContext.Account.Id.Split('@')[0])]"
                        FirstName    = $userDetails.FirstName
                        LastName     = $userDetails.LastName
                        Account      = $currentContext.Account.Id
                        ObjectId     = $userDetails.ObjectId
                        Subscription = $currentContext.Subscription.Name
                        Tenant       = $currentContext.Tenant.Id
                        Environment  = $currentContext.Environment.Name
                        Roles        = $userDetails.Roles
                    }
                }
                else {
                    Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Context '$SwitchTo' not found" -Severity 'Error'
                }
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }

    <#
    .SYNOPSIS
        Manages Azure PowerShell contexts.

    .DESCRIPTION
        The `Set-Context` function provides a way to list and switch between Azure PowerShell contexts.
        It displays available contexts in a user-friendly format and allows switching to a specific context
        using an index number, context name, account ID, subscription name, or a friendly name.

    .PARAMETER SwitchTo
        Specifies the context to switch to. This parameter supports the following values:
        - Index number (as displayed in the list)

    .EXAMPLE
        Set-Context
        Lists all available Azure contexts in a friendly format.

    .EXAMPLE
        Set-Context -SwitchTo 1
        Switches to the Azure context at index 1 in the list.

    .NOTES
        Author: Rogier Dijkman
        This function uses `Get-AzContext` to retrieve available contexts and `Select-AzContext` to switch between them.
        It also provides detailed information about the current context after switching.
    #>
}