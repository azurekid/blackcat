function Get-CurrentUser {
    [cmdletbinding()]
    param ()

    begin {
        # Sets the authentication header to the Microsoft Graph API
        try {
            $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
        } catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message 'An error has occured invoking BlackCat' -Severity 'Error'
            break
        }
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
                $user = Invoke-RestMethod @requestParam

                Write-Verbose "Getting current user's group memberships"
                $groupUri = "$($sessionVariables.graphUri)/me/memberOf"

                $groupRequestParam = @{
                    Headers = $script:graphHeader
                    Uri     = $groupUri
                    Method  = 'GET'
                }

                $groups = Invoke-RestMethod @groupRequestParam

                # Add group memberships to the user object
                $user | Add-Member -MemberType NoteProperty -Name 'Groups' -Value ($groups.value | Select-Object -Property displayName, IsAssignableToRole)

                # Return the user object with group memberships
                return $user | Select-Object -Property id, displayName, userPrincipalName, jobTitle, Groups
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
Retrieves information about the current authenticated user from Microsoft Graph API, including group memberships.

.DESCRIPTION
The Get-CurrentUser function queries the Microsoft Graph API to get details about the currently authenticated user.
It also retrieves the group memberships of the user and includes them in the output.
It utilizes the existing authentication header and session variables to make the API requests.

.EXAMPLE
Get-CurrentUser

Returns the current user's information from Microsoft Graph API, including group memberships.

.EXAMPLE
Get-CurrentUser -Verbose

Returns the current user's information with verbose output showing the API call progress, including group memberships.

.NOTES
This function requires:
- Valid authentication to Microsoft Graph API
- Appropriate permissions to access user information and group memberships
- The BlackCat module to be loaded with proper session variables

.OUTPUTS
Returns a PSCustomObject containing the current user's information from Microsoft Graph API, including group memberships.
The exact properties returned depend on the permissions granted to the authenticated session.
#>
}