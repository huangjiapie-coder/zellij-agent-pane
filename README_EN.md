# Zellij Agent Pane

Automatically creates a zellij pane on the right side when Claude Code spawns sub-agents (team mode `/agents`), showing real-time agent output. Closes the pane automatically when the agent finishes.

---

## Quick Start — One-Click Deploy

**On any machine**, copy the project directory and run (choose one based on your system):

### Option 1: Windows Recommended (Most Convenient)

Double-click or run from command line:

```cmd
deploy.bat
```

Auto-detects bash availability:
- **bash available** → calls `bash deploy.sh`
- **bash not available** → calls `powershell deploy.ps1`

### Option 2: PowerShell (Standalone)

No Git Bash, WSL, or MSYS2 required — PowerShell comes with every Windows system:

```powershell
powershell -ExecutionPolicy Bypass -File deploy.ps1
```

Silent install:

```powershell
powershell -ExecutionPolicy Bypass -File deploy.ps1 -Yes
```

Dry-run mode:

```powershell
powershell -ExecutionPolicy Bypass -File deploy.ps1 -DryRun
```

> **Note**: `-ExecutionPolicy Bypass` temporarily bypasses execution restrictions.

### Option 3: Bash (requires Git Bash, WSL, or MSYS2)

```bash
bash deploy.sh
```

Options:

```bash
bash deploy.sh -y           # Silent mode
bash deploy.sh --dry-run    # Preview mode
bash deploy.sh --help       # Show help
```

### What the deploy script does

| Feature | Description |
|---------|-------------|
| OS Detection | Auto-detect MSYS2/Windows, Linux, macOS, WSL |
| Dependency Check | Verify zellij, Python 3, bash, Claude Code |
| Install Guidance | Show platform-specific install commands for missing deps |
| Config Merge | Idempotent merge hooks into existing `settings.json` (no duplicates) |
| Auto Backup | Timestamped backup before modifying `settings.json` |
| Deploy Verification | Check file integrity, JSON validity, hook script test |
| Interactive/Silent | Prompts in interactive mode; `-y` for automation |
| Dry-Run | `--dry-run` previews everything without modifying files |
| **Platform-aware** | **Windows uses PowerShell hooks, non-Windows uses bash hooks** |

---

## Requirements

| Dependency | Required | Check | Install (Windows/MSYS2) |
|------------|----------|-------|------------------------|
| [zellij](https://zellij.dev/) | Yes | `zellij --version` | `winget install Zellij.Zellij` or `scoop install zellij` |
| Python 3 | Yes | `python3 --version` | `pacman -S python` or `winget install Python.Python.3` |
| bash | Optional | `bash --version` | Bundled with MSYS2 |
| Claude Code CLI | No (warn) | `claude --version` | `npm install -g @anthropic-ai/claude-code` |

> **Note**: Claude Code must run inside a zellij session for the pane feature to work.

---

## Diagnostic Tool

If sub-agent panes are not appearing after deployment, run the diagnostic tool:

```bash
bash ~/.claude/scripts/doctor.sh
```

Or (PowerShell):

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE/.claude/scripts/doctor.ps1"
```

The diagnostic checks:
1. Script files installed
2. Dependencies (zellij, Python 3, bash)
3. Are you inside a zellij session?
4. Claude Code hooks configuration
5. Debug log errors
6. Pane map status

You can also run from the project directory:

```bash
bash doctor.sh
powershell -ExecutionPolicy Bypass -File doctor.ps1
```

---

## Troubleshooting

### Sub-agent panes not appearing

1. **Run inside zellij**: Start `zellij` first, then launch Claude Code inside the zellij session
2. **Restart Claude Code**: After changing settings.json, Claude Code needs a restart
3. **Run diagnostics**: `bash doctor.sh` or `doctor.ps1`
4. **Check debug log**: `cat ~/.claude/zellij-hooks-debug.log`

---

## Uninstall

### Windows Recommended

Double-click or run from command line:

```cmd
uninstall.bat
```

### PowerShell (Standalone)

```powershell
powershell -ExecutionPolicy Bypass -File uninstall.ps1
```

Silent uninstall:

```powershell
powershell -ExecutionPolicy Bypass -File uninstall.ps1 -Yes
```

### Bash (requires Git Bash, WSL, or MSYS2)

```bash
bash uninstall.sh
```

Silent uninstall:

```bash
bash uninstall.sh -y
```

The uninstall script:
1. Backup `~/.claude/settings.json`
2. Remove Zellij Agent Pane hooks (preserves hooks from other tools)
3. Delete deployed script files
4. Clean up runtime data (pane map, debug log, temp files)

---

## Files

| File | Purpose |
|------|---------|
| `deploy.bat` | Windows unified launcher (auto selects bash or PowerShell) |
| `uninstall.bat` | Windows unified uninstaller (auto selects bash or PowerShell) |
| `deploy.sh` | One-click deploy script (Bash, env check + auto install) |
| `deploy.ps1` | One-click deploy script (PowerShell, env check + auto install) |
| `uninstall.sh` | Uninstall script (Bash) |
| `uninstall.ps1` | Uninstall script (PowerShell) |
| `doctor.sh` | Diagnostic tool (Bash, troubleshoot sub-agent pane issues) |
| `doctor.ps1` | Diagnostic tool (PowerShell, troubleshoot sub-agent pane issues) |
| `libdeploy.py` | Deployment library (**Single source of truth**: OS detection, dep check, JSON merge, hooks config) |
| `zellij-agent-pane.sh` | Hook script (bash): handles SubagentStart/SubagentStop events, manages zellij panes |
| `zellij-agent-pane.ps1` | Hook script (PowerShell): handles SubagentStart/SubagentStop events, manages zellij panes |
| `zellij-monitor.py` | Watches agent JSONL transcript and renders formatted output in the pane |
| `zellij-claude-code-pane-progress.md` | Dev notes, architecture, and troubleshooting history |

---

## Manual Installation

If you prefer not to use the deploy script:

```bash
# 1. Copy scripts
mkdir -p ~/.claude/scripts
cp zellij-agent-pane.sh ~/.claude/scripts/
cp zellij-agent-pane.ps1 ~/.claude/scripts/  # Windows also needs
cp zellij-monitor.py ~/.claude/scripts/
cp libdeploy.py ~/.claude/scripts/
```

Edit `~/.claude/settings.json`:

**Windows (PowerShell hooks):**
```json
{
  "hooks": {
    "SubagentStart": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "powershell -ExecutionPolicy Bypass -File \"$env:USERPROFILE\\.claude\\scripts\\zellij-agent-pane.ps1\" start-hook",
            "timeout": 30
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "powershell -ExecutionPolicy Bypass -File \"$env:USERPROFILE\\.claude\\scripts\\zellij-agent-pane.ps1\" stop-hook",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

**Non-Windows (bash hooks):**
```json
{
  "hooks": {
    "SubagentStart": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/scripts/zellij-agent-pane.sh start-hook",
            "timeout": 30
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/scripts/zellij-agent-pane.sh stop-hook",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

---

## Test it

Launch Claude Code inside a zellij session, then run:

```
/agents
```

A new pane will appear on the right showing the sub-agent's output in real time.

---

## Management Commands

**PowerShell (Windows):**
| Command | Description |
|---------|-------------|
| `powershell -File ~/.claude/scripts/zellij-agent-pane.ps1 list` | Show current agent → pane map |
| `powershell -File ~/.claude/scripts/zellij-agent-pane.ps1 clean` | Clear pane map |

**Bash (non-Windows):**
| Command | Description |
|---------|-------------|
| `bash ~/.claude/scripts/zellij-agent-pane.sh start-hook` | Called automatically by SubagentStart hook |
| `bash ~/.claude/scripts/zellij-agent-pane.sh stop-hook` | Called automatically by SubagentStop hook |
| `bash ~/.claude/scripts/zellij-agent-pane.sh list` | Show current agent → pane map |
| `bash ~/.claude/scripts/zellij-agent-pane.sh clean` | Clear pane map |

---

## Architecture Notes

### Single Source of Truth

All hooks configuration is centralized in `libdeploy.py`, auto-selected by OS:
- `win32`: PowerShell hooks
- Others (linux/macos/msys2/wsl): bash hooks

This avoids configuration desync issues.

### Notes

- **Must** run inside a zellij session — `zellij action new-pane` will fail otherwise
- Chinese path handling: JSON payload is passed via `HOOK_INPUT` env var to avoid MSYS2/bash Unicode corruption
- Sub-agent transcript path: `dirname(main_transcript)/{session_id}/subagents/agent-{id}.jsonl`
- Pane auto-closes 5 seconds after the agent stops
- The pane-map file (`~/.claude/zellij-pane-map.json`) has no concurrency lock — avoid launching many agents simultaneously
