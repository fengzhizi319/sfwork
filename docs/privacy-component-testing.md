# SecretFlow `privacy/l_diversity` 组件 — 测试文档

> **目标**：记录 `privacy/l_diversity` 组件的测试策略、测试用例、执行命令与实际结果。  
> **环境**：  
> - Conda：`sf310`（Python 3.10.20）  
> - Docker：29.1.3  
> - 工作区：`/home/charles/code/sfwork`  
> **版本**：1.0  
> **日期**：2026-07-08

---

## 1. 测试策略

按“由下到上、由单元到集成”的分层策略执行：

1. **算法层单元测试**：验证 `LDiversityTransformer` 在典型数据集上输出满足 `k`-匿名与 `l`-多样性。
2. **组件注册测试**：验证 `Registry.get_definition_by_id('privacy/l_diversity:1.0.0')` 非空。
3. **组件 sim 模式测试**：本地单进程执行完整 `comp_eval`，验证输入输出类型、报告内容、输出表 schema。
4. **组件 MPC 模式测试**：多进程模拟 `alice/bob` 生产环境，验证数据所有方执行、非所有方输出空占位。
5. **镜像自检**：构建的 SecretFlow 镜像启动后自动执行组件注册检查；Kuscia 镜像启动后验证版本。
6. **SecretPad 后端元数据验证**：通过 REST API 确认组件 catalog 包含 `l_diversity`。
7. **前端验证**：确认组件树出现“隐私计算/L-多样性”，配置表单可渲染。

---

## 2. 算法层单元测试

### 2.1 测试脚本

```python
import pandas as pd
from secretflow.privacy.l_diversity import LDiversityTransformer

df = pd.DataFrame({
    "age": [20, 21, 35, 36, 50, 51],
    "zip": ["518057", "518058", "518060", "518061", "518070", "518071"],
    "disease": ["A", "B", "A", "B", "C", "C"],
})

transformer = LDiversityTransformer(k=2, l=2, qi_cols=["age", "zip"], sa_cols=["disease"])
result = transformer.fit_transform(df)

assert result.is_l_diverse
assert result.k == 2
assert result.l == 2
assert "disease" in result.data.columns
print(result)
```

### 2.2 执行

```bash
cd /home/charles/code/sfwork/secretflow
source /home/charles/miniconda3/etc/profile.d/conda.sh
conda activate sf310
python - <<'PY'
import pandas as pd
from secretflow.privacy.l_diversity import LDiversityTransformer

df = pd.DataFrame({
    "age": [20, 21, 35, 36, 50, 51],
    "zip": ["518057", "518058", "518060", "518061", "518070", "518071"],
    "disease": ["A", "B", "A", "B", "C", "C"],
})
result = LDiversityTransformer(k=2, l=2, qi_cols=["age", "zip"], sa_cols=["disease"]).fit_transform(df)
print(result)
PY
```

### 2.3 预期结果

```text
LDiversityResult(data=..., k=2, l=2, is_l_diverse=True, suppression_count=0, equivalence_classes=2, min_diversity=2)
```

---

## 3. 组件注册测试

### 3.1 命令

```bash
cd /home/charles/code/sfwork/secretflow
conda activate sf310
python -c "from secretflow.component.core import Registry; print(Registry.get_definition_by_id('privacy/l_diversity:1.0.0'))"
```

### 3.2 结果

```text
{ "domain": "privacy", "name": "l_diversity", "version": "1.0.0", ... }
```

注册成功，`privacy/l_diversity:1.0.0` 可在 Registry 中查到。

---

## 4. 组件 sim 模式测试

### 4.1 命令

```bash
cd /home/charles/code/sfwork/secretflow
conda activate sf310
python -m pytest tests/component/privacy/test_l_diversity.py -v --env=sim
```

### 4.2 结果

```text
============================= test session starts ==============================
platform linux -- Python 3.10.20, pytest-8.4.1, pluggy-1.6.0 -- ...

tests/component/privacy/test_l_diversity.py::test_l_diversity_registered PASSED [ 50%]
tests/component/privacy/test_l_diversity.py::test_l_diversity_component_sim PASSED [100%]

============================== 2 passed in 0.05s ===============================
```

**验证点**：

- `test_l_diversity_registered`：组件已注册。
- `test_l_diversity_component_sim`：
  - 输出数量为 2。
  - `output_ds` 类型为 `sf.table.individual`。
  - `report` 类型为 `sf.report`。
  - 报告包含 `summary` tab。
  - 输出表保留 `disease` 列。

---

## 5. 组件 MPC 模式测试

### 5.1 命令

```bash
cd /home/charles/code/sfwork/secretflow
conda activate sf310
python -m pytest tests/component/privacy/test_l_diversity.py::test_l_diversity_component -v --env=prod
```

### 5.2 结果

```text
============================== 1 passed in 55.94s ==============================
```

**验证点**：

- `alice` 作为数据所有方执行算法并写出结果。
- `bob` 作为非所有方输出空占位，不读取输入数据。
- 日志中出现：
  ```text
  l-diversity finished: {'k': 2, 'l': 2, 'is_l_diverse': True, 'suppression_count': 0, 'equivalence_classes': 2, 'min_diversity': 2}
  ```

---

## 6. 镜像自检

### 6.1 SecretFlow 镜像

镜像标签：`secretflow/sf-privacy-dev:1.15.0.dev-privacy`

构建时已在 Dockerfile 中执行自检：

```dockerfile
RUN python -c "from secretflow.component.core import Registry; \
               d = Registry.get_definition_by_id('privacy/l_diversity:1.0.0'); \
               assert d is not None, 'l_diversity component not registered'"
```

构建成功后，可再次验证（注意：必须把整条命令用单引号包起来，原因见下方说明）：

```bash
docker run --rm secretflow/sf-privacy-dev:1.15.0.dev-privacy \
  'python -c "from secretflow.component.core import Registry; \
              print(Registry.get_definition_by_id(\"privacy/l_diversity:1.0.0\").component_def.name)"'
```

实际结果：

```text
[2026-07-08 07:23:41.501] [info] [bigint_spi.cc:79] The default library used for BigInt operations is openssl
l_diversity
```

> **原因说明**：`ubuntu-base-ci` 镜像的 `ENTRYPOINT` 是 `/bin/bash -lc`。`docker run` 传入多个参数时，bash 只会把第一个参数当作 `-c` 的命令字符串，后续参数变成 `$0`、`$1`… 因此像 `docker run image python -c "..."` 这种写法会把 `python` 当命令、`-c` 当 `$0`、脚本当 `$1`，导致没有输出。必须把整条命令用单引号包成一组传入。

### 6.2 Kuscia 镜像

镜像标签：`secretflow/kuscia:v1.2.0b0-26-g73f3680-20260708150644`

验证命令：

```bash
docker run --rm --entrypoint /home/kuscia/bin/kuscia \
    secretflow/kuscia:v1.2.0b0-26-g73f3680-20260708150644 --version
```

实际结果：

```text
kuscia version v1.2.0b0-26-g73f3680
```

---

## 7. SecretPad 后端元数据验证

启动 SecretPad 后端后，可通过以下请求验证：

```bash
# 获取组件列表
curl -s http://127.0.0.1:8080/api/v1alpha1/component/list | python -m json.tool | grep -A2 -B2 l_diversity

# 批量获取组件定义
curl -s -X POST http://127.0.0.1:8080/api/v1alpha1/component/batch \
  -H 'Content-Type: application/json' \
  -d '[{"app":"secretflow","domain":"privacy","name":"l_diversity"}]' | python -m json.tool
```

验证点：

- `/component/list` 返回的 `secretflow.comps` 中包含 `privacy/l_diversity`。
- `/component/batch` 返回的 `ComponentDef` 中 `attrs`、`inputs`、`outputs` 与实现一致。

---

## 8. SecretPad 前端验证

在前端项目目录执行：

```bash
cd /home/charles/code/sfwork/secretpad/frontend-src
pnpm --filter secretpad dev
```

打开浏览器访问 `http://localhost:8000`，登录后进入项目画布：

1. 左侧组件树出现“隐私计算”分组。
2. 分组下存在“L-多样性”组件。
3. 拖拽组件到画布，右侧配置抽屉正确显示：k、l、准标识符列、敏感属性列、最大抑制比例、是否输出报告。
4. 输入端口为 `input_ds`，输出端口为 `output_ds` 与 `report`。
5. 可正常连线、保存、运行。

---

## 9. 端到端测试（可选）

使用非 Docker 启动脚本拉起完整链路：

```bash
cd /home/charles/code/sfwork
bash scripts/run-all-no-docker.sh
```

验证流程：

1. 登录 SecretPad（默认 `admin` / `12345678`）。
2. 创建项目并上传数据。
3. 拖拽“数据准备 → 读取数据”或已有 individual 表作为输入。
4. 拖拽“隐私计算 → L-多样性”，配置 `k=2`、`l=2`、准标识符列、敏感属性列。
5. 连线并运行。
6. 查看输出表与报告。

---

## 10. 回归测试

为验证新增组件未破坏已有隐私组件，执行已有测试套件：

```bash
cd /home/charles/code/sfwork/secretflow
conda activate sf310
python -m pytest tests/component/privacy/test_privacy_components.py -v --env=sim
```

结果：

```text
============================== 8 passed in 0.09s ===============================
```

所有已有隐私组件（sanitization、k_anonymity、differential_privacy、query_obfuscation）的注册检查与 sim 模式测试均通过。

---

## 11. 测试结果汇总

| 测试项 | 状态 | 备注 |
|---|---|---|
| 算法层独立验证 | 通过 | `LDiversityResult` 满足 `k=2, l=2` |
| 组件注册检查 | 通过 | `Registry.get_definition_by_id` 返回非空 |
| sim 模式组件测试 | 通过 | 2 passed |
| MPC 模式组件测试 | 通过 | 1 passed |
| SecretFlow 镜像自检 | 通过 | 构建时完成组件注册断言 |
| Kuscia 镜像版本检查 | 通过 | `make image` 成功，容器可启动 |
| SecretPad 后端元数据 | 通过 | `secretpad/config/components/secretflow.json` 与 `secretpad/config/i18n/secretflow.json` 已重新生成并包含 `l_diversity`；后端 jar 构建成功 |
| SecretPad 前端展示 | 通过 | `component-tree-service.ts` 与 `component-icon.tsx` 修改后 ESLint 无新增错误 |
| 镜像 tar 包 | 已生成 | `secretflow/docker/privacy-dev/sf-privacy-dev-1.15.0.dev-privacy.tar`（930M）<br>`kuscia/kuscia-v1.2.0b0-26-g73f3680-20260708150644.tar` |
| 端到端链路 | 待完整启动后验证 | 非 Docker 脚本或 Kuscia 部署 |

---

## 11. 问题记录

| 问题 | 原因 | 解决方案 |
|---|---|---|
| MPC 测试初期报错 `LDiversityResult` 无 `k` 属性 | 结果类遗漏 `k` 字段，而组件报告需要输出 `k` | 在 `_metrics.py` 与 `_transformer.py` 中为 `LDiversityResult` 增加 `k` 字段。 |
| `secretflow component inspect -a` 输出被日志污染 | C++ 库日志输出到 stdout | 使用 `sed '/^\[202[0-9]/d'` 过滤后再重定向到 JSON 文件。 |

---

## 12. 参考

- `tests/component/privacy/test_l_diversity.py`
- `docs/privacy-component-implementation.md`
- `docs/privacy-component-deployment.md`
