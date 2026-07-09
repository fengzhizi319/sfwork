# 前后端、Kuscia 及 SecretFlow 算法模块联调与 Bug 定位指南

> 适用对象：在 `sfwork` 工作区中同时改动 SecretPad 前端、SecretPad 后端、Kuscia 或 SecretFlow 算法组件的开发者。
> 目标：建立一条从页面点击到算法组件执行的完整链路认知，并提供可复现、可定位问题的调试方法。

---

## 1. 整体架构与数据流

```text
SecretPad 前端（React/Umi，localhost:8000）
        │  REST /api/v1alpha1/*
        ▼
SecretPad 后端（Spring Boot，localhost:8080/8443）
        │  gRPC（KusciaAPI，默认 localhost:18083）
        ▼
Kuscia Master（Docker，${USER}-kuscia-master）
        │  调度 KusciaJob / KusciaTask / Pod
        ▼
Kuscia Lite（Docker，${USER}-kuscia-lite-alice / lite-bob）
        │  containerd 拉起 SecretFlow Pod
        ▼
SecretFlow（Python）
        │  secretflow.kuscia.entry
        ▼
component / privacy / ml.* 等算法组件
```

关键抽象：

- **前端**：把“训练流/节点/属性”翻译成 `ProjectGraph` 的 REST 调用。
- **后端**：把 `ProjectGraph` 转换成 `ProjectJob`，再生成 `KusciaJob` 的 `TaskInputConfig`。
- **Kuscia**：把 `KusciaJob` 拆成 `KusciaTask`，最终在 Lite 节点上运行 Pod。
- **SecretFlow**：Pod 内通过 `python -m secretflow.kuscia.entry ./kuscia/task-config.conf` 读取任务配置，调用 `comp_eval` 执行组件。

定位问题时要先判断**卡在哪一层**，再向下钻取。

---

## 2. 环境启动与端口速查

### 2.1 推荐启动方式

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

### 2.2 本地默认端口

| 服务 | 端口 | 说明 |
|------|------|------|
| SecretPad 前端 dev server | 8000 | Umi，/api 代理到后端 8080 |
| SecretPad 后端 HTTP | 8080 | Spring Boot `server.http-port` |
| SecretPad 后端 HTTPS | 8443 | Spring Boot `server.port` |
| Kuscia API gRPC | 18083 | 后端通过它创建/查询 Job |
| Kuscia Gateway | 18080 | 外部访问 |
| Kuscia Envoy 内部 | 13081 | 数据面通信 |

### 2.3 关键环境变量（后端连接 Kuscia）

`scripts/dev-start.sh` 启动后端时会自动设置：

```bash
export KUSCIA_API_ADDRESS=127.0.0.1
export KUSCIA_API_PORT=18083
export KUSCIA_GW_ADDRESS=127.0.0.1:13081
export KUSCIA_PROTOCOL=notls
```

如果你手动启动后端 jar，也需要带上这些变量。

---

## 3. 问题分层定位法

遇到“流水线卡住/报错/没结果”时，按以下顺序排查。

### 3.1 第一层：前端是否把请求正确发出去

打开浏览器开发者工具：

1. **Network 面板**：找到对应的 `/api/v1alpha1/...` 请求，确认：
   - HTTP status 是否为 200；
   - 请求体里的 `projectId`、`graphId`、`nodes` 是否正确；
   - 响应 `status.code` 是否为 0。
2. **Console 面板**：查看是否有 React/TypeScript 异常、 Antd 表单校验失败等。
3. **Sources 面板**：在关键位置打断点，例如：
   - `secretpad/frontend-src/apps/platform/src/modules/pipeline/pipeline-creation-view.tsx`（创建训练流）
   - `secretpad/frontend-src/apps/platform/src/modules/main-dag/graph-service.ts`（保存节点配置、启动图）
   - `secretpad/frontend-src/apps/platform/src/modules/component-config/...`（组件属性面板）

常用前端状态观察：

```ts
// Valtio 状态，可在控制台直接打印
import { getModel } from '@/util/valtio-helper';
import { DefaultPipelineService } from '@/modules/pipeline/pipeline-service';
console.log(getModel(DefaultPipelineService));
```

#### 典型前端问题

- **模板没出现在 TEE/枢纽模式**：检查 `computeMode` 是否包含 `'TEE'`。
- **快速配置保存后节点属性没更新**：检查 `saveTemplateQuickConfig` 是否正确调用 `fullUpdateGraph`。
- **运行按钮点击无反应**：通常是因为后端返回非 0，前端没有额外提示；看 Network 面板最准确。

---

### 3.2 第二层：后端是否收到并正确处理请求

#### 3.2.1 看日志

```bash
# 实时跟踪后端日志
tail -f /home/charles/code/sfwork/logs/backend.log

# 只看错误
grep -iE "error|exception|fail" /home/charles/code/sfwork/logs/backend.log | tail -50
```

后端日志里通常会打印：`Executing: SecretPadResponse org.secretflow.secretpad.web.controller.XXXController.xxx(...)`，后面紧跟请求参数。

#### 3.2.2 常用 REST 端点

| 功能 | 端点 | 关键类 |
|------|------|--------|
| 创建图 | `/api/v1alpha1/graph/create` | `GraphController.createGraph` |
| 启动图 | `/api/v1alpha1/graph/start` | `GraphController.startGraph` |
| 查询节点状态 | `/api/v1alpha1/graph/node/status` | `GraphController.listGraphNodeStatus` |
| 查询项目任务 | `/api/v1alpha1/project/job` | `ProjectController.getJob` |
| 调度一次 | `/api/v1alpha1/scheduled/graph/once/success` | `ScheduledController.onceSuccess` |

#### 3.2.3 关键后端类

- **图转作业**：`secretpad-service/src/main/java/org/secretflow/secretpad/service/graph/converter/KusciaJobConverter.java`
  - `renderTaskInputConfig()` 生成 `TaskInputConfig`，其中 `sf_node_eval_param` 就是传给 SecretFlow 的节点参数。
- **节点属性构建**：`secretpad-service/src/main/java/org/secretflow/secretpad/service/graph/chain/JobRenderHandler.java`
  - 把前端保存的 `nodeDef` 转成 `Pipeline.NodeDef`。
- **Kuscia 调用封装**：`secretpad-manager` 模块下的 `KusciaApiService` / `KusciaGrpcClientAdapter`。
- **任务状态同步**：`secretpad-service/src/main/java/org/secretflow/secretpad/manager/integration/job/JobManager.java`

#### 3.2.4 如何确定后端已经把任务交给 Kuscia

搜索后端日志里的 `CreateJobRequest` 或 `jobId`：

```bash
grep "CreateJobRequest\|jobId=\|jobId:" /home/charles/code/sfwork/logs/backend.log | tail -30
```

如果看到 `CreateJobRequest` 且响应成功，说明后端已完成工作，问题在 Kuscia 或更下层。

---

### 3.3 第三层：Kuscia 是否把任务调度成 Pod

#### 3.3.1 进入 Kuscia Master 容器

```bash
docker exec -it ${USER}-kuscia-master bash
```

常用命令：

```bash
# 查看 KusciaJob
kubectl get kj -A

# 查看 KusciaTask（跨域任务）
kubectl get kt -A

# 查看 Pod
kubectl get pods -A

# 查看 AppImage
kubectl get appimage

# 查看事件
kubectl get events -A --sort-by='.lastTimestamp' | tail -30
```

#### 3.3.2 判断任务状态

```text
Pending    → 可能在等镜像、等资源、等 DomainRoute
Running    → Pod 已启动，正在执行
Failed     → Pod 退出码非 0，需看容器日志
Succeed    → 任务完成
```

#### 3.3.3 Pod 常见问题

1. **ErrImagePull / ImagePullBackOff**

   说明 Kuscia Lite 节点找不到对应镜像。常见原因：
   - 自定义镜像只存在宿主机 Docker，没有 `kuscia image load`；
   - AppImage 指向的镜像 tag 错误；
   - 镜像前缀被改成了 `docker.io/...` 但本地没有该 tag。

   检查并修复：

   ```bash
   # 查看 lite 节点已有的镜像
   docker exec ${USER}-kuscia-lite-alice kuscia image list
   docker exec ${USER}-kuscia-lite-bob kuscia image list

   # 手动导入本地镜像（通过 stdin，避免权限问题）
   docker save secretflow/sf-privacy-dev:1.15.0.dev-privacy | \
     docker exec -i ${USER}-kuscia-lite-alice kuscia image load
   docker save secretflow/sf-privacy-dev:1.15.0.dev-privacy | \
     docker exec -i ${USER}-kuscia-lite-bob kuscia image load
   ```

2. **Pending 长时间不调度**

   ```bash
   kubectl describe pod <pod-name> -n <namespace>
   ```

   重点看 `Events` 和 `Conditions`，常见原因：
   - `TaskResourceGroup` 未就绪；
   - `DomainRoute` 未建立；
   - 端口被占。

3. **Pod 状态为 Error / CrashLoopBackOff**

   进入对应 Lite 节点查看容器日志：

   ```bash
   # 列出该 Lite 节点上所有容器（含已退出）
   docker exec ${USER}-kuscia-lite-alice crictl ps -a

   # 看日志
   docker exec ${USER}-kuscia-lite-alice crictl logs <container-id>
   ```

   如果 `kubectl logs` 报 `proxy error ... 502 Bad Gateway`，直接用 `crictl logs` 更可靠。

#### 3.3.4 Kuscia 日志定位

```bash
# Master 容器整体日志
docker logs --tail 200 ${USER}-kuscia-master

# Lite 节点日志
docker logs --tail 200 ${USER}-kuscia-lite-alice
```

---

### 3.4 第四层：SecretFlow 组件是否正确执行

#### 3.4.1 拿到任务配置文件

任务启动后，SecretFlow Pod 会读取 `/home/kuscia/task-config.conf`（ConfigMap 挂载）。你可以在 Lite 节点上找到这个文件：

```bash
# 在 Lite 节点容器内查找当前任务配置
docker exec ${USER}-kuscia-lite-alice find /home/charles/kuscia -name "task-config.conf" 2>/dev/null | tail -5
```

更直接的方式是进 **Pod 容器** 里看：

```bash
# 先拿到容器 ID
docker exec ${USER}-kuscia-lite-alice crictl ps -a | grep <jobId>

# 进入容器
docker exec -it ${USER}-kuscia-lite-alice crictl exec -it <container-id> bash

# 查看任务配置
cat ./kuscia/task-config.conf
```

重点关注：

- `sf_node_eval_param`：组件 ID、属性、输入输出；
- `sf_input_ids` / `sf_output_uris`：数据ID；
- `sf_cluster_desc`：参与方信息；
- `sf_datasource_config`：数据源配置。

#### 3.4.2 看 SecretFlow 容器日志

```bash
docker exec ${USER}-kuscia-lite-alice crictl logs <container-id>
```

常见错误：

- `component<xxx> cannot be found`：组件未注册或镜像里没有该组件；
- `ParseError: Message type ... has no field named ...`：前后端 protobuf 协议不匹配；
- `Privacy budget exhausted`：差分隐私预算参数设置错误；
- 各种 Python traceback：组件内部异常。

#### 3.4.3 本地快速验证 SecretFlow 组件

如果你修改了 `secretflow/secretflow/component/...` 下的组件，推荐先在本地单进程跑通，再放到 Kuscia 里跑。

```bash
cd /home/charles/code/sfwork/secretflow

# 激活 conda 环境
conda activate sf310

# 运行已有组件测试
python -m pytest tests/component/privacy/test_privacy_components.py::test_differential_privacy_component_sim -v
```

一个最小可复现的本地测试骨架：

```python
import json
import tempfile
import pandas as pd

from secretflow.component.core import (
    DistDataType,
    build_node_eval_param,
    comp_eval,
    make_storage,
)
from secretflow_spec.v1.data_pb2 import (
    DistData,
    IndividualTable,
    StorageConfig,
    TableSchema,
)

wd = tempfile.mkdtemp()
storage_config = StorageConfig(
    type="local_fs", local_fs=StorageConfig.LocalFSConfig(wd=wd)
)
storage = make_storage(storage_config)

input_path = "dp/input.csv"
report_path = "dp/report"

with storage.get_writer(input_path) as w:
    pd.DataFrame({"age": [20, 21, 35, 36, 50, 51]}).to_csv(w, index=False)

param = build_node_eval_param(
    domain="privacy",
    name="differential_privacy",
    version="1.0.0",
    attrs={
        "query_type": "mean",
        "query_col": "age",
        "epsilon_total": 1.0,
        "epsilon_per_query": 0.1,
        "column_sensitivities_json": json.dumps({"age": 1.0}),
        "random_state": 42,
    },
    inputs=[
        DistData(
            name="input_data",
            type=str(DistDataType.INDIVIDUAL_TABLE),
            data_refs=[DistData.DataRef(uri=input_path, party="alice", format="csv")],
        )
    ],
    output_uris=[report_path],
)

meta = IndividualTable(
    schema=TableSchema(features=["age"], feature_types=["float32"])
)
param.inputs[0].meta.Pack(meta)

res = comp_eval(param=param, storage_config=storage_config, cluster_config=None)
print(res)
```

本地通过后再打镜像、导入 Kuscia。

#### 3.4.4 在组件代码里加调试日志

如果问题只出现在 Kuscia 环境，可以在 `secretflow/secretflow/component/<your_component>.py` 里增加日志：

```python
import logging
logger = logging.getLogger(__name__)

class MyComponent(Component):
    def evaluate(self, ctx):
        logger.info(f"inputs={self.input_ds}, attrs=...")
        ...
```

重新构建镜像并 `--reset-kuscia` 后，容器日志里会打印这些日志。

---

## 4. 典型 Bug 定位流程示例

### 案例：差分隐私流水线 reset 后卡住

**现象**：页面点击“运行”后，节点状态一直不变，后端日志反复打印 `getProjectJob projectResultDOS =[]`。

**定位步骤**：

1. 前端 Network 显示 `/graph/start` 返回 200，有 `jobId`；排除前端问题。
2. 后端日志看到 `CreateJobRequest` 成功；排除后端问题。
3. Kuscia Master 里查 Pod：

   ```bash
   kubectl get pods -A
   # alice  <jobId>-node-2-0  0/1  ErrImagePull
   ```

4. `kubectl describe pod` 看到从 `docker.io/secretflow/sf-privacy-dev:1.15.0.dev-privacy` 拉取失败。
5. 结论：本地自定义镜像没有进入 Kuscia Lite 镜像仓库。修复：用 `docker save ... | kuscia image load` 导入。
6. 再次运行后 Pod 变成 `Error`，`crictl logs` 看到：

   ```text
   ParseError: Message type "secretflow_spec.v1.NodeEvalParam" has no field named "domain"
   ```

7. 结论：SecretPad 后端仍按旧协议生成 `NodeDef`（domain/name/version），而 SecretFlow 1.15 镜像已使用新协议 `NodeEvalParam`（comp_id）。需要前后端协议版本对齐。

---

### 案例：SecretPad 后端编译失败（NodeEvalParam 协议升级）

**现象**：将 `TaskInputConfig.sf_node_eval_param` 从旧 `secretflow.pipeline.NodeDef` 升级为 `secretflow_spec.v1.NodeEvalParam` 后，`secretpad` 后端编译报错：

```text
NodeDefUtils.java:98: cannot find symbol addAllI64s
KusciaJobConverter.java:234: cannot find symbol variable NodeDefUtils
ModelExportServiceImpl.java:377: cannot find symbol variable NodeDefUtils
```

**定位步骤**：

1. 确认 `proto/secretflow/protos/kuscia/task_config.proto` 中 `sf_node_eval_param` 的类型已改为 `secretflow_spec.v1.NodeEvalParam`，Java 代码已重新生成。
2. 查看生成的 `com.secretflow.spec.v1.Attribute` 类，发现 repeated `int64` 列表的 builder 方法名为 `addAllI64S`（大写 S），而不是直觉上的 `addAllI64s`。
3. 检查所有构造 `TaskInputConfig` 的地方：
   - `KusciaJobConverter`：已调用 `NodeDefUtils.toNodeEvalParam(...)`，但缺少 `import`。
   - `ModelExportServiceImpl`：同样缺少 `NodeDefUtils` 的 `import`。
   - `KusciaTeeDataManagerConverter`：已正确调用 `NodeDefUtils.toNodeEvalParam(...)`。
   - `KusciaTrustedFlowJobConverter`：之前只设置了 `tee_task_config`，没有设置 `sf_node_eval_param`。

**修复方案**：

- 修正 `NodeDefUtils.convertStructToAttribute` 中的方法调用：`addAllI64s` → `addAllI64S`。
- 在 `KusciaJobConverter` 和 `ModelExportServiceImpl` 中补充 `import org.secretflow.secretpad.service.graph.NodeDefUtils;`。
- 在 `KusciaTrustedFlowJobConverter` 的 `TaskInputConfig` 构建链中增加：

  ```java
  .setSfNodeEvalParam(NodeDefUtils.toNodeEvalParam(newPipelineNodeDef))
  ```

**验证**：

```bash
cd /home/charles/code/sfwork/secretpad
mvn clean install -Dmaven.test.skip=true -Dfile.encoding=UTF-8
mvn test -pl secretpad-service -Dtest=KusciaJobConverterTest,ModelExportServiceImplTest
```

结果：**BUILD SUCCESS**，相关单测 `Tests run: 9, Failures: 0`。

**经验总结**：

- 协议升级（尤其是 protobuf 字段/类型变更）必须全链路检查：
  - `.proto` 源文件；
  - 重新生成 Java/Python 桩代码；
  - 所有构造/解析该消息的后端 converter；
  - SecretFlow 侧对同一消息的解析逻辑。
- Java protobuf 生成的方法名对大小写敏感，repeated 字段如 `i64s` 会生成 `addAllI64S`、`getI64SList` 等，遇到 `cannot find symbol` 时应直接去生成的类里确认。
- 新旧协议共存时，可用一个独立的 `NodeDefUtils` 做单向转换（旧 `NodeDef` → 新 `NodeEvalParam`），避免在每个 converter 里写重复转换逻辑。

### 案例：差分隐私流水线运行失败（protobuf Any type_url 不匹配）

**现象**：管道模式下“样本表”节点执行成功，“差分隐私”节点执行失败。SecretFlow 容器日志报：

```text
ParseError: Can not find message descriptor by type_url:
type.googleapis.com/secretflow.spec.v1.IndividualTable
```

Kuscia 任务状态为 `Failed`，错误摘要：

```text
The remaining no-failed party task counts 0 are less than the task success threshold 1.
```

**定位步骤**：

1. 后端 `TaskInputConfig.sf_node_eval_param.inputs` 中，`meta` 字段是 `google.protobuf.Any` 类型，JSON 序列化后带有 `@type`：

   ```json
   "meta": {
     "@type": "type.googleapis.com/secretflow.spec.v1.IndividualTable",
     "line_count": "-1"
   }
   ```

2. 进入 SecretFlow 容器确认 Python 包里的实际 full name：

   ```bash
   docker run --rm --entrypoint python secretflow/sf-privacy-dev:1.15.0.dev-privacy \
     -c "from secretflow_spec.v1 import data_pb2; print(data_pb2.IndividualTable.DESCRIPTOR.full_name)"
   ```

   输出：

   ```text
   secretflow_spec.v1.IndividualTable
   ```

3. 结论：SecretPad 后端 `.proto` 里的 `package secretflow.spec.v1;` 生成的 Any `type_url` 是 `secretflow.spec.v1`（点号），而 SecretFlow 1.15 的 Python 包期望的是 `secretflow_spec.v1`（下划线），两者不一致。

**修复方案**：

修改 `secretpad/proto/secretflow/spec/v1/` 下的所有 `.proto` 文件：

```protobuf
// 修改前
package secretflow.spec.v1;

// 修改后
package secretflow_spec.v1;
```

同时修改引用这些类型的其他 `.proto` 文件：

- `secretpad/proto/secretflow/protos/kuscia/task_config.proto`：
  `secretflow.spec.v1.NodeEvalParam` → `secretflow_spec.v1.NodeEvalParam`
- `secretpad/proto/secretflow/protos/pipeline/pipeline.proto`：
  `secretflow.spec.v1.DistData` → `secretflow_spec.v1.DistData`

> 注意：`.proto` 中的 `option java_package = "com.secretflow.spec.v1";` 保持不变，这样 Java 类的包名和现有 import 都不会变。

然后重新生成 Java 桩代码并重启后端：

```bash
cd /home/charles/code/sfwork/secretpad
mvn clean install -Dmaven.test.skip=true -Dfile.encoding=UTF-8

# 只重启后端（Kuscia 不需要重启）
bash /home/charles/code/sfwork/scripts/dev-stop.sh
cd /home/charles/code/sfwork/secretpad
export KUSCIA_API_ADDRESS=127.0.0.1
export KUSCIA_API_PORT=18083
export KUSCIA_GW_ADDRESS=127.0.0.1:13081
export KUSCIA_PROTOCOL=notls
nohup java \
  -Dspring.profiles.active=dev \
  -Dsun.net.http.allowRestrictedHeaders=true \
  -Dserver.port=8443 \
  -jar target/secretpad.jar \
  > /home/charles/code/sfwork/logs/backend.log 2>&1 &
```

**验证**：重新运行差分隐私流水线，观察 `sf_node_eval_param.inputs[0].meta.@type` 已变为：

```json
"@type": "type.googleapis.com/secretflow_spec.v1.IndividualTable"
```

SecretFlow 容器不再报 `Can not find message descriptor`，任务应能正常执行。

**经验总结**：

- 当 SecretPad 后端与 SecretFlow 镜像分别使用不同版本的 `secretflow-spec` 时，不仅要检查字段名，还要核对 **protobuf package 名** 和 Any 的 `type_url`。
- 一个快速核对命令：

  ```bash
  # 后端生成的 type_url
  grep -R "package secretflow\\.spec\\.v1" secretpad/proto

  # SecretFlow 镜像里的真实 full_name
  docker run --rm --entrypoint python secretflow/sf-privacy-dev:1.15.0.dev-privacy \
    -c "from secretflow_spec.v1 import data_pb2; print(data_pb2.IndividualTable.DESCRIPTOR.full_name)"
  ```

- 如果两者不一致，优先让 `.proto` 的 `package` 与 SecretFlow Python 包保持一致，并通过 `java_package` 保留 Java 侧已有的包路径。

### 案例：自定义 SecretFlow 镜像构建失败（pip 哈希校验失败）

**现象**：执行镜像构建时，安装 `secretflow` wheel 的过程中报错：

```text
ERROR: THESE PACKAGES DO NOT MATCH THE HASHES FROM THE REQUIREMENTS FILE.
secretflow_serving_lib==0.10.0.dev20250414 from https://mirrors.aliyun.com/pypi/...
    Expected sha256 88305d35343b0ba9c792a55ae2af630e62b69982d50a7656f252f4128dc5baa0
         Got        4601f835307700ec2de38ad630a1415420a9c5de1c297579228d6ee91f385fe8
```

构建命令：

```bash
cd /home/charles/code/sfwork/secretflow/docker/privacy-dev
docker build . -f Dockerfile -t secretflow/sf-privacy-dev:1.15.0.dev-privacy
```

**定位步骤**：

1. 直接下载镜像中失败的同一个 URL，计算 sha256，发现与 `Expected` 一致：

   ```bash
   curl -sL -o /tmp/secretflow_serving_lib_aliyun.whl \
     'https://mirrors.aliyun.com/pypi/packages/4b/a6/.../secretflow_serving_lib-0.10.0.dev20250414-cp310-cp310-manylinux2014_x86_64.whl'
   sha256sum /tmp/secretflow_serving_lib_aliyun.whl
   # 88305d35343b0ba9c792a55ae2af630e62b69982d50a7656f252f4128dc5baa0
   ```

2. 说明阿里云镜像上的 wheel 本身是正确的，报错时实际下载大小只有 16.2/33.8 MB，`Got` 的 sha256 对应的是**不完整/损坏的下载文件**。
3. 结论：这不是 requirements 文件中哈希写错，而是单次网络下载中断导致 pip 校验失败。

**修复方案**：

- **方案 A（推荐，治本）**：网络稳定时直接重试构建，或改用官方 PyPI 源：

  ```bash
  cd /home/charles/code/sfwork/secretflow/docker/privacy-dev
  docker build . -f Dockerfile \
    --build-arg PIP_INDEX_URL=https://pypi.org/simple/ \
    -t secretflow/sf-privacy-dev:1.15.0.dev-privacy
  ```

  `Dockerfile` 已改为使用 `ARG PIP_INDEX_URL=...`（默认阿里云），因此可以直接用 `--build-arg` 切换到官方 PyPI。

- **方案 B（救急）**：如果已有旧版本镜像且源码改动仅限于少量 Python 文件，可直接基于旧镜像打补丁，无需重新安装全部依赖：

  ```bash
  # 1. 备份旧镜像
  docker tag secretflow/sf-privacy-dev:1.15.0.dev-privacy \
             secretflow/sf-privacy-dev:1.15.0.dev-privacy-backup

  # 2. 启动临时容器并替换修改过的 Python 文件
  docker run -d --name sf-patch --entrypoint sleep \
    secretflow/sf-privacy-dev:1.15.0.dev-privacy 60
  docker cp /home/charles/code/sfwork/secretflow/secretflow/kuscia/meta_conversion.py \
    sf-patch:/root/miniconda3/lib/python3.10/site-packages/secretflow/kuscia/meta_conversion.py
  docker commit sf-patch secretflow/sf-privacy-dev:1.15.0.dev-privacy
  docker rm -f sf-patch

  # 3. 重新导入到 Kuscia Lite 节点
  docker save secretflow/sf-privacy-dev:1.15.0.dev-privacy | \
    docker exec -i ${USER}-kuscia-lite-alice kuscia image load
  docker save secretflow/sf-privacy-dev:1.15.0.dev-privacy | \
    docker exec -i ${USER}-kuscia-lite-bob kuscia image load
  ```

**验证**：

```bash
# 确认镜像里已是最新代码
docker run --rm --entrypoint cat secretflow/sf-privacy-dev:1.15.0.dev-privacy \
  /root/miniconda3/lib/python3.10/site-packages/secretflow/kuscia/meta_conversion.py | \
  grep -A2 "_message_to_json_compat"
```

应看到兼容 helper 或 `including_default_value_fields=True`。

**经验总结**：

- pip 哈希校验失败时，先确认镜像源上的文件哈希是否真与 lock 文件不同；多数情况下是下载中断。
- 隐私计算镜像依赖很大（30 MB+ wheel），构建时建议保持网络稳定，必要时用 `nohup` / `screen` 在后台执行。
- 日常调试不必每次都全量构建，局部 Python 文件改动可用 `docker cp + docker commit` 快速验证，确认后再重新打正式镜像。

---

### 案例：差分隐私流水线运行失败（MessageToJson 参数不兼容）

**现象**：`read_data/datatable` 节点成功，`privacy/differential_privacy` 节点失败。SecretFlow 容器日志或本地复现报：

```text
TypeError: MessageToJson() got an unexpected keyword argument 'always_print_fields_with_no_presence'
```

**定位步骤**：

1. SecretFlow 镜像里的 protobuf 版本是 4.25.9，该版本 `google.protobuf.json_format.MessageToJson` 的签名只有 `including_default_value_fields`，没有 `always_print_fields_with_no_presence`（后者是 protobuf >= 5.0 的 API）。
2. `secretflow/kuscia/meta_conversion.py:convert_dist_data_to_domain_data` 原代码直接调用：

   ```python
   MessageToJson(x, always_print_fields_with_no_presence=True, indent=0)
   ```

3. 该函数在组件执行输出 `DistData` → Kuscia `DomainData` 时会被调用，因此任何会写入 DomainData 的组件（包括差分隐私、L-多样性等）都会触发报错。

**修复方案**：

在 `secretflow/kuscia/meta_conversion.py` 中加入兼容性 helper，运行时自动判断参数可用性：

```python
import inspect
from google.protobuf.json_format import MessageToJson


def _message_to_json_compat(message, **kwargs):
    """Call MessageToJson with backwards-compatible args."""
    if 'always_print_fields_with_no_presence' not in inspect.signature(
        MessageToJson
    ).parameters:
        if kwargs.pop('always_print_fields_with_no_presence', False):
            kwargs['including_default_value_fields'] = True
    return MessageToJson(message, **kwargs)
```

然后替换原调用：

```python
# 修改前
domain_data.attributes["dist_data"] = MessageToJson(
    x, always_print_fields_with_no_presence=True, indent=0
)

# 修改后
domain_data.attributes["dist_data"] = _message_to_json_compat(
    x, always_print_fields_with_no_presence=True, indent=0
)
```

**验证**：

1. 本地用旧镜像复现错误：

   ```bash
   docker run --rm --entrypoint python secretflow/sf-privacy-dev:1.15.0.dev-privacy-backup -c "
   from secretflow_spec.v1.data_pb2 import DistData, IndividualTable, TableSchema
   from secretflow.kuscia.meta_conversion import convert_dist_data_to_domain_data
   dd = DistData(name='t', type='sf.table.individual',
                 data_refs=[DistData.DataRef(uri='a.csv', party='alice', format='csv')])
   meta = IndividualTable(schema=TableSchema(features=['age'], feature_types=['float']))
   dd.meta.Pack(meta)
   convert_dist_data_to_domain_data('id','ds', dd, 'out','alice','')
   "
   # TypeError: MessageToJson() got an unexpected keyword argument ...
   ```

2. 用新镜像验证成功：

   ```bash
   docker run --rm --entrypoint python secretflow/sf-privacy-dev:1.15.0.dev-privacy -c "
   from secretflow_spec.v1.data_pb2 import DistData, IndividualTable, TableSchema
   from secretflow.kuscia.meta_conversion import convert_dist_data_to_domain_data
   dd = DistData(name='t', type='sf.table.individual',
                 data_refs=[DistData.DataRef(uri='a.csv', party='alice', format='csv')])
   meta = IndividualTable(schema=TableSchema(features=['age'], feature_types=['float']))
   dd.meta.Pack(meta)
   res = convert_dist_data_to_domain_data('id','ds', dd, 'out','alice','')
   print('OK', res.attributes.get('dist_data','')[:80])
   "
   # OK {"name": "t", "type": "sf.table.individual", ...
   ```

3. 端到端重跑差分隐私流水线：

   ```bash
   TOKEN=$(curl -s -X POST http://127.0.0.1:8080/api/login \
     -H 'Content-Type: application/json' \
     -d '{"name":"admin","passwordHash":"'$(echo -n 12345678 | sha256sum | awk '{print $1}')'"}' | \
     python3 -c "import sys,json; print(json.load(sys.stdin)['data']['token'])")

   curl -s -X POST http://127.0.0.1:8080/api/v1alpha1/graph/start \
     -H 'Content-Type: application/json' -H "User-Token: ${TOKEN}" \
     -d '{"projectId":"ddebgquk","graphId":"atkncwfs","nodes":["atkncwfs-node-1","atkncwfs-node-2"]}'
   ```

   查询任务列表，新 job 状态为 `SUCCEED`，`finishedTaskCount/taskCount = 2/2`，`reportCount = 1`。

**经验总结**：

- protobuf 的 `MessageToJson` 参数在不同版本间有 break change：`including_default_value_fields`（旧） vs `always_print_fields_with_no_presence`（新）。
- 隐私计算镜像通常预装固定 protobuf 版本，本地开发环境（如 conda）的 protobuf 版本可能不同，不能只看本地能跑。
- 对这类 API 不兼容点，加一个运行时判断的 wrapper 比硬改参数更安全，能同时兼容 protobuf 4.x 和 5.x/6.x。
- 镜像变更后务必重新导入 Kuscia Lite，否则 Kuscia 仍会调度旧镜像，导致“已经改了代码为什么还报错”的错觉。

## 5. 常用命令速查表

### 服务状态

```bash
# 后端进程
cat /home/charles/code/sfwork/logs/backend.pid
ps -p $(cat /home/charles/code/sfwork/logs/backend.pid) -o pid,cmd

# 前端进程
cat /home/charles/code/sfwork/logs/frontend.pid

# Kuscia 容器
docker ps --filter name=kuscia
```

### 后端登录取 Token（用于 curl 调试）

```bash
# 12345678 的 sha256
PASS_HASH=$(echo -n '12345678' | sha256sum | awk '{print $1}')
TOKEN=$(curl -s -X POST http://127.0.0.1:8080/api/login \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"admin\",\"passwordHash\":\"${PASS_HASH}\"}" | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['data']['token'])")
echo $TOKEN
```

### Kuscia 任务诊断

```bash
# 查看 KusciaJob / KusciaTask / Pod
docker exec ${USER}-kuscia-master kubectl get kj,kt,pods -A

# 查看 Pod 事件
docker exec ${USER}-kuscia-master kubectl describe pod <pod> -n <ns>

# Lite 节点容器列表
docker exec ${USER}-kuscia-lite-alice crictl ps -a

# 看容器日志
docker exec ${USER}-kuscia-lite-alice crictl logs <container-id>

# 导入本地镜像到 Lite 节点
docker save <image:tag> | docker exec -i ${USER}-kuscia-lite-alice kuscia image load

# 查看 AppImage
docker exec ${USER}-kuscia-master kubectl get appimage secretflow-image -o yaml
```

### SecretFlow 组件相关

```bash
# 查看镜像里有哪些组件
docker run --rm --entrypoint python secretflow/sf-privacy-dev:1.15.0.dev-privacy \
  -c "from secretflow.component.core import Registry; print(Registry.get_definition_keys())"

# 查看组件列表 JSON
docker run --rm secretflow/sf-privacy-dev:1.15.0.dev-privacy cat /app/docker/comp_list.json | head -100

# 本地运行组件测试
cd /home/charles/code/sfwork/secretflow
python -m pytest tests/component/privacy/test_privacy_components.py -v
```

---

## 6. 调试建议与最佳实践

1. **改完 SecretFlow 组件先本地跑 pytest**，不要直接打镜像。
2. **SecretFlow 镜像变更后必须 `--reset-kuscia`**，否则 Kuscia 的 AppImage 仍指向旧镜像。
3. **reset 后检查 Lite 节点镜像是否存在**，`kuscia image list` 里找不到对应 tag 就一定要导入。
4. **后端日志关注 `CreateJobRequest` 和 `jobId`**，它是后端与 Kuscia 的分界线。
5. **Kuscia 任务卡住先看 Pod 状态**：
   - `Pending` → `describe pod` / `describe kt`；
   - `ErrImagePull` → 镜像导入；
   - `Error` → `crictl logs`。
6. **协议/字段不匹配时**，优先对比 `secretpad/proto/secretflow/protos/...` 与 `secretflow/secretflow/protos/...` 以及 `secretflow-spec` 的版本。
7. **不要同时启动多个 Kuscia Master**，端口冲突会导致调度异常。
8. **保留现场**：定位问题时先 `docker logs` / `crictl logs` 保存一份，避免重启后丢失。

---

## 7. 扩展：新增一个算法组件的端到端 checklist

1. 在 `secretflow/secretflow/component/<domain>/<name>.py` 实现组件，加 `@register`。
2. 本地 `comp_eval(..., cluster_config=None)` 验证通过。
3. 更新 `secretflow/docker/comp_list.json`（如需要）。
4. 构建自定义镜像：
   - `bash scripts/dev-start.sh --reset-kuscia` 会自动构建。
   - 若阿里云 PyPI 下载超时/哈希校验失败，可手动切到官方 PyPI：
     ```bash
     cd secretflow/docker/privacy-dev
     docker build . -f Dockerfile \
       --build-arg PIP_INDEX_URL=https://pypi.org/simple/ \
       -t secretflow/sf-privacy-dev:1.15.0.dev-privacy
     ```
5. 确认 Kuscia Lite 节点已导入新镜像。
6. 在 SecretPad 前端新增/调整模板：
   - 组件列表：`secretpad/config/components/secretflow.json` / `secretpad-web/config/components/secretflow.json`。
   - 快速配置面板：`apps/platform/src/modules/component-config/template-quick-config/quick-config-privacy.tsx`。
   - 流水线模板：`apps/platform/src/modules/pipeline/templates/pipeline-template-privacy.ts` 等。
   - 模板中 `nodeDef` 的 `domain` / `name` / `version` / `attrs` 要与 SecretFlow 组件定义一致。
     例如 `privacy/l_diversity:1.0.0` 对应 `domain=privacy`、`name=l_diversity`、`version=1.0.0`。
7. 创建训练流 → 运行 → 按本章分层法排查。
