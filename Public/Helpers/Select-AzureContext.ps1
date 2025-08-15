function Select-AzureContext {
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param (
        [Parameter(Mandatory = $false, ParameterSetName = 'List')]
        [switch]$List,
        
        [Parameter(Mandatory = $false, ParameterSetName = 'Switch', ValueFromPipelineByPropertyName = $true)]
        [ArgumentCompleter({
                param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)

                $contexts = Get-AzContext -ListAvailable
                $index = 1
                $contextCompletions = @()
                
                $contexts | ForEach-Object {
                    $userName = $_.Account.Id.Split('@')[0]
                    $subscriptionName = $_.Subscription.Name -replace '^\s+', ''
                    $indexedName = "$index - [$userName] $subscriptionName"
                    $contextCompletions += "$indexedName"
                    
                    $index++
                }
                
                if ($WordToComplete) {
                    $contextCompletions | Where-Object { $_ -like "*$WordToComplete*" }
                }
                else {
                    $contextCompletions
                }
            })]
        [Alias("Context", "Name")]
        [string]$SwitchTo,
        
        [Parameter(Mandatory = $false, ParameterSetName = 'Switch')]
        [switch]$Force,
        
        [Parameter(Mandatory = $false, ParameterSetName = 'Switch')]
        [switch]$ShowDetails
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {
        try {
            $contexts = Get-AzContext -ListAvailable
            $currentContext = Get-AzContext

            if ($PSCmdlet.ParameterSetName -eq 'List' -or !$SwitchTo) {
                $index = 1
                $contextList = $contexts | ForEach-Object {
                    $userName = $_.Account.Id.Split('@')[0]
                    $subscriptionName = $_.Subscription.Name -replace '^\s+', ''
                    
                    # More robust current context comparison
                    $isCurrent = ($currentContext -and 
                                  $_.Account.Id -eq $currentContext.Account.Id -and 
                                  $_.Subscription.Id -eq $currentContext.Subscription.Id -and
                                  $_.Tenant.Id -eq $currentContext.Tenant.Id)
                    
                    $currentMarker = if ($isCurrent) { "*" } else { " " }
                    
                    [PSCustomObject]@{
                        ' '          = $currentMarker
                        Index        = $index++
                        Account      = $_.Account.Id
                        Subscription = $subscriptionName
                        Tenant       = $_.Tenant.Id.Substring(0, 32) + "..." # Shortened for readability
                        Environment  = $_.Environment.Name
                        IsDefault    = $_.IsDefault
                    }
                }
                
                Write-Host "Available Azure Contexts (* indicates current context):" -ForegroundColor Cyan
                $contextList | Format-Table -AutoSize
                Write-Host "To switch contexts, use: Select-AzureContext -SwitchTo <Index>" -ForegroundColor DarkCyan
                return
            } 
            else {
                # First, try to find an exact match
                $targetContext = $null
                
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
                    $targetContext = $contexts | Where-Object {
                        $userName = $_.Account.Id.Split('@')[0]
                        $subscriptionName = $_.Subscription.Name -replace '^\s+', ''
                        $friendlyName = """[$userName] $subscriptionName"""
                        
                        # Check for exact matches first
                        $_.Name -eq $SwitchTo -or
                        $_.Account.Id -eq $SwitchTo -or
                        $_.Subscription.Name -eq $SwitchTo -or
                        $friendlyName -eq $SwitchTo -or
                        $userName -eq $SwitchTo
                    }
                    
                    if (-not $targetContext) {
                        $targetContext = $contexts | Where-Object {
                            $userName = $_.Account.Id.Split('@')[0]
                            
                            $_.Name -like "*$SwitchTo*" -or
                            $_.Account.Id -like "*$SwitchTo*" -or
                            $_.Subscription.Name -like "*$SwitchTo*" -or
                            $userName -like "*$SwitchTo*"
                        } | Select-Object -First 1
                    }
                }

                if ($targetContext) {
                    if ($targetContext -is [array] -and $targetContext.Count -gt 1) {
                        Write-Host "Multiple contexts matched your criteria. Please be more specific:" -ForegroundColor Yellow
                        $index = 1
                        $targetContext | ForEach-Object {
                            $userName = $_.Account.Id.Split('@')[0]
                            $subscriptionName = $_.Subscription.Name -replace '^\s+', ''
                            Write-Host "$index - [$userName] $subscriptionName" -ForegroundColor Yellow
                            $index++
                        }
                        return
                    }
                    
                    Select-AzContext -InputObject $targetContext
                    $MyInvocation.MyCommand.Name | Invoke-BlackCat -ChangeProfile
                    $currentContext = Get-AzContext
                    $userName = $currentContext.Account.Id.Split('@')[0]
                    $subscriptionName = $currentContext.Subscription.Name -replace '^\s+', ''

                    Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "Switched to context: [$userName] $subscriptionName" -Severity 'Information'

                    # Show detailed info if requested
                    if ($ShowDetails) {
                        $userDetails = ConvertFrom-JWT -Base64JWT $script:authHeader.Values

                        [PSCustomObject]@{
                            Context        = "[$userName] $subscriptionName"
                            FirstName      = $userDetails.FirstName
                            LastName       = $userDetails.LastName
                            Account        = $currentContext.Account.Id
                            ObjectId       = $userDetails.ObjectId
                            Subscription   = $currentContext.Subscription.Name
                            SubscriptionId = $currentContext.Subscription.Id
                            Tenant         = $currentContext.Tenant.Id
                            Environment    = $currentContext.Environment.Name
                            Roles          = $userDetails.Roles
                        }
                    }
                    else {
                        # Just show minimal info
                        [PSCustomObject]@{
                            Context        = "[$userName] $subscriptionName"
                            Account        = $currentContext.Account.Id
                            SubscriptionId = $currentContext.Subscription.Id
                            Tenant         = $currentContext.Tenant.Id
                        }
                    }
                }
                else {
                    Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "No context found matching '$SwitchTo'" -Severity 'Error'
                }
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }

    <#
    .SYNOPSIS
        Lists and selects Azure PowerShell contexts.

    .DESCRIPTION
        Lists available Azure contexts and allows switching between them using friendly names, 
        index numbers, subscription names, or usernames. Provides tab completion and partial
        name matching for easier context selection.

    .PARAMETER List
        Switch parameter to list all available contexts (default behavior).

    .PARAMETER SwitchTo
        Specifies the context to switch to. Can be:
        - Index number (as displayed in the list)
        Supports tab completion and partial name matching.
        
    .PARAMETER ShowDetails
        Shows detailed information about the selected context after switching.

    .EXAMPLE
        Select-AzureContext
        Lists all available Azure contexts.

    .EXAMPLE
        Select-AzureContext -SwitchTo "MySubscription"
        Switches to the context with the specified subscription name.

    .EXAMPLE
        Select-AzureContext -SwitchTo 2
        Switches to the context at index 2 in the list.
        
    .EXAMPLE
        Select-AzureContext -SwitchTo "prod" -Force
        Switches to the context matching "prod" without confirmation.

    .EXAMPLE
        Select-AzureContext -SwitchTo "john" -ShowDetails
        Switches to the context for user "john" and shows detailed information.

    .NOTES
        Author: Rogier Dijkman
    #>
}

# Create an alias for backward compatibility
New-Alias -Name Switch-Context -Value Select-AzureContext -Description "Alias for backward compatibility" -Force
Export-ModuleMember -Function Select-AzureContext -Alias Switch-Context