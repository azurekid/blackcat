BeforeAll {
    # Import the function being tested - this is the direct approach
    . "$PSScriptRoot/../Public/Exfiltration/anonymous/Get-AzBlobContent.ps1"
    
    # Import dependencies
    . "$PSScriptRoot/../Private/Write-Message.ps1"
    
    # Mock functions
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
        # Simply capture the message for testing purposes
        $script:LastMessage = @{
            Message = $Message
            Severity = $Severity
            FunctionName = $FunctionName
        }
    }
}

Describe "Get-AzBlobContent Regex Patterns" {
    BeforeEach {
        # Reset mocks and variables for each test
        $script:LastMessage = $null
    }

    Context "Validate URL pattern" {
        It "Should accept valid Azure Blob Storage URLs" {
            $validUrls = @(
                'https://storage.blob.core.windows.net/container',
                'https://mystorageacct.blob.core.windows.net/my-container',
                'https://test123.blob.core.windows.net/container/path',
                'https://storageaccount.blob.core.windows.net/container?param=value'
            )

            foreach ($url in $validUrls) {
                $url -match '^https://[a-z0-9]+\.blob\.core\.windows\.net/[^?]+' | Should -BeTrue
            }
        }

        It "Should reject invalid Azure Blob Storage URLs" {
            $invalidUrls = @(
                'http://storage.blob.core.windows.net/container',  # Non-https
                'https://storage.files.core.windows.net/container', # Wrong service
                'https://storage.blob.core.windows.net',  # Missing container
                'ftp://storage.blob.core.windows.net/container',   # Wrong protocol
                'https://UPPERCASE.blob.core.windows.net/container', # Uppercase not allowed
                'https://storage_account.blob.core.windows.net/container' # Underscore not allowed
            )

            foreach ($url in $invalidUrls) {
                # Test that the validation attribute would reject these URLs
                $validationAttribute = [ValidatePattern]('^https://[a-z0-9]+\.blob\.core\.windows\.net/[^?]+')
                try {
                    $validationAttribute.ValidateArgumentValue($url)
                    # If we get here, the validation passed, which is wrong
                    $false | Should -BeTrue -Because "URL should be rejected: $url"
                } catch {
                    # This is the expected path - validation should fail
                    $true | Should -BeTrue
                }
            }
        }
    }

    Context "URL parsing regex" {
        It "Should correctly extract service endpoint and container name from URL" {
            $testUrls = @(
                @{
                    Url = 'https://mystorageacct.blob.core.windows.net/container'
                    ExpectedServiceEndpoint = 'https://mystorageacct.blob.core.windows.net/'
                    ExpectedContainer = 'container'
                },
                @{
                    Url = 'https://storage123.blob.core.windows.net/my-container'
                    ExpectedServiceEndpoint = 'https://storage123.blob.core.windows.net/'
                    ExpectedContainer = 'my-container'
                },
                @{
                    Url = 'https://storageacct.blob.core.windows.net/container/path'
                    ExpectedServiceEndpoint = 'https://storageacct.blob.core.windows.net/'
                    ExpectedContainer = 'container'
                },
                @{
                    Url = 'https://store.blob.core.windows.net/container?param=value'
                    ExpectedServiceEndpoint = 'https://store.blob.core.windows.net/'
                    ExpectedContainer = 'container'
                }
            )

            foreach ($test in $testUrls) {
                if ($test.Url -match '^(https?://[^/]+)/([^/?]+)') {
                    $serviceEndpoint = $matches[1] + "/"
                    $containerName = $matches[2]
                    
                    $serviceEndpoint | Should -Be $test.ExpectedServiceEndpoint
                    $containerName | Should -Be $test.ExpectedContainer
                } else {
                    # This should fail the test if the regex doesn't match
                    $false | Should -BeTrue -Because "URL pattern should match: $($test.Url)"
                }
            }
        }
    }

    Context "XML parsing regex" {
        BeforeEach {
            # Sample XML responses (matching the exact format in the function)
            $script:sampleXml = @'
<EnumerationResults>
    <Blobs>
        <Blob><Name>file1.txt</Name><VersionId>2020-06-01T12:00:00.0000000Z</VersionId><IsCurrentVersion>true</IsCurrentVersion></Blob>
        <Blob><Name>file2.txt</Name><VersionId>2020-06-02T12:00:00.0000000Z</VersionId><IsCurrentVersion>false</IsCurrentVersion></Blob>
        <Blob><Name>file3.txt</Name><VersionId>2020-06-03T12:00:00.0000000Z</VersionId></Blob>
        <Blob><Name>nested/file4.txt</Name><VersionId>2020-06-04T12:00:00.0000000Z</VersionId><IsCurrentVersion>true</IsCurrentVersion></Blob>
    </Blobs>
</EnumerationResults>
'@

            # Sample XML for testing the enhanced regex pattern
            $script:alternateFormatXml = @'
<EnumerationResults>
    <Blobs>
        <Blob><n>file1.txt</n><VersionId>2020-06-01T12:00:00.0000000Z</VersionId><IsCurrentVersion>true</IsCurrentVersion></Blob>
        <Blob><n>file2.txt</n><VersionId>2020-06-02T12:00:00.0000000Z</VersionId><IsCurrentVersion>false</IsCurrentVersion></Blob>
    </Blobs>
</EnumerationResults>
'@
        }

        It "Should match current version blobs correctly" {
            # Define the regex pattern as in the original function
            $isCurrentVersion = '<Blob><Name>([^<]+)</Name><VersionId>([^<]+)</VersionId><IsCurrentVersion>([^<]+)</IsCurrentVersion>'
            
            $currentVersionMatches = [regex]::Matches($script:sampleXml, $isCurrentVersion)
            
            $currentVersionMatches.Count | Should -Be 3  # There are 3 matching items
            $currentVersionMatches[0].Groups[1].Value | Should -Be "file1.txt"
            $currentVersionMatches[0].Groups[3].Value | Should -Be "true"
            
            $currentVersionMatches[1].Groups[1].Value | Should -Be "file2.txt"
            $currentVersionMatches[1].Groups[3].Value | Should -Be "false"

            # The 3rd matched item is "nested/file4.txt"
            $currentVersionMatches[2].Groups[1].Value | Should -Be "nested/file4.txt"
            $currentVersionMatches[2].Groups[3].Value | Should -Be "true"
        }
        
        It "Should match non-current version blobs correctly" {
            # Define the regex pattern exactly as in the function
            $isNotCurrentVersion = '<Blob><Name>([^<]+)</Name><VersionId>([^<]+)</VersionId>(?!<IsCurrentVersion>true</IsCurrentVersion>)'
            
            $nonCurrentVersionMatches = [regex]::Matches($script:sampleXml, $isNotCurrentVersion)
            
            $nonCurrentVersionMatches.Count | Should -Be 2
            $nonCurrentVersionMatches[0].Groups[1].Value | Should -Be "file2.txt"
            $nonCurrentVersionMatches[1].Groups[1].Value | Should -Be "file3.txt"
        }
        
        It "Should handle nested file paths correctly" {
            $isCurrentVersion = '<Blob>(?:.*?)<(?:Name|n)>([^<]+)</(?:Name|n)>(?:.*?)<VersionId>([^<]+)</VersionId>(?:.*?)<IsCurrentVersion>([^<]+)</IsCurrentVersion>'
            
            $currentVersionMatches = [regex]::Matches($script:sampleXml, $isCurrentVersion)
            
            # Check that the nested path is matched correctly
            $hasNestedPath = $false
            foreach ($match in $currentVersionMatches) {
                if ($match.Groups[1].Value -eq "nested/file4.txt") {
                    $hasNestedPath = $true
                    break
                }
            }
            
            $hasNestedPath | Should -BeTrue
        }
        
        It "Should handle alternate XML format with <n> tags instead of <Name>" {
            # Using a more flexible regex pattern for the alternate format
            $isCurrentVersion = '<Blob>(?:.*?)<(?:Name|n)>([^<]+)</(?:Name|n)>(?:.*?)<VersionId>([^<]+)</VersionId>(?:.*?)<IsCurrentVersion>([^<]+)</IsCurrentVersion>'
            
            $currentVersionMatches = [regex]::Matches($script:alternateFormatXml, $isCurrentVersion)
            
            $currentVersionMatches.Count | Should -Be 2
            $currentVersionMatches[0].Groups[1].Value | Should -Be "file1.txt"
            $currentVersionMatches[0].Groups[3].Value | Should -Be "true"
        }
    }
}
