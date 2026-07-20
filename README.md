# sfwork — c-life 隐私计算平台开发工作区

sfwork 是 SecretFlow 隐私计算生态的本地开发工作区，聚合了 Kuscia、SecretFlow、SecretPad（含前端）三个核心仓库，并提供统一的文档与编排脚本。

> **注意**：本仓库本身不包含子项目源码。子项目通过 `scripts/clone-repos.sh` 独立克隆和管理。

---

## 项目定位

c-life 隐私计算平台是一个全栈隐私计算系统，提供三层核心能力：

```
数据接入 → 分类分级(L1~L5) → 本地隐私处理 → FL/MPC 联邦计算 → 审计与预算管控
```

- **分类分级**：规则引擎 → 小样本 NER → 本地 VLM/LLM 多模态医疗数据识别
- **本地隐私**：脱敏、K-匿名、差分隐私、查询混淆
- **联邦计算**：跨域协同计算，数据可用不可见

### 📅 关键里程碑

| 里程碑 | 交付日期 | 核心交付物 |
|--------|---------|----------|
| **M1: 本地隐私 SDK** | 2025-08-15 | DP/脱敏/K-匿名/QOL SDK + Agent + 分类分级引擎 |
| **M2: 数据库处理集成版** | 2025-09-15 | 前端+后端+Kuscia+SecretFlow 完整集成（**柳州项目商业交付**） |
| **M3: 完整隐私计算平台** | 2025-10-31 | 联邦学习 + MPC 完整算法集（**比原计划提前 1 个月**） |

详细计划见 [docs/隐私计算平台-团队汇报与落地规划.md](./docs/隐私计算平台-团队汇报与落地规划.md#91-项目计划)。

---

## 目录结构

### 工作区根目录

```text
sfwork/
├── scripts/                      # 编排脚本
│   ├── clone-repos.sh            # 克隆/更新子项目
│   ├── dev-start.sh              # Docker 开发环境一键启动（使用自定义 SecretFlow 镜像）
│   ├── dev-stop.sh               # 停止 Docker 开发环境
│   └── run-all-no-docker.sh      # 无 Docker 本地开发环境一键启动
├── docs/                         # 文档归档中心
│   ├── doc-center/               # 集中化文档索引（推荐从这里开始阅读）
│   │   ├── 00-项目总览/          # 白皮书、PPT、总体介绍
│   │   ├── 01-架构设计/          # HLD/LLD、模块设计、接口映射
│   │   ├── 02-前端开发/          # SecretPad 前端开发指南
│   │   ├── 03-后端开发/          # SecretPad 后端开发指南
│   │   ├── 04-Kuscia/            # Kuscia 部署与开发
│   │   ├── 05-算法与隐私/        # 分类分级、差分隐私、本地隐私原语
│   │   ├── 06-部署运维/          # 部署指南、监控、日志
│   │   └── 07-开发规范/          # CI/CD、代码规范
│   ├── privacy-component-*.md    # 隐私计算组件设计与实现文档
│   ├── 二次开发运行说明.md        # Docker 开发模式运行说明
│   └── 无docker运行说明.md        # 无 Docker 开发模式运行说明
├── .agents/skills/               # AI Agent 技能定义
│   ├── sfwork-workspace/         # 工作区导航技能
│   ├── doc-center-reader/        # 文档中心检索技能
│   ├── secretpad-frontend-dev/   # 前端开发技能
│   ├── secretpad-backend-dev/    # 后端开发技能
│   └── kuscia-dev/               # Kuscia 开发技能
├── AGENTS.md                     # AI 编码助手完整项目指南（必读）
├── PROJECT_SUMMARY.md            # 英文项目架构总览
├── 项目总结.md                    # 中文项目架构总览
└── .gitignore                    # 忽略子项目目录、日志、本地运行时数据
```

### 子项目目录（独立 git 仓库，由 `scripts/clone-repos.sh` 管理）

```text
secretflow/     # 隐私计算框架（Python，含 MPC/HEU/SPU/TEE/FL 能力）
kuscia/         # 联邦学习编排引擎（Go，基于 Kubernetes CRD）
secretpad/      # Web 管理控制台（Java Spring Boot 后端 + React 前端 frontend-src/）
```

### 配套本地隐私 SDK（独立仓库，与 sfwork 同级目录）

| 项目 | 语言 | 用途 |
|------|------|------|
| **privacy-java-sdk** | Java 17 | Java/SecretPad 后端本地隐私 SDK |
| **privacy-go-sdk** | Go 1.21 | Go 微服务本地隐私 SDK |
| **privacy-local-agent** | Python 3.10+ | REST + gRPC Sidecar，多语言通用访问 |

选择指南：同语言嵌入用 SDK；跨语言或无法嵌入时用 Agent。详见 [docs/dp/README.md](./docs/dp/README.md)。

---

## 技术栈概览

| 项目 | 语言 | 核心技术 |
|------|------|----------|
| **Kuscia** | Go 1.24.7 | Kubernetes CRD、gRPC、Envoy、Apache Arrow Flight |
| **SecretFlow** | Python 3.10/3.11 | JAX、NumPy、SPU/HEU/TEEU、PyArrow、DuckDB |
| **SecretPad Backend** | Java 17 | Spring Boot 3.3.5、JPA/Hibernate、Flyway、gRPC |
| **SecretPad Frontend** | TypeScript 4.9 | React 18、Umi 4、Ant Design 5、Valtio、Nx |

详细技术栈见 [AGENTS.md §3](./AGENTS.md#3-technology-stack)。

---

## 系统架构与数据流

```
SecretPad Frontend (React/Umi, port 8000 dev)
        │  REST /api/v1alpha1/*
        ▼
SecretPad Backend (Spring Boot, ports 8080/8443/9001)
        │  gRPC
        ▼
Kuscia Master/Lite (Go, gRPC port 8083, Envoy ports 80/1080)
        │  调度 pods / DomainData / DomainRoute
        ▼
SecretFlow (Python)  ← 在容器内执行隐私保护算法
```

数据访问由 **DataMesh**（Kuscia 的一部分）通过 gRPC 和 Apache Arrow Flight 协调。

详细架构图见 [PROJECT_SUMMARY.md §Architecture Integration](./PROJECT_SUMMARY.md#architecture-integration)。

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

详细启动流程见 [AGENTS.md §8](./AGENTS.md#8-runtime-architecture--ports)。

---

## 端口速查

| 服务 | 端口 | 说明 |
|------|------|------|
| SecretPad 前端开发服务器 | 8000 | Umi dev，代理 `/api` 到后端 |
| SecretPad 后端 HTTP | 8080 | Spring Boot `server.http-port` |
| SecretPad 后端 HTTPS | 8443 | Spring Boot `server.port` |
| SecretPad 内部 API | 9001 | `server.http-port-inner` |
| Kuscia API gRPC | 8083 | 非 Docker 模式；Docker 模式映射为 18083 |
| Kuscia Envoy 网关 | 80/1080 | 非 Docker 模式；Docker 模式映射为 13081 |
| CoreDNS | 53 | 需要 root 权限 |

开发登录凭据：`admin` / `12345678`

完整端口列表见 [AGENTS.md §8](./AGENTS.md#8-runtime-architecture--ports)。

---

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `PRIVACY_IMAGE` | `secretflow/sf-privacy-dev:1.15.0.dev-privacy` | 自定义 SecretFlow 镜像 tag |
| `CONDA_ENV` | `sf310` | 构建 SecretFlow wheel 使用的 conda 环境 |
| `SUDO_PWD` | `110734` | 无 Docker 模式下 sudo 密码 |
| `KUSCIA_API_ADDRESS` | `127.0.0.1` | Kuscia API gRPC 地址（Docker 模式） |
| `KUSCIA_API_PORT` | `18083` | Kuscia API gRPC 端口（Docker 模式映射） |
| `KUSCIA_GW_ADDRESS` | `127.0.0.1:13081` | Kuscia Envoy 网关地址（Docker 模式映射） |
| `KUSCIA_PROTOCOL` | `notls` | 开发模式不使用 mTLS |

---

## 常用命令速查

### Kuscia

```bash
cd kuscia
make build                  # 构建二进制文件
make test                   # 运行单元测试
make generate               # 生成 CRD/clientset/proto 代码
make image                  # 构建 Docker 镜像
```

### SecretFlow

```bash
cd secretflow
pip install -e .            # 可编辑安装
python -m pytest tests/ -v  # 运行测试（仿真模式）
python -m pytest tests/ --env=prod -v  # MPC 生产模式
```

### SecretPad Backend

```bash
cd secretpad
mvn clean package -DskipTests  # 构建 jar 包（跳过测试）
mvn clean test                 # 运行单元测试
make image                     # 构建 Docker 镜像
```

### SecretPad Frontend

```bash
cd secretpad/frontend-src
pnpm bootstrap                 # 安装依赖并构建共享包
pnpm --filter secretpad dev    # 启动开发服务器（http://localhost:8000）
pnpm --filter secretpad test   # 运行测试
```

完整命令参考见 [AGENTS.md §4](./AGENTS.md#4-build--test-commands)。

---

## 文档索引

### 推荐入口

1. **[文档中心 README](./docs/doc-center/README.md)** —— 按主题分类的完整文档索引
2. **[AGENTS.md](./AGENTS.md)** —— AI 编码助手完整项目指南（技术栈、构建命令、代码规范、测试方法、部署流程）
3. **[PROJECT_SUMMARY.md](./PROJECT_SUMMARY.md)** —— 英文项目架构总览
4. **[项目总结.md](./项目总结.md)** —— 中文项目架构总览

### 按角色查找

| 角色 | 推荐文档 |
|------|----------|
| 产品经理 / 项目经理 | [docs/doc-center/00-项目总览/](./docs/doc-center/00-项目总览/) 白皮书、PPT |
| 前端开发 | [docs/doc-center/02-前端开发/](./docs/doc-center/02-前端开发/)、[AGENTS.md §4.4](./AGENTS.md#44-secretpad-frontend) |
| 后端开发 | [docs/doc-center/03-后端开发/](./docs/doc-center/03-后端开发/)、[AGENTS.md §4.3](./AGENTS.md#43-secretpad-backend) |
| Kuscia 运维 / 部署 | [docs/doc-center/04-Kuscia/](./docs/doc-center/04-Kuscia/)、[AGENTS.md §4.1](./AGENTS.md#41-kuscia) |
| 算法工程师 | [docs/doc-center/05-算法与隐私/](./docs/doc-center/05-算法与隐私/) |
| 安全合规 | [docs/doc-center/05-算法与隐私/](./docs/doc-center/05-算法与隐私/)、白皮书 |
| 问题排查 | [docs/doc-center/08-问题排查/](./docs/doc-center/08-问题排查/)、[无docker运行说明.md](./docs/无docker运行说明.md) |

### AI Agent 技能

本项目配置了 Kimi Agent 技能，位于 `.agents/skills/`：

- **sfwork-workspace** —— 工作区导航与跨项目命令
- **doc-center-reader** —— 文档中心检索与导航
- **secretpad-frontend-dev** —— 前端开发工作流
- **secretpad-backend-dev** —— 后端开发工作流
- **kuscia-dev** —— Kuscia 开发工作流

AI 助手会自动加载这些技能以提供准确的项目级指导。

---

## 安全注意事项

- **mTLS**：Kuscia 在生产环境使用 mTLS 进行跨域通信；开发模式使用 `KUSCIA_PROTOCOL=notls`
- **证书**：`secretpad/scripts/test/setup.sh` 生成开发 CA/客户端证书和 `config/server.jks`，切勿提交到版本控制
- **认证**：SecretPad 使用自定义 `LoginInterceptor` + Token 数据库，非 Spring Security
- **授权**：Kuscia 使用 Casbin；DataMesh 强制执行 domaindata 授权
- **密钥管理**：Kuscia pre-commit hooks 运行 gitleaks；不要硬编码密码、令牌或证书密钥
- **sudo 权限**：本地 Kuscia 需要 root 权限绑定 CoreDNS 端口 53
- **敏感文件**：前端 `.env` 代理配置已加入 gitignore；证书目录 `config/certs/` 和 `.local-kuscia/var/certs/` 仅限本地

详见 [AGENTS.md §10](./AGENTS.md#10-security-considerations)。

---

## 跨项目集成要点

修改代码时需明确各层契约归属：

- **前端 ↔ 后端**：REST JSON under `/api/v1alpha1/*`，DTOs 位于 `secretpad-service`
- **后端 ↔ Kuscia**：gRPC 通过生成的客户端 `secretpad-api/client-java-kusciaapi`，连接参数由环境变量控制
- **Kuscia ↔ SecretFlow**：Kuscia 调度容器化的 SecretFlow 任务；SecretFlow 通过 DataMesh 读取 `DomainData`
- **DataMesh ↔ SecretFlow**：gRPC + Apache Arrow Flight；客户端代码在 `secretflow/kuscia/datamesh.py`
- **Protobuf 契约**：共享 `.proto` 文件位于 `kuscia/proto/` 和 `secretflow/protos/`；修改 proto 需重新生成所有消费语言的 stub

详见 [AGENTS.md §11](./AGENTS.md#11-cross-project-integration)。

---

## 典型开发工作流

1. **从根目录开始**：`cd /home/charles/code/sfwork`
2. **选择启动器**：
   - 无 Docker 全量启动：`bash scripts/run-all-no-docker.sh`
   - Docker Kuscia + 本地后端/前端：`bash scripts/dev-start.sh`
3. **修改后端代码**：`cd secretpad && mvn clean install -Dmaven.test.skip=true`，重启后端
4. **修改前端代码**：`cd secretpad/frontend-src && pnpm --filter secretpad dev` 支持热重载
5. **修改 Kuscia 代码**：`cd kuscia && bash hack/build.sh -t kuscia`，重启 Kuscia Master
6. **提交前运行测试**：在对应子项目中执行测试
7. **查看日志**：`logs/kuscia-master.log`、`logs/backend.log`、`logs/frontend.log` 及各项目专属日志目录

详见 [AGENTS.md §12](./AGENTS.md#12-common-development-workflow)。

---

## 远程仓库

```text
https://github.com/fengzhizi319/sfwork.git
```

---

## 更多信息

- **完整技术细节**：请阅读 [AGENTS.md](./AGENTS.md)（570 行完整项目指南）
- **架构总览**：[PROJECT_SUMMARY.md](./PROJECT_SUMMARY.md)（英文）、[项目总结.md](./项目总结.md)（中文）
- **文档中心**：[docs/doc-center/README.md](./docs/doc-center/README.md)（分类文档索引）
- **运行说明**：[无docker运行说明.md](./docs/无docker运行说明.md)、[二次开发运行说明.md](./docs/二次开发运行说明.md)
