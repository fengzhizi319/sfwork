# sfwork CI/CD 设计与实现文档

## 1. 设计目标

sfwork 是一个聚合了 Kuscia、SecretFlow、SecretPad（Java 后端 + React 前端）的二次开发工作区。原有 CI/CD 存在以下问题：

- 各子项目 CI 独立，缺少 workspace 级统一编排
- SecretPad 后端 CI 薄弱（仅 PR 触发 Maven test，无静态分析）
- SecretPad 前端 CI 不跑测试、不做类型检查、Node 版本已 EOL
- 自定义隐私计算镜像 `secretflow/sf-privacy-dev` 无自动构建
- 缺少镜像安全扫描、SBOM、部署模板

本设计按 **P0（基础质量门禁）→ P1（集成能力）→ P2（安全与部署工程化）** 的优先级补齐，形成从代码提交到部署模板的完整 CI/CD 能力。

---

## 2. 设计原则

| 原则 | 说明 |
|---|---|
| **分层治理** | 根仓库负责 workspace 级编排与集成；子项目保留自身构建细节 |
| **失败隔离** | 新增静态分析 job 与原有 test job 独立，避免一次性阻塞既有流程 |
| **配置外置** | 敏感信息与可变配置通过 `.env` 注入，不提交到版本控制 |
| **可本地复现** | CI 中执行的命令（`mvn spotless:check`、`pnpm nx affected --target=test` 等）均可在本地执行 |
| **渐进增强** | P2 安全扫描、部署模板先提供能力，再根据项目成熟度逐步收紧阻断阈值 |

---

## 3. CI/CD 架构总览

```text
┌─────────────────────────────────────────────────────────────────┐
│                       sfwork 根仓库 CI/CD                        │
├─────────────────────────────────────────────────────────────────┤
│  P0 基础质量                                                     │
│    ├── .github/workflows/ci.yml                                  │
│    │     ├── bash-syntax                                         │
│    │     ├── shellcheck                                          │
│    │     ├── .env.example consistency                            │
│    │     └── markdown-lint                                       │
│    ├── secretpad/.github/workflows/test.yml                      │
│    │     ├── build (mvn test, push + PR)                         │
│    │     └── static-analysis (spotless/checkstyle/spotbugs)      │
│    └── secretpad/frontend-src/.github/workflows/ci.yml           │
│          ├── lint/format                                         │
│          ├── lint:typing                                         │
│          └── test                                                │
├─────────────────────────────────────────────────────────────────┤
│  P1 集成能力                                                     │
│    ├── .github/workflows/integration.yml                         │
│    │     ├── build-secretpad-backend                             │
│    │     ├── build-secretpad-frontend                            │
│    │     └── dev-env-check                                       │
│    └── .github/workflows/build-privacy-image.yml                 │
│          └── build secretflow/sf-privacy-dev                     │
├─────────────────────────────────────────────────────────────────┤
│  P2 安全与部署                                                   │
│    ├── .github/workflows/build-privacy-image.yml                 │
│    │     ├── scan (Trivy SARIF + CRITICAL 阻断)                  │
│    │     └── sbom (Syft SPDX-JSON)                               │
│    └── deploy/                                                   │
│          ├── docker-compose.yml                                  │
│          ├── .env.example                                        │
│          └── README.md                                           │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. P0：基础质量门禁

### 4.1 根仓库 CI（`.github/workflows/ci.yml`）

触发：push / pull_request 到 `main`/`master`，workflow_dispatch。

| Job | 作用 | 本地等价命令 |
|---|---|---|
| `bash-syntax` | 验证所有 `scripts/*.sh` 语法 | `bash -n scripts/*.sh` |
| `shellcheck` | Shell 脚本静态检查 | `shellcheck scripts/*.sh` |
| `env-consistency` | 确保 `.env.example` 中变量在脚本中有引用 | `grep` 自定义脚本 |
| `markdown-lint` | 文档格式检查 | `markdownlint --config .markdownlint.json '**/*.md'` |

### 4.2 SecretPad 后端（`.github/workflows/test.yml`）

触发：push / pull_request 到 `main`。

| Job | 作用 | 关键命令 |
|---|---|---|
| `build` | Maven 测试 + JaCoCo 覆盖率报告 | `mvn clean test` |
| `static-analysis` | 代码质量三件套 | `mvn spotless:check checkstyle:check spotbugs:check` |

**静态分析工具配置：**

- **Spotless** (`secretpad/pom.xml`)：
  - 自动移除未使用的 import
  - 校验 Apache 2.0 license header
- **Checkstyle** (`secretpad/checkstyle.xml`)：
  - 禁止文件中出现 Tab
  - 行长度不超过 200
  - 禁止 `import *`
- **SpotBugs** (`secretpad/pom.xml`)：
  - 仅对 `High` 及以上级别问题报错（渐进策略）

### 4.3 SecretPad 前端（`secretpad/frontend-src/.github/workflows/ci.yml`）

触发：push / pull_request 到 `main`。

| 步骤 | 作用 | 关键命令 |
|---|---|---|
| lint/format | JS/CSS/格式检查 | `pnpm run ci` |
| type check | TypeScript 类型检查 | `pnpm nx affected --target=lint:typing --nx-bail=true` |
| test | 单元测试 | `pnpm nx affected --target=test --nx-bail=true` |

Node 版本从 16.x 升级到 **20.x**。

---

## 5. P1：集成能力

### 5.1 Workspace 集成流水线（`.github/workflows/integration.yml`）

触发：push / schedule / workflow_dispatch。

| Job | 作用 | 说明 |
|---|---|---|
| `build-secretpad-backend` | 克隆子仓库，构建 `secretpad.jar` | 产物保存 7 天 |
| `build-secretpad-frontend` | 克隆子仓库，构建前端 dist | 产物保存 7 天 |
| `dev-env-check` | 安装 JDK/Maven/Node/pnpm/conda 后执行 `dev-start.sh --check` | 验证开发环境依赖完整性 |

### 5.2 自定义隐私计算镜像自动构建

新增 `scripts/build-privacy-image.sh`：

```bash
# 激活 conda → 构建 SecretFlow wheel → 构建 Docker 镜像
bash scripts/build-privacy-image.sh
```

对应 workflow：`.github/workflows/build-privacy-image.yml`

触发：
- `secretflow/**` 变更
- `scripts/build-privacy-image.sh` 变更
- `.github/workflows/build-privacy-image.yml` 变更
- 每周一凌晨定时构建

---

## 6. P2：安全与部署工程化

### 6.1 镜像安全扫描

在 `.github/workflows/build-privacy-image.yml` 中：

- `scan` job：
  - Trivy 扫描生成 SARIF，上传 GitHub Security tab
  - 对 CRITICAL 漏洞再次扫描并阻断构建
- `sbom` job：
  - Syft 生成 SPDX-JSON SBOM
  - 作为 artifact 保存 30 天

### 6.2 部署模板

新增 `deploy/` 目录：

| 文件 | 作用 |
|---|---|
| `deploy/docker-compose.yml` | 本地/测试环境 Kuscia + SecretPad 部署模板 |
| `deploy/.env.example` | 镜像版本、端口、密码等配置模板 |
| `deploy/README.md` | 使用说明与安全提示 |

### 6.3 默认密钥处理

- `scripts/run-all-no-docker.sh`：
  - 移除硬编码 `SUDO_PWD=111111`
  - 支持从 `.env` 读取
  - 未设置 SUDO_PWD 且无免密 sudo 时直接报错退出
- `.env.example`：新增 `SUDO_PWD` 配置项与警告

---

## 7. 本地调试与维护

### 7.1 根仓库脚本

```bash
# 验证所有脚本语法
for f in scripts/*.sh; do bash -n "$f"; done

# 手动执行 env 一致性检查
cd /home/charles/code/sfwork
vars=$(grep -oE '^[A-Z_][A-Z0-9_]*=' .env.example | sed 's/=$//' | sort -u)
for v in $vars; do
  grep -Rq --include='*.sh' "\b$v\b" scripts/ || echo "MISSING: $v"
done

# markdownlint
npm install -g markdownlint-cli
markdownlint --config .markdownlint.json '**/*.md'
```

### 7.2 SecretPad 后端静态分析

```bash
cd secretpad

# 自动修复格式与未使用 import
mvn spotless:apply

# 检查（CI 使用）
mvn spotless:check
mvn checkstyle:check
mvn spotbugs:check
```

### 7.3 SecretPad 前端

```bash
cd secretpad/frontend-src

# 安装依赖并构建内部包
pnpm bootstrap

# 类型检查
pnpm nx affected --target=lint:typing --nx-bail=true

# 测试
pnpm nx affected --target=test --nx-bail=true
```

### 7.4 自定义镜像构建

```bash
bash scripts/build-privacy-image.sh
```

---

## 8. 后续演进方向

| 优先级 | 方向 | 说明 |
|---|---|---|
| P1+ | Helm Chart | 提供 Kubernetes 生产部署能力 |
| P1+ | GitOps 示例 | ArgoCD / Flux 配置 |
| P2+ | 镜像签名 | `cosign sign` 所有发布镜像 |
| P2+ | 统一版本管理 | `release-please` 或 `semantic-release` 对齐 Kuscia/SecretFlow/SecretPad 版本 |
| P2+ | 全链路集成测试 | 在 workspace 集成流水线中启动 Kuscia + SecretPad 并执行 API 冒烟测试 |
| P2+ | SecretPad 前端独立容器化 | 前端不再完全依赖嵌入后端 jar |

---

## 9. 文件清单

### 新增文件

- `.github/workflows/ci.yml`
- `.github/workflows/integration.yml`
- `.github/workflows/build-privacy-image.yml`
- `.markdownlint.json`
- `scripts/build-privacy-image.sh`
- `deploy/docker-compose.yml`
- `deploy/.env.example`
- `deploy/README.md`
- `secretpad/checkstyle.xml`

### 修改文件

- `.gitignore`
- `.env.example`
- `scripts/dev-start.sh`
- `scripts/dev-stop.sh`
- `scripts/run-all-no-docker.sh`
- `secretpad/pom.xml`
- `secretpad/.github/workflows/test.yml`
- `secretpad/frontend-src/.github/workflows/ci.yml`
