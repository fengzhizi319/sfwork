#!/bin/bash
#
# ============================================================================
# sfwork 自定义 SecretFlow 隐私计算镜像构建脚本
# ============================================================================
#
# 功能概述：
#   基于 secretflow/docker/privacy-dev/Dockerfile 构建包含本地 privacy 组件的
#   自定义 SecretFlow 镜像（默认 tag 由 .env 或环境变量 PRIVACY_IMAGE 指定）。
#
# 用法：
#   bash scripts/build-privacy-image.sh          # 使用默认配置构建
#   PRIVACY_IMAGE=myregistry/sf:dev bash scripts/build-privacy-image.sh
#
# 前置条件：
#   - sfwork 子项目 secretflow/ 已克隆到本地
#   - 已安装 conda 且环境 sf310（或由 CONDA_ENV 指定）存在
#   - Docker 可用且当前用户有权限执行 docker 命令
# ============================================================================

set -euo pipefail

SFWORK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETFLOW_DIR="$SFWORK_ROOT/secretflow"

# 加载 .env 配置
DEV_START_ENV_FILE="${DEV_START_ENV_FILE:-$SFWORK_ROOT/.env}"
if [ -f "$DEV_START_ENV_FILE" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$DEV_START_ENV_FILE"
    set +a
fi

PRIVACY_IMAGE="${PRIVACY_IMAGE:-secretflow/sf-privacy-dev:1.15.0.dev-privacy}"
CONDA_ENV="${CONDA_ENV:-sf310}"

echo "[INFO] 自定义 SecretFlow 镜像：$PRIVACY_IMAGE"
echo "[INFO] conda 环境：$CONDA_ENV"

if [ ! -d "$SECRETFLOW_DIR" ]; then
    echo "[ERROR] 未找到 $SECRETFLOW_DIR，请先执行 bash scripts/clone-repos.sh" >&2
    exit 1
fi

# 激活 conda 环境
conda_base="$(conda info --base)"
# shellcheck source=/dev/null
source "$conda_base/etc/profile.d/conda.sh"
conda activate "$CONDA_ENV"

cd "$SECRETFLOW_DIR"

echo "[INFO] 清理历史构建产物 ..."
rm -rf dist build

echo "[INFO] 构建 SecretFlow wheel ..."
python -m build --wheel

wheel="$(ls "$SECRETFLOW_DIR"/dist/secretflow-*.whl | head -1)"
if [ -z "$wheel" ]; then
    echo "[ERROR] 未找到构建出的 wheel 文件" >&2
    exit 1
fi
echo "[INFO] wheel 文件：$wheel"

mkdir -p "$SECRETFLOW_DIR/docker/privacy-dev"
cp "$wheel" "$SECRETFLOW_DIR/docker/privacy-dev/"

cd "$SECRETFLOW_DIR/docker/privacy-dev"
echo "[INFO] 构建 Docker 镜像 ..."
docker build . -f Dockerfile -t "$PRIVACY_IMAGE"

echo "[INFO] 镜像构建完成：$PRIVACY_IMAGE"
