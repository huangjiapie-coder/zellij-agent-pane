<#
.SYNOPSIS
    Zellij Agent Pane — Uninstall (PowerShell)
.DESCRIPTION
    Removes Zellij Agent Pane hooks, deployed files, and runtime data.
    Uses libdeploy.py as single source of truth for hook configuration.

.PARAMETER Yes
    Non-interactive mode — skip confirmation prompt.
.PARAMETER Help
    Show this help message.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File uninstall.ps1
    powershell -ExecutionPolicy Bypass -File uninstall.ps1 -Yes
#>

param(
    [switch]$Yes,
    [switch]$Help
)

# ── Constants ──────────────────────────────────────────────────────────────
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

$TargetDir = Join-Path $env:USERPROFILE ".claude\scripts"
$SettingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
$PaneMapPath = Join-Path $env:USERPROFILE ".claude\zellij-pane-map.json"
$DebugLogPath = Join-Path $env:USERPROFILE ".claude\zellij-hooks-debug.log"
$LibDeployPy = Join-Path $ScriptDir "libdeploy.py"

# Colors
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
Usage: powershell -ExecutionPolicy Bypass -File uninstall.ps1 [OPTIONS]

Zellij Agent Pane — Uninstall (PowerShell)

Parameters:
  -Yes         Non-interactive mode (skip confirmation)
  -Help        Show this help message

Examples:
  powershell -ExecutionPolicy Bypass -File uninstall.ps1
  powershell -ExecutionPolicy Bypass -File uninstall.ps1 -Yes
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

function Get-PythonCommand {
    $cmds = @("python", "python3", "py")
    foreach ($cmd in $cmds) {
        try {
            $result = & $cmd --version 2>&1
            if ($LASTEXITCODE -eq 0) { return $cmd }
        } catch {
            continue
        }
    }
    return $null
}

function Invoke-LibDeploy {
    param([string[]]$Arguments)
    $python = Get-PythonCommand
    if (-not $python) {
        return $null
    }
    # Try to use libdeploy.py from project first, then from target dir
    if (-not (Test-Path $LibDeployPy)) {
        $LibDeployPy = Join-Path $TargetDir "libdeploy.py"
        if (-not (Test-Path $LibDeployPy)) {
            return $null
        }
    }
    $output = & $python $LibDeployPy @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        return $null
    }
    return $output
}

# ── Main ───────────────────────────────────────────────────────────────────

function Main {
    if ($Help) { Show-Help }

    Write-Host "+================================================+" -ForegroundColor $Colors.Banner
    Write-Host "|     Zellij Agent Pane - Uninstall              |" -ForegroundColor $Colors.Banner
    Write-Host "+================================================+" -ForegroundColor $Colors.Banner
    Write-Host ""

    # Check if anything is installed
    $anythingInstalled = $false
    $checkFiles = @("zellij-agent-pane.sh", "zellij-agent-pane.ps1", "zellij-monitor.py", "libdeploy.py")
    foreach ($f in $checkFiles) {
        $fp = Join-Path $TargetDir $f
        if (Test-Path $fp) { $anythingInstalled = $true; break }
    }
    if (Test-Path $SettingsPath) {
        try {
            $settings = Get-Content $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($settings.hooks) {
                $anythingInstalled = $true
            }
        } catch {}
    }

    if (-not $anythingInstalled) {
        Write-Info "No Zellij Agent Pane installation detected. Nothing to uninstall."
        exit 0
    }

    # Show what will be removed
    Write-Warn "The following will be removed:"
    foreach ($f in $checkFiles) {
        $fp = Join-Path $TargetDir $f
        if (Test-Path $fp) { Write-Host "  • $fp" }
    }
    Write-Host "  • $SettingsPath (hooks config will be removed)"
    if (Test-Path $PaneMapPath) { Write-Host "  • $PaneMapPath" }
    if (Test-Path $DebugLogPath) { Write-Host "  • $DebugLogPath" }
    Write-Host ""

    if (-not (Confirm-YesNo "Confirm uninstall?" "N")) {
        Write-Info "Uninstall cancelled."
        exit 0
    }

    # Step 1: Backup settings.json
    Write-Step "Step 1/4 — Backing Up Configuration"
    if (Test-Path $SettingsPath) {
        $ts = Get-Date -Format "yyyyMMddHHmmss"
        $bakPath = "$SettingsPath.bak.$ts"
        Copy-Item -Path $SettingsPath -Destination $bakPath -Force
        Write-OK "Backup created: $bakPath"
    } else {
        Write-Skip "No settings to backup"
    }
    Write-Host ""

    # Step 2: Remove hooks from settings.json
    Write-Step "Step 2/4 — Removing Hooks from settings.json"
    if (Test-Path $SettingsPath) {
        $hooksRemoved = $false
        # Try libdeploy.py first if available
        $removeResult = Invoke-LibDeploy "remove-hooks", $SettingsPath, "win32"
        if ($removeResult) {
            try {
                $result = $removeResult | ConvertFrom-Json
                if ($result.removed) {
                    Write-OK "Zellij Agent Pane hooks removed from settings.json ($($result.hook_count) hooks remaining)"
                    $hooksRemoved = $true
                } else {
                    Write-OK "No matching hooks found in settings.json"
                    $hooksRemoved = $true
                }
            } catch {}
        }

        if (-not $hooksRemoved) {
            Write-Warn "Could not automatically remove hooks via libdeploy.py - doing manual removal"
            # Manual fallback: read settings, filter out known hooks
            try {
                $settings = Get-Content $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
                # Convert PSObject to hashtable
                if ($settings -is [PSCustomObject]) {
                    $ht = @{}
                    foreach ($prop in $settings.PSObject.Properties) {
                        $ht[$prop.Name] = $prop.Value
                    }
                    $settings = $ht
                }

                $changed = $false
                if ($settings.ContainsKey("hooks")) {
                    $hooks = $settings["hooks"]
                    foreach ($eventName in @("SubagentStart", "SubagentStop")) {
                        if ($hooks.ContainsKey($eventName) -and $hooks[$eventName]) {
                            $newMatchers = @()
                            foreach ($matcher in $hooks[$eventName]) {
                                $filteredHooks = @()
                                if ($matcher.hooks) {
                                    foreach ($h in $matcher.hooks) {
                                        $cmd = $h.command
                                        if (-not ($cmd -match "zellij-agent-pane")) {
                                            $filteredHooks += $h
                                        }
                                    }
                                }
                                if ($filteredHooks.Count -gt 0) {
                                    $matcher.hooks = $filteredHooks
                                    $newMatchers += $matcher
                                } else {
                                    $changed = $true
                                }
                            }
                            if ($newMatchers.Count -gt 0) {
                                $hooks[$eventName] = $newMatchers
                            } else {
                                $hooks.Remove($eventName)
                                $changed = $true
                            }
                        }
                    }
                    if (-not $hooks -or $hooks.Count -eq 0) {
                        $settings.Remove("hooks")
                    }
                    if ($changed) {
                        $settings | ConvertTo-Json -Depth 10 | Set-Content $SettingsPath -Encoding UTF8
                        Write-OK "Zellij Agent Pane hooks removed from settings.json"
                    } else {
                        Write-OK "No matching hooks found in settings.json"
                    }
                } else {
                    Write-OK "No hooks key in settings.json"
                }
            } catch {
                Write-Fail "Failed to remove hooks manually: $_"
            }
        }
    } else {
        Write-OK "settings.json does not exist"
    }
    Write-Host ""

    # Step 3: Delete deployed files
    Write-Step "Step 3/4 — Removing Deployed Files"

    $deletedCount = 0
    foreach ($f in $checkFiles + @("doctor.sh", "doctor.ps1")) {
        $fp = Join-Path $TargetDir $f
        if (Test-Path $fp) {
            Remove-Item -Path $fp -Force
            Write-OK "Deleted: $fp"
            $deletedCount++
        }
    }

    if (Test-Path $PaneMapPath) {
        Remove-Item -Path $PaneMapPath -Force
        Write-OK "Deleted: $PaneMapPath"
    }

    if (Test-Path $DebugLogPath) {
        Remove-Item -Path $DebugLogPath -Force
        Write-OK "Deleted: $DebugLogPath"
    }

    # Remove temp monitor files
    $tempFiles = Get-ChildItem (Join-Path $env:USERPROFILE ".claude\.mon-*.json") -ErrorAction SilentlyContinue
    if ($tempFiles) {
        foreach ($tf in $tempFiles) {
            Remove-Item -Path $tf.FullName -Force
        }
        Write-OK "Cleaned monitor temp files ($($tempFiles.Count) file(s))"
    }

    # Remove scripts directory if empty
    if (Test-Path $TargetDir) {
        $remaining = Get-ChildItem $TargetDir -ErrorAction SilentlyContinue
        if (-not $remaining) {
            Remove-Item -Path $TargetDir -Force
            Write-OK "Removed empty directory: $TargetDir"
        }
    }

    if ($deletedCount -eq 0) {
        Write-Skip "No deployed files found to remove"
    }
    Write-Host ""

    # Step 4: Summary
    Write-Step "Step 4/4 — Uninstall Complete"
    Write-Host ""
    Write-Host "  ✓ Uninstall successful" -ForegroundColor $Colors.Pass
    Write-Host ""
    Write-Host "  ── Removed ──"
    Write-Host "    • Script files (zellij-agent-pane.sh/.ps1, zellij-monitor.py, libdeploy.py)"
    Write-Host "    • Runtime data (pane map, debug log, temp files)"
    Write-Host "    • settings.json hooks configuration"
    Write-Host ""
    Write-Host "  ── Preserved ──"
    Write-Host "    • settings.json backup (can be manually restored if needed)"
    Write-Host "    • Other configurations in ~/.claude/"
    Write-Host ""
    Write-Info "To reinstall, run: powershell -ExecutionPolicy Bypass -File `"$ScriptDir\deploy.ps1`""
    Write-Info "Or use the unified launcher: deploy.bat"
    Write-Host ""
    Write-Host "按任意键退出..." -ForegroundColor Green
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

Main
