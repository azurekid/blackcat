function Read-SASToken {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [Alias('SasUri', 'SasToken', 'Uri', 'Token', 'Url')]
        [string]$InputString
    )

    process {
        Add-Type -AssemblyName system.web

        $InputString = $InputString.TrimStart('?')

        # Auto-detect if input is a full URI or just a token
        if ($InputString -match '^https?://') {
            $storageUri = $InputString -split "\?"
            $baseUri = $storageUri[0]
            $tokenArray = $storageUri[1] -split '&'
            Write-Verbose "Detected full URI input"
        }
        elseif ($InputString -match 'sv=') {
            $tokenArray = $InputString -split '&'
            $baseUri = $null
            Write-Verbose "Detected SAS token input"
        }
        else {
            Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message "Invalid input: expected a SAS URI or SAS token containing 'sv=' parameter" -Severity 'Error'
            break
        }

        if ($tokenArray.count -lt 1) {
            Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message "No valid SAS token parameters found" -Severity 'Error'
            break
        }

        $resourceTypeMap = @{
            's' = 'Service-level APIs'
            'c' = 'Container-level APIs'
            'o' = 'Object-level APIs'
        }
        $storageResourceMap = @{
            'b'  = 'Blob'
            'bv' = 'Blob version'
            'bs' = 'Blob snapshot'
            'c'  = 'Container'
            'd'  = 'Directory'
        }
        $serviceMap = @{
            'b' = 'Blob'
            'q' = 'Queue'
            't' = 'Table'
            'f' = 'File'
        }
        $permissionMap = @{
            'r' = 'Read'
            'a' = 'Add'
            'c' = 'Create'
            'w' = 'Write'
            'd' = 'Delete'
            'x' = 'Delete Version'
            'y' = 'Permanent Delete'
            'l' = 'List'
            't' = 'Tags'
            'f' = 'Find'
            'm' = 'Move'
            'e' = 'Execute'
            'o' = 'Ownership'
            'P' = 'Permissions'
            'i' = 'Set Immutability Policy'
        }

        $tokenObjects = [ordered]@{}
        if ($baseUri) {
            $tokenObjects.'Storage Uri' = $baseUri
        }

        Write-Verbose "Processing SAS token properties"
        $tokenArray | ForEach-Object {
            if ($_ -like "spr=*") { $tokenObjects.Protocol = $_.substring(4) }
            if ($_ -like "st=*")  { $tokenObjects."Start Time" = $_.substring(3) }
            if ($_ -like "se=*")  { $tokenObjects."Expiry Time" = $_.substring(3) }
            if ($_ -like "sv=*")  { $tokenObjects."Service Version" = $_.substring(3) }
            if ($_ -like "sp=*")  { $tokenObjects."Permissions" = $_.substring(3) }
            if ($_ -like "sip=*") { $tokenObjects."IP Address" = $_.substring(4) }

            if ($_ -like "sig=*") {
                $tokenObjects."Signature" = $_.substring(4)
                $tokenObjects."Base64 Signature" = [System.Web.HttpUtility]::UrlDecode($tokenObjects."Signature")
            }

            if ($_ -like "srt=*") {
                $tokenObjects."Resource Types" = $_.substring(4)
                $tokenObjects."Token Type" = 'Account-level SAS'
                $tokenObjects."Resource Types" = [string[]]($tokenObjects."Resource Types".ToCharArray() | ForEach-Object { $resourceTypeMap[$_.ToString()] })
            }

            if ($_ -like "sr=*") {
                $tokenObjects."Storage Resource" = $_.substring(3)
                $tokenObjects."Token Type" = 'user-level SAS'
                $tokenObjects."Storage Resource" = [string[]]($tokenObjects."Storage Resource".ToCharArray() | ForEach-Object { $storageResourceMap[$_.ToString()] })
            }

            if ($_ -like "ss=*") {
                $tokenObjects."Services" = $_.substring(3)
                Write-Verbose "Processing service types: $($tokenObjects.Services)"
                $tokenObjects."Services" = [string[]]($tokenObjects."Services".ToCharArray() | ForEach-Object { $serviceMap[$_.ToString()] })
            }

            if ($_ -like "sp=*") {
                Write-Verbose "Processing permission flags: $($tokenObjects.Permissions)"
                $tokenObjects."Permissions" = [string[]]($tokenObjects.Permissions.ToCharArray() | ForEach-Object { $permissionMap[$_.ToString()] })
            }
        }
        return $tokenObjects | ConvertTo-Json | ConvertFrom-Json
    }
<#
    .SYNOPSIS
        Reads and processes a Shared Access Signature (SAS) token or URI.

    .DESCRIPTION
        Parses SAS URI or token to extract properties including permissions and signature.

    .PARAMETER InputString
        The SAS URI or SAS token string to parse. The function automatically detects the input type:
        - If the input starts with 'http://' or 'https://', it's treated as a full URI
        - Otherwise, it's treated as a SAS token string
        Aliases: SasUri, SasToken, Uri, Token, Url

    .EXAMPLE
        Read-SASToken "https://example.blob.core.windows.net/container?sv=2019-12-12&ss=b&srt=s&sp=rwdlac&se=2022-01-01T00:00:00Z&st=2021-01-01T00:00:00Z&spr=https&sig=xxxx"

        This example reads the information from a full SAS URI. The storage URI will be extracted and displayed.

    .EXAMPLE
        Read-SASToken "sv=2019-12-12&ss=b&srt=s&sp=rwdlac&se=2022-01-01T00:00:00Z&st=2021-01-01T00:00:00Z&spr=https&sig=xxxx"

        This example reads the information from just a SAS token string.

    .EXAMPLE
        Read-SASToken "?sv=2019-12-12&ss=b&srt=sco&sp=rl&se=2028-01-21T22:14:47Z&st=2026-01-21T13:59:47Z&spr=https&sig=xxxx"

        This example shows that leading '?' characters are automatically trimmed.

    .EXAMPLE
        $url | Read-SASToken

        This example shows pipeline input support.

    .NOTES
    Author: Rogier Dijkman (https://securehats.gitbook.io/BlackCat)

.LINK
    MITRE ATT&CK Tactic: TA0006 - Credential Access
    https://attack.mitre.org/tactics/TA0006/

.LINK
    MITRE ATT&CK Technique: T1552.005 - Unsecured Credentials: Cloud Instance Metadata API
    https://attack.mitre.org/techniques/T1552/005/
#>
}