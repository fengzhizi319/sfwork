# SFWork 项目总结

> 本文档是 `sfwork` 工作空间的总体说明，面向需要同时改动 SecretPad 前端、SecretPad 后端、Kuscia 或 SecretFlow 算法组件的开发者。内容综合了 `AGENTS.md`、`PROJECT_SUMMARY.md`、`docs/前后端Kuscia及SecretFlow算法模块联调与Bug定位指南.md` 以及各隐私计算组件文档，力求覆盖架构、技术栈、构建方式、运行端口和常见问题的完整信息。

---

## 1. 项目定位

`sfwork` 是 SecretFlow 隐私计算生态的本地二次开发工作空间，采用“单仓库多项目”的组织形式，把四个紧密集成的仓库放在同一目录下：

| 项目 | 语言/框架 | 作用 | 目录 |
|------|-----------|------|------|
| **Kuscia** | Go 1.24.7 | Kubernetes 风格的隐私计算任务编排引擎 | `kuscia/` |
| **SecretFlow** | Python 3.10/3.11 | MPC/HEU/SPU/TEE/FL 等隐私计算算法框架 | `secretflow/` |
| **SecretPad 后端** | Java 17 + Spring Boot 3.3.5 | Web 管理控制台后端，负责业务逻辑和与 Kuscia 交互 | `secretpad/` |
| **SecretPad 前端** | TypeScript + React 18 + Umi 4 | Web 管理控制台 UI | `secretpad/frontend-src/` |

> 注意：根目录下还有一个 `secretpad-frontend/`，是前端代码的历史副本，当前活跃开发在 `secretpad/frontend-src/`。

---

## 2. 整体架构与数据流

```text
SecretPad 前端 (React/Umi，localhost:8000)
        │  REST /api/v1alpha1/*
        ▼
SecretPad 后端 (Spring Boot，localhost:8080/8443/9001)
        │  gRPC (KusciaAPI，localhost:18083)
        ▼
Kuscia Master/Lite (Docker，charles-kuscia-master / charles-kuscia-lite-*)
        │  调度 KusciaJob / KusciaTask / Pod
        ▼
SecretFlow (Python)  ← 在容器内执行隐私计算算法
        │
        ▼
DataMesh (Kuscia 内置)  ← 通过 gRPC + Apache Arrow Flight 读写 DomainData
```

关键抽象：

- **前端**：把“训练流/节点/属性”翻译成 `ProjectGraph` 的 REST 调用。
- **后端**：把 `ProjectGraph` 转换成 `ProjectJob`，再生成 `KusciaJob` 的 `TaskInputConfig`。
- **Kuscia**：把 `KusciaJob` 拆成 `KusciaTask`，最终在 Lite 节点上运行 Pod。
- **SecretFlow**：Pod 内通过 `python -m secretflow.kuscia.entry ./kuscia/task-config.conf` 读取任务配置，调用 `comp_eval` 执行组件。
- **DataMesh**：Kuscia 内置的数据访问与授权层，管理 `DomainData`、`DomainDataSource`、`DomainDataGrant`。

---

## 3. 各子项目详解

### 3.1 Kuscia

**项目描述**
Kuscia 是 SecretFlow 生态的底层编排引擎，以 Kubernetes CRD 为核心抽象，管理联邦学习/隐私计算场景中的分布式任务、数据资产和多方通信。

**主要语言与技术栈**

- Go 1.24.7
- Kubernetes CRDs (`k8s.io/* v0.33.5`)
- gRPC / Protocol Buffers
- Gin（内部 HTTP）、Envoy（网关）、CoreDNS（服务发现）
- containerd / runc / K3s（嵌入式控制平面）
- Apache Arrow Flight（DataMesh I/O）
- Zap / 自定义 `nlog` 日志、Viper 配置

**关键目录**

| 目录 | 用途 |
|------|------|
| `cmd/kuscia/` | CLI 入口与模块初始化 |
| `pkg/agent/` | Kubelet-like 代理，Pod 生命周期、CRI |
| `pkg/controllers/` | CRD 控制器（job、task、domain、route、domaindata 等） |
| `pkg/kusciaapi/` | 外部 HTTP/gRPC API 服务器 |
| `pkg/datamesh/` | DataMesh HTTP/gRPC + Arrow Flight |
| `pkg/gateway/` | Envoy xDS 控制平面、domain route、握手 |
| `pkg/scheduler/` | 调度插件 |
| `pkg/web/` | 内部 Gin + gRPC web 框架 |
| `pkg/crd/` | 生成的 Go 类型、clientset、informers、listers |
| `crds/v1alpha1/` | CRD YAML 清单 |
| `proto/api/v1alpha1/` | Protobuf 定义 |
| `scripts/deploy/` | Docker 部署脚本 |

**构建与测试**

```bash
cd /home/charles/code/sfwork/kuscia
make build              # 构建 kuscia 二进制
make test               # 单元测试
make lint-golang        # Lint
make image              # Docker 镜像
```

**常用端口（非 Docker 本地开发）**

| 服务 | 端口 | 说明 |
|------|------|------|
| KusciaAPI gRPC | 18083 | SecretPad 后端连接 |
| Kuscia Envoy 内部 | 13081 | 数据面通信 |
| Gateway 公共 | 18080 | 外部访问 |

> 本次开发 Kuscia 源码未改动，主要使用官方 Kuscia 镜像。

---

### 3.2 SecretFlow

**项目描述**
SecretFlow 是统一的隐私保护计算框架，支持安全多方计算（MPC）、同态加密（HEU）、可信执行环境（TEE）、联邦学习（FL）等，在不暴露原始数据的前提下执行联合分析和建模。

**主要语言与技术栈**

- Python 3.10 / 3.11
- JAX、NumPy、pandas、scikit-learn
- SPU、HEU、sf-sml、secretflow-spec、secretflow-dataproxy
- PyArrow、DuckDB、gRPC
- 构建：`pdm-backend`，PEP 517 wheel

**关键目录**

| 目录 | 用途 |
|------|------|
| `secretflow/device/` | `PYU`、`SPU`、`HEU`、`TEEU` 设备抽象 |
| `secretflow/component/` | 组件/流水线系统 |
| `secretflow/ml/` | FL/SL 算法 |
| `secretflow/preprocessing/` | 特征工程 |
| `secretflow/privacy/` | 差分隐私、k-匿名、L-多样性等 |
| `secretflow/kuscia/` | Kuscia 任务入口、DataMesh 客户端 |
| `secretflow/protos/` | 源 `.proto` 文件 |
| `tests/` | pytest 测试套件 |

**构建与测试**

```bash
cd /home/charles/code/sfwork/secretflow

# 可编辑安装
pip install -e .

# 构建 wheel
python -m build --wheel

# 测试
python -m pytest tests/ -v                  # simulation 模式
python -m pytest tests/ --env=prod -v       # MPC 模式
```

**自定义隐私计算镜像**

```bash
cd /home/charles/code/sfwork/secretflow/docker/privacy-dev

# 默认使用阿里云 PyPI 镜像源
docker build . -f Dockerfile -t secretflow/sf-privacy-dev:1.15.0.dev-privacy

# 若阿里云源下载中断/哈希校验失败，切换到官方 PyPI：
docker build . -f Dockerfile \
  --build-arg PIP_INDEX_URL=https://pypi.org/simple/ \
  -t secretflow/sf-privacy-dev:1.15.0.dev-privacy
```

镜像构建完成后会断言 `privacy/l_diversity:1.0.0` 组件已注册。

---

### 3.3 SecretPad 后端

**项目描述**
SecretPad 是 Web 管理控制台后端，处理用户、项目、图、作业、数据表等业务逻辑，并通过 KusciaAPI gRPC 把作业下发给 Kuscia。

**主要语言与技术栈**

- Java 17
- Spring Boot 3.3.5
- Spring Data JPA + Hibernate，SQLite 默认、MySQL 可选
- Flyway 数据库迁移
- gRPC 1.62.2 + Protobuf 3.25.5
- Quartz 调度、Ehcache 3
- Maven 多模块

**模块划分**

| 模块 | 职责 |
|------|------|
| `secretpad-common` | 工具、异常、枚举、常量 |
| `secretpad-persistence` | JPA 实体（`*DO`）、仓库、Flyway、数据同步 |
| `secretpad-manager` | Kuscia、数据、节点、作业、 serving 等集成管理 |
| `secretpad-service` | 业务逻辑、DTO/VO、DAG 图构建 |
| `secretpad-scheduled` | Quartz 定时任务 |
| `secretpad-api` | 生成的 gRPC 客户端（`client-java-kusciaapi`） |
| `secretpad-web` | Spring Boot 主应用、控制器、过滤器 |

**构建与测试**

```bash
cd /home/charles/code/sfwork/secretpad
mvn clean test
mvn clean package -DskipTests -Dfile.encoding=UTF-8   # 产物 target/secretpad.jar
```

**关键后端类**

- `GraphController`：REST 接口 `/api/v1alpha1/graph/*`
- `KusciaJobConverter`：把 `ProjectJob` 转成 `CreateJobRequest`
- `NodeDefUtils`：旧 `Pipeline.NodeDef` → 新 `secretflow_spec.v1.NodeEvalParam` 转换
- `JobRenderHandler`：渲染节点输入 `DistData`

---

### 3.4 SecretPad 前端

**项目描述**
SecretPad 的 Web UI，提供数据管理、训练流 DAG 编辑、作业监控和结果可视化。

**主要语言与技术栈**

- Node.js >= 16.14.0
- pnpm 8.8.0
- React 18 + Umi 4
- Ant Design 5
- TypeScript 4.9
- Valtio 状态管理（注意：不是 Dva）
- Nx monorepo、tsup 构建共享包
- Jest + React Testing Library

**目录结构**

| 目录 | 用途 |
|------|------|
| `apps/platform/` | 主 SecretPad Web 应用 |
| `apps/docs/` | Dumi 文档站 |
| `packages/dag/` | `@secretflow/dag` DAG 图引擎 |
| `packages/utils/` | `@secretflow/utils` 共享工具 |
| `tooling/eslint/` / `stylelint/` / `tsconfig/` / `jest/` / `tsup/` | 共享工程配置 |

**常用命令**

```bash
cd /home/charles/code/sfwork/secretpad/frontend-src
pnpm bootstrap                    # 安装依赖并构建共享包
pnpm --filter secretpad dev       # 开发服务器 http://localhost:8000
pnpm --filter secretpad build
pnpm --filter secretpad test
pnpm --filter secretpad lint:js
```

**关键前端文件**

- `component-tree-service.ts`：组件树分组与排序
- `component-icon.tsx`：组件分类图标
- `quick-config-privacy.tsx`：隐私计算快速配置抽屉
- `pipeline-template-privacy.ts` / `pipeline-template-privacy-guide.ts`：隐私计算流水线模板

---
## 4. 最近完成的重要修改

本次开发围绕 SecretFlow 1.15 隐私计算组件（特别是 `privacy/l_diversity`）的端到端打通，主要改动如下：

### 4.1 协议升级：`NodeEvalParam` 替换旧 `NodeDef`

- `TaskInputConfig.sf_node_eval_param` 从 `secretflow.pipeline.NodeDef` 升级为 `secretflow_spec.v1.NodeEvalParam`。
- `NodeEvalParam` 使用 `comp_id`（格式 `domain/name:version`）取代原来的 `domain`/`name`/`version` 三个字段。
- 后端新增 `NodeDefUtils.toNodeEvalParam()` 统一完成旧 → 新协议转换。
- 修复了 Java protobuf 生成方法名大小写问题（`addAllI64S` 而非 `addAllI64s`）。
- 所有构造 `TaskInputConfig` 的 converter（`KusciaJobConverter`、`KusciaTrustedFlowJobConverter`、`ModelExportServiceImpl` 等）均完成适配。

### 4.2 Protobuf package 对齐

- `secretpad/proto/secretflow/spec/v1/*.proto` 的 `package` 从 `secretflow.spec.v1` 改为 `secretflow_spec.v1`，与 SecretFlow Python 包一致。
- `option java_package = "com.secretflow.spec.v1"` 保持不变，Java 侧 import 路径不变。
- 修复了 Any 的 `type_url` 不匹配导致的 `Can not find message descriptor` 错误。

### 4.3 `MessageToJson` 兼容性修复

- SecretFlow 镜像内 protobuf 版本为 4.25.9，不支持 `always_print_fields_with_no_presence`（protobuf >= 5.0 才支持）。
- `secretflow/kuscia/meta_conversion.py` 新增 `_message_to_json_compat` helper，运行时自动判断可用参数，回退到 `including_default_value_fields=True`。
- 修复后差分隐私流水线可正常输出 `DomainData` 并生成报告。

### 4.4 自定义镜像构建与导入

- `secretflow/docker/privacy-dev/Dockerfile` 将 `ENV PIP_INDEX_URL=...` 改为 `ARG PIP_INDEX_URL=...`，默认阿里云，可用 `--build-arg` 切换到官方 PyPI，解决网络不稳定导致的 pip 哈希校验失败/Read timed out。
- 镜像构建时断言 `privacy/l_diversity:1.0.0` 已注册。
- `scripts/dev-start.sh` 修复了 `import_custom_image_to_lite` 对 `kuscia image list` 输出流的判断（合并 stdout/stderr 后过滤）。
- `scripts/` 下所有脚本补充了详细中文注释。

### 4.5 前端隐私计算模板

- 新增/调整 `quick-config-privacy.tsx`、`pipeline-template-privacy.ts`、`pipeline-template-privacy-guide.ts`。
- 组件列表 `secretpad/config/components/secretflow.json` 与 i18n 文件已包含 `privacy/l_diversity`。

### 4.6 文档完善

- 新增/更新 `docs/前后端Kuscia及SecretFlow算法模块联调与Bug定位指南.md`，覆盖协议升级、Any type_url、镜像构建失败、MessageToJson 兼容、前端 Network/Console/Sources 调试等案例。
- 更新 `docs/二次开发运行说明.md`、`docs/privacy-component-*.md`、`docs/配置说明.md` 以匹配最新代码。

---

## 5. 本地开发环境与端口

### 5.1 推荐启动方式

```bash
cd /home/charles/code/sfwork

# 首次或 SecretFlow 镜像变更后必须加 --reset-kuscia
bash scripts/dev-start.sh --reset-kuscia

# 平时只改前后端代码时直接启动
bash scripts/dev-start.sh

# 停止（默认不停 Kuscia，加 --kuscia 才停容器）
bash scripts/dev-stop.sh
bash scripts/dev-stop.sh --kuscia
```

### 5.2 默认端口速查

| 服务 | 端口 | 说明 |
|------|------|------|
| SecretPad 前端 dev server | 8000 | Umi dev，/api 代理到后端 8080 |
| SecretPad 后端 HTTP | 8080 | `server.http-port` |
| SecretPad 后端 HTTPS | 8443 | `server.port` |
| SecretPad 内部 API | 9001 | `server.http-port-inner` |
| KusciaAPI gRPC | 18083 | SecretPad 后端连接 |
| Kuscia Gateway 公共 | 18080 | 外部访问 |
| Kuscia Envoy 内部 | 13081 | 数据面通信 |

### 5.3 后端连接 Kuscia 的环境变量

```bash
export KUSCIA_API_ADDRESS=127.0.0.1
export KUSCIA_API_PORT=18083
export KUSCIA_GW_ADDRESS=127.0.0.1:13081
export KUSCIA_PROTOCOL=notls
```

### 5.4 开发登录

- 地址：`http://localhost:8000`
- 账号：`admin`
- 密码：`12345678`

---

## 6. 构建与测试速查表

| 目标 | 命令 |
|------|------|
| 构建 Kuscia | `cd kuscia && make build` |
| 测试 Kuscia | `cd kuscia && make test` |
| 构建 SecretFlow wheel | `cd secretflow && python -m build --wheel` |
| 测试 SecretFlow | `cd secretflow && python -m pytest tests/ -v` |
| 构建 SecretPad jar | `cd secretpad && mvn clean package -DskipTests` |
| 测试 SecretPad | `cd secretpad && mvn clean test` |
| 构建隐私计算镜像 | `cd secretflow/docker/privacy-dev && docker build . -f Dockerfile -t secretflow/sf-privacy-dev:1.15.0.dev-privacy` |
| 前端安装+构建共享包 | `cd secretpad/frontend-src && pnpm bootstrap` |
| 前端开发服务器 | `cd secretpad/frontend-src && pnpm --filter secretpad dev` |
| 一键启动全部 | `bash /home/charles/code/sfwork/scripts/dev-start.sh` |
| 停止全部 | `bash /home/charles/code/sfwork/scripts/dev-stop.sh` |

---

## 7. 典型问题与分层定位

遇到“流水线卡住/报错/没结果”时，按以下顺序排查。

### 7.1 第一层：前端是否把请求正确发出去

打开浏览器开发者工具（`F12` / `Ctrl+Shift+I` / `Cmd+Option+I`）：

1. **Network 面板**
   - 清空记录，勾选 `Preserve log`。
   - 触发操作，观察是否出现 `/api/v1alpha1/...` 请求。
   - 检查 `Headers`（状态码 200）、`Payload`（`projectId`/`graphId`/`nodes` 是否正确）、`Response`（`status.code` 是否为 0）。
   - 过滤框输入 `api/v1alpha1` 可快速定位接口。
2. **Console 面板**：查看 React/TypeScript 异常、Antd 表单校验失败等红色报错。
3. **Sources 面板**：按 `Ctrl/Cmd + P` 搜索 `graph-service.ts`，在 `startGraph`/`saveGraph` 处打断点。

### 7.2 第二层：后端是否收到并正确处理请求

```bash
# 实时跟踪后端日志
tail -f /home/charles/code/sfwork/logs/backend.log

# 只看错误
grep -iE "error|exception|fail" /home/charles/code/sfwork/logs/backend.log | tail -50
```

常用 REST 端点：

| 功能 | 端点 | 关键类 |
|------|------|--------|
| 创建图 | `/api/v1alpha1/graph/create` | `GraphController.createGraph` |
| 启动图 | `/api/v1alpha1/graph/start` | `GraphController.startGraph` |
| 查询节点状态 | `/api/v1alpha1/graph/node/status` | `GraphController.listGraphNodeStatus` |

### 7.3 第三层：Kuscia 是否正常调度

```bash
# 查看 Kuscia 容器
docker ps --filter name=kuscia

# 查看 Lite 节点镜像是否导入
docker exec -i charles-kuscia-lite-alice kuscia image list 2>&1 | grep sf-privacy-dev

# 查看 Pod/任务
docker exec charles-kuscia-master kubectl get kj,kt,pods -A
```

### 7.4 第四层：SecretFlow 容器内执行是否成功

```bash
# 查看 Pod 日志
docker exec charles-kuscia-lite-alice crictl ps -a
docker exec charles-kuscia-lite-alice crictl logs <container-id>
```

### 7.5 几个高频问题

| 现象 | 根因 | 解决 |
|------|------|------|
| Kuscia 任务报 `ParseError: Can not find message descriptor by type_url: type.googleapis.com/secretflow.spec.v1.IndividualTable` | `.proto` package 不一致 | 将 `secretpad/proto/secretflow/spec/v1/*.proto` 的 `package` 改为 `secretflow_spec.v1` |
| SecretFlow 容器报 `TypeError: MessageToJson() got an unexpected keyword argument 'always_print_fields_with_no_presence'` | protobuf 4.25.9 不支持新参数 | 使用 `_message_to_json_compat` helper |
| Docker build 报 pip 哈希校验失败 / Read timed out | 阿里云 PyPI 下载中断 | 追加 `--build-arg PIP_INDEX_URL=https://pypi.org/simple/` |
| Kuscia Pod `ErrImagePull` | 自定义镜像未导入 Lite 节点 | `docker save image:tag \| docker exec -i lite kuscia image load` |
| 前端运行按钮点击无反应 | 后端返回非 0，前端未提示 | 看 Network 面板 Response 最准确 |

---

## 8. 隐私计算组件端到端 checklist

以新增 `privacy/l_diversity` 为例：

1. **SecretFlow 侧**
   - 实现 `secretflow/component/privacy/l_diversity.py` 并加 `@register(domain="privacy", version="1.0.0", name="l_diversity")`。
   - 本地 `comp_eval(..., cluster_config=None)` 验证通过。
   - 生成 wheel 并构建镜像，确认镜像内 `Registry.get_definition_by_id('privacy/l_diversity:1.0.0')` 非空。
2. **SecretPad 后端侧**
   - 重新生成 `secretpad/config/components/secretflow.json` 和 `secretpad/config/i18n/secretflow.json`。
   - `mvn clean install` 通过。
3. **SecretPad 前端侧**
   - `component-tree-service.ts` 加入 `privacy` 分组与排序。
   - `component-icon.tsx` 加入 `SafetyOutlined` 图标。
   - 如需模板，新增 `quick-config-privacy.tsx`、`pipeline-template-privacy.ts`。
4. **Kuscia 侧**
   - 将新镜像导入 `charles-kuscia-lite-alice` 和 `charles-kuscia-lite-bob`。
5. **验证**
   - 前端组件树出现“隐私计算/L-多样性”。
   - 拖拽配置、连线、运行，任务状态 `SUCCEED`，`reportCount = 1`。

---

## 9. 参考资料

- `AGENTS.md`：本工作空间的 Agent 开发指南（技术栈、构建命令、代码风格）。
- `PROJECT_SUMMARY.md`：英文版项目架构概览。
- `docs/前后端Kuscia及SecretFlow算法模块联调与Bug定位指南.md`：完整的联调与 Bug 定位案例。
- `docs/二次开发运行说明.md`：非 Docker 本地运行手册。
- `docs/privacy-component-*.md`：隐私计算组件的 HLD/LLD/实现/测试/部署文档。
- `docs/配置说明.md`：配置与交付 summary。

---

> 最后更新：2026-07-09
