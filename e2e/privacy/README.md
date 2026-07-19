# Privacy 算法 E2E 测试套件

本目录用于验证隐私算法库迁移后，**前端 → SecretPad 后端 → Kuscia → SecretFlow 镜像** 的全链路执行结果与直接在 SecretFlow 中运行 `comp_eval` 的结果一致。

## 目录结构

```text
e2e/privacy/
├── data/                     # 测试输入 CSV
├── params/                   # 预生成的组件参数 JSON
├── run_direct.py             # 直接调用 SecretFlow comp_eval（本地模拟模式）
├── run_e2e.py                # 通过 SecretPad REST API 走完整链路
├── compare.py                # 对比 direct 与 e2e 输出
├── TEST_DESIGN.md            # 端到端测试设计文档
└── results/                  # 运行结果（自动创建）
    ├── direct/
    └── e2e/
```

## 参数与数据

- `params/*.json` 中的 `component` 和 `attrs` 字段同时被 `run_direct.py` 和 `run_e2e.py` 使用，保证两端输入完全一致。
- 所有含随机性的组件（差分隐私、LDP、查询混淆）均使用固定 `random_state`，确保可复现。

## 直接运行（Direct）

用于生成预期结果：

```bash
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate sf310
cd /home/charles/code/sfwork
PYTHONPATH=./secretflow python e2e/privacy/run_direct.py
```

结果写入 `e2e/privacy/results/direct/`，每个参数文件对应独立子目录。

## 完整链路运行（E2E）

前置条件：

1. Kuscia Master + Lite（alice/bob）容器已启动。
2. SecretPad 后端已启动，监听 `http://127.0.0.1:8080`。
3. 自定义 SecretFlow 镜像 `secretflow/sf-privacy-dev:1.15.0.dev-privacy` 已构建并重新注册到 Kuscia 的 AppImage。

启动后端/前端（如未启动）：

```bash
cd /home/charles/code/sfwork
bash scripts/dev-start.sh
```

运行 E2E：

```bash
python e2e/privacy/run_e2e.py
```

结果写入 `e2e/privacy/results/e2e/`。

## 结果对比

```bash
python e2e/privacy/compare.py
```

如果所有组件的直接结果与 E2E 结果一致，脚本退出码为 0；否则输出差异并退出码 1。

> 注意：Kuscia 本地存储的表输出为 ORC 二进制，`compare.py` 会通过文件头魔数（`ORC\n`）自动识别并使用 `pyarrow.orc` 读取；报告输出会按后端返回的 `tabs` 字段解析。

## 已覆盖的隐私组件

| 组件 | 版本 | 说明 |
|---|---|---|
| data_classification | 1.1.0 | 数据分类分级（auto 模式） |
| differential_privacy | 1.1.0 | 差分隐私统计（count / sum / mean / histogram） |
| k_anonymity | 1.1.0 | K-匿名脱敏（Mondrian） |
| sanitization | 1.1.0 | 数据脱敏（mask_id_card / mask_mobile / mask_name） |
| query_obfuscation | 1.1.0 | 查询混淆（单条 + batch） |
| local_differential_privacy | 1.0.0 | 本地差分隐私（binary RR 扰动） |

## 结果正确性说明

- 所有算法均为确定性执行（随机种子固定），因此 `direct` 与 `e2e` 的表内容应逐行一致。
- 报告字段（如 DP 剩余预算、K-匿名等价类数量、混淆后的 dummy 数量等）也应完全一致。
- 若结果不一致，差异会打印在 `compare.py` 的输出中。
