# 隐私算法库迁移与组件升级报告

## 1. 背景与目标

`privacy-local-agent` 中的 `privacy_local_agent/privacy` 子目录已经包含了最新版本的本地隐私算法实现（差分隐私、K-匿名、查询混淆、数据脱敏、分类分级等）。
`secretflow/secretflow/privacy/` 中对应的旧版实现参数与行为已经落后，且 `secretflow/secretflow/component/privacy/` 中注册的组件版本也停留在旧版本。

本次任务目标：

1. 将 `privacy-local-agent/privacy_local_agent/privacy` 中的最新算法迁移到 `secretflow/secretflow/privacy/`。
2. 更新 `secretflow/secretflow/component/privacy/` 中的组件注册，暴露新版参数与能力，并新增本地差分隐私组件。
3. 在前端增加对应的隐私组件模板与场景卡，使用户能从首页一键创建隐私处理流水线。
4. 预生成统一的测试参数与数据，分别通过“直接调用 SecretFlow”与“前端 → 后端 → Kuscia → SecretFlow 镜像”两条路径执行，并验证结果完全一致。
5. 补齐相关文档，并将所有改动提交到 Git。

## 2. 算法库迁移范围

| 源模块 | 目标子包 | 主要更新 |
|---|---|---|
| `dp.py` + `budget.py` | `secretflow/privacy/differential_privacy/` | 引入 `PrivacyBudgetExhausted`、解析高斯校准、显式 clip 支持、`min_count` 均值保护、分类直方图联合敏感度 1 的单次预算消费 |
| `local_dp.py`（新） | `secretflow/privacy/local_dp.py` | 新增 Warner / k-ary 随机响应、频率/直方图估计 |
| `kano.py` / `kano_table.py` | `secretflow/privacy/k_anonymity/` | 新增内置层次泛化（age/zipcode/gender）与 `max_depth` |
| `qol.py` | `secretflow/privacy/query_obfuscation/` | 改为 domain-pool + 槽位填充 + 长度优选策略，保留同义词替换 legacy 路径 |
| `masking.py` | `secretflow/privacy/sanitization/` | 新增 `mask_mobile`、`mask_id_card`、`mask_name`、`mask_bank_card`、`auto_mask` 等脱敏方法 |
| `classification*.py` | `secretflow/privacy/data_classification/` | 升级分类分级模型，支持 template(gbt35273/gdpr/jrt0197)、shadow 模式、复合规则、review 条目 |

迁移过程中：

- 移除所有对 `prometheus_client` / `observability` 的依赖，避免组件运行时的全局 side effect。
- 保持原有组件层公共 API 不变（`PrivacyAccountant`、`DPTransformer`、`KAnonymityTransformer`、`QueryObfuscator`、`SanitizationEngine`、`ClassificationAPI` / `classify_dataframe`）。
- 所有外部模型（NER、LLM）采用惰性导入 + NoOp 兜底，确保没有模型文件时也能正常构建/运行。

## 3. 组件注册更新

| 组件 | 旧版本 | 新版本 | 主要新增参数 |
|---|---|---|---|
| `privacy/data_classification` | 1.0.0 | **1.1.0** | `template`、`shadow_mode`、`enable_review`、`return_field_values`、`enable_composite_rules` |
| `privacy/differential_privacy` | 1.0.0 | **1.1.0** | `min_count`、clip 模式 union（`use_column_sensitivity` / `explicit_clip`） |
| `privacy/k_anonymity` | 1.0.0 | **1.1.0** | `max_depth`、`hierarchies_json` |
| `privacy/l_diversity` | 1.0.0 | 1.0.0 | 无变化 |
| `privacy/query_obfuscation` | 1.0.0 | **1.1.0** | `domain`、`medical_pool_json`、`generic_pool_json`（`synonym_map_json` 改为可选） |
| `privacy/sanitization` | 1.0.0 | **1.1.0** | 版本升级，规则方法支持 `mask_mobile` / `mask_id_card` / `mask_name` / `mask_bank_card` / `auto_mask` / `hmac_hash` |
| `privacy/local_differential_privacy` | 无 | **1.0.0** | 新组件：`op`（perturb/estimate）、`mechanism`（binary_rr/categorical_rr）、`query_col`、`epsilon`、`categories_json`、`random_state` |

组件注册后，通过 `secretflow component inspect -a` 重新生成了：

- `secretpad/config/components/secretflow.json`
- `secretpad/config/i18n/secretflow.json`（合并 `secretflow/secretflow/component/translation.json`）

所有 7 个隐私组件的中文翻译已补齐，并删除了过时的 `privacy/l_diversity:1` 和 `privacy/data_classification:1.0.0` 重复键。

## 4. 前端页面

在前端 `secretpad/frontend-src/apps/platform/src/modules/` 中：

- 新增 5 个流水线模板：
  - `pipeline-template-k-anonymity.ts`
  - `pipeline-template-l-diversity.ts`
  - `pipeline-template-sanitization.ts`
  - `pipeline-template-query-obfuscation.ts`
  - `pipeline-template-local-differential-privacy.ts`
- 更新现有模板版本号至 1.1.0：
  - `pipeline-template-data-classification.ts`
  - `pipeline-template-privacy.ts`（差分隐私）
- 在 `src/modules/pipeline/pipeline-protocol.tsx` 增加 `PipelineTemplateType` 枚举与 `TemplateIcon` 映射。
- 在 `src/modules/pipeline/index.ts` 注册所有新模板。
- 在 `src/modules/privacy-scenes/index.tsx` 中把 6 张场景卡绑定到对应模板（K-匿名、差分隐私、分类分级、查询混淆、L-多样性、本地差分隐私），不再使用空白模板。

参数面板仍由后端组件 schema 驱动，无需为每个组件写自定义 UI。

## 5. 测试与 E2E 验证

### 5.1 单元测试

迁移后新增/更新了 `secretflow/tests/privacy/` 与 `secretflow/tests/component/privacy/` 中的测试：

```bash
cd /home/charles/code/sfwork/secretflow
source "$(conda info --base)/etc/profile.d/conda.sh" && conda activate sf310
python -m pytest tests/privacy --env=sim -q          # 140 passed
python -m pytest tests/component/privacy --env=sim -q  # 25 passed
```

### 5.2 预生成测试参数

在 `e2e/privacy/params/` 中为 6 个组件预生成了参数 JSON，在 `e2e/privacy/data/` 中预置了 3 张测试 CSV：

- `medical_records.csv`：用于分类分级、K-匿名、脱敏
- `salary_stats.csv`：用于差分隐私 sum
- `has_disease.csv`：用于本地差分隐私 binary RR

### 5.3 直接运行（Direct）

```bash
python e2e/privacy/run_direct.py
```

结果写入 `e2e/privacy/results/direct/`。

### 5.4 完整链路运行（E2E）

通过 SecretPad REST API 完成：登录 → 建项目 → 添加节点 → 上传数据 → 创建 datatable → 加入项目 → 创建/更新 graph → 启动 → 轮询 → 拉取输出。

```bash
python e2e/privacy/run_e2e.py
```

结果写入 `e2e/privacy/results/e2e/`。

### 5.5 结果对比

```bash
python e2e/privacy/compare.py
```

对比结果：6 个组件的 E2E 输出与直接运行输出在结构和数值上一致。E2E 下载的表输出为 Kuscia 本地存储的 ORC 二进制，`compare.py` 已兼容读取 ORC 与 CSV 两种格式；报告输出从 SecretPad 后端 `tabs` 字段解析保存。

| 组件 | 直接运行 | E2E 链路 | 一致性 |
|---|---|---|---|
| data_classification | ✅ | ✅ | ✅ |
| differential_privacy | ✅ | ✅ | ✅ |
| k_anonymity | ✅ | ✅ | ✅ |
| local_differential_privacy | ✅ | ✅ | ✅ |
| query_obfuscation | ✅ | ✅ | ✅ |
| sanitization | ✅ | ✅ | ✅ |

### 5.6 E2E 过程中修复的跨层问题

在跑通“前端 → 后端 → Kuscia → SecretFlow”全链路时，发现并修复了以下问题：

1. **E2E 驱动输出数量不匹配**
   - 问题：`run_e2e.py` 之前为所有组件硬编码 2 个输出，但 `differential_privacy` 与 `query_obfuscation` 只有 1 个 `report` 输出，导致 Kuscia 任务参数校验失败。
   - 修复：`run_e2e.py` 从 `secretpad/config/components/secretflow.json` 动态读取每个组件的输出数量，并增加请求频率限制重试。

2. **E2E 报告输出保存错误**
   - 问题：SecretPad 后端对报告类型输出通过 `tabs` 字段返回报告内容，而 `run_e2e.py` 原从 `meta` 字段取值，导致所有报告文件保存为 `null`，`compare.py` 无法对比。
   - 修复：在 `run_e2e.py` 中改为保存 `output.tabs`，并封装为 `{tabs: [...]}` 与直接运行结果结构对齐。

3. **E2E 表输出格式识别**
   - 问题：Kuscia 本地存储的表输出为 ORC 二进制，`compare.py` 按 CSV 解析时遇到非 UTF-8 字节报错。
   - 修复：`compare.py` 增加 ORC 魔数检测（`ORC\n`），对 ORC 文件使用 `pyarrow.orc` 读取为 DataFrame 后再对比。

4. **SecretFlow 入口不支持零输入组件**
   - 问题：`secretflow/kuscia/entry.py` 的 `preprocess_sf_node_eval_param` 在 `sf_input_ids` 为 `None` 时直接调用 `len(None)`，导致 `query_obfuscation` 等无输入组件在 Kuscia 内启动失败。
   - 修复：在 `preprocess_sf_node_eval_param` 中将 `sf_input_ids` 默认空列表化。

5. **Checkpoint 参与方推断失败**
   - 问题：`secretflow/component/core/entry.py` 在创建 `Checkpoint` 时通过输入数据推导参与方，无输入组件得到空集合并触发 `assert len(parties) > 0`。
   - 修复：当输入数据无法推断参与方时，使用 `cluster_config.private_config.self_party` 作为默认参与方。

6. **SecretPad 后端无输入组件缺少 initiator**
   - 问题：对于没有数据输入的组件，`GraphServiceImpl.startGraph` 推导出的参与方集合为空，Kuscia 创建 Job 时提示 `initiator can not be empty`。
   - 修复：在 `GraphServiceImpl.startGraph` 中，当参与方集合为空时，回退到项目中的第一个节点（如 `alice`），确保 Kuscia 能正常调度。

## 6. 镜像与 Kuscia AppImage

自定义镜像：`secretflow/sf-privacy-dev:1.15.0.dev-privacy`。

构建流程：

```bash
cd /home/charles/code/sfwork/secretflow
source "$(conda info --base)/etc/profile.d/conda.sh" && conda activate sf310
python -m build --wheel
cp dist/secretflow-*.whl docker/privacy-dev/
cd docker/privacy-dev
docker build . -t secretflow/sf-privacy-dev:1.15.0.dev-privacy
```

镜像构建时通过 `Dockerfile` 中的注册断言验证 7 个隐私组件（含 `local_differential_privacy:1.0.0`）是否全部可用。由于 `data_classification` 已升级至 `1.1.0`，同步更新了断言中的版本号。

```bash
docker save secretflow/sf-privacy-dev:1.15.0.dev-privacy | docker exec -i charles-kuscia-lite-alice kuscia image load
docker save secretflow/sf-privacy-dev:1.15.0.dev-privacy | docker exec -i charles-kuscia-lite-bob kuscia image load
docker exec charles-kuscia-master scripts/deploy/register_app_image.sh -i secretflow/sf-privacy-dev:1.15.0.dev-privacy -m
```

## 7. Git 提交

本次改动涉及四个 Git 仓库：

- `secretflow/`：算法库与组件代码、测试
- `secretpad/`：组件配置、i18n、后端修复
- `secretpad/frontend-src/`：前端模板与场景卡（SecretPad 前端子仓库）
- `sfwork` 根仓库：`e2e/` 测试套件、启动脚本与本文档

各仓库分别提交并推送。

## 8. 结论

- 算法库已完成迁移并全部通过测试。
- 组件注册已升级，新增本地差分隐私组件。
- 前端已增加对应模板与场景卡。
- 预生成参数与数据覆盖全部隐私组件，E2E 验证结果与直接运行一致。
