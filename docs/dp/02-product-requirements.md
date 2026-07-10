# 02 产品需求文档

> 面向本地隐私保护原语（DP / K-匿名 / 脱敏 / 查询混淆）的产品需求，重点覆盖批量模式与本地模式两种操作对象，以及参数配置与治理。

## 1. 产品定位

为 SecretFlow / SecretPad 平台提供一套**可本地执行、可批量执行、可参数化治理**的隐私保护原语能力，让：

- **平台管理员/算法工程师**能够在 DAG 中对整表执行 DP、K-匿名、脱敏、查询混淆。
- **业务开发/数据工程师**能够在业务代码、微服务、医生工作站、大模型网关中像调用函数一样调用隐私保护能力。
- **安全合规人员**能够统一管理参数模板、隐私预算、审计日志。

## 2. 目标用户与场景

| 用户 | 核心场景 | 操作对象 | 典型诉求 |
|---|---|---|---|
| 平台管理员 | 配置平台级隐私策略模板 | 批量 + 本地 | 统一治理、按数据分级自动推荐参数 |
| 算法工程师 | 在 DAG 中预处理数据 | 批量（DataMesh 表） | 拖拽组件、查看隐私证明、预算管理 |
| 数据工程师 | 数据出域前的脱敏/K-匿名 | 批量 | 按规则配置文件批量处理、生成审计报告 |
| 后端开发 | 在业务接口中实时脱敏 | 本地（单值/记录） | SDK/HTTP 调用、低延迟、多语言 |
| 大模型应用开发 | 查询混淆、意图保护 | 本地（查询文本） | 自动注入 Dummy Queries |
| 合规/审计人员 | 查看隐私预算消耗与审计日志 | 批量 + 本地 | 全链路可追溯 |

## 3. 功能需求

### 3.1 批量模式（DataMesh / DAG）

#### FR-B1 组件库扩充
- 在 SecretPad 组件库新增四类组件：
  - **差分隐私（DP）**：`dp_count`、`dp_sum`、`dp_mean`、`dp_sgd`。
  - **K-匿名**：`k_anonymity_transformer`。
  - **脱敏**：`data_sanitization`。
  - **查询混淆**：`query_obfuscation`（通常用于本地网关，但可在批量流水线中预生成混淆模板）。

#### FR-B2 组件配置面板
- 选择参数来源：
  - 使用平台推荐模板（按数据分级自动填充）。
  - 使用项目级 Profile。
  - 手动输入参数。
- 展示参数说明与合理性提示（如 ε 越小噪声越大）。
- 支持上传/下载 YAML/JSON 参数配置。

#### FR-B3 输入输出绑定
- 输入：从 DataMesh / 项目数据表中选择源表。
- 输出：生成新表或覆盖原表，并自动更新 Data Catalog 安全标签（如 `L2_K_ANON_K5`）。

#### FR-B4 隐私证明展示
- 执行完成后，组件属性面板展示：
  - K/L/T 验证结果
  - 信息损失值
  - 抑制记录数
  - DP 实际消耗 ε
  - 审计日志摘要

#### FR-B5 隐私预算管理
- 为每个项目/数据集显示剩余隐私预算。
- 当预算耗尽时，禁止继续执行 DP 组件并提示。

### 3.2 本地模式（SDK / API）

#### FR-L1 Python SDK
- 提供 `secretflow.privacy.local` 模块，包含：
  - `mask_value(field, value, context)`
  - `mask_record(record, context)`
  - `k_anonymize_record(record, qi_cols, hierarchies, k, l, t)`
  - `dp_count(values, epsilon, mechanism)`
  - `dp_sum(values, epsilon, mechanism)`
  - `obfuscate_query(query, num_dummies, domain)`
- 输入支持 dict、pandas Series/DataFrame、JSON、Arrow。
- 输出保持与输入同格式。

#### FR-L2 本地 Agent
- 提供可选的 `Local Privacy Agent`：
  - REST API：`POST /v1/privacy/mask`、`POST /v1/privacy/dp`、`POST /v1/privacy/k_anonymize`、`POST /v1/privacy/obfuscate_query`。
  - gRPC：`PrivacyService`。
  - 支持策略热加载、参数缓存、审计日志落盘。
- Agent 默认监听 `127.0.0.1:8079`，不出本机。

#### FR-L3 多语言客户端
- 提供 Java/Go 客户端示例或 SDK：
  - `PrivacyClient client = PrivacyClient.create("http://127.0.0.1:8079");`
  - `client.mask("id_card", "110105...", "doctor_query");`
- 提供 OpenAPI 文档（Swagger / gRPC reflection）。

#### FR-L4 本地调试与预览
- 提供 CLI 工具：
  - `sf-privacy mask --field id_card --value ... --context doctor_query`
  - `sf-privacy k-anon --input record.json --profile profile.yaml`
- 返回结果与隐私证明 JSON。

### 3.3 参数配置与治理

#### FR-P1 参数模板中心
- 预置模板：
  - 医疗科研共享
  - 医保局统计发布
  - 跨院联邦学习
  - 测试环境
  - 大模型查询保护
- 模板包含 K/L/T/ε/δ、脱敏规则、预算池。

#### FR-P2 项目级 Profile
- 支持在项目中上传 `privacy-profile.yaml`。
- Profile 中可定义：
  - 默认模板
  - 字段级规则
  - 上下文覆盖
  - 禁止策略

#### FR-P3 自动参数推荐
- 根据数据分级标签（L1-L5）和用途自动选择模板。
- 对未配置字段，给出默认规则建议。

#### FR-P4 手动参数覆盖
- 在组件配置面板或 SDK 中显式传入参数。
- 手动参数优先级高于模板，但受平台强制策略约束。

#### FR-P5 参数版本与审计
- Profile/模板支持版本号。
- 每次执行记录实际生效的参数快照。
- 支持参数变更审批流程（可选）。

#### FR-P6 密钥与敏感参数管理
- FPE Key、Salt 等敏感参数通过 KMS/环境变量注入，不在配置文件中明文保存。
- 配置文件中使用占位符 `${KMS:fpe_key_v1}` 或 `${ENV:SALT_RESEARCH}`。

## 4. 非功能性需求

| 类别 | 要求 | 说明 |
|---|---|---|
| 性能 | 本地单值 < 50ms P99；本地小批量 < 200ms；批量按表大小线性 | 满足业务实时查询 |
| 可用性 | Agent 启动时间 < 3s；支持热加载配置 | 便于集成 |
| 安全 | 本地数据不出进程；批量数据不出域；密钥不落地 | 符合隐私计算核心诉求 |
| 兼容性 | Python ≥ 3.10；Agent 支持容器化部署 | 与现有 SecretFlow 一致 |
| 可观测 | 提供 metrics：QPS、延迟、预算消耗、失败率 | 接入 Prometheus |
| 多租户 | 按 namespace/project 隔离参数与预算 | 避免跨项目污染 |

## 5. 交互需求

### 5.1 SecretPad 组件配置面板

```
┌─────────────────────────────────────────────┐
│  K-匿名组件配置                              │
├─────────────────────────────────────────────┤
│  参数来源：                                  │
│  ○ 平台推荐模板    ○ 项目 Profile   ● 手动   │
│                                              │
│  模板：医疗科研共享                           │
│  K 值：  [ 5  ]                              │
│  L 值：  [ 2  ]                              │
│  T 值：  [ 0.2 ]                             │
│  抑制策略：  删除  /  合并到兄弟分区           │
│                                              │
│  QI 列：  [age ▼] [zipcode ▼] [gender ▼]    │
│  SA 列：  [disease ▼] [cost ▼]              │
│                                              │
│  [预览效果]  [保存]  [查看隐私证明]            │
└─────────────────────────────────────────────┘
```

### 5.2 本地 SDK 使用示例页面
- 在文档/控制台提供多语言示例：
  - Python SDK
  - Java Client
  - cURL
  - gRPC proto

### 5.3 隐私预算看板
- 项目维度展示：
  - 总预算
  - 已用预算
  - 剩余预算
  - 每次查询消耗明细

## 6. 权限需求

| 功能 | 管理员 | 算法工程师 | 数据工程师 | 业务开发 | 审计 |
|---|---|---|---|---|---|
| 管理模板 | ✅ | ❌ | ❌ | ❌ | 只读 |
| 配置项目 Profile | ✅ | ✅ | ✅ | ❌ | 只读 |
| 在 DAG 使用组件 | ✅ | ✅ | 只读 | ❌ | 只读 |
| 调用本地 SDK | ✅ | ✅ | ✅ | ✅ | 只读 |
| 查看审计日志 | ✅ | 只读 | 只读 | 只读 | ✅ |
| 查看隐私预算 | ✅ | ✅ | ✅ | ❌ | ✅ |

## 7. 依赖与集成

- **SecretFlow**：作为批量模式执行引擎。
- **Kuscia / DataMesh**：批量数据读写与任务调度。
- **SecretPad**：组件库与配置面板。
- **KMS/TEE**：FPE Key、Salt 管理。
- **Prometheus / Grafana**：可观测。

## 8. 验收标准

- [ ] 四种原语均能在 DAG 中拖拽使用并正确执行。
- [ ] Python SDK 能在本地对单条记录完成 K-匿名、脱敏、DP、QOL。
- [ ] 本地 Agent 的 REST/gRPC 接口可被 Java/Go 客户端调用。
- [ ] 参数模板能按数据分级自动推荐，且手动参数可覆盖。
- [ ] 隐私预算台账准确记录每次 DP 调用消耗。
- [ ] 审计日志包含请求者、时间、原语、参数、证明摘要。
