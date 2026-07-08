#!/bin/bash
#
# Docker 镜像打包示例脚本
# 功能：使用 docker buildx 构建镜像，支持指定平台、推送仓库、导出 tar 包。
# 用法：bash scripts/build.sh [OPTIONS]
#

# set -e：遇到任何命令失败时立即退出，避免错误继续执行。
set -e

# 获取脚本所在目录的上一层（即项目根目录），并切换到项目根目录。
# 这样无论从哪个路径调用 scripts/build.sh，都能正确找到 Dockerfile。
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# ==================== 默认值配置 ====================
# 这些变量可以在命令行通过参数覆盖。

# 镜像名，最终镜像形如 docker-packaging-demo:dev-20260101120000
IMAGE_NAME="docker-packaging-demo"

# 镜像 Tag，默认使用 dev- 前缀 + 当前时间戳，避免多次构建 tag 冲突。
VERSION="dev-$(date +%Y%m%d%H%M%S)"

# 镜像仓库前缀（可选）。若设置，镜像名会变为 ${REGISTRY}/${IMAGE_NAME}:${VERSION}
REGISTRY=""

# 目标构建平台，默认 linux/amd64。可改为 linux/arm64 体验多平台构建。
PLATFORM="linux/amd64"

# 是否推送镜像到远程仓库，默认 false。
PUSH=false

# 是否导出为 tar 包，默认 false。
EXPORT_TAR=false

# ==================== 帮助信息 ====================
# usage 函数：当用户传入 -h/--help 或未知参数时显示帮助并退出。
usage() {
    cat <<EOF
用法: $0 [OPTIONS]

选项:
  -n, --name NAME      镜像名 (默认: docker-packaging-demo)
  -v, --version VER    版本号/Tag (默认: dev-<datetime>)
  -r, --registry URL   镜像仓库前缀，例如 registry.example.com/demo
  -p, --platform PLAT  目标平台 (默认: linux/amd64)
      --push           构建完成后推送镜像
      --tar            构建完成后导出为 tar 包
  -h, --help           显示帮助

示例:
  bash scripts/build.sh
  bash scripts/build.sh -v 1.0.0 --tar
  bash scripts/build.sh -r registry.example.com/demo -v 1.0.0 --push
EOF
}

# ==================== 命令行参数解析 ====================
# 使用 while + case 循环解析参数。每处理一个参数后 shift 移动位置。
while [[ $# -gt 0 ]]; do
    case $1 in
        # -n 或 --name：设置镜像名，后面紧跟的值赋给 IMAGE_NAME，并向后移动 2 个位置。
        -n|--name)
            IMAGE_NAME="$2"; shift 2 ;;

        # -v 或 --version：设置镜像 Tag。
        -v|--version)
            VERSION="$2"; shift 2 ;;

        # -r 或 --registry：设置镜像仓库前缀。
        -r|--registry)
            REGISTRY="$2"; shift 2 ;;

        # -p 或 --platform：设置目标平台，如 linux/amd64、linux/arm64。
        -p|--platform)
            PLATFORM="$2"; shift 2 ;;

        # --push：开启推送模式，无需额外值，shift 1 即可。
        --push)
            PUSH=true; shift ;;

        # --tar：开启 tar 导出模式。
        --tar)
            EXPORT_TAR=true; shift ;;

        # -h 或 --help：显示帮助并退出。
        -h|--help)
            usage; exit 0 ;;

        # *)：匹配任何其他未识别的参数，报错并退出。
        *)
            echo "未知参数: $1"; usage; exit 1 ;;
    esac
done

# ==================== 组合完整镜像名 ====================
# 如果用户指定了 REGISTRY，镜像名为 ${REGISTRY}/${IMAGE_NAME}:${VERSION}；
# 否则为 ${IMAGE_NAME}:${VERSION}。
if [[ -n "$REGISTRY" ]]; then
    FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${VERSION}"
else
    FULL_IMAGE="${IMAGE_NAME}:${VERSION}"
fi

# 打印本次构建的配置信息，方便用户确认。
echo "========================================"
echo "镜像名: ${FULL_IMAGE}"
echo "目标平台: ${PLATFORM}"
echo "是否推送: ${PUSH}"
echo "是否导出 tar: ${EXPORT_TAR}"
echo "========================================"

# ==================== 准备 docker buildx builder ====================
# docker buildx 需要一个 builder 实例才能进行多平台构建。
# 这里固定使用名为 sfwork-demo-builder 的 builder，避免反复创建。
BUILDER_NAME="sfwork-demo-builder"

# docker buildx inspect 检查 builder 是否存在。
# >/dev/null 2>&1 表示隐藏命令输出。
if ! docker buildx inspect "$BUILDER_NAME" >/dev/null 2>&1; then
    echo "创建 buildx builder: ${BUILDER_NAME}"
    # --platform linux/amd64,linux/arm64 表示该 builder 支持两种平台。
    # --use 表示创建后立即切换为当前使用的 builder。
    docker buildx create --name "$BUILDER_NAME" --platform linux/amd64,linux/arm64 --use
else
    # 如果已存在，切换到这个 builder。
    docker buildx use "$BUILDER_NAME"
fi

# ==================== 组装 docker buildx build 参数 ====================
# BUILD_ARGS 是一个 bash 数组，用于动态存储 build 命令参数。
BUILD_ARGS=(
    # --build-arg：向 Dockerfile 传递构建参数 APP_VERSION，Dockerfile 中可用 ARG APP_VERSION 接收。
    --build-arg "APP_VERSION=${VERSION}"

    # --platform：指定目标平台。
    --platform "$PLATFORM"

    # -t：设置镜像名和 Tag。
    -t "$FULL_IMAGE"

    # -f：指定 Dockerfile 路径。
    -f Dockerfile
)

# 根据 PUSH 变量决定是加载到本地还是推送到远程：
# --load：将构建结果加载到本地 Docker 守护进程，便于本地 docker run 测试。
# --push：构建完成后直接推送到镜像仓库。
if [[ "$PUSH" == true ]]; then
    BUILD_ARGS+=(--push)
else
    BUILD_ARGS+=(--load)
fi

# ==================== 执行镜像构建 ====================
echo "开始构建..."

# "${BUILD_ARGS[@]}" 表示把数组中的每个元素作为独立参数传给 docker buildx build。
# 最后的 . 表示 build context 为当前目录。
docker buildx build "${BUILD_ARGS[@]}" .

echo "构建完成: ${FULL_IMAGE}"

# ==================== 可选：导出 tar 包 ====================
# 仅在 --tar 时执行。docker save 可将本地镜像导出为 tar 文件，便于离线传输。
if [[ "$EXPORT_TAR" == true ]]; then
    TAR_FILE="${PROJECT_DIR}/${IMAGE_NAME}-${VERSION}.tar"
    echo "导出镜像到: ${TAR_FILE}"
    docker save -o "$TAR_FILE" "$FULL_IMAGE"
    echo "导出完成"
fi

# ==================== 提示运行命令 ====================
echo ""
echo "运行示例:"
echo "  docker run -d -p 8080:8080 --name demo ${FULL_IMAGE}"
echo "  curl http://localhost:8080"
