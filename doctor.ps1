<#
.SYNOPSIS
    Zellij Agent Pane — Diagnostic Tool
.DESCRIPTION
    Checks environment, configuration, and dependencies for Zellij Agent Pane.
    Run this to diagnose why sub-agent panes aren't appearing.

.PARAMETER Help
    Show this help message.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File doctor.ps1
#>

param([switch]$Help)

$TargetDir = Join-Path $env:USERPROFILE ".claude\scripts"
$SettingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
$DebugLogPath = Join-Path $env:USERPROFILE ".claude\zellij-hooks-debug.log"
$PaneMapPath = Join-Path $env:USERPROFILE ".claude\zellij-pane-map.json"

$Colors = @{ Pass='Green'; Fail='Red'; Warn='Yellow'; Info='Cyan'; Bold='White' }

function Write-Pass  { Write-Host "  ✓ " -NoNewline -ForegroundColor $Colors.Pass; Write-Host "$args" }
function Write-Fail  { Write-Host "  ✗ " -NoNewline -ForegroundColor $Colors.Fail; Write-Host "$args" }
function Write-Warn  { Write-Host "  ⚠ " -NoNewline -ForegroundColor $Colors.Warn; Write-Host "$args" }
function Write-Info  { Write-Host "  → " -NoNewline -ForegroundColor $Colors.Info; Write-Host "$args" }

function Get-Version {
    param([string]$ExeName)
    try {
        $result = & $ExeName --version 2>&1
        if ($result -is [array]) { return $result[0].Trim() }
        return $result.ToString().Trim()
    } catch { return $null }
}

if ($Help) {
    @"
Usage: powershell -ExecutionPolicy Bypass -File doctor.ps1

Zellij Agent Pane — Diagnostic Tool

Checks your environment for Zellij Agent Pane deployment.
Run this if sub-agent panes are not appearing.

Examples:
  powershell -ExecutionPolicy Bypass -File doctor.ps1
"@
    exit 0
}

Write-Host "=== Zellij Agent Pane — Diagnostic Tool ===" -ForegroundColor $Colors.Info
Write-Host ""

# 1. Script files
Write-Host "[1] Script Files" -ForegroundColor $Colors.Bold

$checkFiles = @("zellij-agent-pane.sh", "zellij-monitor.py")
$allFilesOK = $true
foreach ($f in $checkFiles) {
    $fp = Join-Path $TargetDir $f
    if (Test-Path $fp) {
        Write-Pass "$f installed at $TargetDir"
    } else {
        Write-Fail "$f NOT FOUND at $TargetDir"
        $allFilesOK = $false
    }
}
if (-not $allFilesOK) {
    Write-Info "Run deploy script: powershell -ExecutionPolicy Bypass -File deploy.ps1"
}

# 2. Dependencies
Write-Host ""
Write-Host "[2] Dependencies" -ForegroundColor $Colors.Bold
$depsOK = $true

# Zellij
$zellij = Get-Command "zellij.exe" -ErrorAction SilentlyContinue
if ($zellij) {
    $ver = Get-Version "zellij"
    Write-Pass "zellij: $ver"
} else {
    Write-Fail "zellij: NOT FOUND"
    Write-Info "Install: winget install Zellij.Zellij  or  scoop install zellij"
    $depsOK = $false
}

# Python
$python = Get-Command "python" -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command "python3" -ErrorAction SilentlyContinue }
if ($python) {
    $ver = Get-Version $python.Source
    Write-Pass "python3: $ver"
} else {
    Write-Fail "python3: NOT FOUND"
    Write-Info "Install: winget install Python.Python.3  or  https://python.org"
    $depsOK = $false
}

# Bash
$bash = Get-Command "bash" -ErrorAction SilentlyContinue
if ($bash) {
    $ver = Get-Version "bash"
    Write-Pass "bash: $ver"
} else {
    Write-Fail "bash: NOT FOUND (hooks require bash)"
    Write-Info "Install Git Bash: https://git-scm.com"
    $depsOK = $false
}

# 3. Zellij session
Write-Host ""
Write-Host "[3] Zellij Session" -ForegroundColor $Colors.Bold

$zellijSession = [Environment]::GetEnvironmentVariable("ZELLIJ_SESSION_NAME")
if ($zellijSession) {
    Write-Pass "Running inside zellij session: $zellijSession"
} else {
    # Try to detect via zellij action
    try {
        $null = & "zellij" "action" "dump" 2>&1 | Select-Object -First 1
        Write-Pass "Running inside a zellij session"
    } catch {
        Write-Fail "NOT in a zellij session"
        Write-Info "Start zellij first, then launch Claude Code inside it"
        Write-Info "  zellij"
    }
}

# 4. Settings hooks
Write-Host ""
Write-Host "[4] Claude Code Hooks Configuration" -ForegroundColor $Colors.Bold

if (-not (Test-Path $SettingsPath)) {
    Write-Fail "settings.json NOT FOUND at $SettingsPath"
    Write-Info "Run deploy script to configure hooks"
} else {
    try {
        $content = Get-Content $SettingsPath -Raw -Encoding UTF8
        $settings = $content | ConvertFrom-Json
        $hooks = $settings.hooks

        $total = 0
        $foundZellijHooks = $false
        if ($hooks) {
            foreach ($ev in @("SubagentStart", "SubagentStop")) {
                $matchers = $hooks.$ev
                if ($matchers) {
                    foreach ($m in $matchers) {
                        foreach ($h in $m.hooks) {
                            $total++
                            if ($h.command -match "zellij-agent-pane") {
                                $foundZellijHooks = $true
                                Write-Pass "Hook found: $($h.command)"
                            }
                        }
                    }
                }
            }
        }

        if ($foundZellijHooks) {
            Write-Info "Total: $total hook entr(ies)"
        } else {
            Write-Fail "No Zellij Agent Pane hooks found in settings.json"
            Write-Info "Run deploy script to configure hooks"
        }
    } catch {
        Write-Fail "settings.json is not valid JSON: $_"
    }
}

# 5. Debug log
Write-Host ""
Write-Host "[5] Debug Log" -ForegroundColor $Colors.Bold

if (Test-Path $DebugLogPath) {
    $lines = (Get-Content $DebugLogPath | Measure-Object).Count
    Write-Pass "Debug log exists ($lines lines)"

    $errors = Select-String -Path $DebugLogPath -Pattern "error|fail|missing" -CaseSensitive:$false -SimpleMatch:$false | Measure-Object
    if ($errors.Count -gt 0) {
        Write-Warn "Found $($errors.Count) error/warning entr(ies)"
        Write-Info "Last 10 lines:"
        Get-Content $DebugLogPath -Tail 10 | ForEach-Object { Write-Host "    $_" }
    }
} else {
    Write-Info "Debug log not found (hooks haven't been triggered yet)"
}

# 6. Pane map
Write-Host ""
Write-Host "[6] Pane Map" -ForegroundColor $Colors.Bold

if (Test-Path $PaneMapPath) {
    try {
        $mapContent = Get-Content $PaneMapPath -Raw -Encoding UTF8
        $map = $mapContent | ConvertFrom-Json
        $count = ($map.PSObject.Properties | Measure-Object).Count
        Write-Pass "Pane map exists ($count active agent(s))"
    } catch {
        Write-Info "Pane map exists (but appears empty)"
    }
} else {
    Write-Info "Pane map not created yet"
}

# Summary
Write-Host ""
Write-Host "=== Diagnosis Complete ===" -ForegroundColor $Colors.Info
if ($depsOK -and $allFilesOK) {
    Write-Host "All dependencies and files ready." -ForegroundColor $Colors.Pass
} else {
    Write-Host "Some issues found. Fix the problems above and re-deploy." -ForegroundColor $Colors.Fail
}
Write-Host ""
Write-Host "Common troubleshooting steps:"
Write-Host "  1. Make sure zellij is running:  zellij"
Write-Host "  2. Launch Claude Code INSIDE zellij (not before)"
Write-Host "  3. Check ~/.claude/settings.json has hooks configured"
Write-Host "  4. Restart Claude Code after deployment"