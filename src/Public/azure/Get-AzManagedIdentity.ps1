function Get-AzManagedIdentity {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9-]+[A-Za-z0-9]$', ErrorMessage = "It does not match expected pattern '{1}'")]
        [string]$Name
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {

        try {

            Write-Verbose "Get Managed Identity"
            $uri = "$($SessionVariables.baseUri)/providers/Microsoft.ManagedIdentity/userAssignedIdentities?api-version=2023-01-31"

            $requestParam = @{
                Headers = $script:authHeader
                Uri     = $uri
                Method  = 'GET'
            }
            $apiResponse = (Invoke-RestMethod @requestParam).value

            if ($name) {
                return $apiResponse | Where-Object { $_.name -eq $Name }
            } else {
                return $apiResponse
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
<#
    .SYNOPSIS
    Retrieves information about managed identities.
    .DESCRIPTION
    The Get-AzUserAssignedManagedIdentity function retrieves information about managed identities from the specified API endpoint.
    It can return all available managed identities or filter the results based on a specific name.
    .PARAMETER Name
    Specifies the name of the managed identity to retrieve.
    The name must match the expected pattern '^[A-Za-z0-9][A-Za-z0-9-]+[A-Za-z0-9]$'.
    .EXAMPLE
    Get-AzUserAssignedManagedIdentity -Name "myManagedIdentity"
    Retrieves the managed identity with the name "myManagedIdentity".
    .EXAMPLE
    Get-AzUserAssignedManagedIdentity
    Retrieves all available managed identities.
    .INPUTS
    None. You cannot pipe input to this function.
    .OUTPUTS
    System.Object
    The function returns an object representing the retrieved managed identities.
    If a name is specified, it returns a single managed identity object.
    If no name is specified, it returns an array of all available managed identity objects.
    .NOTES
    This function requires the Invoke-BlackCat and Invoke-RestMethod cmdlets to be available.
    .LINK
    Invoke-BlackCat
#>
}