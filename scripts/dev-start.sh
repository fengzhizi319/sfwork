#!/bin/bash
#
# ============================================================================
# sfwork 二次开发环境一键启动脚本（使用自定义 SecretFlow 隐私计算镜像）
# ============================================================================
#
# 功能概述：
#   本脚本用于一键拉起完整的 sfwork 二次开发环境，核心特点：
#   1. 检测 JDK 17 / Maven / Node.js / pnpm / Docker / conda 等运行时依赖
#   2. 基于 sfwork/secretflow 本地源码构建自定义 SecretFlow 镜像
#      （默认 tag：secretflow/sf-privacy-dev:1.15.0.dev-privacy）
#   3. 部署 Kuscia Docker 环境（Master + alice + bob 三节点）
#   4. 将上述自定义镜像注册为 Kuscia AppImage，供任务调度使用
#   5. 编译并启动 sfwork/secretpad 后端服务（Spring Boot fat jar）
#   6. 启动 sfwork/secretpad 前端开发服务器（Umi dev server）
#
# 设计说明：
#   - Kuscia 代码本次未更新，因此继续使用官方 Kuscia 镜像。
#   - SecretFlow 使用本地二次开发镜像，通过 SECRETFLOW_IMAGE 环境变量透传给
#     secretpad/scripts/install-kuscia-only.sh，确保任务执行时使用新组件。
#   - 后端、前端均从 sfwork/secretpad 本地源码启动，便于源码调试。
#
# 前置条件：
#   - sfwork 已克隆到 /home/charles/code/sfwork
#   - 已创建 conda 环境 sf310（仅在构建 SecretFlow 镜像时需要）
#   - Docker 可用且当前用户有权限执行 docker 命令
#
# 用法：
#   bash scripts/dev-start.sh          # 完整启动
#   bash scripts/dev-start.sh --check  # 仅检查环境
#   bash scripts/dev-start.sh --help   # 显示帮助
#
# 停止服务：
#   bash scripts/dev-stop.sh
#   bash scripts/dev-stop.sh --kuscia  # 同时停止 Kuscia 容器
# ============================================================================

# Bash 严格模式：
#   -e: 任一命令失败立即退出，避免错误继续执行导致更难排查
#   -u: 使用未定义变量时报错，防止拼写错误
#   -o pipefail: 管道中任一命令失败则整个管道失败
set -euo pipefail

# ------------------------------------------------------------------
# 全局路径与变量
# ------------------------------------------------------------------
# SFWORK_ROOT: sfwork 工作区根目录，所有子项目均在此目录下
SFWORK_ROOT="/home/charles/code/sfwork"

# 各子项目路径
SECRETPAD_DIR="$SFWORK_ROOT/secretpad"     # SecretPad 前后端源码
SECRETFLOW_DIR="$SFWORK_ROOT/secretflow"   # SecretFlow 源码（含隐私计算组件）
KUSCIA_DIR="$SFWORK_ROOT/kuscia"           # Kuscia 源码（本次未改动）

# LOG_DIR: 聚合日志目录，后端/前端日志以及 PID 文件均存放于此
LOG_DIR="$SFWORK_ROOT/logs"
mkdir -p "$LOG_DIR"

# PRIVACY_IMAGE: 自定义 SecretFlow 镜像 tag
#   支持通过环境变量覆盖，例如：
#   PRIVACY_IMAGE=myregistry/sf-privacy:dev bash scripts/dev-start.sh
PRIVACY_IMAGE="${PRIVACY_IMAGE:-secretflow/sf-privacy-dev:1.15.0.dev-privacy}"

# CONDA_ENV: 构建 SecretFlow wheel 时使用的 conda 环境名称
CONDA_ENV="${CONDA_ENV:-sf310}"

# ------------------------------------------------------------------
# 颜色与日志系统
# ------------------------------------------------------------------
# ANSI 转义码，用于终端彩色输出，提升可读性
RED='\033[0;31m'      # 红色：错误
GREEN='\033[0;32m'    # 绿色：成功/信息
YELLOW='\033[1;33m'   # 黄色：警告
BLUE='\033[0;34m'     # 蓝色：步骤提示
NC='\033[0m'          # 重置颜色

# 日志函数：统一格式化输出
# log_error 重定向到 stderr，便于外部脚本或 CI 捕获错误
log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }

# ------------------------------------------------------------------
# 工具函数库
# ------------------------------------------------------------------

# command_exists: POSIX 标准方式检测命令是否存在于 PATH
# 返回：0=存在，1=不存在
command_exists() { command -v "$1" >/dev/null 2>&1; }

# version_ge: 版本号比较，判断 $1 >= $2
# 实现原理：
#   将 $2 和 $1 按行输出（注意顺序：$2 在前），使用 sort -V 按语义化版本排序，
#   再用 -C 检查是否已排序。若已排序，说明 $1 >= $2。
# 示例：
#   version_ge "17.0.11" "17"   -> 返回 0 (true)
#   version_ge "16.14.0" "17"   -> 返回 1 (false)
version_ge() {
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

# 获取各运行时版本号
# java -version 输出到 stderr，因此需要 2>&1 重定向
get_java_version() { java -version 2>&1 | awk -F '"' '/version/ {print $2}' | head -1; }
get_mvn_version() { mvn -version 2>&1 | head -1 | grep -oE '[0-9]+(\.[0-9]+)+' | head -1; }
get_node_version() { node -v 2>/dev/null | sed 's/^v//'; }
get_pnpm_version() { corepack pnpm -v 2>/dev/null || true; }
get_docker_version() { docker --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -1; }

# ------------------------------------------------------------------
# 环境检测
# ------------------------------------------------------------------
# check_environment: 检测所有必需运行时依赖
# 检测顺序：Java -> Maven -> Node.js -> pnpm -> Docker -> conda
# 任一依赖缺失或版本不足都会报错退出
check_environment() {
    log_step "检查本地开发环境 ..."

    # Java 检测：SecretPad 后端需要 JDK 17+
    if command_exists java && version_ge "$(get_java_version)" "17"; then
        log_info "Java $(get_java_version) 已满足要求"
    else
        log_error "需要 JDK 17+，请安装后重试"
        exit 1
    fi

    # Maven 检测：SecretPad 多模块项目需要 Maven 3.8.8+
    if command_exists mvn && version_ge "$(get_mvn_version)" "3.8.8"; then
        log_info "Maven $(get_mvn_version) 已满足要求"
    else
        log_error "需要 Maven 3.8.8+，请安装后重试"
        exit 1
    fi

    # Node.js 检测：前端项目最低要求 16.14.0
    if command_exists node && version_ge "$(get_node_version)" "16.14.0"; then
        log_info "Node.js $(get_node_version) 已满足要求"
    else
        log_error "需要 Node.js 16.14.0+，请安装后重试"
        exit 1
    fi

    # pnpm 检测：通过 Node.js 内置的 corepack 管理，版本锁定为 8.8.0
    if command_exists corepack; then
        local pnpm_ver
        pnpm_ver="$(get_pnpm_version)"
        if [ "$pnpm_ver" = "8.8.0" ]; then
            log_info "pnpm $pnpm_ver（通过 corepack）已满足要求"
        else
            log_warn "正在通过 corepack 安装 pnpm@8.8.0 ..."
            # 在 frontend-src 目录下执行，读取 package.json 中的 packageManager 配置
            (cd "$SECRETPAD_DIR/frontend-src" && corepack install)
        fi
    else
        log_error "未找到 corepack，请升级 Node.js 到 16.10+ 或手动安装 pnpm 8.8.0"
        exit 1
    fi

    # Docker 检测：Kuscia 容器化部署必需
    if command_exists docker; then
        local docker_ver
        docker_ver="$(get_docker_version)"
        if version_ge "$docker_ver" "20.10.0"; then
            log_info "Docker $docker_ver 已满足要求"
        else
            log_error "需要 Docker 20.10+，当前版本 $docker_ver"
            exit 1
        fi
    else
        log_error "未找到 Docker，请手动安装 Docker >= 20.10"
        exit 1
    fi

    # conda 检测：构建 SecretFlow wheel 需要 sf310 环境
    if command_exists conda; then
        if conda env list | grep -qE "^$CONDA_ENV[[:space:]]"; then
            log_info "Conda 环境 $CONDA_ENV 已存在"
        else
            log_error "Conda 环境 $CONDA_ENV 不存在，请先创建：conda create -n $CONDA_ENV python=3.10 -y"
            exit 1
        fi
    else
        log_error "未找到 conda，请先安装 Miniconda/Anaconda"
        exit 1
    fi
}

# ------------------------------------------------------------------
# 端口检测与管理
# ------------------------------------------------------------------

# port_in_use: 检测指定 TCP 端口是否正在监听
# 使用 ss -tln（比 netstat 更快，且无需 root 即可查看本机监听端口）
# 正则 \\b 用于精确匹配端口号，避免 8080 误匹配 18080
port_in_use() {
    local port="$1"
    ss -tln 2>/dev/null | grep -qE ":$port\\b"
}

# port_pid: 获取占用指定端口的进程 ID
# 实现：从 ss -tlnp 的输出中提取 pid=数字
port_pid() {
    local port="$1"
    ss -tlnp 2>/dev/null | grep -E ":$port\\b" | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2
}

# read_pidfile: 读取 PID 文件内容
# 用于判断端口占用是否来自本脚本之前启动的进程，避免误杀其他服务
read_pidfile() {
    local f="$1"
    if [ -f "$f" ]; then cat "$f"; fi
}

# wait_for_port: 轮询等待指定端口就绪
# 参数：$1=host, $2=port, $3=超时秒数（默认 60）, $4=服务名称
# 优势：服务就绪后立即返回，比固定 sleep 更智能
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

# check_required_ports: 检查关键端口占用情况
# 规则：
#   - 8080/8443 只能由本脚本启动的后端进程占用
#   - 8000 只能由本脚本启动的前端进程占用
#   - 18080/18082/18083/13081 仅在 Kuscia 未运行时被占用才报错
# 若检测到冲突，提示用户先执行 dev-stop.sh 清理
check_required_ports() {
    log_step "检查关键端口占用情况 ..."
    local backend_pid frontend_pid
    backend_pid="$(read_pidfile "$LOG_DIR/backend.pid")"
    frontend_pid="$(read_pidfile "$LOG_DIR/frontend.pid")"

    # 判断 Kuscia master 容器是否已在运行
    local kuscia_running=false
    if docker ps --filter "name=${USER}-kuscia-master" --format '{{.Names}}' | grep -q .; then
        kuscia_running=true
    fi

    local abort=false

    # 后端端口检测：8080（HTTP）、8443（HTTPS）
    for p in 8080 8443; do
        if port_in_use "$p"; then
            local pid
            pid="$(port_pid "$p")"
            if [ -n "$backend_pid" ] && [ "$pid" = "$backend_pid" ]; then
                log_info "端口 $p 已由当前后端进程占用"
            else
                log_error "端口 $p 被其他进程（pid ${pid:-unknown}）占用，无法启动后端"
                abort=true
            fi
        fi
    done

    # 前端端口检测：8000
    if port_in_use 8000; then
        local pid
        pid="$(port_pid 8000)"
        if [ -n "$frontend_pid" ] && [ "$pid" = "$frontend_pid" ]; then
            log_info "端口 8000 已由当前前端进程占用"
        else
            log_error "端口 8000 被其他进程（pid ${pid:-unknown}）占用，无法启动前端"
            abort=true
        fi
    fi

    # Kuscia 端口检测：仅在 Kuscia 未运行时被占用才报错
    if [ "$kuscia_running" = false ]; then
        for p in 18080 18082 18083 13081; do
            if port_in_use "$p"; then
                log_error "端口 $p 已被占用，无法部署 Kuscia"
                abort=true
            fi
        done
    else
        log_info "Kuscia 已在运行，其端口占用符合预期"
    fi

    if [ "$abort" = true ]; then
        log_error "请先释放占用端口，或执行 bash scripts/dev-stop.sh 清理残留进程"
        exit 1
    fi
}

# ------------------------------------------------------------------
# 进程管理工具函数
# ------------------------------------------------------------------

# is_process_alive: 检测进程是否存活
# 使用 ps -p 而非 kill -0，避免对没有权限的进程误判断
is_process_alive() {
    local pid="$1"
    [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1
}

# stop_service_by_pidfile: 根据 PID 文件优雅停止服务
# 停止策略：
#   1. 发送 SIGTERM（允许进程清理资源）
#   2. 等待 1 秒
#   3. 若仍在运行，发送 SIGKILL 强制终止
#   4. 删除 PID 文件
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
# 自定义 SecretFlow 镜像构建
# ------------------------------------------------------------------
# build_secretflow_image: 基于 secretflow/docker/privacy-dev/Dockerfile
# 构建包含本地 privacy/l_diversity 组件的 SecretFlow 镜像
#
# 构建流程：
#   1. 激活 conda 环境 sf310
#   2. 清理历史构建产物
#   3. 使用 python -m build --wheel 构建 wheel
#   4. 将 wheel 复制到 docker/privacy-dev/ 构建上下文
#   5. docker build 生成镜像
#
# 如果镜像已存在，则跳过构建，避免重复耗时
build_secretflow_image() {
    log_step "构建二次开发 SecretFlow 镜像：$PRIVACY_IMAGE ..."

    # 检查镜像是否已存在：docker image inspect 会返回镜像元数据
    if docker image inspect "$PRIVACY_IMAGE" >/dev/null 2>&1; then
        log_info "镜像 $PRIVACY_IMAGE 已存在，跳过构建"
        log_warn "如需重新构建，请先执行：docker rmi $PRIVACY_IMAGE"
        return 0
    fi

    # 激活 conda 环境
    # 通过 source conda.sh 使当前 shell 支持 conda activate，不修改用户 shell 配置文件
    local conda_base
    conda_base="$(conda info --base)"
    # shellcheck source=/dev/null
    source "$conda_base/etc/profile.d/conda.sh"
    conda activate "$CONDA_ENV"

    cd "$SECRETFLOW_DIR"

    log_info "清理历史构建产物 ..."
    # dist/：wheel 输出目录
    # build/：setuptools 构建临时目录
    rm -rf dist build

    log_info "构建 SecretFlow wheel ..."
    # --wheel: 仅构建 wheel，跳过 sdist，节省时间
    python -m build --wheel

    # 查找构建出的 wheel 文件（按文件名通配，避免硬编码版本号）
    local wheel
    wheel="$(ls "$SECRETFLOW_DIR"/dist/secretflow-*.whl | head -1)"
    if [ -z "$wheel" ]; then
        log_error "未找到构建出的 wheel 文件"
        exit 1
    fi
    log_info "wheel 文件：$wheel"

    # 将 wheel 复制到 Dockerfile 所在目录作为构建上下文
    mkdir -p "$SECRETFLOW_DIR/docker/privacy-dev"
    cp "$wheel" "$SECRETFLOW_DIR/docker/privacy-dev/"

    cd "$SECRETFLOW_DIR/docker/privacy-dev"
    log_info "构建 Docker 镜像 ..."
    docker build . -f Dockerfile -t "$PRIVACY_IMAGE"

    log_info "镜像构建完成：$PRIVACY_IMAGE"
}

# ------------------------------------------------------------------
# 各服务启动函数
# ------------------------------------------------------------------
# 启动顺序（依赖关系）：
#   生成证书 -> 编译后端 -> 构建镜像 -> 启动 Kuscia -> 启动后端 -> 启动前端

# generate_certs: 生成 KusciaAPI 客户端证书与后端 HTTPS 所需的 JKS 密钥库
# 调用 secretpad 自带的测试证书生成脚本
# 产物：config/certs/、config/server.jks
generate_certs() {
    log_step "生成 KusciaAPI 证书与后端 JKS ..."
    cd "$SECRETPAD_DIR"
    bash scripts/test/setup.sh
}

# build_backend: 使用 Maven 编译 SecretPad 后端，生成可执行 fat jar
# 使用 install 而非 package，便于子模块间依赖解析
# -Dmaven.test.skip=true: 跳过测试，加速本地构建
build_backend() {
    log_step "编译 SecretPad 后端 ..."
    cd "$SECRETPAD_DIR"
    mvn clean install -Dmaven.test.skip=true
    if [ ! -f "$SECRETPAD_DIR/target/secretpad.jar" ]; then
        log_error "后端编译失败：未找到 target/secretpad.jar"
        exit 1
    fi
    log_info "后端编译完成"
}

# start_kuscia: 部署 Kuscia 容器环境（master + alice + bob）
# 关键：
#   1. 通过 SECRETFLOW_IMAGE 环境变量将自定义镜像透传给 install-kuscia-only.sh
#   2. install-kuscia-only.sh 会负责拉取/加载镜像、启动容器、注册 AppImage
#   3. Kuscia 代码未更新，因此 KUSCIA_IMAGE 保持官方镜像默认值
#
# 等待端口：
#   - 18083: Kuscia API gRPC（SecretPad 后端连接）
#   - 13081: Kuscia Envoy 内部端口（数据面通信）
start_kuscia() {
    log_step "检查 Kuscia Docker 环境 ..."

    # 如果 Kuscia master 容器已在运行，则跳过部署，支持热更新后端/前端
    if docker ps --filter "name=${USER}-kuscia-master" --format '{{.Names}}' | grep -q .; then
        log_info "Kuscia master 已在运行，跳过部署"
    else
        log_info "正在部署 Kuscia（master + alice + bob）..."
        log_warn "如果脚本询问 'Whether to retain k3s data?(y/n):'，首次部署建议输入 n"

        cd "$SECRETPAD_DIR"
        # 关键：通过环境变量指定二次开发镜像，install-kuscia-only.sh 已支持覆盖
        export SECRETFLOW_IMAGE="$PRIVACY_IMAGE"
        # Kuscia 代码本次未更新，继续使用官方 Kuscia 镜像即可
        bash scripts/install-kuscia-only.sh master -P notls
    fi

    # Kuscia 启动较慢，设置 180 秒超时
    wait_for_port 127.0.0.1 18083 180 "Kuscia API gRPC"
    wait_for_port 127.0.0.1 13081 180 "Kuscia Envoy 内部端口"
}

# start_backend: 启动 SecretPad 后端服务
# 环境变量说明：
#   KUSCIA_API_ADDRESS: Kuscia API 地址
#   KUSCIA_API_PORT: Kuscia API gRPC 端口（install-kuscia-only.sh master 默认映射到宿主机 18083）
#   KUSCIA_GW_ADDRESS: Kuscia Gateway 地址（Envoy 内部端口映射到宿主机 13081）
#   KUSCIA_PROTOCOL: notls，本地开发关闭 TLS
start_backend() {
    log_step "启动 SecretPad 后端 ..."
    local pidfile="$LOG_DIR/backend.pid"

    # 如果后端已在运行且 PID 文件有效，则跳过
    if [ -f "$pidfile" ] && is_process_alive "$(cat "$pidfile")"; then
        log_info "后端已在运行（pid $(cat "$pidfile")）"
        return 0
    fi
    # 否则先清理可能残留的 PID 文件和进程
    stop_service_by_pidfile "$pidfile" "backend"

    export KUSCIA_API_ADDRESS=127.0.0.1
    export KUSCIA_API_PORT=18083
    export KUSCIA_GW_ADDRESS=127.0.0.1:13081
    export KUSCIA_PROTOCOL=notls

    # nohup: 忽略 SIGHUP，终端关闭后进程继续运行
    # 标准输出和错误输出重定向到日志文件
    nohup java \
        -Dspring.profiles.active=dev \
        -Dsun.net.http.allowRestrictedHeaders=true \
        -Dserver.port=8443 \
        -jar "$SECRETPAD_DIR/target/secretpad.jar" > "$LOG_DIR/backend.log" 2>&1 &

    echo $! > "$pidfile"
    log_info "后端进程已启动，pid $!"
    wait_for_port 127.0.0.1 8080 120 "后端 HTTP"
}

# start_frontend: 启动 SecretPad 前端开发服务器
# 前端通过 .env 文件中的 PROXY_URL 将 /api 请求转发到后端 8080 端口
start_frontend() {
    log_step "启动 SecretPad 前端 ..."
    local pidfile="$LOG_DIR/frontend.pid"

    if [ -f "$pidfile" ] && is_process_alive "$(cat "$pidfile")"; then
        log_info "前端已在运行（pid $(cat "$pidfile")）"
        return 0
    fi
    stop_service_by_pidfile "$pidfile" "frontend"

    # 确保前端代理配置指向本地后端 HTTP 端口
    local env_file="$SECRETPAD_DIR/frontend-src/apps/platform/.env"
    if [ ! -f "$env_file" ]; then
        echo "PROXY_URL=http://127.0.0.1:8080" > "$env_file"
    elif ! grep -q '^PROXY_URL=' "$env_file" 2>/dev/null; then
        echo "PROXY_URL=http://127.0.0.1:8080" >> "$env_file"
    fi

    cd "$SECRETPAD_DIR/frontend-src"
    # 首次运行时安装依赖并构建 workspace 内部包
    if [ ! -d "node_modules" ]; then
        log_info "首次运行，安装前端依赖 ..."
        corepack pnpm bootstrap
    fi

    # --filter secretpad: 在 monorepo 中仅启动 secretpad 应用
    nohup corepack pnpm --filter secretpad dev > "$LOG_DIR/frontend.log" 2>&1 &
    echo $! > "$pidfile"
    log_info "前端进程已启动，pid $!"
    wait_for_port 127.0.0.1 8000 120 "前端开发服务器"
}

# print_summary: 打印启动成功后的摘要信息
# 包含访问地址、登录账号、日志位置、停止命令
print_summary() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  sfwork 二次开发环境已启动${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "🌐 前端开发服务器：${BLUE}http://localhost:8000${NC}"
    echo -e "🔧 后端健康检查：${BLUE}http://localhost:8080/actuator/health${NC}"
    echo -e "🔒 后端 HTTPS 地址：${BLUE}https://localhost:8443${NC}"
    echo ""
    echo -e "🐳 自定义 SecretFlow 镜像：${YELLOW}$PRIVACY_IMAGE${NC}"
    echo -e "👤 登录账号：${YELLOW}admin / 12345678${NC}"
    echo ""
    echo -e "📄 日志文件："
    echo -e "   后端：$LOG_DIR/backend.log"
    echo -e "   前端：$LOG_DIR/frontend.log"
    echo ""
    echo -e "🛑 停止服务：${YELLOW}bash scripts/dev-stop.sh${NC}"
    echo -e "🛑 同时停止 Kuscia：${YELLOW}bash scripts/dev-stop.sh --kuscia${NC}"
    echo ""
}

# ------------------------------------------------------------------
# 命令行参数解析
# ------------------------------------------------------------------
# 支持模式：
#   --check / -c: 仅检查环境
#   --help / -h:  显示帮助
#   无参数：       执行完整启动流程
case "${1:-}" in
--check | -c)
    check_environment
    echo ""
    log_info "环境检查通过"
    exit 0
    ;;
--help | -h)
    cat <<EOF
sfwork 二次开发环境一键启动脚本（使用自定义 SecretFlow 镜像）

用法：
  bash scripts/dev-start.sh          完整启动
  bash scripts/dev-start.sh --check  仅检查环境
  bash scripts/dev-start.sh --help   显示本帮助

环境变量：
  PRIVACY_IMAGE   自定义 SecretFlow 镜像 tag（默认：secretflow/sf-privacy-dev:1.15.0.dev-privacy）
  CONDA_ENV       构建 wheel 时使用的 conda 环境（默认：sf310）

停止服务：
  bash scripts/dev-stop.sh
  bash scripts/dev-stop.sh --kuscia  # 同时停止 Kuscia 容器
EOF
    exit 0
    ;;
esac

# ------------------------------------------------------------------
# 主启动流程
# ------------------------------------------------------------------
# 严格按照依赖关系执行：
#   1. 检查环境
#   2. 检查端口
#   3. 生成证书
#   4. 编译后端
#   5. 构建自定义 SecretFlow 镜像
#   6. 部署 Kuscia
#   7. 启动后端
#   8. 启动前端
#   9. 打印摘要
#
# set -euo pipefail 保证任一步骤失败会立即退出并返回非零状态码
check_environment
check_required_ports
generate_certs
build_backend
build_secretflow_image
start_kuscia
start_backend
start_frontend
print_summary
