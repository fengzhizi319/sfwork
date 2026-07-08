#!/bin/bash
#
# 无 Docker 运行脚本 - 一键启动 sfwork 本地开发环境
#
# 用法：
#   bash scripts/run-all-no-docker.sh
#   bash scripts/run-all-no-docker.sh --stop
#   SUDO_PWD=your_password bash scripts/run-all-no-docker.sh
#
# 说明：
#   - 所有组件均使用 sfwork 目录下的本地源码，不依赖 Docker
#   - SecretFlow 使用 conda 环境 sf310 中的本地可编辑安装
#   - Kuscia 使用本地编译的 kuscia 二进制（scripts/run_local_kuscia.sh）
#   - SecretPad 后端使用本地 Maven 构建的 secretpad.jar
#   - SecretPad 前端使用 frontend-src 本地源码
#
set -euo pipefail

ROOT_DIR="/home/charles/code/sfwork"
KUSCIA_DIR="$ROOT_DIR/kuscia"
SECRETPAD_DIR="$ROOT_DIR/secretpad"
SECRETFLOW_DIR="$ROOT_DIR/secretflow"
LOG_DIR="$ROOT_DIR/logs"
PID_DIR="$LOG_DIR/pids"
KUSCIA_HOME="$ROOT_DIR/.local-kuscia"

CONDA_ENV="${CONDA_ENV:-sf310}"
SUDO_PWD="${SUDO_PWD:-110734}"

# 创建日志和 PID 目录
mkdir -p "$LOG_DIR"
mkdir -p "$PID_DIR"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }

# sudo 包装：使用 SUDO_PWD 环境变量，避免脚本内硬编码
run_sudo() {
    echo "$SUDO_PWD" | sudo -S "$@"
}

# 进程管理
is_process_alive() {
    local pid="$1"
    [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1
}

stop_service_by_pidfile() {
    local pidfile="$1" name="$2"
    if [ -f "$pidfile" ]; then
        local pid
        pid="$(cat "$pidfile")"
        if is_process_alive "$pid"; then
            log_info "停止已运行的 $name（pid $pid）..."
            kill "$pid" 2>/dev/null || true
            sleep 1
            if is_process_alive "$pid"; then
                kill -9 "$pid" 2>/dev/null || true
            fi
        fi
        rm -f "$pidfile"
    fi
}

# 端口检测
port_in_use() {
    local port="$1"
    ss -tln 2>/dev/null | grep -qE ":$port\\b"
}

wait_for_port() {
    local host="$1" port="$2" timeout_sec="${3:-60}" what="$4"
    log_info "等待 $what 就绪：$host:$port（最多 ${timeout_sec}s）..."
    for ((i = 0; i < timeout_sec; i++)); do
        if ss -tln 2>/dev/null | grep -qE ":$port\\b"; then
            log_info "$what 已就绪"
            return 0
        fi
        sleep 1
    done
    log_error "$what 在 $host:$port 上未就绪，请查看日志"
    return 1
}

# 激活 conda 环境（如果当前未在目标环境中）
ensure_conda_env() {
    if [ -n "${CONDA_PREFIX:-}" ] && [[ "$(basename "$CONDA_PREFIX")" == "$CONDA_ENV" ]]; then
        return 0
    fi

    local conda_base
    conda_base="$(conda info --base 2>/dev/null)"
    if [ -z "$conda_base" ] || [ ! -f "$conda_base/etc/profile.d/conda.sh" ]; then
        log_error "未找到 conda，请先安装 Anaconda/Miniconda"
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$conda_base/etc/profile.d/conda.sh"
    if ! conda env list | grep -qE "^$CONDA_ENV[[:space:]]"; then
        log_error "conda 环境 $CONDA_ENV 不存在，请先创建"
        exit 1
    fi
    conda activate "$CONDA_ENV"
}

# 检查依赖
 check_dependencies() {
    log_step "检查系统依赖..."

    for cmd in java mvn node pnpm go gcc git openssl conda; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "未找到 $cmd，请先安装"
            exit 1
        fi
    done

    # Java 版本
    local java_version
    java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d. -f1)
    if [ "$java_version" != "17" ]; then
        log_error "需要 Java 17，当前版本: $(java -version 2>&1 | head -1)"
        exit 1
    fi

    # Node 版本
    local node_version
    node_version=$(node -v | sed 's/v//')
    if ! dpkg --compare-versions "$node_version" ge "16.14.0" 2>/dev/null; then
        log_warn "建议 Node.js 版本 >= 16.14.0，当前版本: $(node -v)"
    fi

    # conda 环境
    ensure_conda_env
    log_info "当前 Python 环境：$CONDA_PREFIX ($(python --version))"

    if [ "$SUDO_PWD" = "110734" ]; then
        log_warn "使用默认 sudo 密码 110734；建议通过环境变量 SUDO_PWD 覆盖"
    fi
}

# 检查关键端口
 check_ports() {
    log_step "检查关键端口占用情况..."
    local ports=(53 80 8080 8082 8083 8092 8443 8000)
    local occupied=()
    for port in "${ports[@]}"; do
        if port_in_use "$port"; then
            occupied+=("$port")
        fi
    done
    if [ ${#occupied[@]} -gt 0 ]; then
        log_warn "以下端口已被占用：${occupied[*]}"
        log_warn "若启动失败，请先释放这些端口（尤其是 53 / 80 / 8083）"
    else
        log_info "关键端口空闲"
    fi
}

# 编译并安装本地 SecretFlow
 build_secretflow() {
    log_step "安装本地 SecretFlow（$SECRETFLOW_DIR）..."
    ensure_conda_env
    cd "$SECRETFLOW_DIR"

    # 安装/更新 kuscia Python 包（SecretFlow Kuscia 入口需要）
    pip install -i https://mirrors.aliyun.com/pypi/simple/ --upgrade kuscia 2>&1 | tail -n 5

    # 可编辑安装本地 SecretFlow
    pip install -e . 2>&1 | tail -n 10

    # 自检：确认 l_diversity 组件已注册（如存在）
    python - <<'PY'
from secretflow.component.core import Registry
d = Registry.get_definition_by_id('privacy/l_diversity:1.0.0')
assert d is not None, 'privacy/l_diversity:1.0.0 未注册'
print('SecretFlow 自检通过，已注册组件：privacy/l_diversity:1.0.0')
PY

    log_info "本地 SecretFlow 安装完成"
}

# 编译 Kuscia
 build_kuscia() {
    log_step "编译本地 Kuscia ..."
    cd "$KUSCIA_DIR"
    bash hack/build.sh -t kuscia
    log_info "Kuscia 编译完成：$KUSCIA_DIR/build/apps/kuscia/kuscia"
}

# 启动 Kuscia Master（本地二进制模式，无 Docker）
 start_kuscia_master() {
    log_step "启动 Kuscia Master（本地二进制模式）..."

    stop_kuscia_master

    export KUSCIA_HOME="$KUSCIA_HOME"
    mkdir -p "$KUSCIA_HOME"

    # 使用 sudo 启动，因为 Kuscia Master 需要监听 53 / 80 等特权端口
    run_sudo bash "$KUSCIA_DIR/scripts/run_local_kuscia.sh" master \
        > "$LOG_DIR/kuscia-master.log" 2>&1 &

    # run_local_kuscia.sh 启动后会快速退出，真实的 kuscia 进程 PID 写入 KUSCIA_HOME/var/kuscia.pid
    sleep 2
    local kuscia_pid
    kuscia_pid="$(run_sudo cat "$KUSCIA_HOME/var/kuscia.pid" 2>/dev/null || true)"
    if [ -n "$kuscia_pid" ]; then
        echo "$kuscia_pid" > "$PID_DIR/kuscia-master.pid"
        log_info "Kuscia Master 已启动（pid $kuscia_pid）"
    else
        log_warn "未能从 $KUSCIA_HOME/var/kuscia.pid 读取 Kuscia PID，停止时将通过脚本处理"
    fi

    wait_for_port 127.0.0.1 8082 180 "Kuscia API HTTP"
    wait_for_port 127.0.0.1 8083 180 "Kuscia API gRPC"
    wait_for_port 127.0.0.1 80 180 "Kuscia Envoy 内部端口"
}

# 停止 Kuscia Master
 stop_kuscia_master() {
    log_info "停止 Kuscia Master ..."
    export KUSCIA_HOME="$KUSCIA_HOME"
    # 优先使用脚本自身的 --stop
    if [ -f "$KUSCIA_HOME/var/kuscia.pid" ]; then
        run_sudo bash "$KUSCIA_DIR/scripts/run_local_kuscia.sh" --stop || true
    fi

    # 清理可能残留的 kuscia 进程
    local remaining
    remaining="$(pgrep -f "kuscia start -c" 2>/dev/null || true)"
    if [ -n "$remaining" ]; then
        log_warn "发现残留 Kuscia 进程，强制清理..."
        run_sudo kill -9 $remaining 2>/dev/null || true
    fi

    rm -f "$PID_DIR/kuscia-master.pid"
}

# 编译 SecretPad 后端
 build_secretpad_backend() {
    log_step "编译 SecretPad 后端..."
    cd "$SECRETPAD_DIR"
    mvn clean install -Dmaven.test.skip=true
    if [ ! -f "$SECRETPAD_DIR/target/secretpad.jar" ]; then
        log_error "后端编译失败：未找到 target/secretpad.jar"
        exit 1
    fi
    log_info "SecretPad 后端编译完成"
}

# 生成证书
 generate_certs() {
    log_step "生成证书与 JKS ..."
    cd "$SECRETPAD_DIR"

    if [ -f "$SECRETPAD_DIR/config/server.jks" ] && [ -f "$SECRETPAD_DIR/config/certs/client.crt" ]; then
        log_info "证书与 JKS 已存在，跳过生成"
        return 0
    fi

    rm -f "$SECRETPAD_DIR/config/server.jks"
    rm -rf "$SECRETPAD_DIR/config/certs/"
    bash "$SECRETPAD_DIR/scripts/test/setup.sh"
    log_info "证书生成完成"
}

# 启动 SecretPad 后端
 start_secretpad_backend() {
    log_step "启动 SecretPad 后端..."
    stop_service_by_pidfile "$PID_DIR/secretpad-backend.pid" "SecretPad 后端"

    # 非 Docker 本地模式下，Kuscia 默认端口为 8082(HTTP)/8083(gRPC)，Envoy 内部端口为 80
    export KUSCIA_API_ADDRESS=127.0.0.1
    export KUSCIA_API_PORT=8083
    export KUSCIA_GW_ADDRESS=127.0.0.1:80
    export KUSCIA_PROTOCOL=notls

    nohup java \
        -Dspring.profiles.active=dev \
        -Dsun.net.http.allowRestrictedHeaders=true \
        -Dserver.port=8443 \
        -jar "$SECRETPAD_DIR/target/secretpad.jar" > "$LOG_DIR/backend.log" 2>&1 &

    echo $! > "$PID_DIR/secretpad-backend.pid"
    wait_for_port 127.0.0.1 8080 120 "后端 HTTP"
    log_info "SecretPad 后端已启动"
}

# 启动 SecretPad 前端
 start_secretpad_frontend() {
    log_step "启动 SecretPad 前端..."
    stop_service_by_pidfile "$PID_DIR/secretpad-frontend.pid" "SecretPad 前端"

    local env_file="$SECRETPAD_DIR/frontend-src/apps/platform/.env"
    if [ ! -f "$env_file" ]; then
        log_info "创建前端代理配置 $env_file"
        echo "PROXY_URL=http://127.0.0.1:8080" > "$env_file"
    elif ! grep -q '^PROXY_URL=' "$env_file" 2>/dev/null; then
        log_info "向前端代理配置追加 PROXY_URL"
        echo "PROXY_URL=http://127.0.0.1:8080" >> "$env_file"
    fi

    cd "$SECRETPAD_DIR/frontend-src"
    if [ ! -d "node_modules" ]; then
        log_info "首次运行，安装前端依赖..."
        pnpm bootstrap
    fi

    nohup pnpm --filter secretpad dev > "$LOG_DIR/frontend.log" 2>&1 &
    echo $! > "$PID_DIR/secretpad-frontend.pid"
    wait_for_port 127.0.0.1 8000 120 "前端开发服务器"
    log_info "SecretPad 前端已启动"
}

# 停止所有服务
 stop_all_services() {
    log_step "停止所有服务..."
    stop_service_by_pidfile "$PID_DIR/secretpad-frontend.pid" "SecretPad 前端"
    stop_service_by_pidfile "$PID_DIR/secretpad-backend.pid" "SecretPad 后端"
    stop_kuscia_master
    log_info "所有服务已停止"
}

# 打印摘要
 print_summary() {
    local frontend_url="http://localhost:8000"
    local backend_health="http://localhost:8080/actuator/health"
    local backend_https="https://localhost:8443"
    local kuscia_api_http="http://localhost:8082"

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  所有服务已启动（无 Docker 模式）${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "🌐 前端开发服务器：${BLUE}${frontend_url}${NC}"
    echo -e "🔧 后端健康检查：${BLUE}${backend_health}${NC}"
    echo -e "🔒 后端 HTTPS 地址：${BLUE}${backend_https}${NC}"
    echo -e "⚙️  Kuscia API HTTP：${BLUE}${kuscia_api_http}${NC}"
    echo ""
    echo -e "👤 登录账号：${YELLOW}admin / 12345678${NC}"
    echo ""
    echo -e "📄 日志文件："
    echo -e "   Kuscia：$LOG_DIR/kuscia-master.log"
    echo -e "   后端：$LOG_DIR/backend.log"
    echo -e "   前端：$LOG_DIR/frontend.log"
    echo ""
    echo -e "🛑 停止服务：${YELLOW}bash scripts/run-all-no-docker.sh --stop${NC}"
    echo ""
}

# 主函数
 main() {
    if [ "${1:-}" = "--stop" ]; then
        stop_all_services
        exit 0
    fi

    check_dependencies
    check_ports

    # 1. 本地 SecretFlow（conda 环境）
    build_secretflow

    # 2. 本地 Kuscia
    build_kuscia
    start_kuscia_master

    # 3. 本地 SecretPad 后端
    build_secretpad_backend
    generate_certs
    start_secretpad_backend

    # 4. 本地 SecretPad 前端
    start_secretpad_frontend

    print_summary
}

main "$@"
