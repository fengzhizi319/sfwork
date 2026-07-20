#!/bin/bash
#
# ============================================================================
# sfwork 二次开发环境停止脚本
# ============================================================================
#
# 功能概述：
#   本脚本用于停止由 scripts/dev-start.sh 启动的本地开发环境。
#   默认只停止 SecretPad 后端和前端进程；传入 --kuscia 时额外停止 Kuscia 容器。
#
# 用法：
#   bash scripts/dev-stop.sh           # 停止后端和前端
#   bash scripts/dev-stop.sh --kuscia  # 同时停止 Kuscia 容器
#
# 运行平台：
#   - Linux / macOS 原生 Bash
#   - Windows 请在 Git Bash / MSYS2 / WSL2 的 Bash 环境中运行
#
# 设计说明：
#   - 后端和前端的进程 ID 分别保存在 logs/backend.pid 和 logs/frontend.pid
#   - 通过 PID 文件精确停止本脚本启动的进程，避免误杀其他服务
#   - Kuscia 容器名遵循 ${USER}-kuscia-{master,lite-alice,lite-bob} 命名规则
# ============================================================================

# Bash 严格模式：
#   -e: 任一命令失败立即退出
#   -u: 使用未定义变量时报错
#   -o pipefail: 管道中任一命令失败则整个管道失败
set -euo pipefail

# ------------------------------------------------------------------
# 全局路径与变量
# ------------------------------------------------------------------
# SFWORK_ROOT: sfwork 工作区根目录，根据本脚本所在位置自动推导
# 本脚本位于 sfwork/scripts/ 下，因此根目录为其父目录
SFWORK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ------------------------------------------------------------------
# DEV_START_ENV_FILE: 可自定义 env 文件路径，默认读取 scripts 目录下的 .env
# 使用 set -a / set +a 让 .env 中定义的所有变量自动 export 到当前 shell
DEV_START_ENV_FILE="${DEV_START_ENV_FILE:-$(dirname "${BASH_SOURCE[0]}")/.env}"
if [ -f "$DEV_START_ENV_FILE" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$DEV_START_ENV_FILE"
    set +a
    echo "[INFO] 已加载环境变量配置：$DEV_START_ENV_FILE"
fi

# 节点名称，支持通过环境变量或 .env 覆盖
ALICE_NAME="${ALICE_NAME:-alice}"
BOB_NAME="${BOB_NAME:-bob}"

# LOG_DIR: 与 dev-start.sh 保持一致，PID 文件存放目录
LOG_DIR="$SFWORK_ROOT/logs"

# ------------------------------------------------------------------
# 跨平台工具函数
# ------------------------------------------------------------------
# detect_os
#   功能：检测当前操作系统类型。
#   输出：linux / darwin / windows / unknown
#   说明：Windows 指 Git Bash / MSYS2 / CYGWIN 等 Bash 环境。
detect_os() {
    local os
    os="$(uname -s 2>/dev/null || echo unknown)"
    case "$os" in
        Linux*)     echo linux ;;
        Darwin*)    echo darwin ;;
        MINGW*|MSYS*|CYGWIN*) echo windows ;;
        *)          echo unknown ;;
    esac
}

is_linux() { [[ "$(detect_os)" == "linux" ]]; }
is_macos() { [[ "$(detect_os)" == "darwin" ]]; }
is_windows() { [[ "$(detect_os)" == "windows" ]]; }

# is_alive
#   功能：检测进程是否存活。
#   参数：$1 - 进程 ID
#   返回：0=存活，1=不存在或无权限
#   说明：Linux/macOS 使用 ps -p；Windows 在 ps -p 失败后回退到 tasklist 或 pgrep。
is_alive() {
    local pid="$1"
    [ -n "$pid" ] || return 1
    if ps -p "$pid" >/dev/null 2>&1; then
        return 0
    fi
    if is_windows; then
        if command -v tasklist >/dev/null 2>&1; then
            tasklist /FI "PID eq $pid" 2>/dev/null | grep -qE "[[:space:]]${pid}[[:space:]]"
            return $?
        elif command -v pgrep >/dev/null 2>&1; then
            pgrep -q -F - <<<"$pid" 2>/dev/null
            return $?
        fi
    fi
    return 1
}

# stop_pidfile
#   功能：根据 PID 文件停止指定服务。
#   参数：
#     $1 - PID 文件路径
#     $2 - 服务名称（用于日志）
#   停止策略：
#     1. 发送 SIGTERM（优雅停止，允许进程清理资源）
#     2. 等待 1 秒
#     3. 若仍在运行，发送 SIGKILL 强制终止
#     4. 删除 PID 文件（无论进程是否原本在运行）
#   说明：Windows 下 kill 若失败，回退到 taskkill。
stop_pidfile() {
    local pidfile="$1"
    local name="$2"
    if [ -f "$pidfile" ]; then
        local pid
        pid="$(cat "$pidfile")"
        if is_alive "$pid"; then
            echo "停止 ${name}（pid ${pid}）..."
            # kill 默认发送 SIGTERM（信号 15）
            if ! kill "$pid" 2>/dev/null; then
                if is_windows && command -v taskkill >/dev/null 2>&1; then
                    taskkill /PID "$pid" /F 2>/dev/null || true
                fi
            fi
            sleep 1
            if is_alive "$pid"; then
                # SIGKILL（信号 9）强制终止
                if ! kill -9 "$pid" 2>/dev/null; then
                    if is_windows && command -v taskkill >/dev/null 2>&1; then
                        taskkill /PID "$pid" /F 2>/dev/null || true
                    fi
                fi
            fi
        else
            echo "${name} 未在运行"
        fi
        # 删除 PID 文件，避免残留文件影响下次启动判断
        rm -f "$pidfile"
    else
        echo "未找到 ${name} 的 pid 文件"
    fi
}

# 停止后端和前端
# 注意顺序：先停止前端，再停止后端，避免前端在停止过程中持续请求已停止的后端
stop_pidfile "$LOG_DIR/backend.pid" "后端"
stop_pidfile "$LOG_DIR/frontend.pid" "前端"

# 如果传入 --kuscia，同时停止 Kuscia Docker 容器
# docker stop 会优雅停止容器，保留容器数据卷，便于下次快速启动
if [ "${1:-}" = "--kuscia" ]; then
    echo "停止 Kuscia 容器 ..."
    # 2>/dev/null 隐藏“容器未运行”等错误；|| true 保证任一容器不存在时脚本仍正常退出
    docker stop "${USER}-kuscia-master" "${USER}-kuscia-lite-${ALICE_NAME}" "${USER}-kuscia-lite-${BOB_NAME}" 2>/dev/null || true
fi

echo "完成"
