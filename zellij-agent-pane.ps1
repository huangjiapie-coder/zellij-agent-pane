$Action = $args[0]

$ZELLIJ_PANE_MAP = "$env:USERPROFILE\.claude\zellij-pane-map.json"
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$MONITOR_PY = "$SCRIPT_DIR\zellij-monitor.py"
$DEBUG_LOG = "$env:USERPROFILE\.claude\zellij-hooks-debug.log"

function Write-DebugLog {
    param([string]$Msg)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $DEBUG_LOG -Value "[$timestamp] $Msg" -ErrorAction SilentlyContinue
}

function Invoke-WithRetry {
    param([ScriptBlock]$Block, [int]$MaxRetries = 5, [int]$DelayMs = 100)
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            return & $Block
        } catch {
            if ($attempt -ge $MaxRetries) { throw }
            Write-DebugLog "[retry] attempt $attempt/$MaxRetries failed: $_"
            Start-Sleep -Milliseconds $DelayMs
        }
    }
}

function Read-HookInput {
    try {
        return [Console]::In.ReadToEnd()
    } catch {
        return ""
    }
}

function Get-PythonCommand {
    # Try multiple ways to find python
    $commands = @("python", "python3", "py")
    foreach ($cmd in $commands) {
        try {
            $result = & $cmd --version 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-DebugLog "[python] Found: $cmd"
                return $cmd
            }
        } catch {
            continue
        }
    }
    # Try common install locations
    $locations = @(
        "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
        "C:\Python313\python.exe",
        "C:\Python312\python.exe",
        "C:\Python311\python.exe"
    )
    foreach ($loc in $locations) {
        if (Test-Path $loc) {
            Write-DebugLog "[python] Found at: $loc"
            return "`"$loc`""
        }
    }
    Write-DebugLog "[python] WARNING: Could not find python, falling back to 'python'"
    return "python"
}

switch ($Action) {
    "start-hook" {
        $HOOK_INPUT = Read-HookInput
        Write-DebugLog "[start-hook] RAW INPUT: $HOOK_INPUT"

        try {
            $d = $HOOK_INPUT | ConvertFrom-Json
            $aid = $d.agent_id
            $atp = $d.agent_type
            $tp = $d.transcript_path
            $sid = $d.session_id

            $sd = if ($tp -and $sid) { Join-Path (Split-Path $tp -Parent) "$sid\subagents" } else { $null }
            $stp = if ($sd) { Join-Path $sd "agent-$aid.jsonl" } else { $null }

            if ($stp) {
                $sdDir = Split-Path $stp -Parent
                New-Item -Path $sdDir -ItemType Directory -Force | Out-Null
                $monTmp = "$env:USERPROFILE\.claude\.mon-$aid.json"
                @{path = $stp; type = $atp} | ConvertTo-Json | Set-Content -Path $monTmp -Encoding UTF8
            }

            Write-DebugLog "[start-hook] aid=$aid atp=$atp stp=$stp"

            if (-not $aid) {
                Write-Output '{"continue": true, "suppressOutput": true}'
                exit 0
            }

            if (-not (Test-Path $MONITOR_PY)) {
                Write-DebugLog "[start-hook] ERROR: Monitor script not found at $MONITOR_PY"
                Write-Output '{"continue": true, "suppressOutput": true}'
                exit 0
            }

            $monitorPyPath = Resolve-Path $MONITOR_PY
            $pythonCmd = Get-PythonCommand
            Write-DebugLog "[start-hook] Using python command: $pythonCmd"
            Write-DebugLog "[start-hook] Monitor path: $monitorPyPath"

            # Build zellij command carefully
            $paneName = "Agent: $atp"
            $zellijArgs = @(
                "action", "new-pane",
                "--direction", "right",
                "--name", $paneName,
                "--close-on-exit",
                "--",
                $pythonCmd, "`"$monitorPyPath`"", $aid
            )

            Write-DebugLog "[start-hook] Zellij args: $($zellijArgs -join ' ')"

            $paneOutput = & zellij @zellijArgs 2>&1
            $paneId = ($paneOutput | Where-Object { $_ -match '\S' } | Select-Object -Last 1)

            Write-DebugLog "[start-hook] Zellij output: $paneOutput"
            Write-DebugLog "[start-hook] PANE_ID='$paneId'"

            if ($paneId) {
                Invoke-WithRetry -Block {
                    $map = if (Test-Path $ZELLIJ_PANE_MAP) {
                        Get-Content $ZELLIJ_PANE_MAP -Raw -Encoding UTF8 | ConvertFrom-Json
                    } else {
                        @{}
                    }
                    $newMap = [ordered]@{}
                    if ($map -is [PSCustomObject]) {
                        foreach ($prop in $map.PSObject.Properties) {
                            $newMap[$prop.Name] = $prop.Value
                        }
                    } else {
                        $newMap = $map
                    }
                    $newMap["$aid"] = "$paneId"
                    $newMap | ConvertTo-Json | Set-Content -Path $ZELLIJ_PANE_MAP -Encoding UTF8
                }
            }
        } catch {
            Write-DebugLog "[start-hook] ERROR: $_"
            Write-DebugLog "[start-hook] Stack trace: $($_.ScriptStackTrace)"
        }

        Write-Output '{"continue": true, "suppressOutput": true}'
    }

    "stop-hook" {
        $HOOK_INPUT = Read-HookInput

        try {
            $d = $HOOK_INPUT | ConvertFrom-Json
            $aid = $d.agent_id

            if ($aid -and (Test-Path $ZELLIJ_PANE_MAP)) {
                Invoke-WithRetry -Block {
                    $map = Get-Content $ZELLIJ_PANE_MAP -Raw -Encoding UTF8 | ConvertFrom-Json
                    $paneId = $map.$aid

                    $newMap = [ordered]@{}
                    if ($map -is [PSCustomObject]) {
                        foreach ($prop in $map.PSObject.Properties) {
                            if ($prop.Name -ne $aid) {
                                $newMap[$prop.Name] = $prop.Value
                            }
                        }
                    }
                    $newMap | ConvertTo-Json | Set-Content -Path $ZELLIJ_PANE_MAP -Encoding UTF8
                }

                if ($paneId) {
                    Start-Job -ScriptBlock {
                        param($pid)
                        Start-Sleep -Seconds 5
                        & zellij action close-pane --pane-id $pid 2>&1 | Out-Null
                    } -ArgumentList $paneId | Out-Null
                }

                $monTmp = "$env:USERPROFILE\.claude\.mon-$aid.json"
                if (Test-Path $monTmp) { Remove-Item $monTmp -Force }
            }
        } catch {
            Write-DebugLog "[stop-hook] ERROR: $_"
        }

        Write-Output '{"continue": true, "suppressOutput": true}'
    }

    "list" {
        if (Test-Path $ZELLIJ_PANE_MAP) {
            Get-Content $ZELLIJ_PANE_MAP -Raw
        } else {
            Write-Output "{}"
        }
    }

    "clean" {
        "{}" | Set-Content -Path $ZELLIJ_PANE_MAP -Encoding UTF8
        Write-Output "Cleared pane map"
    }
}

