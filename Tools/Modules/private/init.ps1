function init {
    [CmdletBinding()]

    $logo = `
@"


     __ ) ___  |  |  |          |      ___|    __ \   |
     __ \     /   |  |     __|  |  /  |       / _` |  __|
     |   |   /   ___ __|  (       <   |      | (   |  |
    ____/  _/       _|   \___| _|\_\ \____| \ \__,_| \__|
                                             \____/

        Author : Rogier Dijkman (Azurekid) v0.1.0
"@

    Write-Host $logo -ForegroundColor "Blue"
}