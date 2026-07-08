# SecretFlow `privacy` 组件二次开发设计文档

> 目标：在 `secretflow/component/privacy` 下新增隐私计算组件（如差分隐私、k-匿名等），并打通 SecretPad 前端展示、后端图调度、Kuscia 任务执行的全链路。
> 适用项目：`sfwork` 工作区下的 `secretflow/`、`secretpad/`、`secretpad-frontend-src/`、`kuscia/`。

---

## 1. 整体架构与数据流

新增一个组件本质上是让四方都“认识”它：

```text
SecretPad Frontend (React/Umi)
    │  1. 拉取组件列表 /component/list
    │  2. 渲染组件树、配置表单、DAG 节点
    │  3. 提交图 /graph/start
    ▼
SecretPad Backend (Spring Boot)
    │  4. 解析 CompListDef JSON，暴露 REST API
    │  5. 保存 project_graph / project_graph_node
    │  6. 渲染 NodeEvalParam，调用 Kuscia JobService.CreateJob
    ▼
Kuscia (Go)
    │  7. 创建 KusciaJob → KusciaTask CR
    │  8. 调度 Pod，挂载 task-config.conf
    │  9. 组件对 Kuscia 是黑盒，只负责基础设施
    ▼
SecretFlow (Python, inside container)
    │  10. secretflow.kuscia.entry 读取 task-config.conf
    │  11. comp_eval 通过 Registry 找到组件
    │  12. 执行 Component.evaluate(ctx)
    ▼
DataMesh / DomainData (input/output)
```

**关键原则**：
- **SecretFlow** 是组件真正的“实现者”和“注册中心”。
- **SecretPad** 是组件的“展示层”和“图编排层”，依赖 SecretFlow 生成的组件元数据 JSON。
- **Kuscia** 是“资源调度器”，对组件类型无感知，只调度 SecretFlow 镜像。

---

## 2. 各项目关键模块说明

### 2.1 SecretFlow — 组件定义与执行

| 模块/文件 | 职责 |
|---|---|
| `secretflow/component/__init__.py` | 自动扫描并导入 `secretflow/component/` 下所有使用 `secretflow_spec` 的模块，完成注册。 |
| `secretflow/component/core/` | 组件基座：`Component`、`Context`、`Field`、`Input`、`Output`、`register`、`comp_eval` 等。 |
| `secretflow/component/core/entry.py` | `comp_eval(param, storage_config, cluster_config)`：根据 `comp_id` 查找组件、解析参数、执行 `evaluate()`、收集输出。 |
| `secretflow/component/core/dist_data/base.py` | `DistDataType` 枚举，定义输入输出数据类型（`sf.table.vertical`、`sf.report`、`sf.rule.*` 等）。 |
| `secretflow/component/core/i18n.py` | 组件国际化字符串提取。 |
| `secretflow/component/translation.json` | 组件/属性的中英文显示名。 |
| `secretflow/cli.py` | CLI：`secretflow component inspect -a` 生成 `CompListDef` JSON；`secretflow component get_translation` 生成翻译 JSON。 |
| `secretflow/kuscia/entry.py` | Kuscia 容器入口，把 `task-config.conf` 转换成 `NodeEvalParam` + `SFClusterConfig`，调用 `comp_eval`。 |
| `secretflow/kuscia/meta_conversion.py` | `DistData` 与 Kuscia `DomainData` 的类型映射。 |
| `secretflow/protos/secretflow/spec/extend/*.proto` | 自定义 protobuf 属性定义（普通组件通常不需要新增）。 |

**已有参考**：
- `secretflow/component/stats/table_statistics.py` — 标准统计组件。
- `secretflow/component/privacy/differential_privacy.py` — privacy 域已有示例。
- `tests/component/privacy/test_privacy_components.py` — 测试模板。

---

### 2.2 SecretPad 后端 — 组件元数据与图调度

| 模块/文件 | 职责 |
|---|---|
| `secretpad/config/components/secretflow.json` | SecretFlow 组件 catalog JSON，由 SecretFlow CLI 生成后拷贝进来。 |
| `secretpad/config/i18n/secretflow.json` | 组件/属性翻译 JSON。 |
| `secretpad/secretpad-service/.../configuration/ServiceConfiguration.java` | Spring Bean 加载 `./config/components/*.json` 为 `List<CompListDef>`。 |
| `secretpad/secretpad-service/.../factory/JsonProtobufSourceFactory.java` | JSON → Protobuf `CompListDef` 解析器。 |
| `secretpad/secretpad-service/.../service/impl/ComponentServiceImpl.java` | `/component/list`、`/component/batch` 等业务实现。 |
| `secretpad/secretpad-service/.../service/impl/GraphServiceImpl.java` | 图的 CRUD、启动、节点更新。 |
| `secretpad/secretpad-service/.../service/graph/GraphBuilder.java` | 图依赖解析：output → input 映射、拓扑排序。 |
| `secretpad/secretpad-service/.../service/graph/chain/JobRenderHandler.java` | 把图节点渲染成带 `DistData` 的任务输入。 |
| `secretpad/secretpad-service/.../service/graph/converter/KusciaJobConverter.java` | 把 `ProjectJob` 转成 Kuscia `CreateJobRequest`。 |
| `secretpad/secretpad-persistence/.../entity/ProjectGraphDO.java` | 图实体。 |
| `secretpad/secretpad-persistence/.../entity/ProjectGraphNodeDO.java` | 图节点实体，保存 `codeName`、`nodeDef`、inputs/outputs 等。 |
| `secretpad/secretpad-web/.../controller/GraphController.java` | `/api/v1alpha1/component/*`、`/api/v1alpha1/graph/*` REST 接口。 |

**关键流程**：
1. 启动时加载 `config/components/*.json`。
2. 前端 `/component/list` 拿到组件列表；`/component/batch` 拿到完整 `ComponentDef`。
3. 前端拖拽生成图，后端保存到 `project_graph` / `project_graph_node`。
4. 点击运行时，后端构建 `ProjectJob` → `KusciaJobConverter` → `JobService.CreateJob`。

---

### 2.3 SecretPad 前端 — 组件展示与图编排

| 模块/文件 | 职责 |
|---|---|
| `secretpad/frontend-src/apps/platform/src/modules/component-tree/component-tree-view.tsx` | 左侧组件树 UI。 |
| `secretpad/frontend-src/apps/platform/src/modules/component-tree/component-tree-service.ts` | 拉取 `/component/list`，按 domain 分组排序；需要把新 domain 加入映射表和排序数组。 |
| `secretpad/frontend-src/apps/platform/src/modules/component-tree/component-icon.tsx` | 组件分类图标映射。 |
| `secretpad/frontend-src/apps/platform/src/modules/component-tree/component-protocol.ts` | 组件数据结构类型定义。 |
| `secretpad/frontend-src/apps/platform/src/modules/component-config/component-config-registry.ts` | 把后端 `ComponentDef` 注册成扁平的配置节点树。 |
| `secretpad/frontend-src/apps/platform/src/modules/component-config/component-config-service.ts` | 根据节点获取配置结构。 |
| `secretpad/frontend-src/apps/platform/src/modules/component-config/config-form-view.tsx` | 右侧配置表单渲染。 |
| `secretpad/frontend-src/apps/platform/src/modules/component-config/config-item-render/config-render-contribution.ts` | 默认渲染器（bool、int、float、string、table_column 等）。 |
| `secretpad/frontend-src/apps/platform/src/modules/component-config/config-item-render/custom-render/**` | 自定义渲染器（如 PSI 键选择、SQL 分析）。 |
| `secretpad/frontend-src/apps/platform/src/modules/main-dag/graph-hook-service.ts` | 根据 `ComponentDef` 生成 DAG 节点 input/output 端口。 |
| `secretpad/frontend-src/apps/platform/src/modules/main-dag/graph-service.ts` | 拖拽添加节点、节点运行状态管理。 |
| `secretpad/frontend-src/apps/platform/src/modules/main-dag/graph-request-service.tsx` | 图详情查询、保存、运行请求。 |
| `secretpad/frontend-src/packages/dag/` | DAG 图引擎包（节点、边、端口、布局）。 |

**关键流程**：
1. `component-tree-service` 加载组件列表 → 分类展示。
2. 拖拽节点时，`graph-service` 创建 DAG 节点，codeName 为 `domain/name`。
3. `graph-hook-service` 根据 `ComponentDef` 的 `inputs` / `outputs` 生成端口。
4. 点击节点，`config-form-view` 根据 `ComponentConfigRegistry` 渲染表单。
5. 点击运行，`graph-request-service` 把 nodes/edges 提交到后端 `/graph/start`。

---

### 2.4 Kuscia — 任务调度与执行

| 模块/文件 | 职责 |
|---|---|
| `kuscia/proto/api/v1alpha1/kusciaapi/job.proto` | `JobService` gRPC 定义；`CreateJobRequest` 中的 `Task.task_input_config` 是透传 JSON。 |
| `kuscia/crds/v1alpha1/kuscia.secretflow_kusciajobs.yaml` | `KusciaJob` CRD：包含通用 task 模板列表。 |
| `kuscia/pkg/controllers/kusciajob/handler/scheduler.go` | 根据依赖和 `maxParallelism` 把 task 模板实例化为 `KusciaTask`。 |
| `kuscia/scripts/templates/app_image.secretflow.yaml` | SecretFlow 镜像模板：容器启动命令为 `python -m secretflow.kuscia.entry ./kuscia/task-config.conf`。 |
| `secretflow/secretflow/kuscia/entry.py` | SecretFlow 容器入口。 |

**关键原则**：
- Kuscia 不感知组件类型，只负责把 `task_input_config` 和 `AppImage` 下发到 Pod。
- 新增 `privacy` 组件**不需要修改 Kuscia 代码或 CRD**。

---

## 3. 新增 `privacy` 组件需要修改的模块清单

按改动范围从大到小排列：

### 3.1 SecretFlow（必须）

1. **新增组件实现文件**
   - `secretflow/component/privacy/<comp_name>.py`
   - 继承 `Component`，使用 `@register(domain="privacy", version="1.0.0", name="<comp_name>")`。
   - 声明 `Field.attr`、`Field.input`、`Field.output`。
   - 实现 `evaluate(self, ctx: Context)`。

2. **（可选）算法实现文件**
   - `secretflow/privacy/<comp_name>.py` 或 `secretflow/privacy/<algorithm>.py`
   - 保持组件层薄，算法逻辑下沉。

3. **（可选）公共工具**
   - `secretflow/component/privacy/_utils.py`
   - 用于 load_party_table、dump_party_tables、parse_json_attr 等共享逻辑。

4. **（可选）自定义 protobuf 属性**
   - `secretflow/protos/secretflow/spec/extend/<name>.proto`
   - 只有 `Field.custom_attr` 时才需要。

5. **（可选）国际化**
   - `secretflow/component/translation.json`
   - 给组件名、属性名提供中英文标签。

6. **新增测试**
   - `tests/component/privacy/test_<comp_name>.py`
   - 至少包含注册检查、sim-mode 测试、属性校验。

### 3.2 SecretPad 后端（必须：刷新组件元数据）

1. **重新生成组件 catalog**
   - 在 SecretFlow 环境下执行：
     ```bash
     secretflow component inspect -a > secretpad/config/components/secretflow.json
     secretflow component get_translation > secretpad/config/i18n/secretflow.json
     ```
   - 或使用脚本：`secretpad/scripts/update_components.sh`。

2. **重启 SecretPad**
   - `ServiceConfiguration` 在启动时加载 JSON，运行期不会热加载。

3. **（通常不需要）后端 Java 代码**
   - 如果新组件的输入输出类型、属性类型都是已有类型，则不需要改 Java。
   - 如果引入了全新的 `DistDataType` 或需要特殊图渲染逻辑，才需要改 `GraphBuilder`、`JobRenderHandler` 等。

### 3.3 SecretPad 前端（必须：让 UI 认识新分类）

1. **组件树分类映射**
   - `secretpad/frontend-src/apps/platform/src/modules/component-tree/component-tree-service.ts`
   - 在 `mergedDomainMap` 和 `domainOrder` 中加入 `privacy`。

2. **分类图标**
   - `secretpad/frontend-src/apps/platform/src/modules/component-tree/component-icon.tsx`
   - 为 `privacy` 增加图标。

3. **（可选）自定义表单渲染器**
   - 如果新组件有需要特殊 UI 的属性，添加 custom render 并注册。

4. **（可选）面板样式**
   - `secretpad/frontend-src/apps/platform/src/modules/component-config/component-panel-style-registry/mpc/`

### 3.4 Kuscia（通常不需要修改）

- 不需要修改 Kuscia 代码。
- 需要确保 SecretFlow 镜像（AppImage）包含新的组件代码。
- 如果使用本地非 Docker 模式，只需 SecretFlow 包已更新即可。

---

## 4. 整体设计方案

### 4.1 组件元数据流转设计

```text
secretflow/component/privacy/<comp>.py
    │  @register
    ▼
secretflow_spec Registry (内存)
    │  secretflow component inspect -a
    ▼
CompListDef JSON (secretflow.json)
    │  拷贝到 secretpad/config/components/
    ▼
SecretPad ServiceConfiguration → List<CompListDef>
    │  /component/list, /component/batch
    ▼
SecretPad Frontend
    component-tree-service / component-config-registry
```

**设计要点**：
- SecretFlow 是组件元数据的**唯一来源**。
- SecretPad 不解析 Python 源码，只消费 JSON。
- 每次新增/修改组件字段后，必须重新生成并拷贝 JSON，然后重启 SecretPad。

### 4.2 前端渲染设计

```text
ComponentDef (protobuf JSON)
    ├── domain / name / version / desc       → 组件树节点
    ├── attrs[]                              → 配置表单字段
    │     ├── name, desc, type, choices, ...
    ├── inputs[]                             → DAG 顶部 input 端口
    │     ├── name, types (DistDataType)
    └── outputs[]                            → DAG 底部 output 端口
          ├── name, types (DistDataType)
```

**设计要点**：
- `domain` 决定组件树分类。
- `attrs` 的类型决定表单渲染器（bool/int/float/string/choice/table_column 等）。
- `inputs/outputs` 的 `types` 决定端口是否可连线。
- 对于 `privacy` 域，建议输出 `sf.report` 类型报告，或输出 `sf.table.individual` / `sf.table.vertical`。

### 4.3 执行链路设计

```text
前端 /graph/start
    │
    ▼
SecretPad Backend
    ├── 校验 graph 节点和边
    ├── ProjectJob.genProjectJob()
    ├── JobRenderHandler.renderInputs()  解析上游输出为 DistData
    ├── KusciaJobConverter.converter()   构建 CreateJobRequest
    └── KusciaGrpcClientAdapter.createJob()
        │
        ▼
Kuscia
    ├── KusciaJobController 创建 KusciaJob
    ├── scheduler.go 调度 KusciaTask
    └── Pod 启动，挂载 task-config.conf
        │
        ▼
SecretFlow Container
    ├── secretflow.kuscia.entry.main()
    ├── preprocess_sf_node_eval_param()  DomainData → DistData
    ├── comp_eval()
    │     └── Registry.get_definition_by_id("privacy/<comp>:1")
    │     └── <Component>.evaluate(ctx)
    └── postprocess_sf_node_eval_result() DistData → DomainData
```

**设计要点**：
- `comp_id` 格式为 `privacy/<comp_name>:<major.minor.patch>`，Registry 按 major 版本查找。
- 组件执行时对 Kuscia/SecretPad 完全解耦。
- 输入输出通过 DataMesh 的 `DomainData` 中转。

---

## 5. 详细实施步骤

### 步骤 1：SecretFlow 新增组件

参考 `secretflow/component/privacy/differential_privacy.py`，新建：

```python
# secretflow/component/privacy/my_privacy_comp.py
from secretflow.component.core import (
    Component, Context, DistDataType, Field, Input, Interval, Output, register, Reporter,
)

@register(domain="privacy", version="1.0.0", name="my_privacy_comp")
class MyPrivacyComp(Component):
    epsilon: float = Field.attr(
        desc="Privacy budget epsilon.",
        bound_limit=Interval.open(0, None),
        default=1.0,
    )
    query_type: str = Field.attr(
        desc="Query type.",
        choices=["count", "sum", "mean"],
        default="count",
    )

    input_ds: Input = Field.input(
        desc="Input individual table.",
        types=[DistDataType.INDIVIDUAL_TABLE],
    )
    report: Output = Field.output(
        desc="Privacy report.",
        types=[DistDataType.REPORT],
    )

    def evaluate(self, ctx: Context):
        # 1. 读取输入
        df = ctx.load_table(self.input_ds).to_pandas()
        # 2. 调用算法
        result = self._compute(df)
        # 3. 生成报告输出
        reporter = Reporter(name="my_privacy_comp", system_info=self.input_ds.system_info)
        reporter.add_tab({"result": result}, name="result")
        self.report.data = reporter.to_distdata()

    def _compute(self, df):
        # 实际算法逻辑，建议放到 secretflow/privacy/ 下
        pass
```

### 步骤 2：SecretFlow 本地验证

```bash
cd /home/charles/code/sfwork/secretflow
source .venv/bin/activate  # 或 conda activate sf310

# 检查组件是否被注册
python -c "from secretflow.component.core import Registry; print(Registry.get_definition_by_id('privacy/my_privacy_comp:1.0.0'))"

# 生成组件 catalog
secretflow component inspect -a > /tmp/secretflow.json
secretflow component get_translation > /tmp/secretflow_i18n.json

# 跑单测
python -m pytest tests/component/privacy/test_my_privacy_comp.py -v
```

### 步骤 3：刷新 SecretPad 组件元数据

```bash
cp /tmp/secretflow.json /home/charles/code/sfwork/secretpad/config/components/secretflow.json
cp /tmp/secretflow_i18n.json /home/charles/code/sfwork/secretpad/config/i18n/secretflow.json
```

或使用项目脚本：

```bash
cd /home/charles/code/sfwork/secretpad
bash scripts/update_components.sh <secretflow-image-tag>
```

### 步骤 4：修改 SecretPad 前端

编辑 `secretpad/frontend-src/apps/platform/src/modules/component-tree/component-tree-service.ts`：

```typescript
const mergedDomainMap: { [key: string]: string } = {
  feature: '特征处理',
  preprocessing: '特征处理',
  postprocessing: '特征处理',
  read_data: '数据准备',
  data_prep: '数据准备',
  privacy: '隐私计算',   // 新增
};

const domainOrder = [
  '数据准备',
  'data_filter',
  '特征处理',
  'privacy',            // 新增
  'stats',
  'ml.train',
  'ml.predict',
  'ml.eval',
];
```

编辑 `secretpad/frontend-src/apps/platform/src/modules/component-tree/component-icon.tsx`：

```typescript
export const ComponentIcons: Record<string, React.ReactElement> = {
  default: <DatabaseFilled ... />,
  stats: <PieChartFilled ... />,
  preprocessing: <LayoutFilled ... />,
  privacy: <SafetyOutlined ... />,  // 新增，或选用其他图标
  // ...
};
```

### 步骤 5：重启并验证

1. 重新构建 SecretFlow 包/镜像（Docker 模式）或确保本地包已更新（非 Docker 模式）。
2. 重启 SecretPad 后端。
3. 启动 SecretPad 前端：
   ```bash
   cd /home/charles/code/sfwork/secretpad/frontend-src
   pnpm --filter secretpad dev
   ```
4. 打开前端，检查左侧组件树是否出现“隐私计算”分类。
5. 拖拽组件，配置参数，连线，运行。

---

## 6. 测试策略

### 6.1 SecretFlow 单元/集成测试

```bash
cd /home/charles/code/sfwork/secretflow

# 注册检查 + sim-mode
python -m pytest tests/component/privacy/test_my_privacy_comp.py -v

# MPC / production 模式
python -m pytest tests/component/privacy/test_my_privacy_comp.py -v --env=prod
```

至少覆盖：
- 组件已注册：`Registry.get_definition_by_id("privacy/my_privacy_comp:1.0.0")` 不为空。
- sim-mode 执行成功，输出类型正确。
- 属性边界/非法值校验。
- 多参与方场景下的输入输出（如需要）。

### 6.2 SecretPad 后端测试

- 重启后调用 `/api/v1alpha1/component/list`，确认 `privacy` 分类和组件出现。
- 调用 `/api/v1alpha1/component/batch`，确认 `ComponentDef` 字段正确。
- 创建图并保存，确认 `project_graph_node` 表中的 `nodeDef`、`codeName` 正确。

### 6.3 前端测试

- 组件树正确分类展示。
- 点击组件能打开配置抽屉。
- 表单项类型正确（int、float、string、choice 等）。
- 输入输出端口正确生成，可与其他组件连线。
- 运行后任务状态正常。

### 6.4 端到端测试

- 在非 Docker 模式下启动完整链路：
  ```bash
  bash /home/charles/code/sfwork/scripts/run-all-no-docker.sh
  ```
- 登录 SecretPad，创建项目 → 上传数据 → 拖拽 privacy 组件 → 运行 → 查看结果。

---

## 7. 常见问题与注意事项

### 7.1 组件注册失败

- 检查文件是否在 `secretflow/component/privacy/` 下，且导入了 `secretflow_spec` / `Component` / `register`。
- 检查 `@register` 的 `domain` 是否为 `"privacy"`，`name` 是否与类名或文件名一致。
- 检查 `secretflow/component/__init__.py` 的 `load_component_modules` 是否没有忽略该路径。

### 7.2 SecretPad 看不到新组件

- 必须重新生成 `secretpad/config/components/secretflow.json` 和 `secretpad/config/i18n/secretflow.json`。
- 必须重启 SecretPad 后端，元数据在启动时加载。
- 检查 `secretflow.json` 中是否包含 `privacy` domain 的组件。

### 7.3 前端组件树不显示

- 检查 `component-tree-service.ts` 是否把 `privacy` 加入 `mergedDomainMap` 和 `domainOrder`。
- 检查 `component-icon.tsx` 是否缺少 `privacy` 图标（缺少可能导致 UI 报错）。
- 检查网络请求 `/component/list` 和 `/component/batch` 是否正常返回。

### 7.4 Kuscia 任务失败

- 查看 Kuscia Pod 日志，确认 `task_input_config` 中的 `comp_id` 正确。
- 确认 SecretFlow 镜像/包包含新的组件代码。
- 确认 `comp_eval` 能找到组件：`Registry.get_definition_by_id` 返回非空。
- 检查输入数据类型是否与 `Field.input(types=[...])` 匹配。

### 7.5 版本号约定

- `comp_id` 格式：`domain/name:major.minor.patch`，例如 `privacy/my_privacy_comp:1.0.0`。
- Registry 按 `domain/name:major` 查找，所以同一组件的 1.0.1、1.0.2 会覆盖同一 key。
- 破坏性变更建议升 major 版本。

### 7.6 多语言

- 组件显示名、属性描述优先从 `secretflow/component/translation.json` 或 `secretpad/config/i18n/secretflow.json` 提供。
- 如果缺少翻译，前端会回退到 `name` / `desc` 字段。

---

## 8. 最小改动示例（MVP）

如果只添加一个最简单的 privacy 组件，最少需要改这些文件：

```text
secretflow/
  └── component/
      └── privacy/
          └── my_privacy_comp.py          # 新增：组件实现
  └── tests/component/privacy/
      └── test_my_privacy_comp.py         # 新增：测试

secretpad/
  └── config/
      ├── components/secretflow.json      # 重新生成
      └── i18n/secretflow.json            # 重新生成

secretpad/frontend-src/apps/platform/src/modules/component-tree/
  ├── component-tree-service.ts           # 修改：加入 privacy 分类
  └── component-icon.tsx                  # 修改：加入 privacy 图标
```

Kuscia 不需要改动。

---

## 9. 参考命令速查

```bash
# SecretFlow 生成组件元数据
secretflow component inspect -a > secretpad/config/components/secretflow.json
secretflow component get_translation > secretpad/config/i18n/secretflow.json

# SecretFlow 测试
python -m pytest tests/component/privacy/test_my_privacy_comp.py -v
python -m pytest tests/component/privacy/test_my_privacy_comp.py -v --env=prod

# SecretPad 后端构建
mvn clean install -Dmaven.test.skip=true

# SecretPad 前端启动
cd secretpad/frontend-src
pnpm --filter secretpad dev

# 完整本地链路
bash /home/charles/code/sfwork/scripts/run-all-no-docker.sh
```
