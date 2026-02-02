function Read-SASToken {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [Alias('SasUri', 'SasToken', 'Uri', 'Token', 'Url')]
        [string]$InputString
    )

    process {
        #region common

        Write-Output "[+] Start collection SAS Token information"

        #Variables
        Add-Type -AssemblyName system.web

        # Clean up input - remove leading ? if present
        $InputString = $InputString.TrimStart('?')

        # Auto-detect if input is a full URI or just a token
        if ($InputString -match '^https?://') {
            # Input is a full URI - extract the token portion
            $storageUri = $InputString -split "\?"
            $baseUri = $storageUri[0]
            $tokenArray = $storageUri[1] -split '&'
            Write-Verbose "[+] Detected full URI input"
        }
        elseif ($InputString -match 'sv=') {
            # Input is just a SAS token
            $tokenArray = $InputString -split '&'
            $baseUri = $null
            Write-Verbose "[+] Detected SAS token input"
        }
        else {
            Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message "Invalid input: expected a SAS URI or SAS token containing 'sv=' parameter" -Severity 'Error'
            break
        }

        if ($tokenArray.count -lt 1) {
            Write-Message -FunctionName $MyInvocation.MyCommand.Name -Message "No valid SAS token parameters found" -Severity 'Error'
            break
        }

        $permissionList = New-Object System.Collections.ArrayList
        $resourceList = New-Object System.Collections.ArrayList
        $resourceTypes = New-Object System.Collections.ArrayList
        $services = New-Object System.Collections.ArrayList

        $tokenObjects = [ordered]@{}
        
        # Only add Storage Uri if we detected a full URI
        if ($baseUri) {
            $tokenObjects.'Storage Uri' = $baseUri
        }

        Write-Verbose '[+] Processing token properties'
        $tokenArray | ForEach-Object {
            if ($_ -like "spr=*") { $tokenObjects.Protocol = ($_).substring(4) }
            if ($_ -like "st=*") { $tokenObjects."Start Time" = ($_).substring(3) }
            if ($_ -like "se=*") { $tokenObjects."Expiry Time" = ($_).substring(3) }
            if ($_ -like "sv=*") { $tokenObjects."Service Version" = ($_).substring(3) }
            if ($_ -like "sp=*") { $tokenObjects."Permissions" = ($_).substring(3) }
            if ($_ -like "sip=*") { $tokenObjects."IP Address" = ($_).substring(4) }

            if ($_ -like "sig=*") {
                $tokenObjects."Signature" = ($_).substring(4)
                $tokenObjects."Base64 Signature" = [System.Web.HttpUtility]::UrlDecode($tokenObjects."Signature")
            }

            if ($_ -like "srt=*") {
                $tokenObjects."Resource Types" = ($_).substring(4)
                $tokenObjects."Token Type" = 'Account-level SAS'

                $tokenObjects."Resource Types".ToCharArray() | ForEach-Object {
                    if ($_ -eq 's') { $resourceTypes += ('Service-level APIs') }
                    if ($_ -eq 'c') { $resourceTypes += ('Container-level APIs') }
                    if ($_ -eq 'o') { $resourceTypes += ('Object-level APIs') }
                }

                $tokenObjects."Resource Types" = $resourceTypes

            }

            if ($_ -like "sr=*") {
                $tokenObjects."Storage Resource" = ($_).substring(3)
                $tokenObjects."Token Type" = 'user-level SAS'

                $tokenObjects."Storage Resource".ToCharArray() | ForEach-Object {
                    if ($_ -eq 'b') { $resourceList += ('Blob') }
                    if ($_ -eq 'bv') { $resourceList += ('Blob version') }
                    if ($_ -eq 'bs') { $resourceList += ('Blob snapshot') }
                    if ($_ -eq 'c') { $resourceList += ('Container') }
                    if ($_ -eq 'd') { $resourceList += ('Directory') }
                }

                $tokenObjects."Storage Resource" = $resourceList
            }

            if ($_ -like "ss=*") {
                $tokenObjects."Services" = ($_).substring(3)
                Write-Verbose "[+] Processing Services"

                $tokenObjects."Services".ToCharArray() | ForEach-Object {
                    if ($_ -eq 'b') { $services += ('Blob') }
                    if ($_ -eq 'q') { $services += ('Queue') }
                    if ($_ -eq 't') { $services += ('Table') }
                    if ($_ -eq 'f') { $services += ('File') }
                }

                $tokenObjects."Services" = $services
            }

            if ($_ -like "sp=*") {
                Write-Verbose "[+] Processing Permissions"
                $tokenObjects.Permissions.ToCharArray() | ForEach-Object {
                    if ($_ -eq 'r') { $permissionList += ('Read') }
                    if ($_ -eq 'a') { $permissionList += ('Add') }
                    if ($_ -eq 'c') { $permissionList += ('Create') }
                    if ($_ -eq 'w') { $permissionList += ('Write') }
                    if ($_ -eq 'd') { $permissionList += ('Delete') }
                    if ($_ -eq 'x') { $permissionList += ('Delete Version') }
                    if ($_ -eq 'y') { $permissionList += ('Permanent Delete') }
                    if ($_ -eq 'l') { $permissionList += ('List') }
                    if ($_ -eq 't') { $permissionList += ('Tags') }
                    if ($_ -eq 'f') { $permissionList += ('Find') }
                    if ($_ -eq 'm') { $permissionList += ('Move') }
                    if ($_ -eq 'e') { $permissionList += ('Execute') }
                    if ($_ -eq 'o') { $permissionList += ('Ownership') }
                    if ($_ -eq 'P') { $permissionList += ('Permissions') }
                    if ($_ -eq 'i') { $permissionList += ('Set Immutability Policy') }
                }

                $tokenObjects."Permissions" = $permissionList
            }
        }
        return $tokenObjects | ConvertTo-Json | ConvertFrom-Json
    }
<#
    .SYNOPSIS
        Reads and processes the information from a Shared Access Signature (SAS) token or URI.

    .DESCRIPTION
        The Read-SASToken function reads and processes the information from a Shared Access Signature (SAS) token.
        It automatically detects whether the input is a full SAS URI or just a SAS token string.
        It extracts various properties such as the storage URI, protocol, start time, expiry time, 
        service version, permissions, IP address, signature, resource types, storage resource, and services.

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