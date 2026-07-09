#!/bin/bash
#
# ============================================================================
# 无 Docker 运行脚本 - 一键启动 sfwork 本地开发环境
# ============================================================================
#
# 功能概述：
#   本脚本在本地直接启动 sfwork 完整开发环境，不依赖 Docker 容器。
#   启动内容包括：
#     1. SecretFlow 本地可编辑安装（基于 conda 环境 sf310）
#     2. Kuscia Master 本地二进制（scripts/run_local_kuscia.sh）
#     3. SecretPad 后端（Maven 构建的 secretpad.jar）
#     4. SecretPad 前端（frontend-src 本地源码 + Umi dev server）
#
# 用法：
#   bash scripts/run-all-no-docker.sh
#   bash scripts/run-all-no-docker.sh --stop
#   SUDO_PWD=your_password bash scripts/run-all-no-docker.sh
#
# 说明：
#   - 所有组件均使用 sfwork 目录下的本地源码
#   - SecretFlow 使用 conda 环境 sf310 中的本地可编辑安装
#   - Kuscia 使用本地编译的 kuscia 二进制
#   - SecretPad 后端使用本地 Maven 构建的 secretpad.jar
#   - SecretPad 前端使用 frontend-src 本地源码
#
# 注意：
#   - Kuscia Master 需要监听 53 / 80 等特权端口，因此脚本内部使用 sudo
#   - 默认 sudo 密码为 110734，强烈建议通过 SUDO_PWD 环境变量覆盖
# ============================================================================

# Bash 严格模式：
#   -e: 任一命令失败立即退出
#   -u: 使用未定义变量时报错
#   -o pipefail: 管道中任一命令失败则整个管道失败
set -euo pipefail

# ------------------------------------------------------------------
# 全局路径与常量
# ------------------------------------------------------------------
# ROOT_DIR: sfwork 工作区根目录，所有子项目均在此目录下
ROOT_DIR="/home/charles/code/sfwork"

# 各子项目源码目录
KUSCIA_DIR="$ROOT_DIR/kuscia"
SECRETPAD_DIR="$ROOT_DIR/secretpad"
SECRETFLOW_DIR="$ROOT_DIR/secretflow"

# LOG_DIR: 聚合日志目录；PID_DIR: 进程 ID 文件存放目录
LOG_DIR="$ROOT_DIR/logs"
PID_DIR="$LOG_DIR/pids"

# KUSCIA_HOME: Kuscia 本地运行时的主目录（数据、配置、pid 文件等）
KUSCIA_HOME="$ROOT_DIR/.local-kuscia"

# CONDA_ENV: SecretFlow 运行与构建使用的 conda 环境名称
CONDA_ENV="${CONDA_ENV:-sf310}"

# SUDO_PWD: 用于自动输入 sudo 密码。
# 默认值仅用于本地开发便利；生产环境或共享机器上请通过环境变量覆盖。
SUDO_PWD="${SUDO_PWD:-110734}"

# 创建日志和 PID 目录
# -p 表示若目录已存在则忽略，并自动创建父目录
mkdir -p "$LOG_DIR"
mkdir -p "$PID_DIR"

# ------------------------------------------------------------------
# 颜色与日志
# ------------------------------------------------------------------
# ANSI 转义码，用于终端彩色输出
RED='\033[0;31m'      # 红色：错误
GREEN='\033[0;32m'    # 绿色：正常信息
YELLOW='\033[1;33m'   # 黄色加粗：警告
BLUE='\033[0;34m'     # 蓝色：步骤提示
NC='\033[0m'          # 重置颜色

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }

# ------------------------------------------------------------------
# sudo 包装
# ------------------------------------------------------------------
# run_sudo
#   功能：使用 SUDO_PWD 环境变量自动输入密码，执行 sudo 命令。
#   参数：$@ - 要传递给 sudo 的命令及参数
#   说明：
#     - echo "$SUDO_PWD" 将密码通过管道传给 sudo -S
#     - sudo -S 从 stdin 读取密码，实现非交互式 sudo
#     - 注意：在脚本中明文传递密码存在安全风险，仅建议本地开发使用
run_sudo() {
    echo "$SUDO_PWD" | sudo -S "$@"
}

# ------------------------------------------------------------------
# 进程管理
# ------------------------------------------------------------------

# is_process_alive
#   功能：检测进程是否存活。
#   参数：$1 - 进程 ID
#   返回：0=存活，1=不存在或无权限
#   说明：使用 ps -p 避免对无权限进程使用 kill -0 产生误判。
is_process_alive() {
    local pid="$1"
    [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1
}

# stop_service_by_pidfile
#   功能：根据 PID 文件优雅停止服务。
#   参数：
#     $1 - PID 文件路径
#     $2 - 服务名称（用于日志）
#   停止策略：
#     1. 发送 SIGTERM（允许进程清理资源）
#     2. 等待 1 秒
#     3. 若仍在运行，发送 SIGKILL 强制终止
#     4. 删除 PID 文件
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

# ------------------------------------------------------------------
# 端口检测
# ------------------------------------------------------------------

# port_in_use
#   功能：检测指定 TCP 端口是否正在监听。
#   参数：$1 - 端口号
#   返回：0=已被占用，1=空闲
#   说明：ss -tln 列出所有监听中的 TCP 端口；正则 \\b 精确匹配端口。
port_in_use() {
    local port="$1"
    ss -tln 2>/dev/null | grep -qE ":$port\\b"
}

# wait_for_port
#   功能：轮询等待指定端口就绪。
#   参数：
#     $1 - 主机地址
#     $2 - 端口号
#     $3 - 超时秒数（默认 60）
#     $4 - 服务名称（用于日志）
#   返回：0=就绪，1=超时
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

# ------------------------------------------------------------------
# conda 环境管理
# ------------------------------------------------------------------

# ensure_conda_env
#   功能：激活目标 conda 环境（如果当前尚未激活）。
#   说明：
#     - CONDA_PREFIX 是当前已激活 conda 环境的路径，如 /home/user/miniconda3/envs/sf310
#     - basename 提取环境名，若已等于目标环境则直接返回，避免重复 activate
#     - 否则 source conda.sh 并激活目标环境
ensure_conda_env() {
    # 检查当前是否已在目标 conda 环境中
    if [ -n "${CONDA_PREFIX:-}" ] && [[ "$(basename "$CONDA_PREFIX")" == "$CONDA_ENV" ]]; then
        return 0
    fi

    # conda info --base 输出 conda 安装根目录
    local conda_base
    conda_base="$(conda info --base 2>/dev/null)"
    # 如果找不到 conda 或 conda.sh，说明未安装 conda
    if [ -z "$conda_base" ] || [ ! -f "$conda_base/etc/profile.d/conda.sh" ]; then
        log_error "未找到 conda，请先安装 Anaconda/Miniconda"
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$conda_base/etc/profile.d/conda.sh"
    # 检查目标环境是否已创建
    if ! conda env list | grep -qE "^$CONDA_ENV[[:space:]]"; then
        log_error "conda 环境 $CONDA_ENV 不存在，请先创建"
        exit 1
    fi
    conda activate "$CONDA_ENV"
}

# ------------------------------------------------------------------
# 依赖检查
# ------------------------------------------------------------------

# check_dependencies
#   功能：检查运行本脚本所需的系统命令、Java/Node 版本、conda 环境等。
#   退出码：0=检查通过；否则 exit 1
 check_dependencies() {
    log_step "检查系统依赖..."

    # for 循环遍历所需命令数组
    for cmd in java mvn node pnpm go gcc git openssl conda; do
        # command -v 检测命令是否在 PATH 中
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "未找到 $cmd，请先安装"
            exit 1
        fi
    done

    # Java 版本检测
    # java -version 输出到 stderr，2>&1 重定向到 stdout
    # awk -F '"' 以双引号分隔，提取 version 后的版本号；cut -d. -f1 取主版本号
    local java_version
    java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d. -f1)
    if [ "$java_version" != "17" ]; then
        log_error "需要 Java 17，当前版本: $(java -version 2>&1 | head -1)"
        exit 1
    fi

    # Node.js 版本检测
    # node -v 输出形如 v18.16.0；sed 's/v//' 去掉前缀 v
    local node_version
    node_version=$(node -v | sed 's/v//')
    # dpkg --compare-versions 是 Debian/Ubuntu 系统提供的版本比较工具
    # ge 表示 greater-or-equal；2>/dev/null 兼容非 Debian 系系统
    if ! dpkg --compare-versions "$node_version" ge "16.14.0" 2>/dev/null; then
        log_warn "建议 Node.js 版本 >= 16.14.0，当前版本: $(node -v)"
    fi

    # 确保 conda 环境已激活
    ensure_conda_env
    log_info "当前 Python 环境：$CONDA_PREFIX ($(python --version))"

    # 安全提示：若仍在使用默认 sudo 密码，提醒用户覆盖
    if [ "$SUDO_PWD" = "110734" ]; then
        log_warn "使用默认 sudo 密码 110734；建议通过环境变量 SUDO_PWD 覆盖"
    fi
}

# ------------------------------------------------------------------
# 端口检查
# ------------------------------------------------------------------

# check_ports
#   功能：检查关键端口是否已被占用，提前发现冲突。
#   说明：Kuscia Master 需要 53/80/8083 等端口；SecretPad 需要 8080/8443/8000。
 check_ports() {
    log_step "检查关键端口占用情况..."
    # 数组：需要检查的端口列表
    local ports=(53 80 8080 8082 8083 8092 8443 8000)
    # 数组：存储被占用的端口
    local occupied=()
    for port in "${ports[@]}"; do
        if port_in_use "$port"; then
            # 将被占用端口追加到 occupied 数组
            occupied+=("$port")
        fi
    done
    # ${#occupied[@]} 表示数组元素个数
    if [ ${#occupied[@]} -gt 0 ]; then
        log_warn "以下端口已被占用：${occupied[*]}"
        log_warn "若启动失败，请先释放这些端口（尤其是 53 / 80 / 8083）"
    else
        log_info "关键端口空闲"
    fi
}

# ------------------------------------------------------------------
# SecretFlow 构建
# ------------------------------------------------------------------

# build_secretflow
#   功能：编译并本地安装 SecretFlow。
#   说明：
#     - 先升级 kuscia Python 包（SecretFlow 的 Kuscia 入口依赖）
#     - 再通过 pip install -e . 将当前源码以可编辑模式安装到 conda 环境
#     - 最后执行自检，确认 privacy/l_diversity 组件已注册
 build_secretflow() {
    log_step "安装本地 SecretFlow（$SECRETFLOW_DIR）..."
    ensure_conda_env
    cd "$SECRETFLOW_DIR"

    # 使用阿里云 PyPI 镜像加速安装 kuscia
    # tail -n 5 仅显示最后 5 行，避免日志过长
    pip install -i https://mirrors.aliyun.com/pypi/simple/ --upgrade kuscia 2>&1 | tail -n 5

    # 可编辑安装本地 SecretFlow：修改源码后无需重新安装即可生效
    pip install -e . 2>&1 | tail -n 10

    # 自检：通过 here-document 运行一段 Python 代码
    # <<'PY' 表示 here-document 不展开变量，PY 是结束标记
    python - <<'PY'
from secretflow.component.core import Registry
d = Registry.get_definition_by_id('privacy/l_diversity:1.0.0')
assert d is not None, 'privacy/l_diversity:1.0.0 未注册'
print('SecretFlow 自检通过，已注册组件：privacy/l_diversity:1.0.0')
PY

    log_info "本地 SecretFlow 安装完成"
}

# ------------------------------------------------------------------
# Kuscia 构建
# ------------------------------------------------------------------

# build_kuscia
#   功能：编译本地 Kuscia 二进制。
#   说明：调用 kuscia/hack/build.sh -t kuscia 生成构建产物。
 build_kuscia() {
    log_step "编译本地 Kuscia ..."
    cd "$KUSCIA_DIR"
    bash hack/build.sh -t kuscia
    log_info "Kuscia 编译完成：$KUSCIA_DIR/build/apps/kuscia/kuscia"
}

# ------------------------------------------------------------------
# Kuscia Master 启动与停止
# ------------------------------------------------------------------

# start_kuscia_master
#   功能：启动 Kuscia Master（本地二进制模式，无 Docker）。
#   说明：
#     - 先调用 stop_kuscia_master 清理可能残留的进程
#     - KUSCIA_HOME 指定 Kuscia 运行时主目录
#     - 使用 sudo 启动，因为 Kuscia 需要监听 53 / 80 等特权端口
#     - run_local_kuscia.sh 启动脚本会快速退出，真实 kuscia 进程 PID 写入 KUSCIA_HOME/var/kuscia.pid
#   等待端口：
#     - 8082: Kuscia API HTTP
#     - 8083: Kuscia API gRPC
#     - 80: Kuscia Envoy 内部端口
 start_kuscia_master() {
    log_step "启动 Kuscia Master（本地二进制模式）..."

    # 清理残留，避免端口冲突或进程重复
    stop_kuscia_master

    # 导出 KUSCIA_HOME，使 run_local_kuscia.sh 能正确定位数据目录
    export KUSCIA_HOME="$KUSCIA_HOME"
    mkdir -p "$KUSCIA_HOME"

    # 使用 sudo 启动，因为 Kuscia Master 需要监听 53 / 80 等特权端口
    # 将标准输出和错误输出重定向到日志文件；& 放到后台执行
    run_sudo bash "$KUSCIA_DIR/scripts/run_local_kuscia.sh" master \
        > "$LOG_DIR/kuscia-master.log" 2>&1 &

    # run_local_kuscia.sh 启动后会快速退出，真实的 kuscia 进程 PID 写入 KUSCIA_HOME/var/kuscia.pid
    # 等待 2 秒，让 kuscia 进程有足够时间写入 pid 文件
    sleep 2
    local kuscia_pid
    # run_sudo cat 读取 root 权限创建的 pid 文件；|| true 防止读取失败时脚本退出
    kuscia_pid="$(run_sudo cat "$KUSCIA_HOME/var/kuscia.pid" 2>/dev/null || true)"
    if [ -n "$kuscia_pid" ]; then
        # 将 PID 保存到 PID_DIR，供后续 stop 使用
        echo "$kuscia_pid" > "$PID_DIR/kuscia-master.pid"
        log_info "Kuscia Master 已启动（pid $kuscia_pid）"
    else
        log_warn "未能从 $KUSCIA_HOME/var/kuscia.pid 读取 Kuscia PID，停止时将通过脚本处理"
    fi

    wait_for_port 127.0.0.1 8082 180 "Kuscia API HTTP"
    wait_for_port 127.0.0.1 8083 180 "Kuscia API gRPC"
    wait_for_port 127.0.0.1 80 180 "Kuscia Envoy 内部端口"
}

# stop_kuscia_master
#   功能：停止 Kuscia Master。
#   说明：
#     - 优先使用 run_local_kuscia.sh 自身的 --stop 参数进行优雅停止
#     - 若仍有残留 kuscia 进程，使用 pgrep 查找并通过 sudo 发送 SIGKILL
 stop_kuscia_master() {
    log_info "停止 Kuscia Master ..."
    export KUSCIA_HOME="$KUSCIA_HOME"
    # 优先使用脚本自身的 --stop
    if [ -f "$KUSCIA_HOME/var/kuscia.pid" ]; then
        run_sudo bash "$KUSCIA_DIR/scripts/run_local_kuscia.sh" --stop || true
    fi

    # 清理可能残留的 kuscia 进程
    # pgrep -f "kuscia start -c" 按完整命令行匹配 kuscia 主进程
    local remaining
    remaining="$(pgrep -f "kuscia start -c" 2>/dev/null || true)"
    if [ -n "$remaining" ]; then
        log_warn "发现残留 Kuscia 进程，强制清理..."
        # 注意：$remaining 故意不加引号，以允许空格分隔的多个 PID 被 kill 分别接收
        run_sudo kill -9 $remaining 2>/dev/null || true
    fi

    # 删除本地保存的 pid 文件
    rm -f "$PID_DIR/kuscia-master.pid"
}

# ------------------------------------------------------------------
# SecretPad 后端
# ------------------------------------------------------------------

# build_secretpad_backend
#   功能：编译 SecretPad 后端。
#   说明：使用 Maven 构建多模块项目，跳过测试以加速本地构建。
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

# generate_certs
#   功能：生成 KusciaAPI 客户端证书与后端 HTTPS 所需的 JKS。
#   说明：
#     - 若证书与 JKS 已存在则跳过，避免重复生成
#     - 否则先删除旧证书，再调用 secretpad/scripts/test/setup.sh 生成
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

# start_secretpad_backend
#   功能：启动 SecretPad 后端。
#   说明：
#     - 非 Docker 本地模式下，Kuscia 默认端口为 8082(HTTP)/8083(gRPC)
#     - Envoy 内部端口为 80
#     - KUSCIA_PROTOCOL=notls 关闭 TLS，简化本地开发
 start_secretpad_backend() {
    log_step "启动 SecretPad 后端..."
    # 先停止可能残留的后端进程
    stop_service_by_pidfile "$PID_DIR/secretpad-backend.pid" "SecretPad 后端"

    # 非 Docker 本地模式下，Kuscia 默认端口为 8082(HTTP)/8083(gRPC)，Envoy 内部端口为 80
    export KUSCIA_API_ADDRESS=127.0.0.1
    export KUSCIA_API_PORT=8083
    export KUSCIA_GW_ADDRESS=127.0.0.1:80
    export KUSCIA_PROTOCOL=notls

    # nohup 忽略 SIGHUP，& 后台运行
    # 日志重定向到 backend.log
    nohup java \
        -Dspring.profiles.active=dev \
        -Dsun.net.http.allowRestrictedHeaders=true \
        -Dserver.port=8443 \
        -jar "$SECRETPAD_DIR/target/secretpad.jar" > "$LOG_DIR/backend.log" 2>&1 &

    # 保存后台进程 PID
    echo $! > "$PID_DIR/secretpad-backend.pid"
    wait_for_port 127.0.0.1 8080 120 "后端 HTTP"
    log_info "SecretPad 后端已启动"
}

# ------------------------------------------------------------------
# SecretPad 前端
# ------------------------------------------------------------------

# start_secretpad_frontend
#   功能：启动 SecretPad 前端开发服务器。
#   说明：
#     - 配置前端代理文件 .env，将 /api 请求转发到后端 8080 端口
#     - 首次运行时安装前端依赖
#     - 使用 pnpm --filter secretpad dev 启动 Umi 开发服务器
 start_secretpad_frontend() {
    log_step "启动 SecretPad 前端..."
    stop_service_by_pidfile "$PID_DIR/secretpad-frontend.pid" "SecretPad 前端"

    # 前端代理配置文件路径
    local env_file="$SECRETPAD_DIR/frontend-src/apps/platform/.env"
    if [ ! -f "$env_file" ]; then
        log_info "创建前端代理配置 $env_file"
        echo "PROXY_URL=http://127.0.0.1:8080" > "$env_file"
    elif ! grep -q '^PROXY_URL=' "$env_file" 2>/dev/null; then
        log_info "向前端代理配置追加 PROXY_URL"
        echo "PROXY_URL=http://127.0.0.1:8080" >> "$env_file"
    fi

    cd "$SECRETPAD_DIR/frontend-src"
    # 通过判断 node_modules 是否存在来决定是否需要安装依赖
    if [ ! -d "node_modules" ]; then
        log_info "首次运行，安装前端依赖..."
        pnpm bootstrap
    fi

    # --filter secretpad 表示在 monorepo 中只启动 secretpad 应用
    nohup pnpm --filter secretpad dev > "$LOG_DIR/frontend.log" 2>&1 &
    echo $! > "$PID_DIR/secretpad-frontend.pid"
    wait_for_port 127.0.0.1 8000 120 "前端开发服务器"
    log_info "SecretPad 前端已启动"
}

# ------------------------------------------------------------------
# 服务停止与摘要
# ------------------------------------------------------------------

# stop_all_services
#   功能：停止所有由本脚本启动的服务。
#   说明：按前端 -> 后端 -> Kuscia Master 的顺序停止。
 stop_all_services() {
    log_step "停止所有服务..."
    stop_service_by_pidfile "$PID_DIR/secretpad-frontend.pid" "SecretPad 前端"
    stop_service_by_pidfile "$PID_DIR/secretpad-backend.pid" "SecretPad 后端"
    stop_kuscia_master
    log_info "所有服务已停止"
}

# print_summary
#   功能：打印启动成功后的摘要信息。
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

# ------------------------------------------------------------------
# 主函数
# ------------------------------------------------------------------

# main
#   功能：脚本入口，根据参数决定停止服务或完整启动。
#   参数：$@ - 命令行参数
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

# 调用主函数并将所有命令行参数传递给它
main "$@"
