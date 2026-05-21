# Zellij Agent Pane

当 Claude Code 启动子 agent（团队模式 `/agents`）时，自动在 zellij 中创建右侧窗格，实时显示 agent 的输出。agent 结束后自动关闭对应窗格。

📖 [English README](README_EN.md)

---

## 快速开始 — 一键部署

**在任意电脑上**，复制项目目录后运行（根据系统选择一种方式）：

### 方式 1：Windows 用户推荐（最方便）

直接双击或命令行运行：

```cmd
deploy.bat
```

自动检测 bash 是否可用：
- **有 bash** → 调用 `bash deploy.sh`
- **无 bash** → 调用 `powershell deploy.ps1`

### 方式 2：PowerShell（单独使用）

无需 Git Bash、WSL 或 MSYS2，Windows 系统自带 PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File deploy.ps1
```

静默安装：

```powershell
powershell -ExecutionPolicy Bypass -File deploy.ps1 -Yes
```

预览模式：

```powershell
powershell -ExecutionPolicy Bypass -File deploy.ps1 -DryRun
```

> **注意**: `-ExecutionPolicy Bypass` 可临时绕过执行限制。

### 方式 3：Bash（需 Git Bash、WSL 或 MSYS2）

```bash
bash deploy.sh
```

选项：

```bash
bash deploy.sh -y           # 静默模式
bash deploy.sh --dry-run    # 预览模式
bash deploy.sh --help       # 查看帮助
```

### 一键部署包含的功能

| 功能 | 说明 |
|------|------|
| 操作系统检测 | 自动识别 MSYS2/Windows、Linux、macOS、WSL |
| 依赖检查 | 验证 zellij、Python 3、bash、Claude Code 是否已安装 |
| 安装指引 | 对缺失的依赖显示对应平台的安装命令 |
| 配置合并 | 将 hooks 安全合并到已有 settings.json（幂等设计，不会重复添加） |
| 自动备份 | 修改 settings.json 前自动创建时间戳备份 |
| 部署验证 | 检查文件完整性、JSON 合法性和 hook 脚本可运行性 |
| 交互/静默模式 | 交互模式有确认提示，静默模式适合自动化部署 |
| 预览模式 | `--dry-run` 预览所有操作但不修改任何文件 |
| **平台适配** | **Windows 自动选择 PowerShell hooks，非 Windows 使用 bash hooks** |

---

## 需求

| 依赖 | 版本要求 | 检查方式 | 安装命令（Windows/MSYS2） |
|------|---------|---------|--------------------------|
| [zellij](https://zellij.dev/) | ≥ 0.40 | `zellij --version` | `winget install Zellij.Zellij` 或 `scoop install zellij` |
| Python 3 | ≥ 3.8 | `python3 --version` | `pacman -S python` 或 `winget install Python.Python.3` |
| bash | 可选 | `bash --version` | 随 MSYS2 自动安装 |
| Claude Code CLI | 最新 | `claude --version` | `npm install -g @anthropic-ai/claude-code` |

> **注意**: 必须在 zellij 会话中运行 Claude Code，否则窗格功能不可用。

---

## 诊断工具

如果部署后子 agent 没有创建新窗格，运行诊断脚本快速排查问题：

```bash
bash ~/.claude/scripts/doctor.sh
```

或者（PowerShell）：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude/scripts/doctor.ps1"
```

诊断脚本会检查：
1. 脚本文件是否已安装
2. 依赖（zellij、Python 3、bash）是否可用
3. 是否在 zellij 会话中运行
4. Claude Code hooks 是否正确配置
5. 调试日志中的错误信息
6. Pane 映射文件状态

也可在项目目录中直接运行本地版本：

```bash
bash doctor.sh           # Bash 版本
powershell -ExecutionPolicy Bypass -File doctor.ps1   # PowerShell 版本
```

---

## 常见问题

### 子 agent 没有创建新窗格

1. **确保在 zellij 中运行**: 必须先启动 `zellij`，然后在 zellij 会话中启动 Claude Code
2. **重启 Claude Code**: 修改 settings.json 后需要重启 Claude Code
3. **运行诊断**: `bash doctor.sh` 或 `doctor.ps1` 检查环境
4. **检查 debug 日志**: `cat ~/.claude/zellij-hooks-debug.log`

### 中文路径乱码

脚本通过环境变量 `HOOK_INPUT` 传递 JSON payload，避免 MSYS2/bash 的 Unicode 编码损坏。

---

## 卸载

### Windows 用户推荐

直接双击或命令行运行：

```cmd
uninstall.bat
```

### PowerShell（单独使用）

```powershell
powershell -ExecutionPolicy Bypass -File uninstall.ps1
```

静默卸载：

```powershell
powershell -ExecutionPolicy Bypass -File uninstall.ps1 -Yes
```

### Bash（需 Git Bash、WSL 或 MSYS2）

```bash
bash uninstall.sh
```

静默卸载：

```bash
bash uninstall.sh -y
```

卸载脚本会：
1. 备份 `~/.claude/settings.json`
2. 从中移除 Zellij Agent Pane 的 hooks 配置（保留其他工具的配置）
3. 删除已安装的脚本文件
4. 清理运行时数据（pane 映射、调试日志、临时文件）

---

## 文件清单

| 文件 | 用途 |
|------|------|
| `deploy.bat` | Windows 统一启动器（自动选择 bash 或 PowerShell） |
| `uninstall.bat` | Windows 统一卸载器（自动选择 bash 或 PowerShell） |
| `deploy.sh` | 一键部署脚本（Bash，环境检查 + 自动安装） |
| `deploy.ps1` | 一键部署脚本（PowerShell，环境检查 + 自动安装） |
| `uninstall.sh` | 卸载脚本（Bash） |
| `uninstall.ps1` | 卸载脚本（PowerShell） |
| `doctor.sh` | 诊断工具（Bash，排查子 agent 窗格问题） |
| `doctor.ps1` | 诊断工具（PowerShell，排查子 agent 窗格问题） |
| `libdeploy.py` | 部署逻辑库（**单一数据源**：OS 检测、依赖检查、JSON 合并、hooks 配置） |
| `zellij-agent-pane.sh` | Hook 脚本（bash）：接收 SubagentStart/SubagentStop 事件，管理 zellij pane |
| `zellij-agent-pane.ps1` | Hook 脚本（PowerShell）：接收 SubagentStart/SubagentStop 事件，管理 zellij pane |
| `zellij-monitor.py` | 监控 agent JSONL 日志并在 pane 中实时输出（带格式化渲染） |
| `zellij-claude-code-pane-progress.md` | 项目开发记录及架构说明 |

---

## 手动部署

如果不使用一键部署脚本，也可手动安装：

```bash
# 1. 复制脚本
mkdir -p ~/.claude/scripts
cp zellij-agent-pane.sh ~/.claude/scripts/
cp zellij-agent-pane.ps1 ~/.claude/scripts/  # Windows 还需要
cp zellij-monitor.py ~/.claude/scripts/
cp libdeploy.py ~/.claude/scripts/
```

然后编辑 `~/.claude/settings.json`：

**Windows（PowerShell hooks）：**
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

**非 Windows（bash hooks）：**
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

## 测试

在 zellij 终端中启动 Claude Code，然后运行：

```
/agents
```

子 agent 启动时自动在右侧创建 pane 显示实时输出。

---

## 管理命令

**PowerShell（Windows）：**
| 命令 | 说明 |
|------|------|
| `powershell -File ~/.claude/scripts/zellij-agent-pane.ps1 list` | 查看当前运行的 agent → pane 映射 |
| `powershell -File ~/.claude/scripts/zellij-agent-pane.ps1 clean` | 清除 pane 映射记录 |

**Bash（非 Windows）：**
| 命令 | 说明 |
|------|------|
| `bash ~/.claude/scripts/zellij-agent-pane.sh start-hook` | 子 agent 启动时由 hook 自动调用 |
| `bash ~/.claude/scripts/zellij-agent-pane.sh stop-hook` | 子 agent 结束时由 hook 自动调用 |
| `bash ~/.claude/scripts/zellij-agent-pane.sh list` | 查看当前运行的 agent → pane 映射 |
| `bash ~/.claude/scripts/zellij-agent-pane.sh clean` | 清除 pane 映射记录 |

---

## 架构说明

### 单一数据源设计

所有 hooks 配置集中在 `libdeploy.py` 中，按 OS 自动选择：
- `win32`: PowerShell hooks
- 其他（linux/macos/msys2/wsl）: bash hooks

这样避免配置不同步的问题。

### 注意事项

- **必须**在 zellij 会话中运行，否则 `zellij action new-pane` 会失败
- 中文路径处理：通过环境变量 `HOOK_INPUT` 传递 JSON，避免 MSYS2/bash 编码损坏
- 子 agent 日志路径：`dirname(主转录)/{session_id}/subagents/agent-{id}.jsonl`
- Pane 在 agent 结束后 5 秒自动关闭
- 多人协作时 pane 映射文件 (`~/.claude/zellij-pane-map.json`) 目前无并发锁，注意不要同时启动过多 agent
