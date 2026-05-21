#!/bin/bash
# Zellij Agent Pane — 一键部署脚本
# 用法: bash deploy.sh [OPTIONS]
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
DRY_RUN=false
NON_INTERACTIVE=false

# ── Helper Functions ────────────────────────────────────────────────────────
log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_pass()  { echo -e "${GREEN}[PASS]${NC} $*"; }
log_fail()  { echo -e "${RED}[FAIL]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_dry()   { echo -e "${YELLOW}[DRY-RUN]${NC} $*"; }
log_step()  { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }
log_ok()    { echo -e "  ${GREEN}✓${NC} $*"; }
log_skip()  { echo -e "  ${YELLOW}−${NC} $*"; }

usage() {
    cat <<EOF
用法: bash deploy.sh [OPTIONS]

Zellij Agent Pane — 一键部署 Claude Code 子 agent 窗格工具

Options:
  -y, --yes          Non-interactive mode (skip prompts, use defaults)
  --dry-run          Preview mode (no files modified)
  --help             Show this help message

Examples:
  bash deploy.sh             交互式部署
  bash deploy.sh -y          静默部署（不提示）
  bash deploy.sh --dry-run   预览模式
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes) NON_INTERACTIVE=true; shift ;;
            --dry-run) DRY_RUN=true; shift ;;
            --help) usage ;;
            *) echo "Unknown option: $1"; usage ;;
        esac
    done
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-Y}"
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
    # Wrapper to call libdeploy.py with proper path handling
    if command -v python3 &>/dev/null; then
        python3 "$PYTHON_HELPER" "$@"
    elif command -v python &>/dev/null; then
        python "$PYTHON_HELPER" "$@"
    else
        log_fail "Python 3 not found (neither python3 nor python commands available)"
        exit 1
    fi
}

ensure_python_helper() {
    if [ ! -f "$PYTHON_HELPER" ]; then
        log_fail "libdeploy.py not found alongside deploy.sh"
        log_info "Expected at: $PYTHON_HELPER"
        exit 1
    fi
}

# ── Phase 0: Bootstrap ─────────────────────────────────────────────────────
phase_bootstrap() {
    echo -e "${BOLD}${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║       Zellij Agent Pane — 一键部署               ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"

    ensure_python_helper

    if $DRY_RUN; then
        log_warn "DRY-RUN 模式 — 不会修改任何文件"
        echo ""
    fi
}

# ── Phase 1: OS Detection ──────────────────────────────────────────────────
phase_detect_os() {
    log_step "Phase 1/6 — 检测操作系统"

    local os
    os=$(run_python detect-os)
    echo -e "  系统类型: ${BOLD}$os${NC}"

    if [[ "$os" == "unknown" ]]; then
        log_warn "未能识别操作系统类型，将使用通用配置"
    fi
    echo ""
}

# ── Phase 2: Dependency Check ──────────────────────────────────────────────
phase_check_deps() {
    log_step "Phase 2/6 — 检查依赖项"

    local deps_json
    deps_json=$(run_python check-deps)
    local os
    # Use the same python detection logic for one-liners
    if command -v python3 &>/dev/null; then
        os=$(echo "$deps_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['_os'])")
    else
        os=$(echo "$deps_json" | python -c "import json,sys; print(json.load(sys.stdin)['_os'])")
    fi

    local all_ok=true
    local missing_required=false

    while IFS='|' read -r dep ok version path install_hint; do
        local icon col label
        case "$dep" in
            zellij)   label="zellij       " ;;
            python3)  label="Python 3     " ;;
            bash)     label="bash         " ;;
            claude)   label="Claude Code  " ;;
            *)        label="$dep          " ;;
        esac

        if [[ "$ok" == "True" ]]; then
            log_pass "${label} ${version:-found}  @ ${path:--}"
        else
            if [[ "$dep" == "claude" ]]; then
                log_warn "${label} 未安装 (optional)"
            else
                log_fail "${label} 未安装"
                missing_required=true
            fi
            if [[ -n "${install_hint:-}" ]]; then
                echo -e "        ${YELLOW}→${NC} $install_hint"
            fi
        fi
    done < <(
        if command -v python3 &>/dev/null; then
            echo "$deps_json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for dep in ['zellij','python3','bash','claude']:
    info = d.get(dep, {})
    print(f\"{dep}|{info.get('ok', False)}|{info.get('version','') or ''}|{info.get('path','') or ''}|{info.get('install_hint','') or ''}\")
"
        else
            echo "$deps_json" | python -c "
import json, sys
d = json.load(sys.stdin)
for dep in ['zellij','python3','bash','claude']:
    info = d.get(dep, {})
    print(f\"{dep}|{info.get('ok', False)}|{info.get('version','') or ''}|{info.get('path','') or ''}|{info.get('install_hint','') or ''}\")
"
        fi
    )

    echo ""
    if $missing_required; then
        log_fail "缺少必要依赖，请安装后重试"
        if ! $NON_INTERACTIVE; then
            if ! prompt_yes_no "是否仍要继续部署？（可能导致功能不可用）" "N"; then
                log_info "部署已取消"
                exit 1
            fi
        else
            exit 1
        fi
    else
        log_pass "所有必要依赖已就绪"
    fi
    echo ""
}

# ── Phase 3: Copy Scripts ──────────────────────────────────────────────────
phase_copy_scripts() {
    log_step "Phase 3/6 — 复制脚本文件"

    if $DRY_RUN; then
        log_dry "创建目录: $TARGET_DIR"
        log_dry "复制: zellij-agent-pane.sh → $TARGET_DIR/"
        log_dry "复制: zellij-monitor.py    → $TARGET_DIR/"
        log_dry "复制: libdeploy.py         → $TARGET_DIR/"
        log_dry "复制: doctor.sh            → $TARGET_DIR/"
        log_dry "复制: doctor.ps1           → $TARGET_DIR/"
        log_dry "设置执行权限: *.sh"
        echo ""
        return 0
    fi

    mkdir -p "$TARGET_DIR"

    cp "$SCRIPT_DIR/zellij-agent-pane.sh" "$TARGET_DIR/"
    log_ok "zellij-agent-pane.sh → $TARGET_DIR/"

    cp "$SCRIPT_DIR/zellij-monitor.py" "$TARGET_DIR/"
    log_ok "zellij-monitor.py    → $TARGET_DIR/"

    cp "$PYTHON_HELPER" "$TARGET_DIR/"
    log_ok "libdeploy.py         → $TARGET_DIR/"

    if [ -f "$SCRIPT_DIR/doctor.sh" ]; then
        cp "$SCRIPT_DIR/doctor.sh" "$TARGET_DIR/"
        log_ok "doctor.sh            → $TARGET_DIR/"
    fi
    if [ -f "$SCRIPT_DIR/doctor.ps1" ]; then
        cp "$SCRIPT_DIR/doctor.ps1" "$TARGET_DIR/"
        log_ok "doctor.ps1           → $TARGET_DIR/"
    fi

    chmod +x "$TARGET_DIR/zellij-agent-pane.sh"
    chmod +x "$TARGET_DIR/doctor.sh" 2>/dev/null || true

    # Verify copy
    if [ -f "$TARGET_DIR/zellij-agent-pane.sh" ] && [ -f "$TARGET_DIR/zellij-monitor.py" ] && [ -f "$TARGET_DIR/libdeploy.py" ]; then
        log_pass "所有脚本文件已安装"
    else
        log_fail "文件复制失败，请检查权限"
        exit 1
    fi
    echo ""
}

# ── Phase 4: Settings Merge ────────────────────────────────────────────────
phase_merge_settings() {
    log_step "Phase 4/6 — 配置 Claude Code hooks"

    # Backup
    if $DRY_RUN; then
        log_dry "备份: $SETTINGS → $SETTINGS.bak.<TIMESTAMP>"
    else
        local bak
        bak=$(run_python backup "$SETTINGS")
        if [[ -n "$bak" ]]; then
            log_ok "已备份: $bak"
        else
            log_info "$SETTINGS 不存在，将创建新文件"
        fi
    fi

    # Merge hooks
    if $DRY_RUN; then
        log_dry "将合并 hooks 配置到: $SETTINGS"
        echo ""
        echo -e "  ${YELLOW}待添加的 hooks 配置:${NC}"
        run_python generate-hooks | sed 's/^/    /'
    else
        local merge_result
        merge_result=$(run_python merge-hooks "$SETTINGS")
        local merged hook_count error
        merged=$(echo "$merge_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('merged',False))")
        hook_count=$(echo "$merge_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('hook_count',0))")
        error=$(echo "$merge_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('error','') or '')")

        if [[ -n "$error" ]]; then
            log_fail "$error"
            if prompt_yes_no "是否覆盖 settings.json？（备份文件已创建）" "N"; then
                echo "{ \"hooks\": $(run_python generate-hooks) }" > "$SETTINGS"
                log_ok "settings.json 已覆写"
            else
                log_warn "部署未完成 — 请手动合并 hooks 配置"
                echo ""
                echo -e "  ${YELLOW}请将以下内容添加到 $SETTINGS:${NC}"
                run_python generate-hooks | sed 's/^/    /'
            fi
        elif [[ "$merged" == "True" ]]; then
            log_ok "hooks 配置已合并到 $SETTINGS（共 $hook_count 个 hook 条目）"
        else
            log_ok "hooks 配置已存在，无需修改（共 $hook_count 个 hook 条目）"
        fi
    fi
    echo ""
}

# ── Phase 5: Verification ──────────────────────────────────────────────────
phase_verify() {
    log_step "Phase 5/6 — 验证部署"

    if $DRY_RUN; then
        log_dry "跳过验证（dry-run 模式）"
        echo ""
        return 0
    fi

    # Check files
    local verify_result
    verify_result=$(run_python verify-install "$TARGET_DIR")
    local all_ok
    if command -v python3 &>/dev/null; then
        all_ok=$(echo "$verify_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('all_ok',False))")
    else
        all_ok=$(echo "$verify_result" | python -c "import json,sys; print(json.load(sys.stdin).get('all_ok',False))")
    fi

    echo "  ── 文件检查 ──"
    while IFS='|' read -r name exists exec_bit; do
        if [[ "$exists" == "True" ]]; then
            log_ok "$name 存在${exec_bit:+ (可执行)}"
        else
            log_fail "$name 缺失"
        fi
    done < <(
        if command -v python3 &>/dev/null; then
            echo "$verify_result" | python3 -c "
import json, sys
for f in json.load(sys.stdin).get('files', []):
    print(f\"{f['name']}|{f['exists']}|{f['executable']}\")
"
        else
            echo "$verify_result" | python -c "
import json, sys
for f in json.load(sys.stdin).get('files', []):
    print(f\"{f['name']}|{f['exists']}|{f['executable']}\")
"
        fi
    )
    )

    # Validate settings.json
    echo "  ── 配置检查 ──"
    if [ -f "$SETTINGS" ]; then
        if (command -v python3 &>/dev/null && python3 -c "import json; json.load(open('$SETTINGS', encoding='utf-8-sig')); print('ok')" 2>/dev/null) || \
           (command -v python &>/dev/null && python -c "import json; json.load(open('$SETTINGS', encoding='utf-8-sig')); print('ok')" 2>/dev/null) | grep -q ok; then
            log_ok "settings.json 是有效的 JSON"
        else
            log_fail "settings.json 不是有效的 JSON"
        fi
    else
        log_fail "settings.json 不存在"
    fi

    # Test hook script
    echo "  ── Hook 脚本检查 ──"
    if [ -f "$TARGET_DIR/zellij-agent-pane.sh" ]; then
        local test_result
        test_result=$(bash "$TARGET_DIR/zellij-agent-pane.sh" list 2>/dev/null || echo "FAIL")
        if [[ "$test_result" != "FAIL" ]]; then
            log_ok "zellij-agent-pane.sh list 正常运行"
        else
            log_warn "zellij-agent-pane.sh 测试失败（可能不在 zellij 会话中）"
        fi
    else
        log_fail "zellij-agent-pane.sh 不存在"
    fi

    # Check for leftover temp files
    local leftover
    leftover=$(ls "$HOME/.claude"/.mon-*.json 2>/dev/null || true)
    if [[ -n "$leftover" ]]; then
        log_warn "发现残留的监视器临时文件，可运行 uninstall.sh 清理"
    fi

    echo ""
    if ! $all_ok; then
        log_fail "部署验证未通过，请检查上面的错误信息"
    fi
}

# ── Phase 6: Summary ──────────────────────────────────────────────────────
phase_summary() {
    log_step "Phase 6/6 — 部署摘要"

    if $DRY_RUN; then
        echo -e "  ${YELLOW}DRY-RUN 完成 — 未修改任何文件${NC}"
        echo ""
        echo "  运行 bash deploy.sh 执行实际部署"
        return 0
    fi

    echo -e "  ${GREEN}${BOLD}✓ 部署成功！${NC}"
    echo ""
    echo "  ── 已安装文件 ──"
    echo "    $TARGET_DIR/zellij-agent-pane.sh"
    echo "    $TARGET_DIR/zellij-monitor.py"
    echo "    $TARGET_DIR/libdeploy.py"
    echo ""
    echo "  ── 配置文件 ──"
    echo "    $SETTINGS  (hooks 已配置)"
    echo ""
    echo "  ── 后续步骤 ──"
    echo "    1. 启动 zellij 会话:  ${CYAN}zellij${NC}"
    echo "    2. 启动 Claude Code:  ${CYAN}claude${NC}"
    echo "    3. 测试子 agent 窗格: ${CYAN}/agents${NC}"
    echo ""
    echo "  ── 其他命令 ──"
    echo "    查看映射:   bash $TARGET_DIR/zellij-agent-pane.sh list"
    echo "    清除映射:   bash $TARGET_DIR/zellij-agent-pane.sh clean"
    echo "    卸载:       bash $SCRIPT_DIR/uninstall.sh"
    echo ""
    echo -e "\n${GREEN}${BOLD}按任意键退出...${NC}"
    read -r -n 1 -s
}

# ── Main ───────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"
    phase_bootstrap
    phase_detect_os
    phase_check_deps
    phase_copy_scripts
    phase_merge_settings
    phase_verify
    phase_summary
    wait_for_exit
}

main "$@"