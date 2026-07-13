#!/bin/bash
#
# ============================================================================
# sfwork Kuscia 镜像本地构建脚本
# ============================================================================
#
# 功能概述:
#   基于 kuscia/ 源码构建适用于当前宿主机架构的 Kuscia Docker 镜像。
#   在 macOS ARM64 (Apple Silicon) 上运行时，会生成原生的 linux/arm64 镜像，
#   避免 x86_64 镜像通过 Rosetta/QEMU 模拟运行带来的性能损失或兼容性问题。
#
# 前置条件:
#   - sfwork 工作区已克隆并包含 kuscia/ 源码
#   - Docker 已安装并启用 buildx
#   - Go 1.24.7+ 已安装(与 kuscia/go.mod 保持一致)
#   - 能访问 secretflow-registry.cn-hangzhou.cr.aliyuncs.com 拉取基础镜像
#
# 用法:
#   bash scripts/build-kuscia-image.sh              # 使用当前宿主机架构
#   bash scripts/build-kuscia-image.sh --arch arm64 # 显式指定 arm64
#   bash scripts/build-kuscia-image.sh --tag local  # 自定义额外标签
#   bash scripts/build-# ------------------------------------------------------------------
# 全局路径
# ------------------------------------------------------------------
readonly SFWORK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ------------------------------------------------------------------
# 颜色与日志 (定义为只读常量)
# ------------------------------------------------------------------
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }

usage() {
    cat <<EOF
用法:bash $(basename "$0") [OPTIONS]

选项:
  -a, --arch ARCH     目标架构:amd64 | arm64(默认自动检测宿主机架构)
  -t, --tag TAG       构建完成后额外打上的本地标签(默认:sfwork-local)
  -h, --help          显示本帮助信息

示例:
  # 在 Apple Silicon Mac 上构建 ARM64 镜像
  bash scripts/build-kuscia-image.sh

  # 显式指定架构并自定义本地标签
  bash scripts/build-kuscia-image.sh --arch arm64 --tag my-kuscia

构建完成后使用:
  KUSCIA_IMAGE=secretflow/kuscia:<TAG> bash scripts/dev-start.sh
EOF
}

# ------------------------------------------------------------------
# 主程序入口
# ------------------------------------------------------------------
main() {
    # 切换到工作区根目录
    cd "$SFWORK_ROOT"

    local ARCH=""
    local EXTRA_TAG="sfwork-local"

    # 命令行参数解析
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a | --arch)
                ARCH="$2"
                shift 2
                ;;
            -t | --tag)
                EXTRA_TAG="$2"
                shift 2
                ;;
            -h | --help)
                usage
                exit 0
                ;;
            *)
                log_error "未知参数:$1"
                usage
                exit 1
                ;;
        esac
    done

    # ------------------------------------------------------------------
    # 架构检测
    # ------------------------------------------------------------------
    if [[ -z "$ARCH" ]]; then
        case "$(uname -m)" in
            x86_64)
                ARCH="amd64"
                ;;
            aarch64 | arm64)
                ARCH="arm64"
                ;;
            *)
                log_error "不支持的宿主机架构:$(uname -m)"
                exit 1
                ;;
        esac
    fi

    case "$ARCH" in
        amd64 | arm64)
            ;;
        *)
            log_error "不支持的目标架构:$ARCH，仅支持 amd64 或 arm64"
            exit 1
            ;;
    esac

    # ------------------------------------------------------------------
    # 前置检查
    # ------------------------------------------------------------------
    log_step "检查构建环境 ..."

    if ! command -v docker >/dev/null 2>&1; then
        log_error "未找到 docker 命令，请先安装 Docker"
        exit 1
    fi

    if ! docker buildx version >/dev/null 2>&1; then
        log_error "Docker buildx 不可用"
        log_info "排查建议:"
        log_info "  1. 若使用 Docker Desktop，请升级到最新版(默认已包含 buildx)"
        log_info "  2. 若使用 Homebrew 安装的 docker CLI，请额外安装插件并建立软链:"
        log_info "       brew install docker-buildx"
        log_info "       mkdir -p ~/.docker/cli-plugins"
        log_info "       ln -sf /opt/homebrew/bin/docker-buildx ~/.docker/cli-plugins/docker-buildx"
        log_info "  3. 验证命令:docker buildx version"
        log_info ""
        log_info "注意:官方 Kuscia 镜像已支持 linux/arm64，如未修改 Kuscia 源码，"
        log_info "      可直接运行 bash scripts/dev-start.sh，无需本地构建镜像。"
        exit 1
    fi

    if ! command -v git >/dev/null 2>&1; then
        log_error "未找到 git 命令"
        exit 1
    fi

    if ! command -v go >/dev/null 2>&1; then
        log_error "未找到 go 命令，Kuscia 镜像构建需要 Go 1.24.7+"
        exit 1
    fi

    if [[ ! -d "$SFWORK_ROOT/kuscia" ]]; then
        log_error "未找到 kuscia/ 源码目录，请先在 sfwork 根目录下运行本脚本"
        exit 1
    fi

    # ------------------------------------------------------------------
    # 基础镜像地址(与 kuscia/scripts/make/image.mk 保持一致)
    # ------------------------------------------------------------------
    local envoy_image="${ENVOY_IMAGE:-secretflow-registry.cn-hangzhou.cr.aliyuncs.com/secretflow/kuscia-envoy:0.6.2b0}"
    local deps_image="${DEPS_IMAGE:-secretflow-registry.cn-hangzhou.cr.aliyuncs.com/secretflow/kuscia-deps:0.7.0b0}"

    # ------------------------------------------------------------------
    # 构建 Kuscia 镜像
    # ------------------------------------------------------------------
    log_step "开始构建 Kuscia linux/$ARCH 镜像 ..."
    log_info "目标架构:$ARCH"
    log_info "本地标签:secretflow/kuscia:$EXTRA_TAG"

    cd "$SFWORK_ROOT/kuscia"

    # 获取版本号
    local kuscia_version
    kuscia_version="$(git describe --tags --always 2>/dev/null || echo "dev")"
    
    local datetime
    datetime="$(date +"%Y%m%d%H%M%S")"
    
    local tag="${kuscia_version}-${datetime}"
    local image_name="secretflow/kuscia:${tag}"

    log_info "Kuscia version: $kuscia_version"
    log_info "Image name:     $image_name"

    # 编译 kuscia 二进制
    log_step "编译 kuscia 二进制(linux/$ARCH)..."
    GOOS=linux GOARCH="$ARCH" bash hack/build.sh -t kuscia

    # 整理 Dockerfile 需要的目录结构
    mkdir -p "build/linux/${ARCH}"
    rm -rf "build/linux/${ARCH}/apps"
    cp -rp build/apps "build/linux/${ARCH}/"

    # 使用默认的 docker driver builder 进行构建。
    # 在 Colima / Docker Desktop 等环境下，默认 builder 通常是 docker driver，
    # 直接使用本地 daemon 的 BuildKit，无需从 Docker Hub 拉取 moby/buildkit 镜像。
    log_step "构建 Kuscia Docker 镜像 ..."
    DOCKER_BUILDKIT=1 docker buildx build \
        --build-arg KUSCIA_ENVOY_IMAGE="${envoy_image}" \
        --build-arg DEPS_IMAGE="${deps_image}" \
        -f build/dockerfile/kuscia-anolis.Dockerfile \
        -t "${image_name}" \
        --platform "linux/${ARCH}" \
        --load \
        .

    # 额外打上 latest 与稳定的本地标签
    local built_image="secretflow/kuscia:latest"
    docker tag "${image_name}" "$built_image"
    docker tag "$built_image" "secretflow/kuscia:$EXTRA_TAG"

    # ------------------------------------------------------------------
    # 完成提示
    # ------------------------------------------------------------------
    echo ""
    log_info "Kuscia 镜像构建完成"
    log_info "镜像名(含版本):$image_name"
    log_info "镜像名(本地标签):secretflow/kuscia:$EXTRA_TAG"
    echo ""
    log_info "使用该镜像启动 sfwork 开发环境:"
    echo ""
    echo -e "  ${YELLOW}KUSCIA_IMAGE=secretflow/kuscia:$EXTRA_TAG bash scripts/dev-start.sh${NC}"
    echo ""
    log_info "或仅部署 Kuscia:"
    echo ""
    echo -e "  ${YELLOW}export KUSCIA_IMAGE=secretflow/kuscia:$EXTRA_TAG${NC}"
    echo -e "  ${YELLOW}cd secretpad && bash scripts/install-kuscia-only.sh master -P notls${NC}"
    echo ""
}

# 启动脚本
main "$@"
