#!/bin/bash
#
# ============================================================================
# sfwork 子项目克隆脚本
# ============================================================================
#
# 功能概述：
#   将 sfwork 工作区所需的子项目克隆到本地指定目录。
#   当前 sfwork 根仓库只管理文档、配置和编排脚本；四大子项目及本地隐私 SDK/Agent 作为独立 git 仓库存在。
#
# 默认克隆的子项目：
#   - secretpad             -> ./secretpad/           （SecretPad 后端）
#   - secretpad-frontend    -> ./secretpad/frontend-src/ （SecretPad 前端，嵌套在 secretpad/ 下）
#   - kuscia                -> ./kuscia/
#   - secretflow            -> ./secretflow/
#   - privacy-java-sdk      -> ./privacy-java-sdk/
#   - privacy-go-sdk        -> ./privacy-go-sdk/
#   - privacy-local-agent   -> ./privacy-local-agent/
#
# 说明：
#   - secretpad 仓库本身只包含后端源码，前端源码在 secretpad-frontend 仓库，
#     需要克隆到 ./secretpad/frontend-src/ 目录下（已被 secretpad/.gitignore 忽略）。
#   - 如果目标目录已存在且是 git 仓库，脚本会执行 git pull 并切换到指定分支。
#   - 如果目标目录已存在但不是一个 git 仓库，脚本会跳过并给出警告。
#   - 单个仓库处理失败不会阻塞后续仓库的克隆/更新。
#
# 用法：
#   bash scripts/clone-repos.sh              # 使用默认仓库和分支
#   bash scripts/clone-repos.sh --ssh        # 使用 SSH 协议克隆
#   bash scripts/clone-repos.sh --help       # 显示帮助信息
#
# 环境变量（均可选）：
#   SECRETPAD_REPO             secretpad 仓库地址（默认：https://github.com/fengzhizi319/secretpad.git）
#   SECRETPAD_FRONTEND_REPO    secretpad-frontend 仓库地址（默认：https://github.com/fengzhizi319/secretpad-frontend.git）
#   KUSCIA_REPO                kuscia 仓库地址（默认：https://github.com/fengzhizi319/kuscia.git）
#   SECRETFLOW_REPO            secretflow 仓库地址（默认：https://github.com/fengzhizi319/secretflow.git）
#   PRIVACY_JAVA_REPO          privacy-java-sdk 仓库地址（默认：https://github.com/fengzhizi319/privacy-java-sdk.git）
#   PRIVACY_GO_REPO            privacy-go-sdk 仓库地址（默认：https://github.com/fengzhizi319/privacy-go-sdk.git）
#   PRIVACY_LOCAL_AGENT_REPO   privacy-local-agent 仓库地址（默认：https://github.com/fengzhizi319/privacy-local-agent.git）
#   SECRETPAD_BRANCH           secretpad 分支（默认：main）
#   SECRETPAD_FRONTEND_BRANCH  secretpad-frontend 分支（默认：main）
#   KUSCIA_BRANCH              kuscia 分支（默认：main）
#   SECRETFLOW_BRANCH          secretflow 分支（默认：main）
#   PRIVACY_JAVA_BRANCH        privacy-java-sdk 分支（默认：main）
#   PRIVACY_GO_BRANCH          privacy-go-sdk 分支（默认：main）
#   PRIVACY_LOCAL_AGENT_BRANCH privacy-local-agent 分支（默认：main）
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
# 跨平台工具函数
# ------------------------------------------------------------------
# detect_os
#   功能：检测当前操作系统类型。
#   输出：linux / darwin / windows / unknown
#   说明：Windows 指 Git Bash / MSYS2 / CYGWIN 等 Bash 环境。
detect_os() {
    local os
    os="$(uname -s 2>/dev/null || echo unknown)"
    case "$os" in
        Linux*)     echo linux ;;
        Darwin*)    echo darwin ;;
        MINGW*|MSYS*|CYGWIN*) echo windows ;;
        *)          echo unknown ;;
    esac
}

# is_linux / is_macos / is_windows
#   功能：判断当前操作系统是否为 Linux / macOS / Windows。
#   返回：0=是，1=否
is_linux() { [[ "$(detect_os)" == "linux" ]]; }
is_macos() { [[ "$(detect_os)" == "darwin" ]]; }
is_windows() { [[ "$(detect_os)" == "windows" ]]; }

# command_exists
#   功能：POSIX 标准方式检测命令是否存在于 PATH。
#   参数：$1 - 待检测的命令名
#   返回：0=存在，1=不存在
command_exists() { command -v "$1" >/dev/null 2>&1; }

# ------------------------------------------------------------------
# 命令行参数
# ------------------------------------------------------------------
USE_SSH=false

print_help() {
    sed -n '2,40p' "$0" | sed 's/^# //; s/^#//'
}

# ${1:-} 是参数默认值展开：如果 $1 未定义，则返回空字符串。
case "${1:-}" in
    --ssh)
        USE_SSH=true
        ;;
    --help|-h)
        print_help
        exit 0
        ;;
    "")
        ;;
    *)
        log_error "未知参数：$1"
        log_info "用法：$0 [--ssh|--help]"
        exit 1
        ;;
esac

# ------------------------------------------------------------------
# 仓库配置
# ------------------------------------------------------------------
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
SECRETPAD_FRONTEND_REPO="${SECRETPAD_FRONTEND_REPO:-${BASE_URL}/secretpad-frontend.git}"
KUSCIA_REPO="${KUSCIA_REPO:-${BASE_URL}/kuscia.git}"
SECRETFLOW_REPO="${SECRETFLOW_REPO:-${BASE_URL}/secretflow.git}"
PRIVACY_JAVA_REPO="${PRIVACY_JAVA_REPO:-${BASE_URL}/privacy-java-sdk.git}"
PRIVACY_GO_REPO="${PRIVACY_GO_REPO:-${BASE_URL}/privacy-go-sdk.git}"
PRIVACY_LOCAL_AGENT_REPO="${PRIVACY_LOCAL_AGENT_REPO:-${BASE_URL}/privacy-local-agent.git}"

# 分支名：同样支持环境变量覆盖。
SECRETPAD_BRANCH="${SECRETPAD_BRANCH:-main}"
SECRETPAD_FRONTEND_BRANCH="${SECRETPAD_FRONTEND_BRANCH:-main}"
KUSCIA_BRANCH="${KUSCIA_BRANCH:-main}"
SECRETFLOW_BRANCH="${SECRETFLOW_BRANCH:-main}"
PRIVACY_JAVA_BRANCH="${PRIVACY_JAVA_BRANCH:-main}"
PRIVACY_GO_BRANCH="${PRIVACY_GO_BRANCH:-main}"
PRIVACY_LOCAL_AGENT_BRANCH="${PRIVACY_LOCAL_AGENT_BRANCH:-main}"

# ------------------------------------------------------------------
# 克隆/更新单个仓库
# ------------------------------------------------------------------
# clone_or_update
#   功能：根据目标目录状态，执行 git clone 或更新已有仓库到指定分支。
#   参数：
#     $1 - 仓库远程地址（repo_url）
#     $2 - 本地目标目录（target_dir），相对于 SFWORK_ROOT
#     $3 - 目标分支（branch）
#   返回值：
#     0 - 成功；1 - 失败（已打印错误信息，调用方可继续处理其他仓库）。
#   使用示例：
#     clone_or_update "$SECRETPAD_REPO" "$SFWORK_ROOT/secretpad" "$SECRETPAD_BRANCH"
clone_or_update() {
    local repo_url="$1"
    local target_dir="$2"
    local branch="$3"

    log_step "处理 $target_dir (分支: $branch)..."

    # -d 测试目录是否存在。$target_dir/.git 存在说明这是一个 git 工作区。
    if [ -d "$target_dir/.git" ]; then
        # 目录已存在且是 git 仓库，执行更新。
        log_info "$target_dir 已是 git 仓库，执行更新 ..."
        # 使用圆括号创建子 shell，子 shell 内的 cd 不会影响父 shell 的工作目录。
        (
            cd "$target_dir" || exit 1

            # 若环境变量指定的远程地址与当前 origin 不一致，则更新 origin，
            # 方便在 HTTPS / SSH 之间切换或更换仓库地址后仍能正常更新。
            local current_origin
            current_origin="$(git remote get-url origin 2>/dev/null || true)"
            if [ -n "$current_origin" ] && [ "$current_origin" != "$repo_url" ]; then
                log_info "检测到 origin 地址变化：$current_origin -> $repo_url"
                git remote set-url origin "$repo_url"
            fi

            # 从远程 origin 拉取最新引用，但不合并到当前分支。
            if ! git fetch origin; then
                log_error "$target_dir: git fetch 失败"
                exit 1
            fi

            # 先检查远程是否存在目标分支，避免后续 checkout 指向不存在的引用。
            if ! git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
                log_error "$target_dir: 远程不存在分支 origin/$branch，请检查分支名或 SECRETPAD_BRANCH/KUSCIA_BRANCH/... 环境变量"
                exit 1
            fi

            # git show-ref --verify --quiet 检查本地是否已存在名为 $branch 的分支。
            # --quiet 使成功时不输出任何内容，仅通过退出码判断。
            if ! git show-ref --verify --quiet "refs/heads/$branch"; then
                # 本地没有目标分支时，基于 origin/$branch 创建并检出。
                if ! git checkout -b "$branch" "origin/$branch"; then
                    log_error "$target_dir: 无法创建并切换到分支 $branch"
                    exit 1
                fi
            else
                # 本地已有分支，直接切换。
                if ! git checkout "$branch"; then
                    log_error "$target_dir: 无法切换到分支 $branch"
                    exit 1
                fi
            fi

            # 将当前分支与远程同分支同步。
            if ! git pull origin "$branch"; then
                log_error "$target_dir: git pull origin $branch 失败"
                exit 1
            fi
        ) || return 1
    # -e 测试路径是否存在（文件或目录）。
    # 走到这里说明目标目录存在，但不是 git 仓库，避免误删用户数据，仅给出警告。
    elif [ -e "$target_dir" ]; then
        log_warn "$target_dir 已存在但不是一个 git 仓库，跳过。如需重新克隆，请手动删除该目录。"
        return 1
    else
        # 目录不存在，执行克隆。--branch 指定克隆后直接检出的分支。
        log_info "从 $repo_url 克隆到 $target_dir ..."
        if ! git clone --branch "$branch" "$repo_url" "$target_dir"; then
            log_error "$target_dir: git clone 失败"
            return 1
        fi
    fi
}

# ------------------------------------------------------------------
# 主流程
# ------------------------------------------------------------------
# 输出当前 sfwork 根目录，便于用户核对执行位置。
log_info "sfwork 根目录：$SFWORK_ROOT"
# 命令替换 $([ "$USE_SSH" = true ] && echo SSH || echo HTTPS) 动态选择显示文本。
log_info "使用协议：$([ "$USE_SSH" = true ] && echo SSH || echo HTTPS)"

# 依次处理所有子项目。单个失败不会退出脚本，确保尽可能多的仓库被克隆/更新。
FAILED_COUNT=0

process_repo() {
    local repo_url="$1"
    local target_dir="$2"
    local branch="$3"

    if ! clone_or_update "$repo_url" "$target_dir" "$branch"; then
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
}

process_repo "$SECRETPAD_REPO"           "$SFWORK_ROOT/secretpad"                  "$SECRETPAD_BRANCH"
process_repo "$SECRETPAD_FRONTEND_REPO"  "$SFWORK_ROOT/secretpad/frontend-src"     "$SECRETPAD_FRONTEND_BRANCH"
process_repo "$KUSCIA_REPO"              "$SFWORK_ROOT/kuscia"                     "$KUSCIA_BRANCH"
process_repo "$SECRETFLOW_REPO"          "$SFWORK_ROOT/secretflow"          "$SECRETFLOW_BRANCH"
process_repo "$PRIVACY_JAVA_REPO"        "$SFWORK_ROOT/privacy-java-sdk"    "$PRIVACY_JAVA_BRANCH"
process_repo "$PRIVACY_GO_REPO"          "$SFWORK_ROOT/privacy-go-sdk"      "$PRIVACY_GO_BRANCH"
process_repo "$PRIVACY_LOCAL_AGENT_REPO" "$SFWORK_ROOT/privacy-local-agent" "$PRIVACY_LOCAL_AGENT_BRANCH"

# echo "" 输出空行，提升最终提示的可读性。
echo ""

if [ "$FAILED_COUNT" -eq 0 ]; then
    log_info "所有子项目处理完成"
    log_info "下一步可参考 docs/二次开发运行说明.md 或 docs/无docker运行说明.md 启动环境"
    exit 0
else
    log_error "共 $FAILED_COUNT 个子项目处理失败，请检查上面的错误日志"
    exit 1
fi
