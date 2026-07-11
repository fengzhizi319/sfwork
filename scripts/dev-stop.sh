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
# 从 .env 文件加载环境变量配置
# ------------------------------------------------------------------
# DEV_START_ENV_FILE: 可自定义 env 文件路径，默认读取 sfwork 根目录的 .env
# 使用 set -a / set +a 让 .env 中定义的所有变量自动 export 到当前 shell
DEV_START_ENV_FILE="${DEV_START_ENV_FILE:-$SFWORK_ROOT/.env}"
if [ -f "$DEV_START_ENV_FILE" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$DEV_START_ENV_FILE"
    set +a
    echo "[INFO] 已加载环境变量配置：$DEV_START_ENV_FILE"
fi

# LOG_DIR: 与 dev-start.sh 保持一致，PID 文件存放目录
LOG_DIR="$SFWORK_ROOT/logs"

# is_alive
#   功能：检测进程是否存活。
#   参数：$1 - 进程 ID
#   返回：0=存活，1=不存在或无权限
#   说明：使用 kill -0 不发送信号，仅检查进程是否存在。
is_alive() {
    local pid="$1"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
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
stop_pidfile() {
    local pidfile="$1"
    local name="$2"
    if [ -f "$pidfile" ]; then
        local pid
        pid="$(cat "$pidfile")"
        if is_alive "$pid"; then
            echo "停止 ${name}（pid ${pid}）..."
            # kill 默认发送 SIGTERM（信号 15）
            kill "$pid" 2>/dev/null || true
            sleep 1
            if is_alive "$pid"; then
                # SIGKILL（信号 9）强制终止
                kill -9 "$pid" 2>/dev/null || true
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
    docker stop "${USER}-kuscia-master" "${USER}-kuscia-lite-alice" "${USER}-kuscia-lite-bob" 2>/dev/null || true
fi

echo "完成"
