#!/bin/bash
# Zellij Agent Pane — 诊断脚本
# 检查环境、配置、依赖是否就绪
# 用法: bash doctor.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.claude/scripts"
SETTINGS="$HOME/.claude/settings.json"
DEBUG_LOG="$HOME/.claude/zellij-hooks-debug.log"
PANE_MAP="$HOME/.claude/zellij-pane-map.json"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log_pass() { echo -e "  ${GREEN}✓${NC} $*"; }
log_fail() { echo -e "  ${RED}✗${NC} $*"; }
log_warn() { echo -e "  ${YELLOW}⚠${NC} $*"; }
log_info() { echo -e "  ${BLUE}→${NC} $*"; }

echo -e "${BOLD}${BLUE}=== Zellij Agent Pane — 诊断工具 ===${NC}"
echo ""

# 1. Script files
echo -e "${BOLD}[1] 脚本文件${NC}"
if [ -f "$TARGET_DIR/zellij-agent-pane.sh" ]; then
  log_pass "zellij-agent-pane.sh 已安装"
else
  log_fail "zellij-agent-pane.sh 未安装"
  log_info "运行部署脚本: bash $SCRIPT_DIR/deploy.sh"
fi
if [ -f "$TARGET_DIR/zellij-monitor.py" ]; then
  log_pass "zellij-monitor.py 已安装"
else
  log_fail "zellij-monitor.py 未安装"
fi

# 2. Dependencies
echo ""
echo -e "${BOLD}[2] 依赖检查${NC}"
DEPS_OK=true

if command -v zellij &>/dev/null; then
  log_pass "zellij: $(zellij --version 2>&1 | head -1)"
else
  log_fail "zellij: 未安装"
  log_info "安装方法: winget install Zellij.Zellij 或 brew install zellij"
  DEPS_OK=false
fi

if command -v python3 &>/dev/null; then
  log_pass "python3: $(python3 --version 2>&1)"
elif command -v python &>/dev/null; then
  log_pass "python: $(python --version 2>&1)"
else
  log_fail "python3: 未安装"
  log_info "安装方法: winget install Python.Python.3 或 https://python.org"
  DEPS_OK=false
fi

if command -v bash &>/dev/null; then
  log_pass "bash: $(bash --version 2>&1 | head -1)"
else
  log_fail "bash: 未安装"
  log_info "安装方法: https://git-scm.com (Git Bash)"
  DEPS_OK=false
fi

# 3. Zellij session
echo ""
echo -e "${BOLD}[3] Zellij 会话${NC}"
if [ -n "${ZELLIJ_SESSION_NAME:-}" ]; then
  log_pass "检测到 zellij 会话: $ZELLIJ_SESSION_NAME"
elif zellij action dump 2>/dev/null | head -1 &>/dev/null; then
  log_pass "在 zellij 会话中运行"
else
  log_fail "未在 zellij 会话中运行"
  log_info "请先启动 zellij, 然后在 zellij 中启动 Claude Code"
  log_info "→ zellij"
fi

# 4. Settings hooks
echo ""
echo -e "${BOLD}[4] Claude Code Hooks 配置${NC}"
if [ ! -f "$SETTINGS" ]; then
  log_fail "settings.json 不存在: $SETTINGS"
  log_info "运行 bash deploy.sh 部署"
elif command -v python3 &>/dev/null; then
  # Extract hook info (use heredoc to avoid MSYS2 path corruption)
  HOOK_COUNT=$(python3 << 'PYEOF'
import json, os
path = os.path.expanduser("~/.claude/settings.json")
try:
    with open(path, encoding="utf-8-sig") as f:
        d = json.load(f)
except:
    print("total=0")
    exit(0)
h = d.get("hooks", {})
total = 0
for ev in ("SubagentStart", "SubagentStop"):
    for m in h.get(ev, []):
        total += len(m.get("hooks", []))
        for hook in m.get("hooks", []):
            cmd = hook.get("command", "")
            if "zellij-agent-pane" in cmd:
                print(f"  OK: {cmd}")
print(f"total={total}")
PYEOF
)
  if echo "$HOOK_COUNT" | grep -q "total=0"; then
    log_fail "未找到 Zellij Agent Pane 的 hooks 配置"
    log_info "运行 bash deploy.sh 部署"
  else
    log_pass "Hooks 配置正常"
    echo "$HOOK_COUNT" | while IFS= read -r line; do
      if [[ "$line" == total=* ]]; then
        log_info "共 ${line#total=} 个 hook 条目"
      else
        log_info "$line"
      fi
    done
  fi
fi

# 5. Debug log
echo ""
echo -e "${BOLD}[5] 调试日志${NC}"
if [ -f "$DEBUG_LOG" ]; then
  LINES=$(wc -l < "$DEBUG_LOG" 2>/dev/null || echo 0)
  log_pass "调试日志存在 ($LINES 行)"
  # Check for errors in recent entries
  ERRORS=$(grep -ci "error" "$DEBUG_LOG" 2>/dev/null || echo 0)
  if [ "$ERRORS" -gt 0 ] 2>/dev/null; then
    log_warn "发现 $ERRORS 条错误/警告"
    log_info "最后 10 行:"
    tail -10 "$DEBUG_LOG" | while IFS= read -r line; do
      echo "    $line"
    done
  fi
else
  log_info "调试日志不存在 (尚未触发过 hook)"
fi

# 6. Pane map
echo ""
echo -e "${BOLD}[6] Pane 映射${NC}"
if [ -f "$PANE_MAP" ]; then
  COUNT=$(python3 << 'PYEOF'
import json, os
path = os.path.expanduser("~/.claude/zellij-pane-map.json")
try:
    print(len(json.load(open(path))))
except:
    print("?")
PYEOF
)
  log_pass "Pane 映射存在 ($COUNT 个 agent)"
else
  log_info "Pane 映射不存在 (尚未启动过 agent)"
fi

# Summary
echo ""
echo -e "${BOLD}${BLUE}=== 诊断完成 ===${NC}"
if $DEPS_OK; then
  echo -e "${GREEN}所有必要依赖已就绪。${NC}"
else
  echo -e "${RED}部分依赖缺失。请安装后重试。${NC}"
fi
echo ""
echo "如果问题仍然存在, 请检查:"
echo "  1. zellij 是否正在运行"
echo "  2. ~/.claude/settings.json 中是否有正确的 hooks 配置"
echo "  3. Claude Code 是否在 zellij 会话中启动 (不是先启动 Claude Code 再进入 zellij)"