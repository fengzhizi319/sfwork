# SecretFlow `privacy` 组件二次开发 — 高层设计文档（HLD）

> **依据**：`docs/privacy-component-development-guide.md`  
> **目标**：为在 `sfwork` 工作区中新增 `secretflow/component/privacy` 下的隐私计算组件（如 k-匿名、差分隐私、L-多样性等）提供可直接生成代码的高层设计。  
> **适用项目**：`secretflow/`、`secretpad/`、`secretpad/frontend-src/`、`kuscia/`  
> **版本**：1.0  
> **日期**：2026-07-08

---

## 1. 文档信息

| 项 | 内容 |
|---|---|
| 文档名称 | SecretFlow privacy 组件二次开发高层设计文档 |
| 目标读者 | 算法工程师、后端工程师、前端工程师、测试工程师、DevOps |
| 设计范围 | 新增 `privacy` 域组件的全生命周期：定义 → 注册 → 元数据生成 → 前端展示 → 图调度 → Kuscia 执行 → 结果回流 |
| 非设计范围 | Kuscia 控制面改造、SecretPad 权限体系改造、新 `DistDataType` 的跨语言协议扩展 |
| 关键输入 | `docs/privacy-component-development-guide.md`、现有 `secretflow/component/privacy/*` 参考实现 |

---

## 2. 背景与目标

在 SecretFlow 生态中，新增一个隐私计算组件需要让四个独立系统（SecretFlow、SecretPad 后端、SecretPad 前端、Kuscia）在各自职责范围内“认识”该组件：

1. **SecretFlow**：组件的真正实现者，负责算法逻辑、参数校验、输入输出转换。
2. **SecretPad 后端**：组件的元数据消费者与图编排者，负责把用户拖拽的图转成 Kuscia 任务。
3. **SecretPad 前端**：组件的展示与配置入口，负责组件树、表单、DAG 节点渲染。
4. **Kuscia**：组件的运行基础设施，对组件类型无感知，只调度 SecretFlow 镜像与配置。

本文档给出新增 `privacy` 组件的**高层架构、数据流、模块职责与接口边界**，使各端工程师能据此直接编写或生成代码。

---

## 3. 术语表

| 术语 | 说明 |
|---|---|
| `Component` | SecretFlow 组件基类，通过 `@register` 注册到 `Registry`。 |
| `comp_id` | 组件唯一标识：`domain/name:major.minor.patch`，如 `privacy/l_diversity:1.0.0`。Registry 按 `domain/name:major` 匹配。 |
| `Field.attr` | 组件配置属性（如 `k`、`epsilon`），对应前端表单字段。 |
| `Field.input` / `Field.output` | 组件输入/输出数据槽，对应 DAG 端口。 |
| `DistData` | SecretFlow 内部统一数据对象，含类型、元数据、数据引用。 |
| `DistDataType` | 数据类型枚举，如 `sf.table.individual`、`sf.report`。 |
| `VTable` | 对 `DistData` 的高级封装，描述多方表 schema、party、uri。 |
| `DomainData` | Kuscia 中的数据 CRD，SecretFlow 入口层负责 `DomainData ↔ DistData` 转换。 |
| `NodeEvalParam` | SecretPad 后端渲染出的节点执行参数，SecretFlow `comp_eval` 的输入。 |
| `SFClusterConfig` | SecretFlow 运行时集群配置（parties、self_party、设备配置等）。 |
| `CompListDef` / `ComponentDef` | SecretFlow 组件元数据 protobuf 的 JSON 表示，SecretPad 启动时加载。 |
| `codeName` | 前端 DAG 节点标识，格式 `domain/name`，如 `privacy/l_diversity`。 |
| `task-config.conf` | Kuscia 下发到 Pod 的任务配置，SecretFlow 容器入口读取。 |

---

## 4. 总体架构

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SecretPad Frontend (React/Umi)                     │
│  ┌──────────────┐   ┌──────────────┐   ┌─────────────────────────────────┐  │
│  │ 组件树        │   │ 配置表单      │   │ DAG 画布（节点/端口/连线）         │  │
│  │ component-tree│   │ config-form  │   │ main-dag                         │  │
│  └──────┬───────┘   └──────┬───────┘   └────────────┬────────────────────┘  │
└─────────┼──────────────────┼────────────────────────┼───────────────────────┘
          │ REST /api/v1alpha1/component/*
          │ REST /api/v1alpha1/graph/*
          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          SecretPad Backend (Spring Boot)                     │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐  │
│  │ ServiceConfig│   │ Component    │   │ GraphBuilder │   │ KusciaJob    │  │
│  │ (加载 JSON)   │   │ Service      │   │ /JobRender   │   │ Converter    │  │
│  └──────────────┘   └──────────────┘   └──────┬───────┘   └──────┬───────┘  │
└────────────────────────────────────────────────┼──────────────────┼─────────┘
                                                 │ gRPC CreateJob
                                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                                     Kuscia (Go)                              │
│  KusciaJobController → scheduler → KusciaTask → Pod → task-config.conf       │
└─────────────────────────────────────────────────────────────────────────────┘
                                                 │
                                                 │ 容器启动
                                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          SecretFlow Container (Python)                       │
│  secretflow.kuscia.entry.main() → preprocess → comp_eval() → evaluate()      │
│                                     │                                        │
│                                     ▼                                        │
│                          DataMesh / DomainData / 本地存储                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

**关键边界**：

- SecretFlow 是组件实现与元数据的**唯一来源**。
- SecretPad 不解析 Python，只消费 `secretpad/config/components/secretflow.json` 与 `secretpad/config/i18n/secretflow.json`。
- Kuscia 对组件类型完全无感知，仅透传 `task_input_config`。

---

## 5. 关键设计原则

| 原则 | 说明 |
|---|---|
| **元数据驱动** | 组件的所有展示、表单、端口信息来自 SecretFlow 生成的 `ComponentDef` JSON。 |
| **算法与组件解耦** | 核心算法放在 `secretflow/privacy/<算法>/`，组件胶水层放在 `secretflow/component/privacy/<name>.py`。 |
| **单所有者执行** | `privacy` 组件目前仅处理 `sf.table.individual`（单方表），数据所有方执行，非所有方输出空占位。 |
| **Schema 继承** | 输出表 schema 从输入 schema 派生：保留原列顺序，删除已缺失列，新增列默认 `FEATURE`。 |
| **版本语义化** | 同一 `domain/name:major` 在 Registry 中唯一；破坏性变更升 major，补丁迭代升 patch。 |
| **Kuscia 无侵入** | 新增组件不修改 Kuscia 源码与 CRD，仅依赖 SecretFlow 镜像包含新代码。 |

---

## 6. 组件模型高层设计

### 6.1 类与注解

每个组件是一个继承自 `Component` 的 Python 类，使用 `@register(domain, version, name)` 注册。

```python
@register(domain="privacy", version="1.0.0", name="l_diversity")
class LDiversity(Component):
    # 配置属性
    k: int = Field.attr(...)
    # 输入/输出槽
    input_ds: Input = Field.input(...)
    output_ds: Output = Field.output(...)

    def evaluate(self, ctx: Context):
        ...
```

### 6.2 字段类型与前端映射

| 字段声明 | 语义 | 前端渲染 |
|---|---|---|
| `Field.attr(desc=..., type=int/float/str/bool, ...)` | 组件配置参数 | 对应表单控件：数字输入框、滑动条、开关、下拉单选/多选、文本框等。 |
| `Field.input(desc=..., types=[DistDataType.INDIVIDUAL_TABLE])` | 数据输入槽 | DAG 节点顶部 input 端口，类型匹配时才允许连线。 |
| `Field.output(desc=..., types=[DistDataType.REPORT])` | 数据输出槽 | DAG 节点底部 output 端口。 |

### 6.3 运行时上下文

`evaluate(self, ctx: Context)` 通过 `ctx` 访问：

- `ctx.storage`：读写底层文件（ORC/CSV）。
- `ctx.cluster_config`：分布式运行时配置，`None` 表示本地单进程模式。
- `ctx.load_table(...)` / `VTable.from_distdata(...)`：加载输入数据。
- 输出通过给 `self.output_ds.data` / `self.report.data` 赋值 `DistData` 完成。

### 6.4 报告输出

`Reporter` 用于生成 `sf.report`：

```python
reporter = Reporter(name="l_diversity", system_info=self.input_ds.system_info)
reporter.add_tab({"metric": [value], ...}, name="summary")
self.report.data = reporter.to_distdata()
```

---

## 7. 元数据流转设计

```text
secretflow/component/privacy/<comp>.py
        │  @register
        ▼
secretflow_spec Registry（内存）
        │  secretflow component inspect -a
        ▼
CompListDef JSON（secretflow.json）
        │  拷贝到 secretpad/config/components/
        ▼
ServiceConfiguration → List<CompListDef>
        │  /component/list, /component/batch
        ▼
SecretPad Frontend
        component-tree-service / component-config-registry
```

**设计要点**：

1. 组件字段、描述、类型、边界、默认值等全部来自 Python 源码。
2. 每次修改字段后必须重新生成 JSON 并重启 SecretPad 后端（启动时一次性加载）。
3. 翻译优先从 `secretflow/component/translation.json` 获取，缺省时回退到源码中的 `name` / `desc`。

---

## 8. 前端渲染高层设计

### 8.1 组件树

- `component-tree-service.ts` 按 `domain` 对组件分组。
- `mergedDomainMap` 把 `privacy` 映射为中文分组名“隐私计算”。
- `domainOrder` 控制分组排序。
- `component-icon.tsx` 为 `privacy` 域提供图标。

### 8.2 配置表单

- 用户点击 DAG 节点后，`config-form-view` 从 `ComponentConfigRegistry` 取出 `ComponentDef`。
- 根据 `attrs` 列表逐个渲染默认控件；如需特殊交互（如列选择器），注册自定义 renderer。

### 8.3 DAG 端口与连线

- `graph-hook-service` 根据 `ComponentDef.inputs` / `outputs` 生成节点端口。
- 端口类型（`types` 数组）决定连线兼容性：源端口 `sf.table.individual` 只能连入接受该类型的目标端口。

### 8.4 快速配置与流水线模板

- `quick-config-privacy.tsx` 提供隐私计算组件（差分隐私、L-多样性等）的快速配置抽屉。
- `pipeline-template-privacy.ts` 与 `pipeline-template-privacy-guide.ts` 提供预置的隐私计算训练流模板，降低用户配置成本。

---

## 9. 执行链路高层设计

```text
前端 POST /api/v1alpha1/graph/start
        │
        ▼
SecretPad Backend
  1. 校验 graph 节点、边、必填属性
  2. ProjectJob.genProjectJob()
  3. JobRenderHandler.renderInputs()：把上游 output 映射为当前节点的 DistData
  4. KusciaJobConverter.converter()：构建 CreateJobRequest
  5. KusciaGrpcClientAdapter.createJob()
        │
        ▼
Kuscia
  1. KusciaJobController 创建 KusciaJob CR
  2. scheduler.go 按依赖实例化 KusciaTask
  3. Pod 启动，挂载 task-config.conf
        │
        ▼
SecretFlow Container
  1. secretflow.kuscia.entry.main() 读取配置
  2. preprocess_sf_node_eval_param()：DomainData → DistData
  3. comp_eval()：Registry.get_definition_by_id("privacy/<comp>:1")
  4. <Component>.evaluate(ctx)
  5. postprocess_sf_node_eval_result()：DistData → DomainData
```

**关键点**：

- `comp_id` 由 `domain/name:version` 组成；SecretFlow 通过 `Registry.get_definition_by_id` 查找。
- `task_input_config` 为 JSON，Kuscia 不透传修改。
- 组件执行时只与 `Context`、输入 `DistData`、输出 `DistData` 交互，与 SecretPad/Kuscia 解耦。

---

## 10. 多参与方与数据所有权设计

当前 `privacy` 组件（k-anonymity、l-diversity、differential_privacy 等）设计为处理**单方 individual 表**：

- 输入 `DistData` 的 `parties` 长度应为 1。
- 在分布式模式下，通过 `get_self_party(ctx)` 判断当前进程是否为数据所有方。
- **数据所有方**：读取输入、执行算法、写输出表与报告。
- **非所有方**：直接生成空占位 `DistData`（调用 `make_empty_table_output`），避免跨 party 传输原始数据。
- 本地模式（`cluster_config is None`）：只有一个进程，直接执行。

---

## 11. 安全设计

| 层面 | 安全措施 |
|---|---|
| 参数校验 | 通过 `Field.attr` 的 `bound_limit`、`choices`、`default` 在运行时校验。 |
| JSON 属性 | 用户传入的 JSON 字符串仅使用 `json.loads` 解析，禁止 `eval`。 |
| 数据隔离 | 非数据所有方不读取输入，输出空占位。 |
| 存储访问 | 通过 `ctx.storage` 与 DataMesh 读写，不使用本地绝对路径。 |
| 通信安全 | Kuscia 生产环境使用 mTLS；本地 dev 模式使用 `KUSCIA_PROTOCOL=notls`。 |
| 敏感信息 | 日志中不打印原始数据，仅打印行数、schema、统计指标。 |

---

## 12. 变更范围总览

| 项目 | 必须变更 | 可选变更 | 通常不变 |
|---|---|---|---|
| **SecretFlow** | 新增 `component/privacy/<comp>.py`、测试文件 | 新增 `privacy/<算法>/` 算法实现、`component/translation.json` | — |
| **SecretPad 后端** | 重新生成 `config/components/secretflow.json`、`config/i18n/secretflow.json` | 若引入全新 `DistDataType` 需改 `GraphBuilder` 等 | 业务 Java 代码 |
| **SecretPad 前端** | `component-tree-service.ts` 加 domain、`component-icon.tsx` 加图标 | 自定义 renderer、面板样式 | 框架层代码 |
| **Kuscia** | — | 确保 AppImage 包含新代码 | 源码与 CRD |

---

## 13. 非功能设计

### 13.1 测试策略

- **SecretFlow 单元测试**：sim 模式使用本地存储，无需 Ray 集群；覆盖注册检查、参数非法值、正常执行、输出类型。
- **SecretFlow MPC 测试**：`@pytest.mark.mpc`，多进程生产模式验证 party 隔离。
- **SecretPad 后端测试**：重启后验证 `/component/list`、`/component/batch` 返回新组件。
- **前端测试**：组件树展示、配置抽屉、端口连线。
- **端到端测试**：`scripts/run-all-no-docker.sh` 拉起全链路后手动或自动化验证。

### 13.2 国际化

- 英文描述写在源码 `desc` 中。
- 中文显示名/描述通过 `secretflow/component/translation.json` 提供，再随 CLI 生成到 `secretpad/config/i18n/secretflow.json`。

### 13.3 日志与可观测性

- 组件内使用标准 `logging.getLogger(__name__)`。
- 关键日志：参数摘要、输入行数/列数、算法完成状态、报告指标。
- 避免在日志中输出原始样本值。

### 13.4 版本管理

- 初始版本建议 `1.0.0`。
- 同一 major 内的升级会覆盖 Registry key；破坏性变更必须升 major。

---

## 14. 参考文档

1. `docs/privacy-component-development-guide.md`
2. `secretflow/secretflow/component/privacy/k_anonymity.py`
3. `secretflow/secretflow/component/privacy/differential_privacy.py`
4. `secretflow/secretflow/component/privacy/_utils.py`
5. `secretflow/tests/component/privacy/test_privacy_components.py`
6. `secretpad/frontend-src/apps/platform/src/modules/component-tree/component-tree-service.ts`
7. `secretpad/frontend-src/apps/platform/src/modules/component-tree/component-icon.tsx`
8. `secretpad/frontend-src/apps/platform/src/modules/component-config/template-quick-config/quick-config-privacy.tsx`
9. `secretpad/frontend-src/apps/platform/src/modules/pipeline/templates/pipeline-template-privacy.ts`
10. `secretpad/frontend-src/apps/platform/src/modules/pipeline/templates/pipeline-template-privacy-guide.ts`
