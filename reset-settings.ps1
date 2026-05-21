<#
.SYNOPSIS
    Zellij Agent Pane — Reset Claude Code Settings (PowerShell)
.DESCRIPTION
    Reset settings.json to default state or restore from backup.
    Use this when installation causes errors.

.PARAMETER Yes
    Non-interactive mode — skip confirmation prompt.
.PARAMETER Backup
    Restore from latest backup (if exists).
.PARAMETER Default
    Reset to empty/default state.
.PARAMETER Help
    Show this help message.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File reset-settings.ps1
    powershell -ExecutionPolicy Bypass -File reset-settings.ps1 -Backup
    powershell -ExecutionPolicy Bypass -File reset-settings.ps1 -Default -Yes
#>

param(
    [switch]$Yes,
    [switch]$Backup,
    [switch]$Default,
    [switch]$Help
)

# ── Constants ──────────────────────────────────────────────────────────────
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

$SettingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"

$Colors = @{
    Info    = 'Cyan'
    Pass    = 'Green'
    Fail    = 'Red'
    Warn    = 'Yellow'
    Step    = 'DarkCyan'
    OK      = 'Green'
    Skip    = 'DarkYellow'
    Banner  = 'Cyan'
}

# ── Helper Functions ───────────────────────────────────────────────────────

function Write-Info  { Write-Host "[INFO] " -NoNewline -ForegroundColor $Colors.Info; Write-Host "$args" }
function Write-Pass  { Write-Host "[PASS] " -NoNewline -ForegroundColor $Colors.Pass; Write-Host "$args" }
function Write-Fail  { Write-Host "[FAIL] " -NoNewline -ForegroundColor $Colors.Fail; Write-Host "$args" }
function Write-Warn  { Write-Host "[WARN] " -NoNewline -ForegroundColor $Colors.Warn; Write-Host "$args" }
function Write-Step  { Write-Host "`n--- $args ---" -ForegroundColor $Colors.Step }
function Write-OK    { Write-Host "  ✓ " -NoNewline -ForegroundColor $Colors.OK; Write-Host "$args" }
function Write-Skip  { Write-Host "  − " -NoNewline -ForegroundColor $Colors.Skip; Write-Host "$args" }

function Show-Help {
    @"
Usage: powershell -ExecutionPolicy Bypass -File reset-settings.ps1 [OPTIONS]

Zellij Agent Pane - Reset Claude Code Settings

Use this when installation causes errors.

Parameters:
  -Yes           Non-interactive mode (skip confirmation)
  -Backup        Restore from latest backup (if exists)
  -Default       Reset to empty/default state
  -Help          Show this help message

Examples:
  powershell -ExecutionPolicy Bypass -File reset-settings.ps1
  powershell -ExecutionPolicy Bypass -File reset-settings.ps1 -Backup
  powershell -ExecutionPolicy Bypass -File reset-settings.ps1 -Default -Yes
"@
    exit 0
}

function Confirm-YesNo {
    param([string]$Prompt, [string]$Default = "N")
    if ($Yes) { return $true }

    $hint = if ($Default -eq "Y") { "Y/n" } else { "y/N" }
    $ans = Read-Host "$Prompt [$hint]"
    if ([string]::IsNullOrEmpty($ans)) { $ans = $Default }
    return ($ans -eq 'y' -or $ans -eq 'Y' -or $ans -eq 'yes')
}

function Find-LatestBackup {
    param([string]$Path)
    $parent = Split-Path -Parent $Path
    $filename = Split-Path -Leaf $Path
    $pattern = "$filename.bak.*"

    $backups = Get-ChildItem -Path $parent -Filter $pattern -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    if ($backups) {
        return $backups[0].FullName
    }
    return $null
}

# ── Main ───────────────────────────────────────────────────────────────────

function Main {
    if ($Help) { Show-Help }

    Write-Host "+================================================+" -ForegroundColor $Colors.Banner
    Write-Host "|  Zellij Agent Pane - Reset Settings             |" -ForegroundColor $Colors.Banner
    Write-Host "+================================================+" -ForegroundColor $Colors.Banner
    Write-Host ""

    # Check if settings.json exists
    if (-not (Test-Path $SettingsPath)) {
        Write-Info "settings.json does not exist. Nothing to reset."
        Write-Host ""
        Write-Info "Claude Code will create default settings on next start."
        Write-Host ""
        Write-Host "按任意键退出..." -ForegroundColor Green
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 0
    }

    # Find latest backup
    $latestBackup = Find-LatestBackup $SettingsPath

    # Show current state
    Write-Host ""
    Write-Info "Current settings: $SettingsPath"
    if ($latestBackup) {
        Write-Info "Latest backup found: $latestBackup"
    } else {
        Write-Info "No backup files found"
    }
    Write-Host ""

    # Validate mutually exclusive params
    if ($Backup -and $Default) {
        Write-Fail "Cannot specify both -Backup and -Default"
        exit 1
    }

    # Choose mode if not specified
    $mode = $null
    if ($Backup) { $mode = "backup" }
    elseif ($Default) { $mode = "default" }
    else {
        # Interactive choice
        $options = @()
        if ($latestBackup) { $options += "Restore from latest backup" }
        $options += "Reset to empty/default state"
        $options += "Cancel"

        Write-Host "Please choose an option:"
        $i = 1
        foreach ($opt in $options) {
            Write-Host "  $i) $opt"
            $i++
        }
        Write-Host ""
        while ($true) {
            $ans = Read-Host "Select [1-$($options.Count)]"
            if ($ans -match '^[0-9]+$' -and [int]$ans -ge 1 -and [int]$ans -le $options.Count) {
                $choice = [int]$ans - 1
                if ($latestBackup -and $choice -eq 0) { $mode = "backup" }
                elseif (($latestBackup -and $choice -eq 1) -or (-not $latestBackup -and $choice -eq 0)) { $mode = "default" }
                else { Write-Info "Cancelled"; exit 0 }
                break
            }
            Write-Host "Invalid choice, please enter 1 to $($options.Count)"
        }
        Write-Host ""
    }

    # Validate mode=backup has a backup
    if ($mode -eq "backup" -and -not $latestBackup) {
        Write-Fail "No backup files found, cannot restore from backup"
        Write-Info "Use -Default instead, or choose interactively"
        exit 1
    }

    # Confirmation
    if ($mode -eq "backup") {
        Write-Warn "Will restore from backup:"
        Write-Host "  • Backup: $latestBackup"
        Write-Host "  • Will overwrite: $SettingsPath"
    } else {
        Write-Warn "Will reset to empty/default state:"
        Write-Host "  • Will delete: $SettingsPath"
        Write-Host "  • Will create a backup first just in case"
    }
    Write-Host ""

    if (-not (Confirm-YesNo "Continue?" "N")) {
        Write-Info "Cancelled."
        exit 0
    }

    # Execute
    Write-Step "Executing Restore"

    if ($mode -eq "backup") {
        # First backup current state just in case
        $ts = Get-Date -Format "yyyyMMddHHmmss"
        $extraBak = "$SettingsPath.bak.$ts"
        Copy-Item -Path $SettingsPath -Destination $extraBak -Force
        Write-OK "Extra backup created: $extraBak"

        # Restore from backup
        Copy-Item -Path $latestBackup -Destination $SettingsPath -Force
        Write-OK "Restored from backup: $latestBackup"
    } else {
        # Backup current first
        $ts = Get-Date -Format "yyyyMMddHHmmss"
        $bak = "$SettingsPath.bak.$ts"
        Copy-Item -Path $SettingsPath -Destination $bak -Force
        Write-OK "Backup created: $bak"

        # Delete settings.json
        Remove-Item -Path $SettingsPath -Force
        Write-OK "Reset to default state (settings.json deleted)"
    }

    # Summary
    Write-Host ""
    Write-Step "Complete"
    Write-Host ""
    Write-Host "  ✓ Done" -ForegroundColor $Colors.Pass
    Write-Host ""
    if ($mode -eq "backup") {
        Write-Host "  ── Restored ──"
        Write-Host "    • From: $latestBackup"
    } else {
        Write-Host "  ── Reset ──"
        Write-Host "    • settings.json removed"
        Write-Host "    • Claude Code will create default settings on next start"
    }
    Write-Host ""
    Write-Info "Please restart Claude Code for changes to take effect"
    Write-Host ""

    Write-Host "按任意键退出..." -ForegroundColor Green
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

Main
