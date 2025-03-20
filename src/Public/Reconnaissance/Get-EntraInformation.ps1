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
            # Base Graph API URL
            $graphApiVersion = "beta"
            $baseUri = "https://graph.microsoft.com/$graphApiVersion"

            # Construct query based on parameter set
            switch ($PSCmdlet.ParameterSetName) {
                'ObjectId' {
                    if ($Group) {
                        $uri = "$baseUri/groups/$ObjectId"
                        $response = Invoke-RestMethod -Uri $uri -Method GET -Headers $script:graphHeader
                        $isGroup = $true
                    } else {
                        $uri = "$baseUri/users/$ObjectId"
                        $response = Invoke-RestMethod -Uri $uri -Method GET -Headers $script:graphHeader
                        $isGroup = $false
                    }
                }
                'Name' {
                    if ($Group) {
                        $uri = "$baseUri/groups?`$filter=startswith(displayName,'$Name')"
                        $response = (Invoke-RestMethod -Uri $uri -Method GET -Headers $script:graphHeader).value
                        $isGroup = $true
                    } else {
                        $uri = "$baseUri/users?`$filter=startswith(displayName,'$Name') or startswith(userPrincipalName,'$Name')"
                        $response = (Invoke-RestMethod -Uri $uri -Method GET -Headers $script:graphHeader).value
                        $isGroup = $false
                    }
                }
            }

            foreach ($item in $response) {
                if ($isGroup) {
                    # Get group members
                    $membersUri = "$baseUri/groups/$($item.id)/members"
                    $members = (Invoke-RestMethod -Uri $membersUri -Method GET -Headers $script:graphHeader).value

                    # Get group roles and permissions
                    $rolesUri = "$baseUri/groups/$($item.id)/transitiveMemberOf/microsoft.graph.directoryRole"
                    $roles = (Invoke-RestMethod -Uri $rolesUri -Method GET -Headers $script:graphHeader).value

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
                    $groupsUri = "$baseUri/users/$($item.id)/memberOf"
                    $groups = (Invoke-RestMethod -Uri $groupsUri -Method GET -Headers $script:graphHeader).value

                    # Get directory roles
                    $rolesUri = "$baseUri/users/$($item.id)/transitiveMemberOf/microsoft.graph.directoryRole"
                    $roles = (Invoke-RestMethod -Uri $rolesUri -Method GET -Headers $script:graphHeader).value

                    # Create custom object with user information
                    [PSCustomObject]@{
                        UserPrincipalName = $item.userPrincipalName
                        DisplayName      = $item.displayName
                        ObjectId        = $item.id
                        GroupMemberships = $groups.displayName
                        Roles           = $roles.displayName
                        Mail            = $item.mail
                        JobTitle        = $item.jobTitle
                        Department      = $item.department
                    }
                }
            }
        }
        catch {
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
}
