# Privacy 组件端到端测试设计文档

> 目标：验证 `secretflow` 新增的 privacy 组件功能在 **前端 → SecretPad 后端 → Kuscia → SecretFlow** 全链路中可正确执行，并与直接调用 SecretFlow `comp_eval` 的结果一致。
>
> 覆盖组件：
> - `differential_privacy:1.1.0`（新增 `noisy_count`、`noisy_sum`、`noisy_mean`、`noisy_histogram`、`chunked_*` 等查询类型）
> - `query_obfuscation:1.1.0`（新增 `op=batch` 批量查询混淆）
>
> 本文档先于代码编写，用于统一实现口径与验收标准。

---

## 1. 背景与范围

### 1.1 背景

`privacy-local-agent` 近期更新了本地隐私算法能力（DP 的 `noisy_*`/`chunked_*` 查询、查询混淆的批量模式）。这些能力已迁移到 `secretflow` 的 privacy 组件中，但新增字段和选项需要经过前端输入、后端校验、Kuscia 调度、SecretFlow 执行的完整链路验证。

### 1.2 测试范围

| 层级 | 验证点 |
|------|--------|
| **SecretFlow 组件** | 新增 `query_type`（`noisy_count`、`noisy_sum`、`noisy_mean`、`noisy_histogram`）与 `query_obfuscation.op=batch` 在本地 `comp_eval` 下结果正确。 |
| **SecretPad 后端组件配置** | `secretpad/config/components/secretflow.json` 与 `config/i18n/secretflow.json` 包含 1.1.0 版本的新字段，后端 `/api/v1alpha1/component/list` 可返回正确组件定义。 |
| **前端 DAG/模板** | 前端隐私场景页可加载新参数模板，`differential_privacy` 模板版本从 `1.0.0` 升级到 `1.1.0`，新增参数可预填充。 |
| **全链路 E2E** | 通过 `e2e/privacy/run_e2e.py` 或前端一键执行模板，任务在 Kuscia + SecretFlow 中成功运行，结果与 `run_direct.py` 一致。 |

### 1.3 不覆盖范围

- 不验证 MPC/TEE 多节点联合计算（privacy 组件多为单节点本地计算）。
- 不验证 UI 美观与交互细节，仅验证功能正确性。
- 不覆盖 `local_differential_privacy`、`k_anonymity`、`sanitization`、`data_classification` 的已有功能回归（由现有测试覆盖）。

---

## 2. 环境准备

### 2.1 本地开发环境

参考 `AGENTS.md` 与 `scripts/dev-start.sh`：

| 组件 | 启动方式 | 访问地址 |
|------|---------|----------|
| Kuscia Master + Lite | `bash scripts/dev-start.sh`（Docker 模式） | gRPC `127.0.0.1:18083`，Gateway `127.0.0.1:13081` |
| SecretPad 后端 | `mvn clean package -DskipTests` 后 `java -jar target/secretpad.jar` | `http://127.0.0.1:8080` / `https://127.0.0.1:8443` |
| SecretPad 前端 | `cd secretpad/frontend-src && pnpm bootstrap && pnpm --filter secretpad dev` | `http://localhost:8000` |
| SecretFlow | conda `sf310` 环境，`pip install -e ./secretflow` | 本地命令行直接调用 |

### 2.2 关键环境变量

SecretPad 后端启动前需设置：

```bash
export KUSCIA_API_ADDRESS=127.0.0.1
export KUSCIA_API_PORT=18083
export KUSCIA_GW_ADDRESS=127.0.0.1:13081
export KUSCIA_PROTOCOL=notls
```

### 2.3 数据准备

`e2e/privacy/data/` 已存在：

- `salary_stats.csv`：用于 `differential_privacy` sum/mean/noisy_* 查询。
- `medical_records.csv`：用于 `k_anonymity`/`sanitization`/`data_classification`。
- `has_disease.csv`：用于 `local_differential_privacy`。

新增 `query_obfuscation` 批量测试无需 CSV 输入，参数为字符串列表。

---

## 3. 组件变更清单

### 3.1 `differential_privacy:1.1.0`

新增字段（相对于 1.0.0）：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `true_count` | float | 条件 | `noisy_count`/`noisy_mean` 的真实计数。 |
| `true_sum` | float | 条件 | `noisy_sum`/`noisy_mean` 的真实求和。 |
| `true_counts_json` | string | 条件 | `noisy_histogram` 的真实直方图计数 JSON。 |
| `sensitivity` | float | 条件 | `noisy_sum`/`noisy_mean`/`noisy_histogram` 的全局敏感度。 |

新增 `query_type` 选项：

- `noisy_count`：对真实计数加噪声。
- `noisy_sum`：对真实求和加噪声。
- `noisy_mean`：对真实均值加噪声。
- `noisy_histogram`：对真实直方图计数加噪声。

### 3.2 `query_obfuscation:1.1.0`

新增字段：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `op` | string | 是 | `single` 或 `batch`。 |
| `queries_json` | string | 条件 | `op=batch` 时必填，JSON 字符串列表。 |

---

## 4. 测试用例设计

### 4.1 用例 1：Differential Privacy —— noisy_count

**目标**：验证通过前端输入真实计数和敏感度，组件返回带噪计数。

**输入参数**：

```json
{
  "component": {"domain": "privacy", "name": "differential_privacy", "version": "1.1.0"},
  "attrs": {
    "query_type": "noisy_count",
    "query_col": "",
    "epsilon_total": 1.0,
    "delta": 0.0,
    "epsilon_per_query": 1.0,
    "delta_per_query": 0.0,
    "mechanism": "laplace",
    "column_sensitivities_json": "{}",
    "bins_json": "[]",
    "true_count": 1000.0,
    "true_sum": 0.0,
    "true_counts_json": "{}",
    "sensitivity": 1.0,
    "random_state": 42,
    "min_count": 5.0,
    "mode": "use_column_sensitivity"
  }
}
```

**预期结果**：
- 报告 `result` 接近 `1000.0`（差分隐私噪声），不为 `1000.0` 精确值。
- `remaining_epsilon` 为 `0.0`（已用完）。
- 与 `run_direct.py` 结果一致。

### 4.2 用例 2：Differential Privacy —— noisy_sum

**目标**：验证对真实求和加噪。

**输入参数**：

```json
{
  "attrs": {
    "query_type": "noisy_sum",
    "true_sum": 100000.0,
    "sensitivity": 1000.0,
    "epsilon_total": 1.0,
    "mechanism": "laplace",
    "random_state": 42,
    "mode": "use_column_sensitivity"
  }
}
```

**预期结果**：结果接近 `100000.0`，与 `run_direct.py` 一致。

### 4.3 用例 3：Differential Privacy —— noisy_mean

**目标**：验证对真实均值加噪。

**输入参数**：

```json
{
  "attrs": {
    "query_type": "noisy_mean",
    "true_sum": 500000.0,
    "true_count": 1000.0,
    "sensitivity": 100.0,
    "epsilon_total": 1.0,
    "mechanism": "laplace",
    "random_state": 42,
    "mode": "use_column_sensitivity"
  }
}
```

**预期结果**：结果接近 `500.0`。

### 4.4 用例 4：Differential Privacy —— noisy_histogram

**目标**：验证对真实直方图计数加噪。

**输入参数**：

```json
{
  "attrs": {
    "query_type": "noisy_histogram",
    "true_counts_json": "{\"A\": 100, \"B\": 200, \"C\": 300}",
    "sensitivity": 1.0,
    "epsilon_total": 1.0,
    "mechanism": "laplace",
    "random_state": 42,
    "mode": "use_column_sensitivity"
  }
}
```

**预期结果**：返回字典 `{"A": ~100, "B": ~200, "C": ~300}`，与 `run_direct.py` 一致。

### 4.5 用例 5：Query Obfuscation —— batch 模式

**目标**：验证批量查询混淆返回多组混淆结果。

**输入参数**：

```json
{
  "component": {"domain": "privacy", "name": "query_obfuscation", "version": "1.1.0"},
  "attrs": {
    "op": "batch",
    "query": "",
    "queries_json": "[\"患者张三患有艾滋病，如何查询相关诊疗方案\", \"患者李四患有高血压，如何查询相关诊疗方案\"]",
    "synonym_map_json": "{}",
    "num_dummies": 3,
    "random_state": 42,
    "domain": "medical",
    "medical_pool_json": "[]",
    "generic_pool_json": "[]"
  }
}
```

**预期结果**：
- 报告包含 2 行，`real_query`、`real_index`、`dummy_queries`、`obfuscated_queries` 均正确。
- 每组 `obfuscated_queries` 长度为 4（1 真实 + 3 虚拟）。
- 与 `run_direct.py` 结果一致。

### 4.6 用例 6：Differential Privacy —— 原有 mean 查询回归

**目标**：确保 1.1.0 升级不破坏原有 `sum/mean/histogram` 查询。

**输入参数**：使用现有 `e2e/privacy/params/differential_privacy.json`（`query_type=sum`）。

**预期结果**：与 `run_direct.py` 结果一致。

---

## 5. 前端预加载模板设计

### 5.1 模板更新

前端已有模板：

- `pipeline-template-privacy.ts`（`DIFFERENTIAL_PRIVACY`）
- `pipeline-template-privacy-guide.ts`（`DIFFERENTIAL_PRIVACY_GUIDE`）

升级项：

1. `nodeDef.version` 从 `1.0.0` 改为 `1.1.0`。
2. `attrPaths` 增加 `true_count`、`true_sum`、`true_counts_json`、`sensitivity`。
3. `attrs` 按顺序补充默认值。
4. 新增 `query_obfuscation` 模板（`PipelineTemplateType.QUERY_OBFUSCATION`），用于前端隐私场景页一键执行。

### 5.2 隐私场景页扩展

`privacy-scenes/index.tsx` 新增一个场景卡片：

- 标题：`查询混淆`
- 标签：`QO`
- 模板：`PipelineTemplateType.QUERY_OBFUSCATION`
- 描述：通过将真实查询与虚拟查询混合，隐藏用户的真实查询意图。

### 5.3 模板协议注册

在 `pipeline-protocol.tsx` 中新增 `QUERY_OBFUSCATION` 枚举值，并在模板注册处加入 `TemplateQueryObfuscation`。

---

## 6. 后端组件配置更新

### 6.1 `secretpad/config/components/secretflow.json`

当前文件中的 `differential_privacy`/`query_obfuscation` 为 1.0.0 旧定义，需要：

1. 将 `differential_privacy` 升级到 `1.1.0`，补充新增字段。
2. 将 `query_obfuscation` 升级到 `1.1.0`，补充 `op`/`queries_json`。

**推荐做法**：运行 SecretFlow 容器或本地 `secretflow component inspect -a` 与 `secretflow component get_translation` 生成最新组件定义，然后替换到 `secretpad/config/components/secretflow.json` 与 `config/i18n/secretflow.json`。

### 6.2 翻译文件

`secretflow/secretflow/component/translation.json` 已包含新增字段翻译，但 SecretPad 后端使用 `config/i18n/secretflow.json`。因此需要：

1. 从 SecretFlow 生成最新 `sf_comp_translation.json`。
2. 或手工同步 `translation.json` 中新增键到 `config/i18n/secretflow.json`。

---

## 7. E2E 自动化脚本

### 7.1 参数文件

在 `e2e/privacy/params/` 新增：

- `differential_privacy_noisy_count.json`
- `differential_privacy_noisy_sum.json`
- `differential_privacy_noisy_mean.json`
- `differential_privacy_noisy_histogram.json`
- `query_obfuscation_batch.json`

### 7.2 直接运行（Direct）

`run_direct.py` 已支持读取参数文件并调用 `comp_eval`。新增参数文件后可直接运行：

```bash
python e2e/privacy/run_direct.py
```

生成 `results/direct/` 作为预期基线。

### 7.3 完整链路运行（E2E）

`run_e2e.py` 已支持通过 SecretPad REST API 执行参数文件。运行：

```bash
python e2e/privacy/run_e2e.py
```

生成 `results/e2e/`。

### 7.4 结果对比

`compare.py` 对比 direct 与 e2e 结果。新增参数文件后自动纳入对比。

---

## 8. 验收标准

| 编号 | 验收项 | 通过标准 |
|------|--------|----------|
| A1 | SecretFlow 本地 `comp_eval` | 所有新增参数文件在 `run_direct.py` 中执行成功，结果符合预期。 |
| A2 | SecretPad 后端组件列表 | `/api/v1alpha1/component/list` 返回 `differential_privacy:1.1.0` 与 `query_obfuscation:1.1.0`，字段完整。 |
| A3 | 前端组件树 | 前端隐私组件分类下能看到 `differential_privacy` 与 `query_obfuscation`，且参数面板包含新增字段。 |
| A4 | 前端模板执行 | 隐私场景页点击“查询混淆”模板能创建项目并运行成功。 |
| A5 | E2E 一致性 | `compare.py` 对比 direct 与 e2e 结果无差异（容差范围内）。 |
| A6 | 回归测试 | 原有 `differential_privacy`、`query_obfuscation` 单条模式、其他 privacy 组件结果与之前一致。 |

---

## 9. 实现计划

1. **后端配置**：更新 `secretpad/config/components/secretflow.json` 与 `config/i18n/secretflow.json`。
2. **前端模板**：升级 `pipeline-template-privacy.ts` / `pipeline-template-privacy-guide.ts` 到 1.1.0；新增 `query_obfuscation` 模板并注册到协议与隐私场景页。
3. **E2E 参数**：新增 5 个参数 JSON 文件。
4. **本地验证**：运行 `run_direct.py`、`run_e2e.py`、`compare.py`，确保全部通过。
5. **回归验证**：运行 `tests/component/privacy/` 与 `tests/privacy/test_differential_privacy.py`。

---

## 10. 风险与回退

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 后端组件配置与 SecretFlow 镜像组件版本不一致 | 前端提交图时 Kuscia 找不到组件 | 确保 `secretflow.json` 版本与镜像/本地 SecretFlow 一致；优先使用 `secretflow component inspect` 生成。 |
| 前端模板版本号错误 | 后端报 `COMPONENT_NOT_EXISTS` | 模板 `version` 必须与 `secretflow.json` 完全一致。 |
| 翻译文件缺失 | 前端参数面板显示英文或键名 | 同步 `translation.json` 到 `config/i18n/secretflow.json`。 |
| Kuscia 环境未启动 | E2E 失败 | 运行前执行 `bash scripts/dev-start.sh` 并检查端口。 |

---

*文档版本：v1.0*  
*作者：Kimi Code Agent*  
*日期：2026-07-19*
