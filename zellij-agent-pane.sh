#!/bin/bash
# Zellij Agent Pane — Hook handler for Claude Code SubagentStart/SubagentStop
# Usage: zellij-agent-pane.sh {start-hook|stop-hook|list|clean|diagnose}

ZELLIJ_PANE_MAP="$HOME/.claude/zellij-pane-map.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_PY="$SCRIPT_DIR/zellij-monitor.py"
DEBUG_LOG="$HOME/.claude/zellij-hooks-debug.log"

# Auto-detect python command — new panes may not have python3 on PATH
PYTHON_CMD="python3"
if ! command -v python3 &>/dev/null; then
    if command -v python &>/dev/null; then
        PYTHON_CMD="python"
    fi
fi

# Response helpers — these write JSON to stdout for Claude Code hook protocol
respond_ok()   { echo '{"continue": true, "suppressOutput": true}'; exit 0; }
respond_err()  { echo "{\"continue\": true, \"suppressOutput\": false}"; echo "[Zellij Agent Pane] ERROR: $*" >&2; exit 0; }
respond_msg()  { echo "{\"continue\": true, \"suppressOutput\": false}"; echo "[Zellij Agent Pane] $*" >&2; exit 0; }

log_debug() { echo "[$(date '+%H:%M:%S')] $*" >> "$DEBUG_LOG" 2>&1; }

check_prereqs() {
    if ! command -v zellij &>/dev/null; then
        respond_err "zellij not found on PATH. Install zellij: https://zellij.dev"
    fi

    if ! zellij action dump 2>/dev/null | head -1 &>/dev/null; then
        respond_err "Not inside a zellij session. Start zellij first, then launch Claude Code inside it."
    fi

    if ! command -v "$PYTHON_CMD" &>/dev/null; then
        respond_err "Python ($PYTHON_CMD) not found. Install Python 3 to use agent pane monitoring."
    fi
}

case "$1" in
  start-hook)
    export HOOK_INPUT
    HOOK_INPUT=$(cat)
    log_debug "start-hook RAW: $HOOK_INPUT"

    # Quick prereq check (exits with error if not met)
    check_prereqs

    EXTRACTED=$($PYTHON_CMD -c "
import json, os, sys
d = json.loads(os.environ['HOOK_INPUT'])
aid = d.get('agent_id', '')
atp = d.get('agent_type', '')
tp = d.get('transcript_path', '')
sid = d.get('session_id', '')
sd = os.path.join(os.path.dirname(tp), sid, 'subagents') if tp and sid else ''
stp = os.path.join(sd, 'agent-' + aid + '.jsonl') if sd else ''

# Write temp metadata NOW while HOOK_INPUT encoding is pristine
if stp:
    os.makedirs(sd, exist_ok=True)
    mon_tmp = os.path.join(os.path.expanduser('~'), '.claude', '.mon-' + aid + '.json')
    with open(mon_tmp, 'w') as mf:
        json.dump({'path': stp, 'type': atp}, mf)

sys.stderr.write(f'[start-hook py] aid={aid} atp={atp} stp={stp}\\n')
print(f'{aid}|{atp}')
")

    AGENT_ID=$(echo "$EXTRACTED" | cut -d'|' -f1)
    AGENT_TYPE=$(echo "$EXTRACTED" | cut -d'|' -f2)
    log_debug "start-hook AGENT_ID=$AGENT_ID AGENT_TYPE=$AGENT_TYPE"

    if [ -z "$AGENT_ID" ]; then
        log_debug "start-hook ERROR: empty agent_id"
        respond_err "Could not extract agent_id from hook input."
    fi

    if [ ! -f "$MONITOR_PY" ]; then
        log_debug "start-hook ERROR: monitor not found at $MONITOR_PY"
        respond_err "Monitor script not found at $MONITOR_PY. Re-run deploy script."
    fi

    PANE_ID=$(zellij action new-pane --direction right --name "Agent: $AGENT_TYPE" -- $PYTHON_CMD "$MONITOR_PY" "$AGENT_ID" 2>>"$DEBUG_LOG" || echo "")
    log_debug "start-hook PANE_ID='$PANE_ID'"

    if [ -z "$PANE_ID" ]; then
        log_debug "start-hook ERROR: zellij new-pane failed"
        respond_err "Failed to create zellij pane. Is this a zellij session? (Run 'zellij' first, then launch Claude Code inside it)"
    fi

    # Persist mapping
    if [ -f "$ZELLIJ_PANE_MAP" ]; then MAP=$(cat "$ZELLIJ_PANE_MAP"); else MAP="{}"; fi
    NEW_MAP=$($PYTHON_CMD -c "import json,sys; d=json.load(sys.stdin); d['$AGENT_ID']='$PANE_ID'; json.dump(d,sys.stdout)" <<< "$MAP")
    echo "$NEW_MAP" > "$ZELLIJ_PANE_MAP"

    log_debug "start-hook OK: pane=$PANE_ID agent=$AGENT_ID"
    respond_ok
    ;;

  stop-hook)
    export HOOK_INPUT
    HOOK_INPUT=$(cat)
    log_debug "stop-hook RAW: $HOOK_INPUT"

    AGENT_ID=$($PYTHON_CMD -c "
import json, os
d = json.loads(os.environ['HOOK_INPUT'])
print(d.get('agent_id', ''))
")

    if [ -n "$AGENT_ID" ] && [ -f "$ZELLIJ_PANE_MAP" ]; then
      MAP=$(cat "$ZELLIJ_PANE_MAP")
      PANE_ID=$($PYTHON_CMD -c "import json,sys; print(json.load(sys.stdin).get('$AGENT_ID',''))" <<< "$MAP")
      NEW_MAP=$($PYTHON_CMD -c "import json,sys; d=json.load(sys.stdin); d.pop('$AGENT_ID',None); json.dump(d,sys.stdout)" <<< "$MAP")
      echo "$NEW_MAP" > "$ZELLIJ_PANE_MAP"
      if [ -n "$PANE_ID" ]; then
        log_debug "stop-hook closing pane=$PANE_ID agent=$AGENT_ID"
        (sleep 5 && zellij action close-pane --pane-id "$PANE_ID" 2>/dev/null || true) &
      fi
    fi

    respond_ok
    ;;

  list)
    if [ -f "$ZELLIJ_PANE_MAP" ]; then cat "$ZELLIJ_PANE_MAP"
    else echo "{}"
    fi
    ;;

  clean)
    echo "{}" > "$ZELLIJ_PANE_MAP"
    echo "Cleared pane map"
    ;;

  diagnose)
    echo "=== Zellij Agent Pane Diagnostics ==="
    echo ""

    # 1. Check script location
    echo "[1] Script location: $SCRIPT_DIR"
    for f in "zellij-agent-pane.sh" "zellij-monitor.py"; do
      if [ -f "$SCRIPT_DIR/$f" ]; then echo "  ✓ $f found"; else echo "  ✗ $f MISSING"; fi
    done

    # 2. Check dependencies
    echo ""
    echo "[2] Dependencies:"
    echo "  Python command: $PYTHON_CMD"
    if command -v zellij &>/dev/null; then
      echo "  ✓ zellij: $(zellij --version 2>&1 | head -1)"
    else
      echo "  ✗ zellij: NOT FOUND on PATH"
    fi
    if command -v python3 &>/dev/null; then
      echo "  ✓ python3: $(python3 --version 2>&1)"
    elif command -v python &>/dev/null; then
      echo "  ✓ python: $(python --version 2>&1)"
    else
      echo "  ✗ python3: NOT FOUND"
    fi
    if command -v bash &>/dev/null; then
      echo "  ✓ bash: $(bash --version 2>&1 | head -1)"
    else
      echo "  ✗ bash: NOT FOUND (hooks will fail)"
    fi

    # 3. Zellij session check
    echo ""
    echo "[3] Zellij session:"
    if zellij action dump 2>/dev/null | head -1 &>/dev/null; then
      echo "  ✓ Running inside a zellij session"
      echo "  Active panes:"
      zellij action list-panes 2>/dev/null || echo "  (cannot list panes)"
    else
      echo "  ✗ NOT in a zellij session"
      echo "  → Start zellij first:  zellij"
    fi

    # 4. Settings check
    echo ""
    echo "[4] Claude Code hooks config:"
    SETTINGS_FILE="$HOME/.claude/settings.json"
    if [ -f "$SETTINGS_FILE" ]; then
      echo "  ✓ settings.json exists: $SETTINGS_FILE"
      if command -v "$PYTHON_CMD" &>/dev/null; then
        HOOK_COUNT=$($PYTHON_CMD << 'PYEOF' 2>/dev/null
import json, os
path = os.path.expanduser("~/.claude/settings.json")
try:
    d = json.load(open(path, encoding="utf-8-sig"))
except:
    print("parse_error")
    exit(0)
h = d.get("hooks", {})
total = sum(1 for ev in ("SubagentStart","SubagentStop") for m in h.get(ev,[]) for _ in m.get("hooks",[]))
print(total)
PYEOF
)
            if [ "$HOOK_COUNT" != "parse_error" ] && [ "$HOOK_COUNT" -ge 1 ]; then
          echo "  ✓ $HOOK_COUNT hook entr(ies) configured"
        else
          echo "  ✗ No hooks found or settings.json is invalid"
        fi
      fi
    else
      echo "  ✗ settings.json NOT FOUND at $SETTINGS_FILE"
      echo "  → Run deploy script to configure hooks"
    fi

    # 5. Pane map
    echo ""
    echo "[5] Pane map ($ZELLIJ_PANE_MAP):"
    if [ -f "$ZELLIJ_PANE_MAP" ]; then
      cat "$ZELLIJ_PANE_MAP" | head -5
    else
      echo "  (empty — no active agent panes)"
    fi

    # 6. Debug log
    echo ""
    echo "[6] Debug log ($DEBUG_LOG):"
    if [ -f "$DEBUG_LOG" ]; then
      LINES=$(wc -l < "$DEBUG_LOG")
      echo "  $LINES lines written"
      echo "  Last 5 entries:"
      tail -5 "$DEBUG_LOG" | sed 's/^/  /'
    else
      echo "  (no debug log)"
    fi

    echo ""
    echo "=== End of diagnostics ==="
    ;;

  *)
    echo "Usage: $0 {start-hook|stop-hook|list|clean|diagnose}"
    exit 1
    ;;
esac