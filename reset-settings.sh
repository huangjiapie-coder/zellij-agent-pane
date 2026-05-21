#!/bin/bash
# Zellij Agent Pane — 恢复默认设置脚本
# 用法: bash reset-settings.sh [OPTIONS]
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.claude/scripts"
SETTINGS="$HOME/.claude/settings.json"
PYTHON_HELPER="$SCRIPT_DIR/libdeploy.py"

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
MODE=""  # "backup", "default", or "" for interactive

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
用法: bash reset-settings.sh [OPTIONS]

Zellij Agent Pane — 恢复 Claude Code 默认设置脚本

当安装后出现报错时，使用此脚本快速恢复 settings.json。

Options:
  -y, --yes          Non-interactive mode (skip confirmation prompt)
  --backup           Restore from latest backup (if exists)
  --default          Reset to empty/default state
  --help             Show this help message

Examples:
  bash reset-settings.sh              交互式选择恢复方式
  bash reset-settings.sh --backup     从最新备份恢复
  bash reset-settings.sh --default    重置为默认空配置
  bash reset-settings.sh -y --default 静默重置
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes) NON_INTERACTIVE=true; shift ;;
            --backup) MODE="backup"; shift ;;
            --default) MODE="default"; shift ;;
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

prompt_choice() {
    local prompt="$1"
    shift
    local options=("$@")
    if $NON_INTERACTIVE; then
        return 1  # can't choose interactively
    fi
    echo ""
    echo "$prompt"
    local i=1
    for opt in "${options[@]}"; do
        echo "  $i) $opt"
        ((i++))
    done
    echo ""
    while true; do
        read -r -p "请选择 [1-${#options[@]}]: " ans
        if [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= ${#options[@]} )); then
            return $((ans - 1))
        fi
        echo "无效选择，请输入 1 到 ${#options[@]}"
    done
}

run_python() {
    local helper="$PYTHON_HELPER"
    if [ ! -f "$helper" ]; then
        log_fail "libdeploy.py not found at $helper"
        return 1
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
    echo "║     Zellij Agent Pane — 恢复默认设置             ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Check if settings.json exists
    if [ ! -f "$SETTINGS" ]; then
        log_info "settings.json 不存在，无需恢复"
        echo ""
        log_info "Claude Code 将在下次启动时创建默认配置"
        echo ""
        echo -e "\n${GREEN}${BOLD}按任意键退出...${NC}"
        read -r -n 1 -s
        exit 0
    fi

    # Find latest backup
    local latest_backup=""
    latest_backup=$(run_python find-latest-backup "$SETTINGS" 2>/dev/null || echo "")

    # Show current state
    echo ""
    log_info "当前配置文件: $SETTINGS"
    if [[ -n "$latest_backup" ]]; then
        log_info "找到最新备份: $latest_backup"
    else
        log_info "未找到备份文件"
    fi
    echo ""

    # Choose mode if not specified
    if [[ -z "$MODE" ]]; then
        local options=()
        options+=("从最新备份恢复 (如果有)")
        options+=("重置为默认空配置")
        options+=("取消")
        prompt_choice "请选择恢复方式:" "${options[@]}"
        local choice=$?
        case $choice in
            0) MODE="backup" ;;
            1) MODE="default" ;;
            2) log_info "已取消"; exit 0 ;;
        esac
        echo ""
    fi

    # Validate mode=backup has a backup
    if [[ "$MODE" == "backup" && -z "$latest_backup" ]]; then
        log_fail "没有找到备份文件，无法从备份恢复"
        log_info "请使用 --default 模式，或者交互式选择其他方式"
        exit 1
    fi

    # Confirmation
    if [[ "$MODE" == "backup" ]]; then
        log_warn "将从备份恢复配置:"
        echo "  • 备份文件: $latest_backup"
        echo "  • 将覆盖: $SETTINGS"
    else
        log_warn "将重置为默认空配置:"
        echo "  • 将删除: $SETTINGS"
        echo "  • 会先创建一个备份以防万一"
    fi
    echo ""

    if ! prompt_yes_no "确认继续？" "N"; then
        log_info "已取消"
        exit 0
    fi

    # Execute
    log_step "执行恢复"

    if [[ "$MODE" == "backup" ]]; then
        # First backup current state just in case
        local extra_bak=""
        extra_bak=$(run_python backup "$SETTINGS" 2>/dev/null || echo "")
        if [[ -n "$extra_bak" ]]; then
            log_ok "已额外备份当前状态: $extra_bak"
        fi

        # Restore
        local result
        result=$(run_python restore "$SETTINGS" "$latest_backup" 2>&1)
        if echo "$result" | grep -q '"ok":\s*true'; then
            log_ok "已从备份恢复: $latest_backup"
        else
            log_fail "恢复失败: $result"
            exit 1
        fi
    else
        # Reset to default (delete, will create backup first)
        local result
        result=$(run_python reset-to-default "$SETTINGS" 2>&1)
        local bak=$(echo "$result" | grep -o '"backup":\s*"[^"]*"' | sed 's/"backup":\s*"//;s/"$//')
        if echo "$result" | grep -q '"ok":\s*true'; then
            log_ok "已重置为默认配置"
            if [[ -n "$bak" && "$bak" != "null" ]]; then
                log_ok "原配置已备份至: $bak"
            fi
        else
            log_fail "重置失败: $result"
            exit 1
        fi
    fi

    # Summary
    echo ""
    log_step "恢复完成"
    echo ""
    echo -e "  ${GREEN}${BOLD}✓ 操作成功${NC}"
    echo ""
    if [[ "$MODE" == "backup" ]]; then
        echo "  ── 已恢复 ──"
        echo "    • 来源: $latest_backup"
    else
        echo "  ── 已重置 ──"
        echo "    • settings.json 已移除"
        echo "    • Claude Code 将在下次启动时创建默认配置"
    fi
    echo ""
    log_info "请重启 Claude Code 以使更改生效"
    echo ""

    echo -e "\n${GREEN}${BOLD}按任意键退出...${NC}"
    read -r -n 1 -s
}

main "$@"
