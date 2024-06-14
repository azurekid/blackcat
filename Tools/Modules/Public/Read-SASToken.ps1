<#
.SYNOPSIS
    Reads and processes the information from a Shared Access Signature (SAS) token.

.DESCRIPTION
    The Read-SASToken function reads and processes the information from a Shared Access Signature (SAS) token. It extracts various properties from the SAS token, such as the storage URI, protocol, start time, expiry time, service version, permissions, IP address, signature, base64 signature, resource types, storage resource, and services.

.PARAMETER SasUri
    The SAS URI from which to extract the token information. This parameter is optional.

.PARAMETER SasToken
    The SAS token from which to extract the token information. This parameter is optional.

.EXAMPLE
    $sasUri = "https://example.blob.core.windows.net/container?sv=2019-12-12&ss=b&srt=s&sp=rwdlac&se=2022-01-01T00:00:00Z&st=2021-01-01T00:00:00Z&spr=https&sig=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    $tokenInfo = Read-SASToken -SasUri $sasUri

    $tokenInfo

    This example reads the information from a SAS token specified by the SasUri parameter and stores it in the $tokenInfo variable. The extracted token information is then displayed.

.EXAMPLE
    $sasToken = "sv=2019-12-12&ss=b&srt=s&sp=rwdlac&se=2022-01-01T00:00:00Z&st=2021-01-01T00:00:00Z&spr=https&sig=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    $tokenInfo = Read-SASToken -SasToken $sasToken

    $tokenInfo

    This example reads the information from a SAS token specified by the SasToken parameter and stores it in the $tokenInfo variable. The extracted token information is then displayed.

.NOTES
  Author: Rogier Dijkman (https://securehats.gitbook.io/BlackCat)
#>

function Read-SASToken {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$SasUri,

        [Parameter(Mandatory = $false)]
        [string]$SasToken
    )

    process {
        #region common

        Write-Host $logo -ForegroundColor "Blue"
        Write-Host "[+] Start collection SAS Token information"
        #Variables
        Add-Type -AssemblyName system.web


        if (![string]::IsNullOrWhiteSpace($SasUri)) {
            $storageUri     = $SasUri -split "\?"
            $tokenArray     = $storageUri[1] -split '&'
        } elseif (!([string]::IsNullOrWhiteSpace($SasToken))) {
            $tokenArray = $SasToken -split '&'
            if ($tokenArray.count -lt 1) {
                Write-Host "[-] Error: No valid SAS token provided" -ForegroundColor Red
                break
            }
        } else {
            Write-Host "[-] Error: No valid parameters provided" -ForegroundColor Red
            break
        }

        $permissionList = New-Object System.Collections.ArrayList
        $resourceList   = New-Object System.Collections.ArrayList
        $resourceTypes  = New-Object System.Collections.ArrayList
        $services       = New-Object System.Collections.ArrayList

        $tokenObjects = [ordered]@{
            'Storage Uri' = "$($storageUri)"
        }

        Write-Verbose '[+] Processing token properties'
        $tokenArray | ForEach-Object {
            if ($_ -like "spr=*") { $tokenObjects.Protocol           = ($_).substring(4) }
            if ($_ -like "st=*")  { $tokenObjects."Start Time"       = ($_).substring(3) }
            if ($_ -like "se=*")  { $tokenObjects."Expiry Time"      = ($_).substring(3) }
            if ($_ -like "sv=*")  { $tokenObjects."Service Version"  = ($_).substring(3) }
            if ($_ -like "sp=*")  { $tokenObjects."Permissions"      = ($_).substring(3) }
            if ($_ -like "sip=*") { $tokenObjects."IP Address"       = ($_).substring(4) }

            if ($_ -like "sig=*") {
                $tokenObjects."Signature"        = ($_).substring(4)
                $tokenObjects."Base64 Signature" = [System.Web.HttpUtility]::UrlDecode($tokenObjects."Signature")
            }

            if ($_ -like "srt=*") {
                $tokenObjects."Resource Types" = ($_).substring(4)
                $tokenObjects."Token Type"     = 'Account-level SAS'

                $tokenObjects."Resource Types".ToCharArray() | ForEach-Object {
                    if ($_ -eq 's')  { $resourceTypes += ('Service-level APIs') }
                    if ($_ -eq 'c')  { $resourceTypes += ('Container-level APIs') }
                    if ($_ -eq 'o')  { $resourceTypes += ('Object-level APIs') }
                }

                $tokenObjects."Resource Types" = $resourceTypes

            }

            if ($_ -like "sr=*") {
                $tokenObjects."Storage Resource" = ($_).substring(3)
                $tokenObjects."Token Type"       = 'user-level SAS'

                $tokenObjects."Storage Resource".ToCharArray() | ForEach-Object {
                    if ($_ -eq 'b')  { $resourceList += ('Blob') }
                    if ($_ -eq 'bv') { $resourceList += ('Blob version') }
                    if ($_ -eq 'bs') { $resourceList += ('Blob snapshot') }
                    if ($_ -eq 'c')  { $resourceList += ('Container') }
                    if ($_ -eq 'd')  { $resourceList += ('Directory') }
                }

                $tokenObjects."Storage Resource" = $resourceList
            }

            if ($_ -like "ss=*") {
                    $tokenObjects."Services" = ($_).substring(3)
                    Write-Verbose "[+] Processing Services"

                    $tokenObjects."Services".ToCharArray() | ForEach-Object {
                        if ($_ -eq 'b')  { $services += ('Blob') }
                        if ($_ -eq 'q')  { $services += ('Queue') }
                        if ($_ -eq 't')  { $services += ('Table') }
                        if ($_ -eq 'f')  { $services += ('File') }
                    }

                    $tokenObjects."Services" = $services
                }
        }

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

        $tokenObjects.Permissions = $permissionList

        return $tokenObjects | ConvertTo-Json | ConvertFrom-Json
    }
}