#!/usr/bin/env python3
"""Zellij Agent Pane — Deployment Library (stdlib only)

Provides CLI commands used by deploy.sh and uninstall.sh:

  detect-os            Print OS identifier (msys2/linux/macos/wsl/unknown)
  check-deps           JSON dependency check results
  read-settings PATH   Read and validate settings.json
  merge-hooks SPATH    Merge hooks into settings.json (idempotent)
  backup PATH          Create timestamped .bak copy, print backup path
  restore SPATH BPATH  Restore settings from backup
  remove-hooks SPATH   Remove matching hooks from settings.json
  verify-install DIR   Verify deployed files exist
  generate-hooks       Print hooks JSON config (single source of truth)
"""

import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path


# ── Constants ────────────────────────────────────────────────────────────────

REQUIRED_FILES = [
    "zellij-agent-pane.sh",
    "zellij-agent-pane.ps1",
    "zellij-monitor.py",
    "doctor.sh",
    "doctor.ps1",
]

# Hooks config by OS - Single Source of Truth
HOOKS_CONFIG = {
    # Windows native (win32) - use PowerShell
    "win32": {
        "SubagentStart": [
            {
                "matcher": "*",
                "hooks": [
                    {
                        "type": "command",
                        "command": "powershell -ExecutionPolicy Bypass -File \"$env:USERPROFILE\\.claude\\scripts\\zellij-agent-pane.ps1\" start-hook",
                        "timeout": 30,
                    }
                ],
            }
        ],
        "SubagentStop": [
            {
                "matcher": "*",
                "hooks": [
                    {
                        "type": "command",
                        "command": "powershell -ExecutionPolicy Bypass -File \"$env:USERPROFILE\\.claude\\scripts\\zellij-agent-pane.ps1\" stop-hook",
                        "timeout": 30,
                    }
                ],
            }
        ],
    },
    # Non-Windows (linux/macos/msys2/wsl) - use bash
    "default": {
        "SubagentStart": [
            {
                "matcher": "*",
                "hooks": [
                    {
                        "type": "command",
                        "command": "bash ~/.claude/scripts/zellij-agent-pane.sh start-hook",
                        "timeout": 30,
                    }
                ],
            }
        ],
        "SubagentStop": [
            {
                "matcher": "*",
                "hooks": [
                    {
                        "type": "command",
                        "command": "bash ~/.claude/scripts/zellij-agent-pane.sh stop-hook",
                        "timeout": 30,
                    }
                ],
            }
        ],
    },
}

# Hook commands to match for removal - by OS
HOOK_COMMANDS = {
    "win32": {
        "powershell -ExecutionPolicy Bypass -File \"$env:USERPROFILE\\.claude\\scripts\\zellij-agent-pane.ps1\" start-hook",
        "powershell -ExecutionPolicy Bypass -File \"$env:USERPROFILE\\.claude\\scripts\\zellij-agent-pane.ps1\" stop-hook",
    },
    "default": {
        "bash ~/.claude/scripts/zellij-agent-pane.sh start-hook",
        "bash ~/.claude/scripts/zellij-agent-pane.sh stop-hook",
    },
}


# ── OS Detection ────────────────────────────────────────────────────────────

def detect_os() -> str:
    """Return one of: msys2/linux/macos/wsl/win32/unknown."""
    platform = sys.platform.lower()

    # MSYS2 / Cygwin on Windows
    if platform == "win32" or platform == "cygwin":
        if os.environ.get("MSYSTEM") in ("MINGW64", "MINGW32", "MSYS", "UCRT64", "CLANG64"):
            return "msys2"
        return "win32"

    # WSL
    if platform.startswith("linux"):
        try:
            r = subprocess.run(
                ["uname", "-r"], capture_output=True, text=True, timeout=5
            )
            if "microsoft" in r.stdout.lower() or "wsl" in r.stdout.lower():
                return "wsl"
        except Exception:
            pass
        return "linux"

    if platform == "darwin":
        return "macos"

    return "unknown"


def get_hooks_config_for_os(os_name: str):
    """Get hooks config for the given OS."""
    if os_name == "win32":
        return HOOKS_CONFIG["win32"]
    return HOOKS_CONFIG["default"]


def get_hook_commands_for_os(os_name: str):
    """Get set of hook commands for the given OS."""
    if os_name == "win32":
        return HOOK_COMMANDS["win32"]
    return HOOK_COMMANDS["default"]


def get_install_guide(dep: str, os_name: str) -> str:
    """Return platform-specific install command for a dependency."""
    guides = {
        "zellij": {
            "msys2": "winget install Zellij.Zellij or scoop install zellij or https://github.com/zellij-org/zellij/releases",
            "win32": "winget install Zellij.Zellij or scoop install zellij",
            "wsl": "cargo install zellij or sudo apt install zellij (if available)",
            "linux": "cargo install zellij or sudo apt install zellij or sudo pacman -S zellij",
            "macos": "brew install zellij",
        },
        "python3": {
            "msys2": "pacman -S python or winget install Python.Python.3",
            "win32": "winget install Python.Python.3 or https://python.org/downloads",
            "wsl": "sudo apt install python3",
            "linux": "sudo apt install python3 or sudo pacman -S python",
            "macos": "brew install python@3",
        },
        "claude": {
            "msys2": "npm install -g @anthropic-ai/claude-code",
            "win32": "npm install -g @anthropic-ai/claude-code",
            "wsl": "npm install -g @anthropic-ai/claude-code",
            "linux": "npm install -g @anthropic-ai/claude-code",
            "macos": "npm install -g @anthropic-ai/claude-code",
        },
    }
    return guides.get(dep, {}).get(os_name, f"Please install {dep} manually")


# ── Dependency Checking ────────────────────────────────────────────────────

def _check_exe(name: str, version_flag: str = "--version") -> dict:
    """Check an executable is on PATH and return its version."""
    exe_path = shutil.which(name)
    if not exe_path:
        # On MSYS2, python3 might be just "python"
        if name == "python3":
            exe_path = shutil.which("python")
        if not exe_path:
            return {"ok": False, "version": None, "path": None}
    try:
        r = subprocess.run(
            [exe_path, version_flag], capture_output=True, text=True, timeout=10
        )
        version = (r.stdout or r.stderr or "").strip().split("\n")[0]
        return {"ok": True, "version": version or "found", "path": exe_path}
    except Exception:
        return {"ok": True, "version": "found", "path": exe_path}


def check_deps() -> dict:
    """Check all dependencies. Returns structured results dict."""
    os_name = detect_os()
    results = {}

    # Zellij — required
    z = _check_exe("zellij")
    results["zellij"] = z

    # Python 3 — required; also verify json module
    p = _check_exe("python3")
    if p["ok"]:
        try:
            r = subprocess.run(
                [p["path"], "-c", "import json; print('.'.join(map(str, __import__('sys').version_info[:3])))"],
                capture_output=True, text=True, timeout=10
            )
            p["version"] = r.stdout.strip() or p["version"]
        except Exception:
            pass
    results["python3"] = p

    # Bash — check (may not be present on Windows)
    b = _check_exe("bash")
    results["bash"] = b

    # Claude Code — soft dependency
    c = _check_exe("claude")
    if not c["ok"]:
        c = _check_exe("claude-code")
    results["claude"] = c

    # Attach install guide for missing deps
    for dep, result in results.items():
        if not result["ok"]:
            result["install_hint"] = get_install_guide(dep, os_name)

    results["_os"] = os_name
    return results


# ── JSON / Settings Operations ─────────────────────────────────────────────────

def read_settings(path: str) -> dict:
    """Read and parse settings.json. Raise on error."""
    p = Path(path)
    if not p.exists():
        return {}
    raw = p.read_text(encoding="utf-8-sig")
    return json.loads(raw)


def write_settings(path: str, data: dict) -> None:
    """Write settings.json with pretty formatting."""
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(
        json.dumps(data, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def backup(path: str) -> str | None:
    """Create timestamped .bak copy. Return backup path or None."""
    p = Path(path)
    if not p.exists():
        return None
    ts = time.strftime("%Y%m%d%H%M%S")
    bak = p.with_name(f"{p.name}.bak.{ts}")
    shutil.copy2(p, bak)
    return str(bak)


def restore(path: str, backup_path: str) -> bool:
    """Restore file from backup. Return success."""
    try:
        shutil.copy2(backup_path, path)
        return True
    except Exception:
        return False


def generate_hooks(os_override: str | None = None) -> str:
    """Return the hooks JSON config as a JSON string."""
    os_name = os_override or detect_os()
    config = get_hooks_config_for_os(os_name)
    return json.dumps(config, indent=2, ensure_ascii=False)


def merge_hooks(settings_path: str, os_override: str | None = None) -> dict:
    """Merge hooks into settings.json idempotently.

    Reads existing settings, injects hooks.SubagentStart and
    hooks.SubagentStop entries. Skips duplicates by matching the
    ``command`` string inside each hook entry.

    Returns a dict with keys:
      - merged: bool — whether any change was made
      - hook_count: int — total hook entries after merge
      - error: str | None
    """
    result = {"merged": False, "hook_count": 0, "error": None}
    os_name = os_override or detect_os()
    hooks_config = get_hooks_config_for_os(os_name)
    hook_commands = get_hook_commands_for_os(os_name)

    try:
        settings = read_settings(settings_path)
    except json.JSONDecodeError as e:
        result["error"] = f"settings.json is not valid JSON: {e}"
        return result
    except Exception as e:
        result["error"] = f"Cannot read settings.json: {e}"
        return result

    # Ensure "hooks" key exists
    if "hooks" not in settings:
        settings["hooks"] = {}
        result["merged"] = True

    hooks = settings["hooks"]

    # For each hook event (SubagentStart, SubagentStop), merge
    for event_name, event_config in hooks_config.items():
        existing_matchers = hooks.get(event_name, [])

        # Build set of known 'command' strings already configured
        existing_commands: set[str] = set()
        for matcher_entry in existing_matchers:
            for h in matcher_entry.get("hooks", []):
                cmd = h.get("command", "")
                if cmd:
                    existing_commands.add(cmd)

        # Check if our commands are already present
        new_matcher = event_config[0]
        our_commands = {
            h["command"] for h in new_matcher.get("hooks", []) if h.get("command")
        }

        if our_commands - existing_commands:
            # Need to add; append the whole matcher entry
            hooks[event_name] = existing_matchers + [new_matcher]
            result["merged"] = True
        elif event_name not in hooks or not hooks[event_name]:
            # Event key exists but is empty
            hooks[event_name] = [new_matcher]
            result["merged"] = True

    # Count total hook entries across all events
    total = 0
    for ev in ("SubagentStart", "SubagentStop"):
        for m in hooks.get(ev, []):
            total += len(m.get("hooks", []))
    result["hook_count"] = total

    # Write back if changed
    if result["merged"]:
        try:
            write_settings(settings_path, settings)
        except Exception as e:
            result["error"] = f"Cannot write settings.json: {e}"

    return result


def remove_hooks(settings_path: str, os_override: str | None = None) -> dict:
    """Remove matching hooks from settings.json.

    Returns dict with keys:
      - removed: bool — whether hooks were removed
      - hook_count: int — remaining hooks after removal
      - error: str | None
    """
    result = {"removed": False, "hook_count": 0, "error": None}
    os_name = os_override or detect_os()
    hook_commands = get_hook_commands_for_os(os_name)

    try:
        settings = read_settings(settings_path)
    except json.JSONDecodeError as e:
        result["error"] = f"settings.json is not valid JSON: {e}"
        return result
    except Exception as e:
        result["error"] = f"Cannot read settings.json: {e}"
        return result

    if "hooks" not in settings:
        return result

    hooks = settings["hooks"]
    changed = False

    for event_name in ("SubagentStart", "SubagentStop"):
        matchers = hooks.get(event_name, [])
        if not matchers:
            continue

        new_matchers = []
        for matcher_entry in matchers:
            orig_hooks = matcher_entry.get("hooks", [])
            filtered = [h for h in orig_hooks if h.get("command", "") not in hook_commands]
            if len(filtered) != len(orig_hooks):
                changed = True
            if filtered:
                new_matchers.append({**matcher_entry, "hooks": filtered})

        if new_matchers:
            hooks[event_name] = new_matchers
        else:
            # All matchers for this event were removed
            del hooks[event_name]
            changed = True

    # If hooks dict is now empty, remove the key entirely
    if not hooks:
        del settings["hooks"]
        changed = True

    result["removed"] = changed

    # Count remaining hooks
    if "hooks" in settings:
        total = 0
        for ev in ("SubagentStart", "SubagentStop"):
            for m in settings["hooks"].get(ev, []):
                total += len(m.get("hooks", []))
        result["hook_count"] = total

    if changed:
        try:
            write_settings(settings_path, settings)
        except Exception as e:
            result["error"] = f"Cannot write settings.json: {e}"

    return result


# ── Verification ────────────────────────────────────────────────────────────

def verify_install(target_dir: str) -> dict:
    """Verify all required files exist in target directory.

    Returns dict with:
      - all_ok: bool
      - files: list of {name, exists, executable}
      - missing: list of missing filenames
    """
    d = Path(target_dir)
    files = []
    missing = []

    for fname in REQUIRED_FILES:
        fp = d / fname
        exists = fp.is_file()
        executable = os.access(fp, os.X_OK) if exists else False
        entry = {"name": fname, "exists": exists, "executable": executable}
        files.append(entry)
        if not exists:
            missing.append(fname)

    return {"all_ok": len(missing) == 0, "files": files, "missing": missing}


# ── CLI Dispatch ───────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <command> [args...]", file=sys.stderr)
        print(f"Commands: detect-os, check-deps, read-settings, merge-hooks,", file=sys.stderr)
        print(f"          backup, restore, remove-hooks, verify-install, generate-hooks", file=sys.stderr)
        sys.exit(1)

    command = sys.argv[1]

    if command == "detect-os":
        print(detect_os())

    elif command == "check-deps":
        deps = check_deps()
        print(json.dumps(deps, indent=2, ensure_ascii=False))

    elif command == "read-settings":
        if len(sys.argv) < 3:
            print("Usage: read-settings <path>", file=sys.stderr)
            sys.exit(1)
        try:
            settings = read_settings(sys.argv[2])
            print(json.dumps(settings, indent=2, ensure_ascii=False))
        except Exception as e:
            print(f"ERROR: {e}", file=sys.stderr)
            sys.exit(1)

    elif command == "merge-hooks":
        if len(sys.argv) < 3:
            print("Usage: merge-hooks <settings_path> [os_override]", file=sys.stderr)
            sys.exit(1)
        os_override = sys.argv[3] if len(sys.argv) > 3 else None
        result = merge_hooks(sys.argv[2], os_override)
        print(json.dumps(result, ensure_ascii=False))

    elif command == "backup":
        if len(sys.argv) < 3:
            print("Usage: backup <path>", file=sys.stderr)
            sys.exit(1)
        bak = backup(sys.argv[2])
        if bak:
            print(bak)
        else:
            print("")

    elif command == "restore":
        if len(sys.argv) < 4:
            print("Usage: restore <path> <backup_path>", file=sys.stderr)
            sys.exit(1)
        ok = restore(sys.argv[2], sys.argv[3])
        print(json.dumps({"ok": ok}))

    elif command == "remove-hooks":
        if len(sys.argv) < 3:
            print("Usage: remove-hooks <settings_path> [os_override]", file=sys.stderr)
            sys.exit(1)
        os_override = sys.argv[3] if len(sys.argv) > 3 else None
        result = remove_hooks(sys.argv[2], os_override)
        print(json.dumps(result, ensure_ascii=False))

    elif command == "verify-install":
        if len(sys.argv) < 3:
            print("Usage: verify-install <target_dir>", file=sys.stderr)
            sys.exit(1)
        result = verify_install(sys.argv[2])
        print(json.dumps(result, indent=2, ensure_ascii=False))

    elif command == "generate-hooks":
        os_override = sys.argv[2] if len(sys.argv) > 2 else None
        print(generate_hooks(os_override))

    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
