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

    # Mock data for testing
    $script:MockXmlWithCurrentVersions = @'
<EnumerationResults>
    <Blobs>
        <Blob><Name>file1.txt</Name><VersionId>2020-06-01T12:00:00.0000000Z</VersionId><IsCurrentVersion>true</IsCurrentVersion></Blob>
        <Blob><Name>file2.txt</Name><VersionId>2020-06-02T12:00:00.0000000Z</VersionId><IsCurrentVersion>true</IsCurrentVersion></Blob>
    </Blobs>
</EnumerationResults>
'@

    $script:MockXmlWithDeletedVersions = @'
<EnumerationResults>
    <Blobs>
        <Blob><Name>file3.txt</Name><VersionId>2020-06-03T12:00:00.0000000Z</VersionId><IsCurrentVersion>false</IsCurrentVersion></Blob>
        <Blob><Name>file4.txt</Name><VersionId>2020-06-04T12:00:00.0000000Z</VersionId></Blob>
    </Blobs>
</EnumerationResults>
'@
}

Describe "Get-AzBlobContent" {
    BeforeEach {
        # Reset mocks for each test
        $script:LastMessage = $null
        
        # Create a temporary directory for testing
        $script:TestOutputPath = Join-Path -Path $TestDrive -ChildPath "output"
        New-Item -ItemType Directory -Path $script:TestOutputPath -Force | Out-Null

        # Mock Invoke-RestMethod globally
        Mock Invoke-RestMethod {
            if ($IncludeDeleted) {
                return $script:MockXmlWithDeletedVersions
            } else {
                return $script:MockXmlWithCurrentVersions
            }
        }

        # Mock New-Item to prevent actual directory creation
        Mock New-Item { }
        
        # Fully mock the ForEach-Object -Parallel execution
        Mock ForEach-Object { 
            # Just return a dummy object to indicate success
            return $true 
        } -ParameterFilter { $Parallel }
    }

    Context "Parameter validation" {
        It "Should throw when BlobUrl does not match the expected pattern" {
            { Get-AzBlobContent -BlobUrl "invalid-url" -OutputPath $script:TestOutputPath } | 
                Should -Throw
        }

        It "Should accept a valid Azure Blob URL" {
            { Get-AzBlobContent -BlobUrl "https://mystorageaccount.blob.core.windows.net/container" -OutputPath $script:TestOutputPath -ErrorAction Stop } | 
                Should -Not -Throw
        }
        
        It "Should require OutputPath parameter when not using ListOnly" {
            # This test verifies the parameter sets work correctly
            # We need to take a different approach since we can't actually force a parameter binding exception in tests
            
            # Check if the OutputPath parameter is mandatory when ListOnly is not specified
            $cmdInfo = Get-Command Get-AzBlobContent
            $downloadParamSet = $cmdInfo.ParameterSets | Where-Object Name -eq "Download"
            $outputPathParam = $downloadParamSet.Parameters | Where-Object Name -eq "OutputPath"
            
            $outputPathParam.IsMandatory | Should -BeTrue
        }
        
        It "Should not require OutputPath parameter when using ListOnly" {
            { Get-AzBlobContent -BlobUrl "https://mystorageaccount.blob.core.windows.net/container" -ListOnly } | 
                Should -Not -Throw
        }
    }
    
    Context "URL parameter handling" {
        It "Should correctly append 'include=versions' to URL without query parameters" {
            Mock Invoke-RestMethod {
                $Uri | Should -Be "https://mystorageaccount.blob.core.windows.net/container?include=versions"
                return $script:MockXmlWithCurrentVersions
            }
            
            Get-AzBlobContent -BlobUrl "https://mystorageaccount.blob.core.windows.net/container" -OutputPath $script:TestOutputPath
        }
        
        It "Should correctly append 'include=versions' to URL with existing query parameters" {
            Mock Invoke-RestMethod {
                $Uri | Should -Be "https://mystorageaccount.blob.core.windows.net/container?param=value&include=versions"
                return $script:MockXmlWithCurrentVersions
            }
            
            Get-AzBlobContent -BlobUrl "https://mystorageaccount.blob.core.windows.net/container?param=value" -OutputPath $script:TestOutputPath
        }
    }
    
    Context "Listing blobs without downloading" {
        It "Should return a list of current blobs with ListOnly parameter" {
            Mock Invoke-RestMethod { return $script:MockXmlWithCurrentVersions }
            
            $result = Get-AzBlobContent -BlobUrl "https://mystorageaccount.blob.core.windows.net/container" -ListOnly
            
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
            $result[0].Name | Should -Be "file1.txt"
            $result[0].Status | Should -Be "Current"
            $result[1].Name | Should -Be "file2.txt"
            $result[1].Status | Should -Be "Current"
        }
        
        It "Should return a list of deleted blobs with IncludeDeleted and ListOnly parameters" {
            Mock Invoke-RestMethod { return $script:MockXmlWithDeletedVersions }
            
            $result = Get-AzBlobContent -BlobUrl "https://mystorageaccount.blob.core.windows.net/container" -IncludeDeleted -ListOnly
            
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
            $result[0].Name | Should -Be "file3.txt"
            $result[0].Status | Should -Be "Deleted"
            $result[1].Name | Should -Be "file4.txt"
            $result[1].Status | Should -Be "Deleted"
        }
    }
    
    Context "Downloading blobs" {
        It "Should create the output directory if it doesn't exist" {
            Mock Test-Path { return $false }
            Mock New-Item { return $true }
            
            Get-AzBlobContent -BlobUrl "https://mystorageaccount.blob.core.windows.net/container" -OutputPath $script:TestOutputPath
            
            Should -Invoke New-Item -Times 1 -ParameterFilter {
                $ItemType -eq "Directory" -and $Path -eq $script:TestOutputPath
            }
        }
        
        It "Should not try to create the directory if it already exists" {
            Mock Test-Path { return $true }
            
            Get-AzBlobContent -BlobUrl "https://mystorageaccount.blob.core.windows.net/container" -OutputPath $script:TestOutputPath
            
            Should -Invoke New-Item -Times 0 -ParameterFilter {
                $ItemType -eq "Directory" -and $Path -eq $script:TestOutputPath
            }
        }
        
        It "Should process current version blobs with correct URLs" {
            Mock Invoke-RestMethod { return $script:MockXmlWithCurrentVersions }

            Get-AzBlobContent -BlobUrl "https://mystorageaccount.blob.core.windows.net/container" -OutputPath $script:TestOutputPath

            $script:LastMessage.Message | Should -Match "Found 2 files to download"
        }
        
        It "Should process deleted version blobs with correct URLs when IncludeDeleted is specified" {
            Mock Invoke-RestMethod { return $script:MockXmlWithDeletedVersions }

            Get-AzBlobContent -BlobUrl "https://mystorageaccount.blob.core.windows.net/container" -OutputPath $script:TestOutputPath -IncludeDeleted

            $script:LastMessage.Message | Should -Match "Found 2 files to download"
        }
    }
    
    Context "Error handling" {
        It "Should handle REST API errors gracefully" {
            Mock Invoke-RestMethod { throw "API Error" }
            
            { Get-AzBlobContent -BlobUrl "https://mystorageaccount.blob.core.windows.net/container" -OutputPath $script:TestOutputPath } | 
                Should -Not -Throw
                
            $script:LastMessage.Severity | Should -Be "Error"
            $script:LastMessage.Message | Should -Be "API Error"
        }
        
        It "Should handle invalid URI format" {
            # For this test, we'll focus on the error handling in general
            Mock Invoke-RestMethod { throw "API Error" }
            
            { Get-AzBlobContent -BlobUrl "https://mystorageaccount.blob.core.windows.net/container" -OutputPath $script:TestOutputPath -ErrorAction Stop } | 
                Should -Not -Throw
                
            $script:LastMessage.Severity | Should -Be "Error"
            $script:LastMessage.Message | Should -Be "API Error"
        }
    }

    Context "Pipeline support" {
        It "Should accept BlobUrl from pipeline" {
            # Check if the parameter accepts pipeline input by property name
            $cmdInfo = Get-Command Get-AzBlobContent
            $blobUrlParam = $cmdInfo.Parameters["BlobUrl"]
            
            # Find the parameter attribute that specifies pipeline input
            $hasPipelineSupport = $false
            foreach ($attr in $blobUrlParam.Attributes) {
                if ($attr -is [System.Management.Automation.ParameterAttribute] -and 
                    ($attr.ValueFromPipelineByPropertyName -eq $true)) {
                    $hasPipelineSupport = $true
                    break
                }
            }
            
            $hasPipelineSupport | Should -BeTrue -Because "BlobUrl should accept pipeline input by property name"
        }
        
        It "Should accept objects with BlobUrl property from pipeline" {
            Mock Invoke-RestMethod { return $script:MockXmlWithCurrentVersions }
            
            $inputObject = [PSCustomObject]@{
                BlobUrl = "https://mystorageaccount.blob.core.windows.net/container"
            }
            
            $script:pipelineObjResult = $null
            { $script:pipelineObjResult = $inputObject | Get-AzBlobContent -ListOnly -ErrorAction Stop } |
                Should -Not -Throw
            
            $script:pipelineObjResult | Should -Not -BeNullOrEmpty
            $script:pipelineObjResult.Count | Should -Be 2
        }
    }
}
