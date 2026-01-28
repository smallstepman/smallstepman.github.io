# WSL Installation Script
# Quick install (no parameters):
#   iex (iwr -useb https://smallstepman.github.io/wsl/install.ps1)
#
# With parameters, download first:
#   iwr -useb https://smallstepman.github.io/wsl/install.ps1 -OutFile install.ps1
#   .\install.ps1 -Help
#   .\install.ps1 -DryRun

[CmdletBinding()]
param(
    [switch]$Help,
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Show-Help {
    Write-ColorOutput "WSL Installation Script" "Cyan"
    Write-ColorOutput "========================" "Cyan"
    Write-ColorOutput ""
    Write-ColorOutput "Usage:" "Yellow"
    Write-ColorOutput "  iex (iwr -useb https://smallstepman.github.io/wsl/install.ps1)" "White"
    Write-ColorOutput ""
    Write-ColorOutput "Options:" "Yellow"
    Write-ColorOutput "  -Help    Show this help message" "White"
    Write-ColorOutput "  -DryRun  Show what would be done without making changes" "White"
    Write-ColorOutput ""
    Write-ColorOutput "This script will:" "Yellow"
    Write-ColorOutput "  1. Check if WSL is already installed" "White"
    Write-ColorOutput "  2. Enable required Windows features" "White"
    Write-ColorOutput "  3. Install WSL if not present" "White"
    Write-ColorOutput "  4. Set WSL 2 as default" "White"
    Write-ColorOutput ""
}

function Test-IsAdministrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-WSLInstalled {
    try {
        # First check if wsl command exists
        $wslCmd = Get-Command wsl -ErrorAction SilentlyContinue
        if (-not $wslCmd) {
            return $false
        }
        
        # Then check if it can run --version
        $null = wsl --version 2>&1
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function Install-WSL {
    Write-ColorOutput "`n=== WSL Installation ===" "Cyan"
    
    if (-not (Test-IsAdministrator)) {
        Write-ColorOutput "ERROR: This script must be run as Administrator!" "Red"
        Write-ColorOutput "Please right-click PowerShell and select 'Run as Administrator'" "Yellow"
        exit 1
    }

    if ($DryRun) {
        Write-ColorOutput "[DRY RUN] Would check if WSL is installed..." "Yellow"
    }
    else {
        Write-ColorOutput "Checking if WSL is already installed..." "White"
    }

    $wslInstalled = Test-WSLInstalled

    if ($wslInstalled) {
        Write-ColorOutput "WSL is already installed!" "Green"
        if ($DryRun) {
            Write-ColorOutput "[DRY RUN] Would display WSL version..." "Yellow"
        }
        else {
            Write-ColorOutput "`nWSL Version Information:" "Cyan"
            wsl --version
        }
        Write-ColorOutput "`nTo install a Linux distribution, run:" "Yellow"
        Write-ColorOutput "  wsl --install -d <DistributionName>" "White"
        Write-ColorOutput "`nAvailable distributions:" "Yellow"
        Write-ColorOutput "  wsl --list --online" "White"
        return
    }

    Write-ColorOutput "WSL is not installed. Installing now..." "Yellow"

    if ($DryRun) {
        Write-ColorOutput "[DRY RUN] Would run: wsl --install" "Yellow"
        Write-ColorOutput "[DRY RUN] This would enable required features and install WSL" "Yellow"
    }
    else {
        try {
            Write-ColorOutput "Running: wsl --install" "White"
            Write-ColorOutput "This will:" "Yellow"
            Write-ColorOutput "  - Enable Virtual Machine Platform" "White"
            Write-ColorOutput "  - Enable Windows Subsystem for Linux" "White"
            Write-ColorOutput "  - Download and install the WSL kernel" "White"
            Write-ColorOutput "  - Set WSL 2 as default" "White"
            Write-ColorOutput "  - Install Ubuntu (default distribution)" "White"
            Write-ColorOutput ""
            
            wsl --install
            
            if ($LASTEXITCODE -eq 0) {
                Write-ColorOutput "`n=== Installation Complete! ===" "Green"
                Write-ColorOutput "A system restart is required to complete the installation." "Yellow"
                Write-ColorOutput "After restart, you can launch your Linux distribution from the Start menu." "White"
                Write-ColorOutput ""
                Write-ColorOutput "Please restart your computer to complete the installation." "Yellow"
            }
            else {
                Write-ColorOutput "WSL installation failed with exit code: $LASTEXITCODE" "Red"
                Write-ColorOutput "Please check Windows Update and try again." "Yellow"
            }
        }
        catch {
            Write-ColorOutput "ERROR: Failed to install WSL" "Red"
            Write-ColorOutput $_.Exception.Message "Red"
            exit 1
        }
    }
}

# Main script execution
if ($Help) {
    Show-Help
    exit 0
}

Write-ColorOutput @"

╦ ╦╔═╗╦  
║║║╚═╗║  
╚╩╝╚═╝╩═╝
Windows Subsystem for Linux Installer

"@ "Cyan"

Install-WSL

Write-ColorOutput "`nFor more information, visit: https://aka.ms/wsl" "Cyan"