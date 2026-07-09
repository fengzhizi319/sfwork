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

# Bash 严格模式：
#   -e（errexit）：任何命令返回非零退出码时立即终止脚本，防止错误继续扩散。
#   -u（nounset）：使用未定义变量时报错，避免拼写错误导致使用空值。
#   -o pipefail：管道中任一命令失败，则整个管道表达式失败。
# 三者组合是 Bash 脚本工程化的常见做法，可在开发阶段尽早暴露问题。
set -euo pipefail

# ------------------------------------------------------------------
# 全局路径
# ------------------------------------------------------------------
# BASH_SOURCE[0] 表示当前脚本文件本身的路径（可能是相对路径）。
# dirname 取得脚本所在目录，再拼接 /.. 返回 sfwork 根目录，最后 cd + pwd 取得绝对路径。
# 这样无论用户从哪个目录执行脚本，都能正确定位到 sfwork 根目录。
SFWORK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SFWORK_ROOT"

# ------------------------------------------------------------------
# 颜色与日志
# ------------------------------------------------------------------
# ANSI 转义序列：\033 是 ESC 字符，[0;31m 设置红色前景色，[0m 恢复默认。
# 使用 -e 选项让 echo 解析转义字符，从而在终端输出彩色日志。
RED='\033[0;31m'      # 红色，用于错误
GREEN='\033[0;32m'    # 绿色，用于正常信息
YELLOW='\033[1;33m'   # 黄色加粗，用于警告
BLUE='\033[0;34m'     # 蓝色，用于步骤提示
NC='\033[0m'          # No Color，重置为终端默认样式

# 日志函数：统一输出格式，减少重复拼接。
# $* 表示函数接收的所有参数，作为一个整体字符串。
# log_error 将输出重定向到标准错误（>&2），便于外部脚本或 CI 捕获错误。
log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }

# ------------------------------------------------------------------
# 仓库配置
# ------------------------------------------------------------------
# USE_SSH：布尔标志，决定是否使用 SSH 协议克隆。
# 默认 false，因为 HTTPS 在大多数新环境中无需配置 SSH key 即可使用。
USE_SSH=false
# ${1:-} 是参数默认值展开：如果 $1 未定义，则返回空字符串。
# 这里判断第一个命令行参数是否为 --ssh，若是则切换为 SSH 方式。
if [ "${1:-}" = "--ssh" ]; then
    USE_SSH=true
fi

# BASE_URL：仓库基地址。
# 根据 USE_SSH 选择 SSH（git@github.com:owner）或 HTTPS（https://github.com/owner）格式。
if [ "$USE_SSH" = true ]; then
    BASE_URL="git@github.com:fengzhizi319"
else
    BASE_URL="https://github.com/fengzhizi319"
fi

# 仓库地址：优先读取环境变量，若未设置则使用上面根据协议拼接的默认地址。
# ${VAR:-default} 表示 VAR 为空或未定义时使用 default。
SECRETPAD_REPO="${SECRETPAD_REPO:-${BASE_URL}/secretpad.git}"
KUSCIA_REPO="${KUSCIA_REPO:-${BASE_URL}/kuscia.git}"
SECRETFLOW_REPO="${SECRETFLOW_REPO:-${BASE_URL}/secretflow.git}"

# 分支名：同样支持环境变量覆盖。
SECRETPAD_BRANCH="${SECRETPAD_BRANCH:-main}"
KUSCIA_BRANCH="${KUSCIA_BRANCH:-main}"
SECRETFLOW_BRANCH="${SECRETFLOW_BRANCH:-charles}"

# ------------------------------------------------------------------
# 克隆/更新单个仓库
# ------------------------------------------------------------------
# clone_or_update
#   功能：根据目标目录状态，执行 git clone 或更新已有仓库到指定分支。
#   参数：
#     $1 - 仓库远程地址（repo_url）
#     $2 - 本地目标目录（target_dir），相对于 SFWORK_ROOT
#     $3 - 目标分支（branch）
#   返回值/退出码：
#     0 - 成功；失败时由 git 命令返回非零码，set -e 会终止脚本。
#   使用示例：
#     clone_or_update "$SECRETPAD_REPO" "$SFWORK_ROOT/secretpad" "$SECRETPAD_BRANCH"
clone_or_update() {
    local repo_url="$1"
    local target_dir="$2"
    local branch="$3"

    log_step "处理 $target_dir（分支：$branch）..."

    # -d 测试目录是否存在。$target_dir/.git 存在说明这是一个 git 工作区。
    if [ -d "$target_dir/.git" ]; then
        # 目录已存在且是 git 仓库，执行更新。
        log_info "$target_dir 已是 git 仓库，执行更新 ..."
        # 使用圆括号创建子 shell，子 shell 内的 cd 不会影响父 shell 的工作目录。
        (
            cd "$target_dir"
            # 从远程 origin 拉取最新引用，但不合并到当前分支。
            git fetch origin
            # git show-ref --verify --quiet 检查本地是否已存在名为 $branch 的分支。
            # --quiet 使成功时不输出任何内容，仅通过退出码判断。
            if ! git show-ref --verify --quiet "refs/heads/$branch"; then
                # 本地没有目标分支时，基于 origin/$branch 创建并检出。
                # 若创建失败（例如远程分支名与本地冲突），则回退为直接 checkout。
                git checkout -b "$branch" "origin/$branch" || git checkout "$branch"
            else
                # 本地已有分支，直接切换。
                git checkout "$branch"
            fi
            # 将当前分支与远程同分支同步。
            git pull origin "$branch"
        )
    # -e 测试路径是否存在（文件或目录）。
    # 走到这里说明目标目录存在，但不是 git 仓库，避免误删用户数据，仅给出警告。
    elif [ -e "$target_dir" ]; then
        log_warn "$target_dir 已存在但不是一个 git 仓库，跳过。如需重新克隆，请手动删除该目录。"
    else
        # 目录不存在，执行克隆。--branch 指定克隆后直接检出的分支。
        log_info "从 $repo_url 克隆到 $target_dir ..."
        git clone --branch "$branch" "$repo_url" "$target_dir"
    fi
}

# ------------------------------------------------------------------
# 主流程
# ------------------------------------------------------------------
# 输出当前 sfwork 根目录，便于用户核对执行位置。
log_info "sfwork 根目录：$SFWORK_ROOT"
# 命令替换 $([ "$USE_SSH" = true ] && echo SSH || echo HTTPS) 动态选择显示文本。
log_info "使用协议：$([ "$USE_SSH" = true ] && echo SSH || echo HTTPS)"

# 依次处理三个子项目。调用顺序不影响结果，但通常按 secretpad -> kuscia -> secretflow 进行。
clone_or_update "$SECRETPAD_REPO"   "$SFWORK_ROOT/secretpad"   "$SECRETPAD_BRANCH"
clone_or_update "$KUSCIA_REPO"      "$SFWORK_ROOT/kuscia"      "$KUSCIA_BRANCH"
clone_or_update "$SECRETFLOW_REPO"  "$SFWORK_ROOT/secretflow"  "$SECRETFLOW_BRANCH"

# echo "" 输出空行，提升最终提示的可读性。
echo ""
log_info "所有子项目处理完成"
log_info "下一步可参考 docs/二次开发运行说明.md 或 docs/无docker运行说明.md 启动环境"
