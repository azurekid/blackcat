function Invoke-RunCommand {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceNameCompleterAttribute(
            "Microsoft.Compute/virtualMachines",
            "ResourceGroupName"
        )]
        [Alias('vm', 'virtual-machine-name', 'vmName')]
        [string[]]$Name,

        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceGroupCompleterAttribute()]
        [Alias('rg', 'resource-group')]
        [string[]]$ResourceGroupName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias('resource-id')]
        [Microsoft.Azure.Commands.ResourceManager.Common.ArgumentCompleters.ResourceIdCompleter(
            "Microsoft.Compute/virtualMachines"
        )][object]$Id,

        [Parameter(Mandatory = $true, ParameterSetName = 'Command')]
        [Alias('cmd', 'command')]`
        [string]$ScriptCommand,

        [Parameter(Mandatory = $true, ParameterSetName = 'ScriptFile')]
        [Alias('file', 'script-file')]
        [System.IO.FileInfo]$ScriptFile,

        [Parameter(Mandatory = $true, ParameterSetName = 'Uri')]
        [Alias('url', 'script-uri')]
        [uri]$ScriptUri,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [Alias('throttle-limit')]
        [int]$ThrottleLimit = 100
    )

    begin {
        [void] $ResourceGroupName #Only used to trigger the ResourceGroupCompleter

        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat

        $result = New-Object System.Collections.ArrayList

        # Prepare script content based on parameter set
        switch ($PSCmdlet.ParameterSetName) {
            'Command' {
                $scriptContent = $ScriptCommand
            }
            'ScriptFile' {
                if (Test-Path -Path $ScriptFile) {
                    $scriptContent = Get-Content -Path $ScriptFile -Raw
                }
                else {
                    throw "Script file not found: $ScriptFile"
                }
            }
            'Uri' {
                try {
                    $scriptContent = (Invoke-WebRequest -Uri $ScriptUri -UseBasicParsing).Content
                }
                catch {
                    throw "Failed to download script from URI: $ScriptUri. $_"
                }
            }
        }
    }

    process {
        try {
            if (!$($Name) -and !$Id) {
                $Id = (Invoke-AzBatch -ResourceType 'Microsoft.Compute/virtualMachines').id
            } elseif ($($Name)) {
                $Id = (Invoke-AzBatch -ResourceType 'Microsoft.Compute/virtualMachines' -Name $($Name)).id
            } else {
                $Id = $Id
            }

            Write-Verbose "Executing run command on VM(s): $(($Id).count)"

            $Id | ForEach-Object {
                try {
                    # $result = $using:result
                    # $scriptContent = $using:scriptContent

                    # Construct the URI for the Run Command API
                    $uri = 'https://management.azure.com{0}/runCommand?api-version=2018-10-01' -f $_

                    $body = @{
                        commandId = "RunPowerShellScript"
                        script = @($scriptContent)
                    } | ConvertTo-Json

                    $requestParam = @{
                        Headers = $script:authHeader
                        Uri = $uri
                        Method = 'POST'
                        Body = $body
                        ContentType = 'application/json'
                        UserAgent = $sessionVariables.userAgent
                    }
                    Write-Host -Message "Executing command on VM: $($_.split('/')[-1])" -InformationAction Continue
                    Write-Host -Message "Command: $scriptContent" -InformationAction Continue

                    $apiResponse = Invoke-RestMethod @requestParam
                    Write-Output $apiResponse

                    # Wait for the operation to complete
                    $operationUri = $apiResponse.id
                    if ($operationUri) {
                        $operationStatus = $null
                        do {
                            Start-Sleep -Seconds 5
                            $operationResponse = Invoke-RestMethod -Method GET -Uri "https://management.azure.com$operationUri" -Headers $using:script:authHeader
                            $operationStatus = $operationResponse.status
                        } while ($operationStatus -eq "InProgress")

                        # Get the results
                        if ($operationStatus -eq "Succeeded") {
                            $output = $operationResponse.properties.output

                            $currentItem = [PSCustomObject]@{
                                "VMName" = $_.split('/')[-1]
                                "Output" = $output.value.Message
                                "ExitCode" = $output.value.Code
                                "Status" = $operationStatus
                            }
                        }
                        else {
                            $currentItem = [PSCustomObject]@{
                                "VMName" = $_.split('/')[-1]
                                "Output" = $operationResponse.error
                                "ExitCode" = -1
                                "Status" = $operationStatus
                            }
                        }
                    }

                    [void] $result.Add($currentItem)
                }
                catch {
                    Write-Information "$($MyInvocation.MyCommand.Name): Failed to execute command on VM '$_': $($_.Exception.Message)" -InformationAction Continue
                    $currentItem = [PSCustomObject]@{
                        "VMName" = $_.split('/')[-1]
                        "Output" = $_.Exception.Message
                        "ExitCode" = -1
                        "Status" = "Failed"
                    }
                    [void] $result.Add($currentItem)
                }
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
    end {
        Write-Verbose "Completed function $($MyInvocation.MyCommand.Name)"
        $result
    }
<#
.SYNOPSIS
Executes a command or script on one or more Azure Virtual Machines.

.DESCRIPTION
The `Invoke-RunCommand` function executes PowerShell commands or scripts on specified Azure Virtual Machines.
It supports executing commands directly, from a script file, or from a URI.

.PARAMETER Name
Specifies the name(s) of the virtual machine(s) to execute the command on.
This parameter accepts an array of strings and supports pipeline input.

.PARAMETER ResourceGroupName
Specifies the name(s) of the resource group(s) containing the virtual machine(s).
This parameter accepts an array of strings.

.PARAMETER Id
Specifies the resource ID(s) of the virtual machine(s).
This parameter accepts an object and supports pipeline input by property name.

.PARAMETER ScriptCommand
Specifies the PowerShell command to execute on the virtual machine(s).

.PARAMETER ScriptFile
Specifies the path to a PowerShell script file to execute on the virtual machine(s).

.PARAMETER ScriptUri
Specifies the URI of a PowerShell script to download and execute on the virtual machine(s).

.PARAMETER ThrottleLimit
Specifies the maximum number of concurrent operations to run when executing commands.
The default value is 100.

.INPUTS
- [string[]] Name
- [string[]] ResourceGroupName
- [object] Id
- [string] ScriptCommand
- [System.IO.FileInfo] ScriptFile
- [uri] ScriptUri

.OUTPUTS
- [PSCustomObject] A custom object containing the VM name, command output, exit code, and status.

.EXAMPLE
Invoke-RunCommand -Name "myvm" -ResourceGroupName "myresourcegroup" -ScriptCommand "Get-Process"

Executes the "Get-Process" command on the virtual machine named "myvm" in the resource group "myresourcegroup".

.EXAMPLE
Invoke-RunCommand -Id "/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.Compute/virtualMachines/{vmName}" -ScriptFile "C:\scripts\myscript.ps1"

Executes the script from the file "C:\scripts\myscript.ps1" on the virtual machine specified by its resource ID.

.EXAMPLE
Invoke-RunCommand -Name "myvm" -ScriptUri "https://example.com/scripts/myscript.ps1"

Downloads the script from the specified URI and executes it on the virtual machine named "myvm".

.NOTES
- This function uses Azure REST API to execute commands on virtual machines.
- Ensure that you have the necessary permissions to execute commands on the virtual machines.
- The virtual machine must have the Azure VM agent installed and running.

#>
}