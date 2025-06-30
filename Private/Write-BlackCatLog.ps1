function Write-BlackCatLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter(Mandatory = $false, Position = 1)]
        [ValidateSet("TRACE", "DEBUG", "INFO", "WARN", "WARNING", "ERROR", "FATAL")]
        [string]$Level = "INFO",

        [Parameter(Mandatory = $false)]
        [string]$FunctionName,

        [Parameter(Mandatory = $false)]
        [string]$LogPath,

        [Parameter(Mandatory = $false)]
        [switch]$WriteHost,

        [Parameter(Mandatory = $false)]
        [switch]$NoTimestamp,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Black", "Blue", "Cyan", "DarkBlue", "DarkCyan", "DarkGray", "DarkGreen",
            "DarkMagenta", "DarkRed", "DarkYellow", "Gray", "Green", "Magenta", "Red", "White", "Yellow")]
        [string]$Color
    )

    begin {
        # Normalize log level (WARNING is an alias for WARN)
        if ($Level -eq "WARNING") {
            $Level = "WARN"
        }

        # Auto-detect calling function if not provided
        if (-not $FunctionName) {
            try {
                $CallStack = Get-PSCallStack
                if ($CallStack.Count -gt 1) {
                    $FunctionName = $CallStack[1].FunctionName
                    # Clean up function name (remove module prefixes, etc.)
                    if ($FunctionName -eq '<ScriptBlock>') {
                        $FunctionName = $CallStack[1].ScriptName | Split-Path -Leaf
                    }
                }
                else {
                    $FunctionName = "Unknown"
                }
            }
            catch {
                $FunctionName = "Unknown"
            }
        }

        # Use default log path from session variables if available and not specified
        if (-not $LogPath -and $script:SessionVariables -and $script:SessionVariables.ContainsKey('defaultLogPath')) {
            $LogPath = $script:SessionVariables.defaultLogPath
        }

        # Default colors for different log levels
        if (-not $Color) {
            $ColorMap = @{
                "TRACE" = "Gray"
                "DEBUG" = "Cyan"
                "INFO"  = "Green"
                "WARN"  = "Yellow"
                "ERROR" = "Red"
                "FATAL" = "Magenta"
            }
            $Color = $ColorMap[$Level]
        }
    }
    
    process {
        # Build log entry components
        $Components = @()

        # Add timestamp unless suppressed
        if (-not $NoTimestamp) {
            $Components += "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')]"
        }

        # Add log level
        $Components += "[$Level]"

        # Add function context
        if ($FunctionName -and $FunctionName -ne "Unknown") {
            $Components += "[$FunctionName]"
        }

        # Add the message
        $Components += $Message

        # Combine all components
        $LogEntry = $Components -join " "

        # Output to console based on log level and WriteHost switch
        if ($WriteHost -or $Level -in @("ERROR", "FATAL")) {
            # Use Write-Host for user-facing messages or errors
            Write-Host $LogEntry -ForegroundColor $Color
        }
        elseif ($Level -eq "WARN") {
            # Use Write-Warning for warnings
            Write-Warning $LogEntry
        }
        elseif ($Level -in @("TRACE", "DEBUG")) {
            # Use Write-Debug for debug messages (only shown with -Debug)
            Write-Debug $LogEntry
        }
        else {
            # Use Write-Verbose for INFO and other levels
            Write-Verbose $LogEntry
        }

        # Write to log file if path is provided
        if ($LogPath) {
            try {
                # Ensure directory exists
                $LogDir = Split-Path -Path $LogPath -Parent
                if ($LogDir -and -not (Test-Path -Path $LogDir)) {
                    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
                }

                # Append to log file
                Add-Content -Path $LogPath -Value $LogEntry -Encoding UTF8 -ErrorAction SilentlyContinue
            }
            catch {
                # Silently continue if file write fails to avoid disrupting the main operation
                # Could optionally write to Windows Event Log or other fallback here
            }
        }
    }
    <#
.SYNOPSIS
    Generic logging function for the BlackCat PowerShell module.

.DESCRIPTION
    The Write-BlackCatLog function provides standardized logging capabilities across the entire BlackCat module.
    It supports multiple log levels, optional file output, function context tracking, and can be used by any
    BlackCat function for consistent logging behavior. The function handles errors gracefully and provides
    both console output and file logging capabilities.

.PARAMETER Message
    The message to log. This parameter is mandatory and supports multi-line strings.

.PARAMETER Level
    The log level for the message. Valid values are: TRACE, DEBUG, INFO, WARN, WARNING, ERROR, FATAL.
    Default is "INFO". WARNING is treated as an alias for WARN.

.PARAMETER FunctionName
    The name of the calling function for context tracking. If not provided, it will attempt to
    automatically detect the calling function name.

.PARAMETER LogPath
    Optional path to a log file where the message should be written in addition to console output.
    If not provided, uses the module's default log path if configured.

.PARAMETER WriteHost
    Switch to write INFO and WARN messages to the host using Write-Host instead of Write-Verbose.
    Useful for user-facing messages that should always be visible.

.PARAMETER NoTimestamp
    Switch to exclude timestamps from log entries. Useful for formatted output or when timestamps
    are not needed.

.PARAMETER Color
    Console color for Write-Host output. Valid PowerShell colors. Defaults are:
    - TRACE: Gray
    - DEBUG: Cyan
    - INFO: Green
    - WARN: Yellow
    - ERROR: Red
    - FATAL: Magenta

.EXAMPLE
    Write-BlackCatLog "Starting Azure resource enumeration"

    Logs an informational message with auto-detected function context.

.EXAMPLE
    Write-BlackCatLog "Authentication failed" "ERROR" -FunctionName "Connect-AzureAccount"

    Logs an error message with explicit function context.

.EXAMPLE
    Write-BlackCatLog "Processing 100 storage accounts" "INFO" -WriteHost

    Logs an informational message that will be visible to the user via Write-Host.

.EXAMPLE
    Write-BlackCatLog "Detailed debugging information" "DEBUG" -LogPath ".\debug.log"

    Logs a debug message to a specific log file.

.EXAMPLE
    Write-BlackCatLog "Critical system failure" "FATAL" -WriteHost -Color "Red"

    Logs a fatal error that will be displayed prominently to the user.

.NOTES
    This function is designed to be used throughout the BlackCat module by any function that needs logging.
    It provides consistent formatting, error handling, and supports both development debugging and user output.

    The function automatically detects the calling function name when not explicitly provided.
    File I/O errors are handled gracefully to avoid disrupting the main operation.

    Log levels follow standard logging conventions:
    - TRACE: Most detailed, for tracing program flow
    - DEBUG: Detailed information for debugging
    - INFO: General information about program execution
    - WARN: Warning messages for potentially harmful situations
    - ERROR: Error events that might allow the application to continue
    - FATAL: Critical errors that may cause termination
#>
}