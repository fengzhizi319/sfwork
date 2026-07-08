# SecretFlow `privacy/l_diversity` 组件 — 设计实现文档

> **依据**：`docs/privacy-component-hld.md`、`docs/privacy-component-lld.md`  
> **目标**：记录本次 `privacy/l_diversity` 组件的实际代码实现、文件变更与关键决策。  
> **版本**：1.0  
> **日期**：2026-07-08

---

## 1. 实现范围

本次实现完成了新增 `privacy/l_diversity` 组件所需的全链路代码：

- **SecretFlow 算法层**：`secretflow/privacy/l_diversity/`
- **SecretFlow 组件层**：`secretflow/component/privacy/l_diversity.py`
- **国际化**：`secretflow/component/translation.json`
- **单元/集成测试**：`tests/component/privacy/test_l_diversity.py`
- **SecretPad 后端元数据**：`secretpad/config/components/secretflow.json`、`secretpad/config/i18n/secretflow.json`
- **SecretPad 前端**：
  - `secretpad/frontend-src/apps/platform/src/modules/component-tree/component-tree-service.ts`
  - `secretpad/frontend-src/apps/platform/src/modules/component-tree/component-icon.tsx`
- **Kuscia**：无源码变更，仅使用新构建的 Kuscia 镜像。

---

## 2. SecretFlow 实现

### 2.1 算法层：`secretflow/privacy/l_diversity/`

| 文件 | 职责 |
|---|---|
| `__init__.py` | 对外暴露 `LDiversityTransformer`、`LDiversityResult`、`check_l_diversity`。 |
| `_metrics.py` | 定义 `LDiversityResult` 数据结构，提供 `check_l_diversity()` 校验函数。 |
| `_transformer.py` | 实现 `LDiversityTransformer`：先应用 k-anonymity，再抑制不满足 l-diversity 的等价类。 |

**关键设计决策**：

- 复用 `secretflow.privacy.k_anonymity.KAnonymityTransformer`，避免重复实现 Mondrian 多维分区逻辑。
- L-Diversity 检查以敏感属性列（`sa_cols`）的 **不同取值数** 为指标。
- 对不满足条件的等价类进行整组抑制，确保输出表最终满足 `l-diversity`。
- `LDiversityResult` 同时携带 `k`、`l` 与 `is_l_diverse` 等指标，便于报告输出。

### 2.2 组件层：`secretflow/component/privacy/l_diversity.py`

组件类 `LDiversity` 继承自 `Component` 并使用 `@register` 注册：

- **属性（attrs）**：
  - `k`、`l`：整数，下界 1。
  - `qi_cols_json`、`sa_cols_json`：JSON 字符串，描述准标识符列与敏感属性列。
  - `suppression_rate`：浮点，范围 `[0.0, 1.0]`。
  - `report_result`：布尔，控制是否输出报告。
- **输入**：`input_ds`，类型 `sf.table.individual`。
- **输出**：`output_ds`（`sf.table.individual`）和 `report`（`sf.report`）。

**执行流程**：

1. 解析 `qi_cols_json` / `sa_cols_json`。
2. 通过 `get_self_party(ctx)` 判断当前进程是否为数据所有方；非所有方输出空占位。
3. 数据所有方调用 `load_party_table()` 读取输入。
4. 调用 `_apply_l_diversity()` 执行算法，得到输出表与报告字典。
5. 使用 `build_schema_from_input()` 重建输出 schema，保留原列 kind。
6. 使用 `dump_party_tables()` 写入输出。
7. 使用 `Reporter` 生成 `sf.report`。

### 2.3 复用的公共工具

`secretflow/component/privacy/_utils.py` 中已有以下工具被直接复用：

- `parse_json_attr`：安全解析 JSON 字符串属性。
- `get_self_party`：获取当前 party。
- `load_party_table`：读取单 party 数据。
- `dump_party_tables`：写回输出表。
- `make_empty_table_output`：非数据所有方生成空占位。
- `build_schema_from_input`：从输入 schema 与输出 DataFrame 重建 schema。

### 2.4 国际化

在 `secretflow/component/translation.json` 中新增了 `privacy/l_diversity:1.0.0` 条目，提供中文显示名与属性描述。生成 `secretpad/config/i18n/secretflow.json` 时，这些中文条目会被保留。

---

## 3. SecretPad 后端实现

后端无 Java 代码变更。实现步骤：

1. 在 SecretFlow 环境（`sf310`）中执行：
   ```bash
   secretflow component inspect -a > secretpad/config/components/secretflow.json
   secretflow component get_translation > secretpad/config/i18n/secretflow.json
   ```
2. 确认生成的 `secretflow.json` 包含 `domain=privacy`、`name=l_diversity` 的 `ComponentDef`。
3. 重启 SecretPad 后端以加载新元数据。

> 由于 `l_diversity` 仅使用已有的 `sf.table.individual` 与 `sf.report` 类型，以及基础属性类型，因此不需要修改 `GraphBuilder`、`JobRenderHandler`、`KusciaJobConverter` 等 Java 模块。

---

## 4. SecretPad 前端实现

### 4.1 组件树分组

在 `component-tree-service.ts` 中：

- `mergedDomainMap` 增加 `privacy: '隐私计算'`，使 `privacy` 域组件归入“隐私计算”分组。
- `domainOrder` 增加 `'privacy'`，位于“特征处理”之后、“stats”之前。

### 4.2 图标

在 `component-icon.tsx` 中：

- 从 `@ant-design/icons` 导入 `SafetyOutlined`。
- 为 `privacy` 域注册安全图标。

### 4.3 表单与 DAG

`l_diversity` 的全部属性均为默认类型（int、float、str、bool），配置表单由默认渲染器自动处理；DAG 端口由 `graph-hook-service` 根据 `ComponentDef.inputs/outputs` 自动生成，无需额外开发。

---

## 5. Kuscia 集成

Kuscia 本身无源码变更。本次构建了新镜像：

```text
secretflow/kuscia:v1.2.0b0-26-g73f3680-20260708150644
```

该镜像包含当前 `kuscia/` 工作目录的最新代码，可直接用于调度包含 `l_diversity` 组件的 SecretFlow 任务。

---

## 6. 镜像打包

### 6.1 SecretFlow 镜像（AppImage）

**设计说明**：SecretFlow 镜像在 Kuscia 架构中属于 **AppImage**（应用镜像），供 Kuscia 调度给任务容器使用；它不是 Kuscia 节点镜像，因此**不需要也不应该**在 Kuscia 镜像之上打包。Kuscia 节点镜像与 SecretFlow AppImage 是分离的两个镜像：

- **Kuscia 镜像**：运行 Kuscia Master/Lite 节点（包含 kuscia、envoy、k3s 等）。
- **SecretFlow AppImage**：被 Kuscia 调度为任务 Pod，执行 `python -m secretflow.kuscia.entry ./kuscia/task-config.conf`。

为便于验证，构建了一个基于官方 `secretflow/ubuntu-base-ci` 基础镜像的 AppImage：

```text
secretflow/sf-privacy-dev:1.15.0.dev-privacy
```

构建方式：

1. 使用 `python -m build --wheel` 在工作区生成 `secretflow-1.15.0.dev20260708-py3-none-any.whl`。
2. 通过 `secretflow/docker/privacy-dev/Dockerfile` 将 wheel 及其运行时依赖安装到 `secretflow/ubuntu-base-ci:20250228` 基础镜像中。
3. 镜像内同时安装了 `kuscia` Python 包，确保 `secretflow.kuscia.entry` 能正常读取 `task-config.conf`。
4. 构建时执行 `Registry.get_definition_by_id('privacy/l_diversity:1.0.0')` 进行组件注册自检。

该镜像主要用于本地/CI 快速验证；生产环境建议使用官方 `docker/dev/build.sh` 或 `docker/release/build.sh` 流程构建完整镜像。

为便于离线分发，已将该镜像导出为 tar：

```text
secretflow/docker/privacy-dev/sf-privacy-dev-1.15.0.dev-privacy.tar   (930M)
```

验证命令（注意整条命令要用单引号包起来）：

```bash
docker run --rm secretflow/sf-privacy-dev:1.15.0.dev-privacy \
  'python -c "from secretflow.component.core import Registry; \
              print(Registry.get_definition_by_id(\"privacy/l_diversity:1.0.0\").component_def.name)"'
```

> **为什么会“吞掉 stdout”**：`ubuntu-base-ci` 镜像的 `ENTRYPOINT` 是 `/bin/bash -lc`。当 `docker run` 传入多个参数时，bash 只会把第一个参数作为 `-c` 的命令字符串，其余参数变成 `$0`、`$1`… 因此未加单引号的 `docker run image python -c "..."` 会把 `python` 当命令、`-c` 当 `$0`、脚本当 `$1`，导致看不到输出。解决方案是**用单引号把整条命令包成一组传入**。

> **关于“在 Kuscia 镜像上打包”**：我们尝试过通过多阶段构建把 `sf-privacy-dev` 的 Python 环境复制到 Kuscia 镜像中，但两个镜像的 Python 环境不同（`ubuntu-base-ci` 使用 `/root/miniconda3`，而 Kuscia 镜像使用系统 `/usr/bin/python3`），直接复制会导致路径和 ABI 不兼容，构建失败。因此遵循官方架构，保持两个镜像独立，并通过 AppImage 方式对接。

### 6.2 Kuscia 镜像（节点镜像）

使用 Kuscia 项目自带 `Makefile`：

```bash
cd /home/charles/code/sfwork/kuscia
make image
```

产物镜像：

```text
secretflow/kuscia:v1.2.0b0-26-g73f3680-20260708150644
```

**说明**：该镜像只包含 Kuscia 节点运行时（kuscia 二进制、envoy、k3s、CRD、脚本等），**不包含 SecretFlow**。SecretFlow 需要作为独立的 AppImage 注册到 Kuscia 中（见第 6.1 节与部署文档中的 AppImage 注册）。

同样已导出 tar 便于离线分发：

```text
kuscia/kuscia-v1.2.0b0-26-g73f3680-20260708150644.tar   (380M)
```

---

## 7. 代码目录变更汇总

```text
secretflow/
  secretflow/privacy/l_diversity/
    ├── __init__.py              [新增]
    ├── _metrics.py              [新增]
    └── _transformer.py          [新增]
  secretflow/component/privacy/
    ├── l_diversity.py           [新增]
    └── _utils.py                [复用，未修改]
  secretflow/component/
    └── translation.json         [追加 l_diversity 翻译条目]
  tests/component/privacy/
    └── test_l_diversity.py      [新增]
  docker/privacy-dev/
    ├── Dockerfile               [新增]
    └── secretflow-*.whl         [构建产物]

secretpad/
  config/
    ├── components/secretflow.json    [重新生成]
    └── i18n/secretflow.json          [重新生成]
  frontend-src/apps/platform/src/modules/component-tree/
    ├── component-tree-service.ts    [修改]
    └── component-icon.tsx           [修改]

kuscia/
  # 无源码变更，仅执行 make image 生成新镜像
```

---

## 8. 关键决策与取舍

| 决策 | 说明 |
|---|---|
| 复用 k-anonymity | 使用 `KAnonymityTransformer` 处理准标识符泛化/抑制，再叠加 l-diversity 检查，避免重复实现 Mondrian 算法。 |
| 单方 individual 表 | 当前 `privacy` 组件（k-anonymity、differential_privacy 等）均按单方表设计，`l_diversity` 沿用该模式，非所有方输出空占位。 |
| 无需自定义 protobuf | 所有属性均使用 SecretFlow 已有原子类型，无需扩展 `secretflow/protos/secretflow/spec/extend/`。 |
| 轻量覆盖镜像 | 为加速验证，基于现有 SecretFlow lite 镜像构建覆盖镜像；生产建议走完整 build.sh。 |

---

## 9. 参考文档

1. `docs/privacy-component-hld.md`
2. `docs/privacy-component-lld.md`
3. `docs/privacy-component-testing.md`
4. `docs/privacy-component-deployment.md`
