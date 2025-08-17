#!/bin/bash
# Cross-platform setup script for Linux and macOS

# Get the directory of the currently executing script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Execute the PowerShell manager script
pwsh "$SCRIPT_DIR/bin/manager.ps1"
