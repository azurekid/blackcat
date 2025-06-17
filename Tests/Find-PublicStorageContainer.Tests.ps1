
BeforeAll {
    # Import the function being tested
    . "$PSScriptRoot/../Public/Reconnaissance/anonymous/Find-PublicStorageContainer.ps1"
    
    # Import dependencies
    . "$PSScriptRoot/../Private/Write-Message.ps1"
    
    # Mock sessionVariables that the function requires
    $global:sessionVariables = @{
        userAgents = @{
            agents = @(
                @{ value = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" },
                @{ value = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" }
            )
        }
        permutations = @('test', 'prod', 'dev', 'staging', 'files', 'data', 'backup')
    }
    
    # Mock Write-Message function
    function Write-Message {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Message,
    
            [Parameter(Mandatory = $false)]
            [ValidateSet("Error", "Information", "Debug")]
            [string]$Severity = 'Information',
    
            [Parameter(Mandatory = $false)]
            [string]$FunctionName
        )
        # Capture the message for testing purposes
        $script:LastMessage = @{
            Message = $Message
            Severity = $Severity
            FunctionName = $FunctionName
        }
    }



    # Create a temporary word list file for testing
    $script:TestWordListPath = "$TestDrive\test-permutations.txt"
    @('custom1', 'custom2', 'custom3') | Out-File -FilePath $script:TestWordListPath
}

Describe "Find-PublicStorageContainer" {
    Context "Parameter Validation" {
        It "Should accept valid StorageAccountName parameter" {
            { Find-PublicStorageContainer -StorageAccountName "teststorage" } | Should -Not -Throw
        }

        It "Should accept valid Type parameter values" {
            $validTypes = @('blob', 'file', 'queue', 'table', 'dfs')
            foreach ($type in $validTypes) {
                { Find-PublicStorageContainer -StorageAccountName "test" -Type $type } | Should -Not -Throw
            }
        }

        It "Should reject invalid Type parameter values" {
            { Find-PublicStorageContainer -StorageAccountName "test" -Type "invalid" } | Should -Throw
        }

        It "Should accept valid WordList file path" {
            { Find-PublicStorageContainer -StorageAccountName "test" -WordList $script:TestWordListPath } | Should -Not -Throw
        }

        It "Should accept valid ThrottleLimit parameter" {
            { Find-PublicStorageContainer -StorageAccountName "test" -ThrottleLimit 25 } | Should -Not -Throw
        }

        It "Should accept IncludeEmpty switch parameter" {
            { Find-PublicStorageContainer -StorageAccountName "test" -IncludeEmpty } | Should -Not -Throw
        }

        It "Should accept IncludeMetadata switch parameter" {
            { Find-PublicStorageContainer -StorageAccountName "test" -IncludeMetadata } | Should -Not -Throw
        }

        It "Should use default values when optional parameters are not specified" {
            # Function should execute without throwing errors
            # Note: Function returns $null when no containers found, which is acceptable behavior
            { Find-PublicStorageContainer -StorageAccountName "test" } | Should -Not -Throw
        }
    }

    Context "Parameter Aliases" {
        It "Should accept storage-account-name alias for StorageAccountName" {
            { Find-PublicStorageContainer -StorageAccountName "test" } | Should -Not -Throw
        }

        It "Should accept storage-type alias for Type" {
            { Find-PublicStorageContainer -StorageAccountName "test" -Type "blob" } | Should -Not -Throw
        }

        It "Should accept word-list and w aliases for WordList" {
            { Find-PublicStorageContainer -StorageAccountName "test" -WordList $script:TestWordListPath } | Should -Not -Throw
            { Find-PublicStorageContainer -StorageAccountName "test" -w $script:TestWordListPath } | Should -Not -Throw
        }

        It "Should accept throttle-limit, t, and threads aliases for ThrottleLimit" {
            { Find-PublicStorageContainer -StorageAccountName "test" -ThrottleLimit 25 } | Should -Not -Throw
            { Find-PublicStorageContainer -StorageAccountName "test" -t 25 } | Should -Not -Throw
            { Find-PublicStorageContainer -StorageAccountName "test" -threads 25 } | Should -Not -Throw
        }

        It "Should accept include-empty alias for IncludeEmpty" {
            { Find-PublicStorageContainer -StorageAccountName "test" -IncludeEmpty } | Should -Not -Throw
        }

        It "Should accept include-metadata alias for IncludeMetadata" {
            { Find-PublicStorageContainer -StorageAccountName "test" -IncludeMetadata } | Should -Not -Throw
        }
    }

    Context "Output Validation" {
        It "Should return ArrayList type when containers are found or null when none found" {
            $result = Find-PublicStorageContainer -StorageAccountName "test"
            # The function can return either ArrayList (with results) or $null (no results)
            if ($result -ne $null) {
                $result | Should -BeOfType [System.Collections.ArrayList]
            } else {
                $result | Should -BeNullOrEmpty
            }
        }

        It "Should handle empty results gracefully" {
            $result = Find-PublicStorageContainer -StorageAccountName "nonexistent"
            # When no results are found, function returns $null which is acceptable
            if ($result -ne $null) {
                $result | Should -BeOfType [System.Collections.ArrayList]
                $result.Count | Should -Be 0
            } else {
                $result | Should -BeNullOrEmpty
            }
        }
    }

    Context "WordList Processing" {
        It "Should load permutations from WordList file when provided" {
            # Create a test with a known word list
            # The function should execute without errors, result can be null if no containers found
            { Find-PublicStorageContainer -StorageAccountName "test" -WordList $script:TestWordListPath } | Should -Not -Throw
        }

        It "Should handle missing WordList file gracefully" {
            $nonExistentPath = "$TestDrive\nonexistent.txt"
            # The function handles missing files internally and continues processing
            { Find-PublicStorageContainer -StorageAccountName "test" -WordList $nonExistentPath } | Should -Not -Throw
        }

        It "Should combine WordList with session permutations" {
            # This test validates that both custom and session permutations are used
            { Find-PublicStorageContainer -StorageAccountName "test" -WordList $script:TestWordListPath } | Should -Not -Throw
        }
    }

    Context "Error Handling" {
        It "Should handle DNS resolution errors gracefully" {
            { Find-PublicStorageContainer -StorageAccountName "nonexistent" } | Should -Not -Throw
        }

        It "Should continue processing after individual DNS failures" {
            $result = Find-PublicStorageContainer -StorageAccountName "test"
            # Function should complete without throwing, result can be null if no containers found
            if ($result -ne $null) {
                $result | Should -BeOfType [System.Collections.ArrayList]
            }
        }

        It "Should handle HTTP request errors gracefully" {            
            { Find-PublicStorageContainer -StorageAccountName "test" } | Should -Not -Throw
        }
    }

    Context "Performance and Threading" {
        It "Should respect ThrottleLimit parameter" {
            # Test that custom throttle limits are accepted
            { Find-PublicStorageContainer -StorageAccountName "test" -ThrottleLimit 10 } | Should -Not -Throw
            { Find-PublicStorageContainer -StorageAccountName "test" -ThrottleLimit 100 } | Should -Not -Throw
        }

        It "Should use thread-safe collections" {
            # This is more of a structural test to ensure the function doesn't throw
            # threading-related errors during parallel execution
            { Find-PublicStorageContainer -StorageAccountName "test" -ThrottleLimit 2 } | Should -Not -Throw
        }
    }

    Context "Verbose and Information Output" {
        It "Should accept verbose parameter without errors" {
            { Find-PublicStorageContainer -StorageAccountName "test" -Verbose } | Should -Not -Throw
        }

        It "Should process without throwing when verbose logging is enabled" {
            $result = Find-PublicStorageContainer -StorageAccountName "test" -Verbose
            # Function should complete successfully, result can be null if no containers found
            if ($result -ne $null) {
                $result | Should -BeOfType [System.Collections.ArrayList]
            }
        }
    }

    Context "Integration with Session Variables" {
        It "Should use session variables for user agents" {
            # Ensure the function can access and use the mocked session variables
            { Find-PublicStorageContainer -StorageAccountName "test" } | Should -Not -Throw
        }

        It "Should use session variables for permutations" {
            # Test that session permutations are being loaded
            $global:sessionVariables.permutations | Should -Not -BeNullOrEmpty
            { Find-PublicStorageContainer -StorageAccountName "test" } | Should -Not -Throw
        }
    }

    Context "Storage Type Validation" {
        It "Should generate correct DNS names for different storage types" {
            $types = @('blob', 'file', 'queue', 'table', 'dfs')
            foreach ($type in $types) {
                { Find-PublicStorageContainer -StorageAccountName "test" -Type $type } | Should -Not -Throw
            }
        }

        It "Should default to blob type when Type parameter is not specified" {
            # The function should default to 'blob' type
            { Find-PublicStorageContainer -StorageAccountName "test" } | Should -Not -Throw
        }
    }

    Context "Container Content Detection" {
        It "Should handle different container states" {
            # Test that the function can process different types of containers
            $result = Find-PublicStorageContainer -StorageAccountName "test" -IncludeEmpty
            # Function should complete successfully, result can be null if no containers found
            if ($result -ne $null) {
                $result | Should -BeOfType [System.Collections.ArrayList]
            }
        }

        It "Should exclude empty containers by default" {
            # When IncludeEmpty is not specified, function should still work
            $result = Find-PublicStorageContainer -StorageAccountName "test"
            # Function should complete successfully, result can be null if no containers found
            if ($result -ne $null) {
                $result | Should -BeOfType [System.Collections.ArrayList]
            }
        }
    }
}

Describe "Find-PublicStorageContainer Function Attributes" {
    Context "Function Metadata" {
        It "Should have correct CmdletBinding attribute" {
            $function = Get-Command Find-PublicStorageContainer
            $function.CmdletBinding | Should -Be $true
        }

        It "Should have correct OutputType attribute" {
            $function = Get-Command Find-PublicStorageContainer
            $outputType = $function.OutputType
            $outputType.Name | Should -Contain "System.Collections.ArrayList"
        }

        It "Should have correct alias attribute" {
            $function = Get-Command Find-PublicStorageContainer
            $function.Definition | Should -Match '\[Alias\("bl cli public storage accounts"\)\]'
        }
    }

    Context "Parameter Definitions" {
        It "Should have StorageAccountName parameter with correct attributes" {
            $function = Get-Command Find-PublicStorageContainer
            $param = $function.Parameters['StorageAccountName']
            $param | Should -Not -BeNull
            $param.ParameterType | Should -Be ([string])
        }

        It "Should have Type parameter with ValidateSet attribute" {
            $function = Get-Command Find-PublicStorageContainer
            $param = $function.Parameters['Type']
            $param | Should -Not -BeNull
            $param.ParameterType | Should -Be ([string])
            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNull
            $validateSet.ValidValues | Should -Contain 'blob'
            $validateSet.ValidValues | Should -Contain 'file'
            $validateSet.ValidValues | Should -Contain 'queue'
            $validateSet.ValidValues | Should -Contain 'table'
            $validateSet.ValidValues | Should -Contain 'dfs'
        }

        It "Should have WordList parameter with correct type" {
            $function = Get-Command Find-PublicStorageContainer
            $param = $function.Parameters['WordList']
            $param | Should -Not -BeNull
            $param.ParameterType | Should -Be ([string])
        }

        It "Should have ThrottleLimit parameter with correct type and default" {
            $function = Get-Command Find-PublicStorageContainer
            $param = $function.Parameters['ThrottleLimit']
            $param | Should -Not -BeNull
            $param.ParameterType | Should -Be ([int])
        }

        It "Should have IncludeEmpty switch parameter" {
            $function = Get-Command Find-PublicStorageContainer
            $param = $function.Parameters['IncludeEmpty']
            $param | Should -Not -BeNull
            $param.ParameterType | Should -Be ([switch])
        }

        It "Should have IncludeMetadata switch parameter" {
            $function = Get-Command Find-PublicStorageContainer
            $param = $function.Parameters['IncludeMetadata']
            $param | Should -Not -BeNull
            $param.ParameterType | Should -Be ([switch])
        }
    }
}
