function Set-UserCredential {
    param (
        [Parameter(Mandatory = $false, ParameterSetName = 'ObjectId')]
        [string]$ObjectId,

        [Parameter(Mandatory = $false, ParameterSetName = 'Name')]
        [string]$Name,

        [Parameter(Mandatory = $false, ParameterSetName = 'UserPrincipalName')]
        [ValidatePattern('^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$', ErrorMessage = "The value '{1}' is not a valid UPN format")]
        [string]$UserPrincipalName,

        [Parameter(ParameterSetName = 'ObjectId')]
        [Parameter(ParameterSetName = 'Name')]
        [Parameter(ParameterSetName = 'UserPrincipalName')]

        [Parameter(Mandatory = $false)]
        [securestring]$Password
    )

    begin {
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat -ResourceTypeName 'MSGraph'

        $userInfo = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
    }

    process {
        # try {
            # Construct query based on parameter set
            switch ($PSCmdlet.ParameterSetName) {
                'ObjectId' {
                        $response = Invoke-MsGraph -relativeUrl "users/$ObjectId" -NoBatch
                }
                'Name' {
                        $response = Invoke-MsGraph -relativeUrl "users?`$filter=startswith(displayName,'$Name') or startswith(userPrincipalName,'$Name')"
                }
                'UserPrincipalName' {
                    $response = Invoke-MsGraph -relativeUrl "users?`$filter=userPrincipalName eq '$UserPrincipalName'"
                }
            }

                # Set password if requested and not a group
                if ($Password) {
                    $patchBody = @{
                        passwordProfile = @{
                            password = ($Password | ConvertFrom-SecureString -AsPlainText)
                            forceChangePasswordNextSignIn = $false
                        }
                    } | ConvertTo-Json -Depth 3

                    $requestParameters = @{
                        Uri             = "$($sessionVariables.graphUri)/users/$($response.id)"
                        Method          = 'PATCH'
                        Headers         = $script:graphHeader
                        Body            = $patchBody
                        ContentType     = 'application/json'
                        UseBasicParsing = $true
                    }
                    Write-Output "requestParameters:" $requestParameters

                    Invoke-RestMethod @requestParameters
                } else {
                    Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message "No password provided. Skipping password update." -Severity 'Error'
                }

            #     {
            #         $groups = Invoke-MsGraph -relativeUrl "users/$($item.id)/memberOf"
            #         $roles = Invoke-MsGraph -relativeUrl "users/$($item.id)/transitiveMemberOf/microsoft.graph.directoryRole"
            #         $currentItem = [PSCustomObject]@{
            #             DisplayName       = $item.displayName
            #             ObjectId          = $item.id
            #             UserPrincipalName = $item.userPrincipalName
            #             JobTitle          = $item.jobTitle
            #             Department        = $item.department
            #             GroupMemberships  = $groups.displayName
            #             Roles             = $roles.displayName
            #             Mail              = $item.mail
            #             AccountEnabled    = $item.accountEnabled
            #             IsPrivileged      = $False
            #         }
            #     }

            #     foreach ($role in $roles) {
            #         $privileged = ($roleDetails | Where-Object { $_.displayName -eq $role.displayName }).IsPrivileged
            #         if ($privileged -eq $true) {
            #             $currentItem.IsPrivileged = $true
            #         }
            #     }

            #     ($userInfo).Add($currentItem)

            # return $userInfo
        # }
        # catch {
        #     Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        # }
    }
}
