# sfwork

sfwork 是 SecretFlow 隐私计算生态的本地开发工作区，聚合了 Kuscia、SecretFlow、SecretPad（含前端）三个核心仓库，并提供统一的文档与编排脚本。

> **注意**：本仓库本身不包含子项目源码。子项目通过 `scripts/clone-repos.sh` 独立克隆和管理。

---

## 目录结构

```text
sfwork/
├── scripts/                      # 编排脚本
│   ├── clone-repos.sh            # 克隆/更新子项目
│   ├── dev-start.sh              # Docker 开发环境一键启动（使用自定义 SecretFlow 镜像）
│   ├── dev-stop.sh               # 停止 Docker 开发环境
│   └── run-all-no-docker.sh      # 无 Docker 本地开发环境一键启动
├── docs/                         # 文档
│   ├── privacy-component-*.md    # 隐私计算组件设计与实现文档
│   ├── 二次开发运行说明.md        # Docker 开发模式运行说明
│   └── 无docker运行说明.md        # 无 Docker 开发模式运行说明
├── AGENTS.md                     # 给 AI 编码助手的项目指南
├── PROJECT_SUMMARY.md            # 项目架构总览
└── .gitignore                    # 忽略子项目目录、日志、本地运行时数据
```

子项目目录（独立 git 仓库，由 `scripts/clone-repos.sh` 管理）：

```text
secretflow/     # 隐私计算框架（含 privacy/l_diversity 组件）
kuscia/         # 联邦学习编排引擎
secretpad/      # Web 管理控制台后端 + 前端 frontend-src/
```

---

## 快速开始

### 1. 克隆子项目

```bash
cd /home/charles/code/sfwork
bash scripts/clone-repos.sh
```

如需使用 SSH：

```bash
bash scripts/clone-repos.sh --ssh
```

### 2. 启动开发环境（二选一）

#### 方式 A：Docker 开发环境（推荐完整功能验证）

使用本地构建的自定义 SecretFlow 镜像：

```bash
bash scripts/dev-start.sh
```

停止：

```bash
bash scripts/dev-stop.sh
bash scripts/dev-stop.sh --kuscia  # 同时停止 Kuscia 容器
```

#### 方式 B：无 Docker 开发环境（源码调试）

所有组件均从本地源码启动，不依赖 Docker：

```bash
SUDO_PWD="110734" bash scripts/run-all-no-docker.sh
```

停止：

```bash
SUDO_PWD="110734" bash scripts/run-all-no-docker.sh --stop
```

---

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `PRIVACY_IMAGE` | `secretflow/sf-privacy-dev:1.15.0.dev-privacy` | 自定义 SecretFlow 镜像 tag |
| `CONDA_ENV` | `sf310` | 构建 SecretFlow wheel 使用的 conda 环境 |
| `SUDO_PWD` | `110734` | 无 Docker 模式下 sudo 密码 |

---

## 文档索引

- [无 Docker 运行说明](docs/无docker运行说明.md)
- [二次开发运行说明](docs/二次开发运行说明.md)
- [隐私计算组件部署文档](docs/privacy-component-deployment.md)
- [Agent 指南](AGENTS.md)

---

## 远程仓库

```text
https://github.com/fengzhizi319/sfwork.git
```
