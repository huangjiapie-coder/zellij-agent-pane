<#
.SYNOPSIS
    Zellij Agent Pane — One-Click Deployment (PowerShell)
.DESCRIPTION
    Deploys Zellij Agent Pane hooks for Claude Code on Windows machines
    without requiring Git Bash, WSL, or MSYS2.

    Uses libdeploy.py as single source of truth for hook configuration.

.PARAMETER Yes
    Non-interactive mode — skip all confirmation prompts.
.PARAMETER DryRun
    Preview mode — show what would be done without modifying any files.
.PARAMETER Help
    Show this help message.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File deploy.ps1
    powershell -ExecutionPolicy Bypass -File deploy.ps1 -Yes
    powershell -ExecutionPolicy Bypass -File deploy.ps1 -DryRun
#>

param(
    [switch]$Yes,
    [switch]$DryRun,
    [switch]$Help
)

# ── Constants ──────────────────────────────────────────────────────────────
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

$TargetDir = Join-Path $env:USERPROFILE ".claude\scripts"
$SettingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
$LibDeployPy = Join-Path $ScriptDir "libdeploy.py"

# Colors (PowerShell 5.1+ supports these names)
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
function Write-Dry   { Write-Host "[DRY-RUN] " -NoNewline -ForegroundColor $Colors.Warn; Write-Host "$args" }
function Write-Step  { Write-Host "`n--- $args ---" -ForegroundColor $Colors.Step }
function Write-OK    { Write-Host "  ✓ " -NoNewline -ForegroundColor $Colors.OK; Write-Host "$args" }
function Write-Skip  { Write-Host "  − " -NoNewline -ForegroundColor $Colors.Skip; Write-Host "$args" }

function Show-Help {
    @"
用法: powershell -ExecutionPolicy Bypass -File deploy.ps1 [OPTIONS]

Zellij Agent Pane — 一键部署 Claude Code 子 agent 窗格工具 (PowerShell)

Parameters:
  -Yes         Non-interactive mode (skip prompts, use defaults)
  -DryRun      Preview mode (no files modified)
  -Help        Show this help message

Examples:
  powershell -ExecutionPolicy Bypass -File deploy.ps1
  powershell -ExecutionPolicy Bypass -File deploy.ps1 -Yes
  powershell -ExecutionPolicy Bypass -File deploy.ps1 -DryRun
"@
    exit 0
}

function Confirm-YesNo {
    param([string]$Prompt, [string]$Default = "Y")
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
        Write-Fail "Python not found - required for libdeploy.py"
        return $null
    }
    $output = & $python $LibDeployPy @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "libdeploy.py failed: $output"
        return $null
    }
    return $output
}

function Get-VersionString {
    param([string]$ExePath)
    try {
        $result = & $ExePath --version 2>&1
        if ($result -is [array]) { return $result[0].Trim() }
        return $result.ToString().Split("`n")[0].Trim()
    } catch {
        return "found"
    }
}

# ── Phase 0: Bootstrap ─────────────────────────────────────────────────────

function Phase-Bootstrap {
    Clear-Host 2>$null
    Write-Host "+================================================+" -ForegroundColor $Colors.Banner
    Write-Host "|       Zellij Agent Pane - One-Click Deploy      |" -ForegroundColor $Colors.Banner
    Write-Host "+================================================+" -ForegroundColor $Colors.Banner
    Write-Host ""

    if ($Help) { Show-Help }

    if ($DryRun) {
        Write-Warn "DRY-RUN mode — no files will be modified"
        Write-Host ""
    }

    # Check required source files exist
    $requiredFiles = @("zellij-agent-pane.sh", "zellij-agent-pane.ps1", "zellij-monitor.py", "libdeploy.py")
    foreach ($f in $requiredFiles) {
        $fp = Join-Path $ScriptDir $f
        if (-not (Test-Path $fp)) {
            Write-Fail "Required file not found: $fp"
            Write-Info "Please run this script from the project root directory"
            exit 1
        }
    }

    # Check python is available for libdeploy.py
    $python = Get-PythonCommand
    if (-not $python) {
        Write-Fail "Python not found - required for deployment"
        Write-Info "Install Python 3: winget install Python.Python.3 or https://python.org/downloads"
        exit 1
    }
    Write-OK "Using Python: $python"
}

# ── Phase 1: OS Detection ──────────────────────────────────────────────────

function Phase-DetectOS {
    Write-Step "Phase 1/6 — OS Detection"

    $osInfo = Get-CimInstance Win32_OperatingSystem 2>$null
    if (-not $osInfo) {
        $osInfo = [PSCustomObject]@{ Caption = "Windows"; Version = [Environment]::OSVersion.Version.ToString() }
    }

    Write-Host "  System: " -NoNewline
    Write-Host "$($osInfo.Caption) $($osInfo.Version)" -ForegroundColor White

    $detectedOS = Invoke-LibDeploy "detect-os"
    Write-Host "  Detected: $detectedOS" -ForegroundColor Cyan

    $msys = [Environment]::GetEnvironmentVariable("MSYSTEM")
    if ($msys) {
        Write-Host "  Shell:  MSYS2 ($msys)"
    } else {
        Write-Host "  Shell:  PowerShell $($PSVersionTable.PSVersion)"
    }

    Write-Host ""
}

# ── Phase 2: Dependency Check ──────────────────────────────────────────────

function Phase-CheckDeps {
    Write-Step "Phase 2/6 — Dependency Check"

    $depsJson = Invoke-LibDeploy "check-deps"
    if (-not $depsJson) {
        Write-Fail "Failed to get dependency info from libdeploy.py"
        exit 1
    }

    try {
        $deps = $depsJson | ConvertFrom-Json
    } catch {
        Write-Fail "Failed to parse dependency JSON: $_"
        Write-Host "Raw output: $depsJson"
        exit 1
    }

    $allOK = $true
    $missingRequired = $false

    foreach ($dep in @("zellij", "python3")) {
        $info = $deps.$dep
        $label = switch ($dep) { "zellij" { "zellij       " } "python3" { "Python 3     " } default { "$dep          " } }

        if ($info.ok) {
            Write-Pass "$label $($info.version)  @ $($info.path)"
        } else {
            Write-Fail "$label not found"
            if ($info.install_hint) {
                Write-Host "        → $($info.install_hint)"
            }
            $missingRequired = $true
        }
    }

    # Check bash (optional)
    $bashInfo = $deps.bash
    if ($bashInfo.ok) {
        Write-Pass "bash         $($bashInfo.version)  @ $($bashInfo.path)"
    } else {
        Write-Warn "bash         not found (will use PowerShell hooks)"
    }

    # Check Claude Code (optional)
    $claudeInfo = $deps.claude
    if ($claudeInfo.ok) {
        Write-Pass "Claude Code  $($claudeInfo.version)  @ $($claudeInfo.path)"
    } else {
        Write-Warn "Claude Code  not found (optional)"
    }

    Write-Host ""

    if ($missingRequired) {
        Write-Fail "Missing required dependencies. Please install them first."
        if (-not $Yes) {
            if (-not (Confirm-YesNo "Continue anyway? (features may not work)" "N")) {
                Write-Info "Deployment cancelled."
                exit 1
            }
        } else {
            exit 1
        }
    } else {
        Write-Pass "All required dependencies are ready"
    }
    Write-Host ""
}

# ── Phase 3: Copy Scripts ──────────────────────────────────────────────────

function Phase-CopyScripts {
    Write-Step "Phase 3/6 — Copying Scripts"

    if ($DryRun) {
        Write-Dry "Create directory: $TargetDir"
        Write-Dry "Copy: zellij-agent-pane.sh → $TargetDir"
        Write-Dry "Copy: zellij-agent-pane.ps1 → $TargetDir"
        Write-Dry "Copy: zellij-monitor.py    → $TargetDir"
        Write-Dry "Copy: libdeploy.py         → $TargetDir"
        Write-Dry "Copy: doctor.sh            → $TargetDir"
        Write-Dry "Copy: doctor.ps1           → $TargetDir"
        Write-Host ""
        return
    }

    # Create target directory
    New-Item -Path $TargetDir -ItemType Directory -Force | Out-Null

    # Copy all files (both .sh and .ps1 for flexibility)
    $coreFiles = @("zellij-agent-pane.sh", "zellij-agent-pane.ps1", "zellij-monitor.py", "libdeploy.py")
    $extraFiles = @("doctor.sh", "doctor.ps1")
    $files = $coreFiles + $extraFiles
    foreach ($f in $files) {
        $src = Join-Path $ScriptDir $f
        if (-not (Test-Path $src)) { continue }  # skip if not in project dir
        $dst = Join-Path $TargetDir $f
        Copy-Item -Path $src -Destination $dst -Force
        Write-OK "$f"
    }

    # Verify copy — only check core files
    $allCopied = $true
    foreach ($f in $coreFiles) {
        $fp = Join-Path $TargetDir $f
        if (-not (Test-Path $fp)) {
            Write-Fail "$f not found after copy"
            $allCopied = $false
        }
    }

    if ($allCopied) {
        Write-Pass "All scripts installed to $TargetDir"
    } else {
        Write-Fail "Some files failed to copy — check permissions"
        exit 1
    }
    Write-Host ""
}

# ── Phase 4: Settings Merge ────────────────────────────────────────────────

function Phase-MergeSettings {
    Write-Step "Phase 4/6 — Configuring Claude Code Hooks"

    if ($DryRun) {
        Write-Dry "Backup: $SettingsPath → $SettingsPath.bak.<TIMESTAMP>"
        Write-Dry "Will merge hooks config into: $SettingsPath"
        Write-Host ""
        Write-Host "  Hooks to add:" -ForegroundColor $Colors.Warn
        $hooksJson = Invoke-LibDeploy "generate-hooks"
        $hooksJson | ForEach-Object { Write-Host "    $_" }
        Write-Host ""
        return
    }

    # Backup
    if (Test-Path $SettingsPath) {
        $ts = Get-Date -Format "yyyyMMddHHmmss"
        $bakPath = "$SettingsPath.bak.$ts"
        Copy-Item -Path $SettingsPath -Destination $bakPath -Force
        Write-OK "Backup created: $bakPath"
    } else {
        Write-Info "settings.json does not exist — will create new file"
    }

    # Merge hooks using libdeploy.py
    Write-Info "Merging hooks using libdeploy.py (win32 OS config)..."
    $mergeResult = Invoke-LibDeploy "merge-hooks", $SettingsPath, "win32"
    if (-not $mergeResult) {
        Write-Fail "Failed to merge hooks"
        return
    }

    try {
        $result = $mergeResult | ConvertFrom-Json
        if ($result.error) {
            Write-Fail $result.error
            if (Confirm-YesNo "Overwrite settings.json? (backup already created)" "N") {
                # Fallback: generate fresh
                $hooksJson = Invoke-LibDeploy "generate-hooks", "win32"
                $settings = "`{`"hooks`": $hooksJson`}"
                $settings | Set-Content -Path $SettingsPath -Encoding UTF8
                Write-OK "settings.json overwritten with fresh config"
            } else {
                Write-Warn "Deployment incomplete — please merge hooks manually"
                return
            }
        } elseif ($result.merged) {
            Write-OK "Hooks config merged into $SettingsPath ($($result.hook_count) total hook entries)"
        } else {
            Write-OK "Hooks config already up to date ($($result.hook_count) total hook entries)"
        }
    } catch {
        Write-Fail "Failed to parse merge result: $_"
        Write-Host "Result: $mergeResult"
    }
    Write-Host ""
}

# ── Phase 5: Verification ──────────────────────────────────────────────────

function Phase-Verify {
    Write-Step "Phase 5/6 — Verification"

    if ($DryRun) {
        Write-Dry "Skipping verification (dry-run mode)"
        Write-Host ""
        return
    }

    # File check using libdeploy.py
    Write-Host "  ── File Check ──"
    $verifyResult = Invoke-LibDeploy "verify-install", $TargetDir
    if ($verifyResult) {
        try {
            $verify = $verifyResult | ConvertFrom-Json
            foreach ($f in $verify.files) {
                if ($f.exists) {
                    Write-OK "$($f.name) exists"
                } else {
                    Write-Fail "$($f.name) is missing"
                }
            }
        } catch {
            Write-Warn "Failed to parse verify output - checking manually"
            $checkFiles = @("zellij-agent-pane.sh", "zellij-agent-pane.ps1", "zellij-monitor.py", "libdeploy.py")
            foreach ($f in $checkFiles) {
                $fp = Join-Path $TargetDir $f
                if (Test-Path $fp) {
                    Write-OK "$f exists"
                } else {
                    Write-Fail "$f is missing"
                }
            }
        }
    }

    # JSON validation
    Write-Host "  ── Config Check ──"
    if (Test-Path $SettingsPath) {
        try {
            $content = Get-Content $SettingsPath -Raw -Encoding UTF8
            $null = $content | ConvertFrom-Json
            Write-OK "settings.json is valid JSON"
        } catch {
            Write-Fail "settings.json is not valid JSON: $_"
        }
    } else {
        Write-Fail "settings.json does not exist"
    }

    # Hook script check
    Write-Host "  ── Hook Script Check ──"
    $hookScript = Join-Path $TargetDir "zellij-agent-pane.ps1"
    if (Test-Path $hookScript) {
        Write-OK "zellij-agent-pane.ps1 exists at $hookScript"
    } else {
        Write-Fail "zellij-agent-pane.ps1 not found"
    }

    # Temp file check
    $tempFiles = Get-ChildItem (Join-Path $env:USERPROFILE ".claude\.mon-*.json") -ErrorAction SilentlyContinue
    if ($tempFiles) {
        Write-Warn "Found leftover monitor temp files — can be safely removed"
    }

    Write-Host ""
}

# ── Phase 6: Summary ───────────────────────────────────────────────────────

function Phase-Summary {
    Write-Step "Phase 6/6 — Summary"

    if ($DryRun) {
        Write-Host "  DRY-RUN complete — no files were modified" -ForegroundColor $Colors.Warn
        Write-Host ""
        Write-Host "  Run the actual deploy:"
        Write-Host "    powershell -ExecutionPolicy Bypass -File `"$ScriptDir\deploy.ps1`""
        return
    }

    Write-Host "  ✓ Deployment successful!" -ForegroundColor $Colors.Pass
    Write-Host ""
    Write-Host "  ── Installed Files ──"
    Write-Host "    $TargetDir\zellij-agent-pane.sh"
    Write-Host "    $TargetDir\zellij-agent-pane.ps1"
    Write-Host "    $TargetDir\zellij-monitor.py"
    Write-Host "    $TargetDir\libdeploy.py"
    Write-Host ""
    Write-Host "  ── Configuration ──"
    Write-Host "    $SettingsPath  (hooks configured)"
    Write-Host ""
    Write-Host "  ── Next Steps ──"
    Write-Host "    1. Start a zellij session:   zellij" -ForegroundColor White
    Write-Host "    2. Launch Claude Code:       claude" -ForegroundColor White
    Write-Host "    3. Test sub-agent panes:     /agents" -ForegroundColor White
    Write-Host ""
    Write-Host "  ── Other Commands ──"
    Write-Host "    View map:    powershell -File $TargetDir\zellij-agent-pane.ps1 list"
    Write-Host "    Clear map:   powershell -File $TargetDir\zellij-agent-pane.ps1 clean"
    Write-Host "    Uninstall:   powershell -ExecutionPolicy Bypass -File `"$ScriptDir\uninstall.ps1`""
    Write-Host ""
    Write-Host "按任意键退出..." -ForegroundColor Green
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# ── Main ───────────────────────────────────────────────────────────────────

function Main {
    Phase-Bootstrap
    Phase-DetectOS
    Phase-CheckDeps
    Phase-CopyScripts
    Phase-MergeSettings
    Phase-Verify
    Phase-Summary
}

Main
