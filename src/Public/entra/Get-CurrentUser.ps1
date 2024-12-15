function Get-CurrentUser {
    [cmdletbinding()]
    param ()

    begin {
        # Sets the authentication header to the Microsoft Graph API
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
    }

    process {

        try {

            Write-Verbose "Getting current user"
            $uri = "$($sessionVariables.graphUri)/me/"

            $requestParam = @{
                Headers = $script:graphHeader
                Uri     = $uri
                Method  = 'GET'
            }

            try {
                Write-Verbose "Invoking Microsoft Graph API"
                $requestParam.Uri = "$($sessionVariables.graphUri)/me/"

                Invoke-RestMethod @requestParam
            }
            catch {
                Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message ($_.ErrorDetails.Message | ConvertFrom-Json).Error.Message -Severity 'Information'
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
    <#
.SYNOPSIS
Retrieves information about the current authenticated user from Microsoft Graph API.

.DESCRIPTION
The Get-CurrentUser function queries the Microsoft Graph API to get details about the currently authenticated user.
It utilizes the existing authentication header and session variables to make the API request.

.EXAMPLE
Get-CurrentUser

Returns the current user's information from Microsoft Graph API.

.EXAMPLE
Get-CurrentUser -Verbose

Returns the current user's information with verbose output showing the API call progress.

.NOTES
This function requires:
- Valid authentication to Microsoft Graph API
- Appropriate permissions to access user information
- The BlackCat module to be loaded with proper session variables

.OUTPUTS
Returns a PSCustomObject containing the current user's information from Microsoft Graph API.
The exact properties returned depend on the permissions granted to the authenticated session.
#>
}