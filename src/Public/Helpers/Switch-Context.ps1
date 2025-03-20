function Switch-Context {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ArgumentCompleter({
                param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)

                $contexts = Get-AzContext -ListAvailable
                $contexts | ForEach-Object {
                    $friendlyName = "$($_.Subscription.Name) [$($_.Account.Id.Split('@')[0])]"
                    if ($friendlyName -like "*$WordToComplete*") {
                        """$friendlyName"""
                    }
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
                $contexts | ForEach-Object {
                    # Create friendly name from subscription and account
                    $friendlyName = "$($_.Subscription.Name) [$($_.Account.Id.Split('@')[0])]"

                    [PSCustomObject]@{
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
                # Enhance context search to include friendly name pattern
                $targetContext = $contexts | Where-Object {
                    $friendlyName = "$($_.Subscription.Name) [$($_.Account.Id.Split('@')[0])]"
                    $_.Name -contains $SwitchTo -or
                    $_.Account.Id -contains $SwitchTo -or
                    $_.Subscription.Name -contains $SwitchTo -or
                    $friendlyName -eq $SwitchTo
                }

                if ($targetContext) {
                    Select-AzContext -InputObject $targetContext
                    $MyInvocation.MyCommand.Name | Invoke-BlackCat -ChangeProfile
                    Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Switched to context: $SwitchTo" -Severity 'Information'

                    $currentContext = Get-AzContext
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

            $userDetails = ConvertFrom-JWT -Base64JWT $script:authHeader.Values

            # Display current context if no parameters specified
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }

    <#
    .SYNOPSIS
        Manages Azure PowerShell contexts.

    .DESCRIPTION
        Lists available Azure contexts and allows switching between them using friendly names.

    .PARAMETER List
        Switch parameter to list all available contexts.

    .PARAMETER SwitchTo
        Specifies the context to switch to (can be context name, account ID, subscription name, or friendly name). Supports tab completion for friendly names.

    .EXAMPLE
        Get-AzureContext -List
        Lists all available Azure contexts.

    .EXAMPLE
        Get-AzureContext -SwitchTo "MySubscription"
        Switches to the context with the specified subscription name.

    .EXAMPLE
        Get-AzureContext
        Shows the current context information.

    .NOTES
        Author: Rogier Dijkman
    #>
}
