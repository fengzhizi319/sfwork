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
# 环境变量配置：
#   - 可在 sfwork 根目录创建 .env 文件（参考 .env.example）
#   - 启动/停止脚本会自动读取 .env 中的变量
#   - 也可通过 DEV_START_ENV_FILE 指定其他 env 文件路径
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

# 各子项目路径
SECRETPAD_DIR="$SFWORK_ROOT/secretpad"     # SecretPad 前后端源码
SECRETFLOW_DIR="$SFWORK_ROOT/secretflow"   # SecretFlow 源码（含隐私计算组件）
KUSCIA_DIR="$SFWORK_ROOT/kuscia"           # Kuscia 源码（本次未改动）

# LOG_DIR: 聚合日志目录，后端/前端日志以及 PID 文件均存放于此
LOG_DIR="$SFWORK_ROOT/logs"
mkdir -p "$LOG_DIR"

# PRIVACY_IMAGE: 自定义 SecretFlow 镜像 tag
#   支持通过 .env 文件或环境变量覆盖，例如：
#   PRIVACY_IMAGE=myregistry/sf-privacy:dev bash scripts/dev-start.sh
PRIVACY_IMAGE="${PRIVACY_IMAGE:-secretflow/sf-privacy-dev:1.15.0.dev-privacy}"

# RESET_KUSCIA: 是否在启动前重置 Kuscia 容器及其数据目录
#   当自定义镜像发生变更（如新增/修改 SecretFlow 组件）后，旧 Kuscia 中注册的
#   secretflow AppImage 仍指向旧镜像，会导致新组件找不到。此时需要重置。
RESET_KUSCIA=false

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

# command_exists
#   功能：POSIX 标准方式检测命令是否存在于 PATH。
#   参数：$1 - 待检测的命令名
#   返回：0=存在，1=不存在
#   原理：command -v 输出命令路径；>/dev/null 2>&1 丢弃输出，仅保留退出码。
#   示例：command_exists java
command_exists() { command -v "$1" >/dev/null 2>&1; }

# version_ge
#   功能：比较两个版本号，判断 $1 >= $2。
#   参数：$1 - 待检测版本，$2 - 最低要求版本
#   返回：0=$1 大于等于 $2，否则 1
#   实现原理：
#     将 $2 和 $1 按行输出（注意顺序：$2 在前），使用 sort -V 按语义化版本排序，
#     再用 -C 检查是否已排序。若已排序，说明 $1 >= $2。
#   示例：
#     version_ge "17.0.11" "17"   -> 返回 0 (true)
#     version_ge "16.14.0" "17"   -> 返回 1 (false)
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
# check_environment
#   功能：检测所有必需运行时依赖是否已安装且版本满足要求。
#   参数：无
#   退出码：0=全部通过；任一依赖缺失或版本不足则 exit 1
#   检测顺序：Java -> Maven -> Node.js -> pnpm -> Docker -> conda
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
        # conda env list 列出所有环境；grep -qE 使用正则匹配行首的环境名。
        # ^$CONDA_ENV[[:space:]] 确保精确匹配环境名，避免 sf310 误匹配 sf310xxx。
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

# port_in_use
#   功能：检测指定 TCP 端口是否正在监听。
#   参数：$1 - 端口号
#   返回：0=已被占用，1=未被占用
#   原理：使用 ss -tln（比 netstat 更快，且无需 root 即可查看本机监听端口）
#   正则 \\b 用于精确匹配端口号，避免 8080 误匹配 18080。
port_in_use() {
    local port="$1"
    ss -tln 2>/dev/null | grep -qE ":$port\\b"
}

# port_pid
#   功能：获取占用指定端口的进程 ID。
#   参数：$1 - 端口号
#   输出：进程 ID（仅输出第一个匹配的 pid）
#   原理：从 ss -tlnp 的输出中提取 pid=数字。
port_pid() {
    local port="$1"
    ss -tlnp 2>/dev/null | grep -E ":$port\\b" | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2
}

# read_pidfile
#   功能：读取 PID 文件内容。
#   参数：$1 - PID 文件路径
#   输出：文件内容（PID）或空字符串
#   用途：用于判断端口占用是否来自本脚本之前启动的进程，避免误杀其他服务。
read_pidfile() {
    local f="$1"
    if [ -f "$f" ]; then cat "$f"; fi
}

# wait_for_port
#   功能：轮询等待指定端口就绪。
#   参数：
#     $1 - 主机名或 IP
#     $2 - 端口号
#     $3 - 超时秒数（默认 60）
#     $4 - 服务名称（用于日志）
#   返回：0=在超时前端口就绪，1=超时未就绪
#   优势：服务就绪后立即返回，比固定 sleep 更智能。
wait_for_port() {
    local host="$1" port="$2" timeout_sec="${3:-60}" what="$4"
    log_info "等待 $what 就绪：$host:$port（最多 ${timeout_sec}s）..."
    # C 语言风格 for 循环，从 0 计数到 timeout_sec-1
    for ((i = 0; i < timeout_sec; i++)); do
        if ss -tln 2>/dev/null | grep -qE ":$port\\b"; then
            log_info "$what 已就绪"
            return 0
        fi
        # 每次轮询间隔 1 秒，避免 CPU 空转
        sleep 1
    done
    log_error "$what 在 $host:$port 上未就绪，请查看日志"
    return 1
}

# check_required_ports
#   功能：检查关键端口占用情况，确保能正常启动各服务。
#   规则：
#     - 8080/8443 只能由本脚本启动的后端进程占用
#     - 8000 只能由本脚本启动的前端进程占用
#     - 18080/18082/18083/13081 仅在 Kuscia 未运行时被占用才报错
#   退出码：0=端口检查通过；1=发现冲突端口
check_required_ports() {
    log_step "检查关键端口占用情况 ..."
    local backend_pid frontend_pid
    backend_pid="$(read_pidfile "$LOG_DIR/backend.pid")"
    frontend_pid="$(read_pidfile "$LOG_DIR/frontend.pid")"

    # 判断 Kuscia master 容器是否已在运行
    local kuscia_running=false
    # docker ps --filter 按容器名过滤；--format 仅输出 Names 字段。
    # grep -q . 判断是否有任何输出（即容器存在且运行中）。
    if docker ps --filter "name=${USER}-kuscia-master" --format '{{.Names}}' | grep -q .; then
        kuscia_running=true
    fi

    local abort=false

    # 后端端口检测：8080（HTTP）、8443（HTTPS）
    for p in 8080 8443; do
        if port_in_use "$p"; then
            local pid
            pid="$(port_pid "$p")"
            # 如果占用的 PID 与 PID 文件一致，说明是本脚本之前启动的残留进程，不算冲突
            if [ -n "$backend_pid" ] && [ "$pid" = "$backend_pid" ]; then
                log_info "端口 $p 已由当前后端进程占用"
            else
                log_error "端口 $p 被其他进程（pid ${pid:-unknown}）占用，无法启动后端"
                log_warn "可尝试执行：sudo kill ${pid:-unknown}"
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
            log_warn "可尝试执行：sudo kill ${pid:-unknown}"
            abort=true
        fi
    fi

    # Kuscia 端口检测：仅在 Kuscia 未运行时被占用才报错
    if [ "$kuscia_running" = false ]; then
        for p in 18080 18082 18083 13081; do
            if port_in_use "$p"; then
                local pid
                pid="$(port_pid "$p")"
                log_error "端口 $p 已被占用（pid ${pid:-unknown}），无法部署 Kuscia"
                log_warn "可尝试执行：sudo kill ${pid:-unknown}"
                abort=true
            fi
        done
    else
        log_info "Kuscia 已在运行，其端口占用符合预期"
    fi

    # 若发现任何冲突，给出清理提示并退出
    if [ "$abort" = true ]; then
        log_error "请先释放占用端口，或执行 bash scripts/dev-stop.sh 清理残留进程"
        exit 1
    fi
}

# ------------------------------------------------------------------
# 进程管理工具函数
# ------------------------------------------------------------------

# is_process_alive
#   功能：检测进程是否存活。
#   参数：$1 - 进程 ID
#   返回：0=存活，1=不存在或无权限
#   说明：使用 ps -p 而非 kill -0，避免对没有权限的进程误判断。
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
#     1. 发送 SIGTERM（默认 kill）（允许进程清理资源）
#     2. 等待 1 秒
#     3. 若仍在运行，发送 SIGKILL（kill -9）强制终止
#     4. 删除 PID 文件，避免旧 PID 被后续误判。
stop_service_by_pidfile() {
    local pidfile="$1" name="$2"
    if [ -f "$pidfile" ]; then
        local pid
        pid="$(cat "$pidfile")"
        if is_process_alive "$pid"; then
            log_info "停止已运行的 $name（pid $pid）..."
            # kill 默认发送 SIGTERM（信号 15），允许进程优雅退出
            kill "$pid" 2>/dev/null || true
            sleep 1
            if is_process_alive "$pid"; then
                # SIGKILL（信号 9）强制终止，进程无法忽略
                kill -9 "$pid" 2>/dev/null || true
            fi
        fi
        # 删除 PID 文件，防止后续将旧 PID 误判为当前服务
        rm -f "$pidfile"
    fi
}

# ------------------------------------------------------------------
# 自定义 SecretFlow 镜像构建
# ------------------------------------------------------------------
# build_secretflow_image
#   功能：基于 secretflow/docker/privacy-dev/Dockerfile
#         构建包含本地 privacy/l_diversity 等组件的 SecretFlow 镜像。
#   构建流程：
#     1. 激活 conda 环境 sf310
#     2. 清理历史构建产物
#     3. 使用 python -m build --wheel 构建 wheel
#     4. 将 wheel 复制到 docker/privacy-dev/ 构建上下文
#     5. docker build 生成镜像
#   说明：如果镜像已存在，则跳过构建，避免重复耗时。
build_secretflow_image() {
    log_step "构建二次开发 SecretFlow 镜像：$PRIVACY_IMAGE ..."

    # 检查镜像是否已存在：docker image inspect 会返回镜像元数据
    if docker image inspect "$PRIVACY_IMAGE" >/dev/null 2>&1; then
        log_info "镜像 $PRIVACY_IMAGE 已存在，跳过构建"
        log_warn "如需重新构建，请先执行删除镜像的命令：docker rmi $PRIVACY_IMAGE"
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

# generate_certs
#   功能：生成 KusciaAPI 客户端证书与后端 HTTPS 所需的 JKS 密钥库。
#   说明：调用 secretpad 自带的测试证书生成脚本。
#   产物：config/certs/、config/server.jks
generate_certs() {
    log_step "生成 KusciaAPI 证书与后端 JKS ..."
    cd "$SECRETPAD_DIR"
    bash scripts/test/setup.sh
}

# build_backend
#   功能：使用 Maven 编译 SecretPad 后端，生成可执行 fat jar。
#   说明：
#     - 使用 install 而非 package，便于子模块间依赖解析
#     - -Dmaven.test.skip=true: 跳过测试，加速本地构建
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

# reset_kuscia
#   功能：删除已有的 Kuscia 容器及数据目录，强制下一次重新部署。
#   适用场景：自定义 SecretFlow 镜像更新后，Kuscia 中注册的 AppImage 仍指向旧镜像。
reset_kuscia() {
    log_step "重置 Kuscia 环境 ..."
    # 数组：需要删除的容器名。${USER} 展开为当前用户名，与 install-kuscia-only.sh 命名保持一致。
    local containers=(
        "${USER}-kuscia-master"
        "${USER}-kuscia-lite-alice"
        "${USER}-kuscia-lite-bob"
    )
    # for ... in 遍历数组；${containers[@]} 展开为数组元素列表。
    for ctr in "${containers[@]}"; do
        # 精确匹配容器名：^/${ctr}$ 防止误匹配前缀相同的容器
        if docker ps -a --filter "name=^/${ctr}$" --format '{{.Names}}' | grep -q .; then
            log_info "删除现有 Kuscia 容器：$ctr"
            # >/dev/null 2>&1 隐藏输出；|| true 保证即使删除失败也不中断脚本
            docker rm -f "$ctr" >/dev/null 2>&1 || true
        fi
    done

    # INSTALL_DIR 由 install-kuscia-only.sh 默认写入 $HOME/kuscia，允许通过环境变量覆盖。
    local kuscia_install_dir="${INSTALL_DIR:-$HOME/kuscia}"
    if [ -d "$kuscia_install_dir" ]; then
        log_warn "删除 Kuscia 数据目录：$kuscia_install_dir"
        # Kuscia 容器以 root 运行，部分数据文件（etcd、pod 日志）为 root 所有，
        # 直接 rm -rf 会权限不足。借助一个 root 权限的临时容器来清理。
        if docker run --rm -v "$kuscia_install_dir:/kuscia_tmp" busybox \
            sh -c 'find /kuscia_tmp -mindepth 1 -delete' >/dev/null 2>&1; then
            log_info "Kuscia 数据目录已清空"
        else
            log_warn "通过 Docker 容器清理失败，尝试 sudo rm -rf ..."
            sudo rm -rf "$kuscia_install_dir" >/dev/null 2>&1 || true
        fi
    fi
    log_info "Kuscia 环境已重置，下次启动将重新部署"
}

# start_kuscia
#   功能：部署 Kuscia 容器环境（master + alice + bob）。
#   关键：
#     1. 通过 SECRETFLOW_IMAGE 环境变量将自定义镜像透传给 install-kuscia-only.sh
#     2. install-kuscia-only.sh 会负责拉取/加载镜像、启动容器、注册 AppImage
#     3. Kuscia 代码未更新，因此 KUSCIA_IMAGE 保持官方镜像默认值
#   等待端口：
#     - 18083: Kuscia API gRPC（SecretPad 后端连接）
#     - 13081: Kuscia Envoy 内部端口（数据面通信）
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
        # -P notls：本地开发关闭 TLS，简化证书配置
        bash scripts/install-kuscia-only.sh master -P notls
    fi

    # Kuscia 启动较慢，设置 180 秒超时
    wait_for_port 127.0.0.1 18083 180 "Kuscia API gRPC"
    wait_for_port 127.0.0.1 13081 180 "Kuscia Envoy 内部端口"
}

# import_custom_image_to_lite
#   功能：将自定义 SecretFlow 镜像导入指定 Kuscia Lite 节点。
#   参数：$1 - 节点名，例如 alice 或 bob
#   返回：0=成功或无需导入，1=导入失败
#   说明：
#     - Kuscia 使用自己的容器镜像存储，宿主机 Docker 中的本地镜像不会自动对 Kuscia 可见。
#     - install-kuscia-only.sh 在全新部署时会导入镜像，但“启动已有容器”模式下不会重新导入，
#       这会导致任务 Pod 出现 ErrImagePull/ImagePullBackOff 而一直挂起。
#     - 本函数通过 stdin 直接加载镜像，避免 register_app_image_0.sh 因 images 目录权限问题失败。
import_custom_image_to_lite() {
    local node="$1"
    local ctr="${USER}-kuscia-lite-${node}"
    # 去掉可能的 docker.io/ 前缀，方便与 kuscia image list 输出比对
    local image_short="${PRIVACY_IMAGE#docker.io/}"
    # 从 tag 中分离镜像名和标签
    local image_name="${image_short%:*}"
    local image_tag="${image_short#*:}"

    # kuscia image list 输出列为：IMAGE TAG IMAGE_ID SIZE，
    # 其中 IMAGE 可能带有 docker.io/ 前缀。注意 kuscia 把列表写到 stderr，
    # 因此用 2>&1 合并后再过滤。
    local image_exists_in_kuscia
    image_exists_in_kuscia() {
        docker exec -i "${ctr}" kuscia image list 2>&1 \
            | grep -E "(${image_name}|docker\.io/${image_name})" \
            | grep -qF "${image_tag}"
    }

    # 如果 Lite 节点容器未运行，则跳过导入
    if ! docker ps --filter "name=^/${ctr}$" --format '{{.Names}}' | grep -q .; then
        log_warn "Kuscia lite ${node} 未运行，跳过镜像导入"
        return 0
    fi

    # 如果镜像已存在于 Kuscia 内部镜像仓库，则无需重复导入
    if image_exists_in_kuscia; then
        log_info "自定义镜像已在 ${node} 节点存在，跳过导入"
        return 0
    fi

    log_step "导入自定义镜像到 Kuscia ${node} 节点 ..."
    # docker save 将镜像导出为 tar 流，通过管道直接送入 docker exec -i 的 stdin，
    # 再由 kuscia image load 加载到 Kuscia 私有镜像存储。
    docker save "${PRIVACY_IMAGE}" | docker exec -i "${ctr}" kuscia image load
    if image_exists_in_kuscia; then
        log_info "自定义镜像已成功导入 ${node} 节点"
    else
        log_error "自定义镜像导入 ${node} 节点失败，请检查 Kuscia 日志"
        return 1
    fi
}

# import_custom_image_to_kuscia
#   功能：确保自定义镜像对 Kuscia 各 Lite 节点可用。
import_custom_image_to_kuscia() {
    log_step "检查并导入自定义 SecretFlow 镜像到 Kuscia ..."
    import_custom_image_to_lite alice
    import_custom_image_to_lite bob
}

# start_backend
#   功能：启动 SecretPad 后端服务。
#   环境变量说明：
#     KUSCIA_API_ADDRESS: Kuscia API 地址
#     KUSCIA_API_PORT: Kuscia API gRPC 端口（install-kuscia-only.sh master 默认映射到宿主机 18083）
#     KUSCIA_GW_ADDRESS: Kuscia Gateway 地址（Envoy 内部端口映射到宿主机 13081）
#     KUSCIA_PROTOCOL: notls，本地开发关闭 TLS
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

    # $! 保存最近一个后台进程的 PID；将其写入 PID 文件以便后续停止或检查
    echo $! > "$pidfile"
    log_info "后端进程已启动，pid $!"
    wait_for_port 127.0.0.1 8080 120 "后端 HTTP"
}

# start_frontend
#   功能：启动 SecretPad 前端开发服务器。
#   说明：
#     - 前端通过 .env 文件中的 PROXY_URL 将 /api 请求转发到后端 8080 端口
#     - 首次运行时会执行 pnpm bootstrap 安装依赖并构建 workspace 内部包
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
        # 文件不存在时直接创建并写入 PROXY_URL
        echo "PROXY_URL=http://127.0.0.1:8080" > "$env_file"
    elif ! grep -q '^PROXY_URL=' "$env_file" 2>/dev/null; then
        # 文件存在但缺少 PROXY_URL 时追加一行
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

# print_summary
#   功能：打印启动成功后的摘要信息。
#   输出内容：访问地址、登录账号、日志位置、停止命令。
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
#   --reset-kuscia: 设置 RESET_KUSCIA=true 后继续执行完整启动流程
#   无参数：       执行完整启动流程
case "${1:-}" in
--check | -c)
    check_environment
    echo ""
    log_info "环境检查通过"
    exit 0
    ;;
--reset-kuscia)
    # 设置标志后 shift，然后继续执行 case 之后的启动流程
    RESET_KUSCIA=true
    shift
    ;;
--help | -h)
    # here-document：从 <<EOF 到 EOF 之间的内容作为 cat 的输入，用于输出多行帮助文本
    cat <<EOF
sfwork 二次开发环境一键启动脚本（使用自定义 SecretFlow 镜像）

用法：
  bash scripts/dev-start.sh          完整启动
  bash scripts/dev-start.sh --check  仅检查环境
  bash scripts/dev-start.sh --reset-kuscia  重置 Kuscia 后完整启动
  bash scripts/dev-start.sh --help          显示本帮助

环境变量：
  PRIVACY_IMAGE        自定义 SecretFlow 镜像 tag（默认：secretflow/sf-privacy-dev:1.15.0.dev-privacy）
  CONDA_ENV            构建 wheel 时使用的 conda 环境（默认：sf310）
  INSTALL_DIR          Kuscia 安装目录（默认：$HOME/kuscia）
  LOG_DIR              日志与 PID 文件目录（默认：<sfwork>/logs）
  DEV_START_ENV_FILE   自定义 env 文件路径（默认：<sfwork>/.env）

停止服务：
  bash scripts/dev-stop.sh
  bash scripts/dev-stop.sh --kuscia  # 同时停止 Kuscia 容器

重置 Kuscia（自定义镜像更新后必需）：
  bash scripts/dev-start.sh --reset-kuscia
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
if [ "$RESET_KUSCIA" = true ]; then
    reset_kuscia
fi
start_kuscia
import_custom_image_to_kuscia
start_backend
start_frontend
print_summary
