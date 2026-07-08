#!/bin/bash
#
# ============================================================================
# sfwork 子项目克隆脚本
# ============================================================================
#
# 功能概述：
#   将 sfwork 工作区所需的子项目克隆到本地指定目录。
#   当前 sfwork 根仓库只管理文档、配置和编排脚本；四大子项目作为独立 git 仓库存在。
#
# 默认克隆的子项目：
#   - secretpad   -> ./secretpad/   （包含前端 frontend-src/ 与后端）
#   - kuscia      -> ./kuscia/
#   - secretflow  -> ./secretflow/
#
# 说明：
#   - secretpad 已包含前端源码，因此无需单独克隆前端仓库。
#   - 如果目标目录已存在且是 git 仓库，脚本会执行 git pull 并切换到指定分支。
#   - 如果目标目录已存在但不是一个 git 仓库，脚本会跳过并给出警告。
#
# 用法：
#   bash scripts/clone-repos.sh              # 使用默认仓库和分支
#   bash scripts/clone-repos.sh --ssh        # 使用 SSH 协议克隆
#
# 环境变量（均可选）：
#   SECRETPAD_REPO       secretpad 仓库地址（默认：https://github.com/fengzhizi319/secretpad.git）
#   KUSCIA_REPO          kuscia 仓库地址（默认：https://github.com/fengzhizi319/kuscia.git）
#   SECRETFLOW_REPO      secretflow 仓库地址（默认：https://github.com/fengzhizi319/secretflow.git）
#   SECRETPAD_BRANCH     secretpad 分支（默认：main）
#   KUSCIA_BRANCH        kuscia 分支（默认：main）
#   SECRETFLOW_BRANCH    secretflow 分支（默认：charles）
# ============================================================================

set -euo pipefail

# 获取 sfwork 根目录
SFWORK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SFWORK_ROOT"

# ------------------------------------------------------------------
# 颜色与日志
# ------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }

# ------------------------------------------------------------------
# 仓库配置
# ------------------------------------------------------------------
# 默认使用 HTTPS 协议，便于在大多数环境中直接运行
USE_SSH=false
if [ "${1:-}" = "--ssh" ]; then
    USE_SSH=true
fi

# 仓库基地址
if [ "$USE_SSH" = true ]; then
    BASE_URL="git@github.com:fengzhizi319"
else
    BASE_URL="https://github.com/fengzhizi319"
fi

# 允许通过环境变量覆盖仓库地址和分支
SECRETPAD_REPO="${SECRETPAD_REPO:-${BASE_URL}/secretpad.git}"
KUSCIA_REPO="${KUSCIA_REPO:-${BASE_URL}/kuscia.git}"
SECRETFLOW_REPO="${SECRETFLOW_REPO:-${BASE_URL}/secretflow.git}"

SECRETPAD_BRANCH="${SECRETPAD_BRANCH:-main}"
KUSCIA_BRANCH="${KUSCIA_BRANCH:-main}"
SECRETFLOW_BRANCH="${SECRETFLOW_BRANCH:-charles}"

# ------------------------------------------------------------------
# 克隆/更新单个仓库
# ------------------------------------------------------------------
# clone_or_update repo_url target_dir branch
#   - 如果 target_dir 不存在：克隆仓库并切换到 branch
#   - 如果 target_dir 是 git 仓库：fetch + checkout branch + pull
#   - 否则：跳过并警告
clone_or_update() {
    local repo_url="$1"
    local target_dir="$2"
    local branch="$3"

    log_step "处理 $target_dir（分支：$branch）..."

    if [ -d "$target_dir/.git" ]; then
        # 目录已存在且是 git 仓库，执行更新
        log_info "$target_dir 已是 git 仓库，执行更新 ..."
        (
            cd "$target_dir"
            git fetch origin
            # 如果本地没有该分支，基于 origin/branch 创建
            if ! git show-ref --verify --quiet "refs/heads/$branch"; then
                git checkout -b "$branch" "origin/$branch" || git checkout "$branch"
            else
                git checkout "$branch"
            fi
            git pull origin "$branch"
        )
    elif [ -e "$target_dir" ]; then
        # 目录存在但不是 git 仓库，跳过以避免误删用户数据
        log_warn "$target_dir 已存在但不是一个 git 仓库，跳过。如需重新克隆，请手动删除该目录。"
    else
        # 目录不存在，执行克隆
        log_info "从 $repo_url 克隆到 $target_dir ..."
        git clone --branch "$branch" "$repo_url" "$target_dir"
    fi
}

# ------------------------------------------------------------------
# 主流程
# ------------------------------------------------------------------
log_info "sfwork 根目录：$SFWORK_ROOT"
log_info "使用协议：$([ "$USE_SSH" = true ] && echo SSH || echo HTTPS)"

clone_or_update "$SECRETPAD_REPO"   "$SFWORK_ROOT/secretpad"   "$SECRETPAD_BRANCH"
clone_or_update "$KUSCIA_REPO"      "$SFWORK_ROOT/kuscia"      "$KUSCIA_BRANCH"
clone_or_update "$SECRETFLOW_REPO"  "$SFWORK_ROOT/secretflow"  "$SECRETFLOW_BRANCH"

echo ""
log_info "所有子项目处理完成"
log_info "下一步可参考 docs/二次开发运行说明.md 或 docs/无docker运行说明.md 启动环境"
