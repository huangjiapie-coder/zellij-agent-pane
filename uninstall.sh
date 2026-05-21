#!/bin/bash
# Zellij Agent Pane — 卸载脚本
# 用法: bash uninstall.sh [OPTIONS]
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.claude/scripts"
SETTINGS="$HOME/.claude/settings.json"
PYTHON_HELPER="$TARGET_DIR/libdeploy.py"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Flags
NON_INTERACTIVE=false

# ── Helper Functions ────────────────────────────────────────────────────────
log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_pass()  { echo -e "${GREEN}[PASS]${NC} $*"; }
log_fail()  { echo -e "${RED}[FAIL]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_step()  { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }
log_ok()    { echo -e "  ${GREEN}✓${NC} $*"; }
log_skip()  { echo -e "  ${YELLOW}−${NC} $*"; }

usage() {
    cat <<EOF
用法: bash uninstall.sh [OPTIONS]

Zellij Agent Pane — 卸载脚本

Options:
  -y, --yes          Non-interactive mode (skip confirmation prompt)
  --help             Show this help message

Examples:
  bash uninstall.sh          交互式卸载
  bash uninstall.sh -y       静默卸载
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes) NON_INTERACTIVE=true; shift ;;
            --help) usage ;;
            *) echo "Unknown option: $1"; usage ;;
        esac
    done
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-N}"
    if $NON_INTERACTIVE; then
        [[ "$default" == "Y" ]] && return 0 || return 1
    fi
    local hint
    [[ "$default" == "Y" ]] && hint="Y/n" || hint="y/N"
    read -r -p "$prompt [$hint]: " ans
    ans="${ans:-$default}"
    [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

run_python() {
    local helper="$PYTHON_HELPER"
    if [ ! -f "$helper" ]; then
        # Fall back to project dir
        helper="$SCRIPT_DIR/libdeploy.py"
        if [ ! -f "$helper" ]; then
            log_fail "libdeploy.py not found (may already be uninstalled)"
            return 1
        fi
    fi
    if command -v python3 &>/dev/null; then
        python3 "$helper" "$@"
    elif command -v python &>/dev/null; then
        python "$helper" "$@"
    else
        log_fail "Python 3 not found (neither python3 nor python commands available)"
        return 1
    fi
}

# ── Main ───────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"

    echo -e "${BOLD}${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║     Zellij Agent Pane — 卸载                     ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Check if anything is installed
    local anything_installed=false
    [ -f "$TARGET_DIR/zellij-agent-pane.sh" ] && anything_installed=true
    [ -f "$TARGET_DIR/zellij-monitor.py" ] && anything_installed=true
    [ -f "$TARGET_DIR/libdeploy.py" ] && anything_installed=true

    if ! $anything_installed; then
        log_info "未检测到 Zellij Agent Pane 安装，无需卸载"
        exit 0
    fi

    # Confirm
    echo ""
    log_warn "将移除以下组件:"
    [ -f "$TARGET_DIR/zellij-agent-pane.sh" ] && echo "  • $TARGET_DIR/zellij-agent-pane.sh"
    [ -f "$TARGET_DIR/zellij-monitor.py" ] && echo "  • $TARGET_DIR/zellij-monitor.py"
    [ -f "$TARGET_DIR/libdeploy.py" ] && echo "  • $TARGET_DIR/libdeploy.py"
    echo "  • $SETTINGS (hooks 配置将被移除)"
    [ -f "$HOME/.claude/zellij-pane-map.json" ] && echo "  • $HOME/.claude/zellij-pane-map.json"
    [ -f "$HOME/.claude/zellij-hooks-debug.log" ] && echo "  • $HOME/.claude/zellij-hooks-debug.log"
    echo ""

    if ! prompt_yes_no "确认卸载？" "N"; then
        log_info "卸载已取消"
        exit 0
    fi

    # 1. Backup settings.json
    log_step "Step 1/4 — 备份配置文件"
    if [ -f "$SETTINGS" ]; then
        local bak
        bak=$(run_python backup "$SETTINGS" 2>/dev/null || echo "")
        if [[ -n "$bak" ]]; then
            log_ok "已备份: $bak"
        else
            log_skip "跳过备份"
        fi
    fi
    echo ""

    # 2. Remove hooks from settings.json
    log_step "Step 2/4 — 移除 hooks 配置"
    if run_python remove-hooks "$SETTINGS" > /dev/null 2>&1; then
        log_ok "Zellij Agent Pane hooks 已从 settings.json 移除"
    else
        log_warn "无法自动移除 hooks（libdeploy.py 可能已卸载）"
        log_info "如需手动移除，请删除 $SETTINGS 中的 SubagentStart/SubagentStop 条目"
    fi
    echo ""

    # 3. Delete deployed files
    log_step "Step 3/4 — 删除已部署文件"

    local deleted_count=0
    for f in "zellij-agent-pane.sh" "zellij-monitor.py" "libdeploy.py" "doctor.sh" "doctor.ps1"; do
        if [ -f "$TARGET_DIR/$f" ]; then
            rm -f "$TARGET_DIR/$f"
            log_ok "已删除: $TARGET_DIR/$f"
            ((deleted_count++))
        fi
    done

    # Remove pane map
    if [ -f "$HOME/.claude/zellij-pane-map.json" ]; then
        rm -f "$HOME/.claude/zellij-pane-map.json"
        log_ok "已删除: $HOME/.claude/zellij-pane-map.json"
    fi

    # Remove debug log
    if [ -f "$HOME/.claude/zellij-hooks-debug.log" ]; then
        rm -f "$HOME/.claude/zellij-hooks-debug.log"
        log_ok "已删除: $HOME/.claude/zellij-hooks-debug.log"
    fi

    # Remove temp monitor files
    local temp_files
    temp_files=$(ls "$HOME/.claude"/.mon-*.json 2>/dev/null || true)
    if [[ -n "$temp_files" ]]; then
        rm -f "$HOME/.claude"/.mon-*.json
        log_ok "已清理监视器临时文件"
    fi

    # Remove scripts directory if empty
    if [ -d "$TARGET_DIR" ] && [ -z "$(ls -A "$TARGET_DIR" 2>/dev/null)" ]; then
        rmdir "$TARGET_DIR"
        log_ok "已删除空目录: $TARGET_DIR"
    fi

    if [[ $deleted_count -eq 0 ]]; then
        log_skip "没有找到已部署的文件"
    fi
    echo ""

    # 4. Summary
    log_step "Step 4/4 — 卸载完成"
    echo ""
    echo -e "  ${GREEN}${BOLD}✓ 卸载成功${NC}"
    echo ""
    echo "  ── 已移 ──"
    echo "    • 脚本文件 (zellij-agent-pane.sh, zellij-monitor.py, libdeploy.py)"
    echo "    • 运行时数据 (pane map, debug log)"
    echo "    • settings.json hooks 配置"
    echo ""
    echo "  ── 保留 ──"
    echo "    • settings.json 备份文件（如有需要可手动恢复）"
    echo "    • ~/.claude/ 目录中的其他配置"
    echo ""

    log_info "如需重新安装，请运行: bash deploy.sh"
    echo ""
    echo -e "\n${GREEN}${BOLD}按任意键退出...${NC}"
    read -r -n 1 -s
}

main "$@"