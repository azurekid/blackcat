function ConvertTo-Base64Url {
    param ([byte[]]$Bytes)
    [System.Convert]::ToBase64String($Bytes).
        TrimEnd('=').
        Replace('+', '-').
        Replace('/', '_')
}
