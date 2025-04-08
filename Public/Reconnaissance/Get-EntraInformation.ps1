function Get-EntraInformation {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'ObjectId')]
        [string]$ObjectId,

        [Parameter(Mandatory = $true, ParameterSetName = 'Name')]
        [string]$Name,

        [Parameter(ParameterSetName = 'ObjectId')]
        [Parameter(ParameterSetName = 'Name')]
        [switch]$Group
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'
    }

    process {
        try {
            # Construct query based on parameter set
            switch ($PSCmdlet.ParameterSetName) {
                'ObjectId' {
                    if ($Group) {
                        $response = Invoke-MsGraph -relativeUrl "groups/$ObjectId" -NoBatch
                        $isGroup = $true
                    } else {
                        $response = Invoke-MsGraph -relativeUrl "users/$ObjectId" -NoBatch
                        $isGroup = $false
                    }
                }
                'Name' {
                    if ($Group) {
                        $response = Invoke-MsGraph -relativeUrl "groups?`$filter=startswith(displayName,'$Name')"
                        $isGroup = $true
                    } else {
                        $response = Invoke-MsGraph -relativeUrl "users?`$filter=startswith(displayName,'$Name') or startswith(userPrincipalName,'$Name')"
                        $isGroup = $false
                    }
                }
            }

            foreach ($item in $response) {
                if ($isGroup) {
                    # Get group members
                    $members = Invoke-MsGraph -relativeUrl "groups/$($item.id)/members"

                    # Get group roles and permissions
                    $roles = Invoke-MsGraph -relativeUrl "groups/$($item.id)/transitiveMemberOf/microsoft.graph.directoryRole"

                    # Create custom object with group information
                    [PSCustomObject]@{
                        DisplayName      = $item.displayName
                        ObjectId        = $item.id
                        Description     = $item.description
                        Roles           = $roles.displayName
                        Members         = $members.displayName
                        GroupType       = $item.groupTypes
                        MailEnabled     = $item.mailEnabled
                        SecurityEnabled = $item.securityEnabled
                    }
                } else {
                    # Rest of the code for users remains the same
                    # Get group memberships
                    $groups = Invoke-MsGraph -relativeUrl "users/$($item.id)/memberOf"

                    # Get directory roles
                    $roles = Invoke-MsGraph -relativeUrl "users/$($item.id)/transitiveMemberOf/microsoft.graph.directoryRole"

                    # Create custom object with user information
                    [PSCustomObject]@{
                        UserPrincipalName = $item.userPrincipalName
                        DisplayName       = $item.displayName
                        ObjectId          = $item.id
                        GroupMemberships  = $groups.displayName
                        Roles             = $roles.displayName
                        Mail              = $item.mail
                        JobTitle          = $item.jobTitle
                        Department        = $item.department
                    }
                }
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
}
