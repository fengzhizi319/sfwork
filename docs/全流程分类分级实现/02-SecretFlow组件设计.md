# SecretFlow 分类分级组件设计

## 1. 设计目标

在 SecretFlow 中新增 `privacy/data_classification` 组件，实现数据分类分级能力：

- 输入单方 `sf.table.individual`。
- 输出分类后的数据表 + 列级汇总报告。
- 支持自动模式与高级模式两种参数配置方式。
- 算法核心复用 `privacy-local-agent` 的规则引擎。

## 2. 文件结构

```text
secretflow/
├── privacy/
│   └── data_classification/
│       ├── __init__.py              # 对外暴露 classify_dataframe, ClassificationParams 等
│       ├── models.py                # pydantic v2 数据模型（从 privacy-local-agent 移植）
│       ├── classification.py        # 规则引擎 + ClassificationAPI（从 privacy-local-agent 移植并精简）
│       └── _utils.py                # 辅助：结果转 DataFrame、报告生成等
└── secretflow/component/privacy/
    └── data_classification.py       # SecretFlow 组件封装
```

## 3. 算法层设计

### 3.1 模型层（models.py）

从 `privacy-local-agent/privacy_local_agent/privacy/classification_models.py` 移植以下核心模型：

- `SensitivityLevel`：L1 ~ L5 枚举。
- `EngineLayer`：L1_RULE / L2_SMALL_NER / L3_LLM。
- `SecurityTag`：单个命中标签。
- `FieldClassificationResult` / `RecordClassificationResult` / `TableClassificationResult`。
- `AuditInfo` / `ClassificationResult`。
- `ClassificationParams`：分类参数模型。
- 工具函数 `max_level`、`parse_level`。

直接使用 pydantic v2 的 `BaseModel` + `ConfigDict(populate_by_name=True)`，保持与原项目一致。

### 3.2 规则引擎（classification.py）

从 `privacy-local-agent/privacy_local_agent/privacy/classification.py` 移植 `DefaultRuleEngine`：

保留以下规则类别：

| 规则 ID | 类别 | 触发条件 | 等级 |
|---------|------|----------|------|
| RULE_ID_G_001 | GENOMIC_BRCA_TP53 | 字段名含 `brca1/brca2/tp53` | L5 |
| RULE_ID_G_002 | GENOMIC_VARIANT | 字段名/值含 `rs\d+`、`snp/cnv/genome/genomic` | L5 |
| RULE_ID_G_003 | GENOMIC_HINT | 字段名含 `gene/mutation/variant` | L5 |
| RULE_ID_G_004 | GENOMIC_FILE | 字段名含 `bam/vcf/fastq` | L5 |
| RULE_ID_001 | PII_ID_CARD | 18 位大陆身份证号校验和通过 | L3 |
| RULE_ID_002 | PII_MOBILE | `1[3-9]\d{9}` | L3 |
| RULE_ID_003 | PII_MEDICAL_CARD | 上海医保卡 9 位校验和通过 | L3 |
| RULE_ID_004 | MEDICAL_ICD10_* | ICD-10 编码，可配置 L4 区间 | L3/L4 |
| RULE_ID_P_001 | PUBLIC_REPORT | 字段名含 `public_report/annual_summary/科普` | L1 |
| RULE_ID_O_001 | OPERATIONAL_STAT | 字段名含 `turnover_rate/device_usage/inventory` | L2 |

新增/保留的入口函数：

```python
def classify_field(field_name: str, value: Any, params: ClassificationParams) -> FieldClassificationResult:
def classify_record(record: dict, params: ClassificationParams, record_index: int = 0) -> RecordClassificationResult:
def classify_dataframe(df: pd.DataFrame, params: ClassificationParams) -> tuple[pd.DataFrame, dict]:
```

其中 `classify_dataframe` 会：

1. 对每一行调用 `classify_record`。
2. 取每行最高等级作为 `__final_level__`。
3. 汇总每列的命中情况用于报告。
4. 返回 `(output_df, report_dict)`。

### 3.3 V1 范围控制

- **实现**：规则引擎 L1_RULE。
- **保留参数但 no-op**：`enable_small_ner`、`enable_llm`。
  - `enable_small_ner=True` 时打印 info 日志提示当前版本未实现，直接返回 L1 结果。
  - `enable_llm=True` 时同样提示未实现。
- 这样保证参数结构完整，后续可无缝扩展。

## 4. 组件层设计

### 4.1 参数定义

使用 `AT_UNION_GROUP` 实现「自动/高级」模式。

```python
from dataclasses import dataclass
from secretflow.component.core import (
    Component, Context, DistDataType, Field, Input, Interval, Output,
    Reporter, UnionGroup, register,
)

@dataclass
class Auto:
    default_level: str = Field.attr(
        desc="Default sensitivity level when no rule matches.",
        choices=["L1", "L2", "L3", "L4", "L5"],
        default="L3",
    )

@dataclass
class Advanced:
    enable_rule_engine: bool = Field.attr(
        desc="Enable rule engine.",
        default=True,
    )
    enable_small_ner: bool = Field.attr(
        desc="Enable small NER classifier (not implemented in v1).",
        default=False,
    )
    enable_llm: bool = Field.attr(
        desc="Enable LLM classifier (not implemented in v1).",
        default=False,
    )
    icd10_l4_intervals_json: str = Field.attr(
        desc='JSON list of ICD-10 intervals to promote to L4, e.g. [{"start":"B20","end":"B24"}].',
        default='[{"start":"B20","end":"B24"},{"start":"F20","end":"F29"},{"start":"C00","end":"C97"}]',
    )
    manual_override_json: str = Field.attr(
        desc='JSON dict mapping field name to forced level, e.g. {"patient_id":"L4"}.',
        default="{}",
    )

@dataclass
class Mode(UnionGroup):
    auto: Auto = Field.struct_attr(desc="Automatic mode with minimal parameters.")
    advanced: Advanced = Field.struct_attr(desc="Advanced mode with full parameter control.")
```

### 4.2 组件类

```python
@register(domain="privacy", version="1.0.0", name="data_classification")
class DataClassification(Component):
    """Classify sensitive data and assign sensitivity levels."""

    mode: Mode = Field.union_attr(
        desc="Classification mode.",
        default="auto",
    )

    input_ds: Input = Field.input(
        desc="Input individual table.",
        types=[DistDataType.INDIVIDUAL_TABLE],
    )
    output_ds: Output = Field.output(
        desc="Output table with classification result columns.",
        types=[DistDataType.INDIVIDUAL_TABLE],
    )
    report: Output = Field.output(
        desc="Column-level classification summary report.",
        types=[DistDataType.REPORT],
    )

    def evaluate(self, ctx: Context):
        ...
```

### 4.3 evaluate 执行流程

```text
1. 解析 union 参数，构造 ClassificationParams
   - auto 模式：default_level + 默认高级参数
   - advanced 模式：读取 advanced/enable_*、icd10_l4_intervals_json、manual_override_json
2. VTable.from_distdata(self.input_ds) 解析输入表元数据
3. 校验为 individual 表且仅有一方数据
4. load_party_table 读取实际数据为 pa.Table
5. pa.Table → pandas.DataFrame
6. classify_dataframe(df, params) 得到 (out_df, report_dict)
7. out_df → pa.Table，使用 build_schema_from_input 构造输出 schema
8. dump_party_tables 写入 output_ds
9. Reporter 生成 report
```

### 4.4 输出构造

#### 数据表

原表列保留，追加 3 列：

| 列名 | 类型 | 来源 |
|------|------|------|
| `__final_level__` | string | 每行 `record_result.final_level` |
| `__needs_review__` | bool | 每行 `record_result.needs_human_review` |
| `__tags_json__` | string | 每行 `record_result.aggregated_tags` JSON 序列化 |

#### 报告

```python
reporter = Reporter(name="data_classification", system_info=self.input_ds.system_info)
reporter.add_tab(report_dict, name="column_summary", desc="Column level classification summary")
self.report.data = reporter.to_distdata()
```

`report_dict` 包含：

```python
{
    "column": [...],
    "final_level": [...],
    "hit_count": [...],
    "categories": [...],
}
```

## 5. 与 SecretFlow 组件规范的对接

### 5.1 注册

- `@register(domain="privacy", version="1.0.0", name="data_classification")`
- 自动注册键：`privacy/data_classification:1`
- 组件 ID：`privacy/data_classification:1.0.0`

### 5.2 输入输出类型

- 输入：`sf.table.individual`
- 输出：`sf.table.individual` + `sf.report`

### 5.3 单方执行

- 不支持多方联合计算，输入表必须仅属于一个 party。
- 非数据所有方直接输出空占位（参考 `l_diversity`）。

## 6. 测试设计

### 6.1 单元测试

文件：`tests/component/privacy/test_data_classification.py`

覆盖：

1. 组件已注册：`Registry.get_definition_by_id("privacy/data_classification:1.0.0")` 非空。
2. 自动模式默认参数可解析。
3. 高级模式参数可解析。
4. sim 模式执行：构造 `NodeEvalParam`，调用 `comp_eval`，验证：
   - `output_ds` 为 `sf.table.individual`
   - 输出表包含 `__final_level__`、`__needs_review__`、`__tags_json__`
   - `report` 为 `sf.report`
   - 对包含身份证、手机号的测试数据，等级判断正确。

### 6.2 测试数据

```python
data = {
    "id": ["1", "2", "3"],
    "name": ["alice", "bob", "charlie"],
    "mobile": ["13800138000", "13900139000", "15000150000"],
    "id_card": ["110101199001011237", "310101198502024515", "110101199003078516"],
    "diagnosis": ["A01.0", "B22.1", "I10.9"],
    "brca1_status": ["normal", "variant", "normal"],
}
```

预期：

- `id`、`name` 未命中规则，默认 L3。
- `mobile` 命中 PII_MOBILE，L3。
- `id_card` 命中 PII_ID_CARD，L3。
- `diagnosis` 中 `B22.1` 命中 ICD-10 L4 区间，其余 L3。
- `brca1_status` 命中 GENOMIC_BRCA_TP53，L5。

## 7. 实现顺序

1. 创建 `secretflow/privacy/data_classification/__init__.py`。
2. 移植 `models.py`。
3. 移植并精简 `classification.py`，实现 `classify_dataframe`。
4. 编写 `_utils.py`（结果转表、报告聚合）。
5. 编写 `secretflow/secretflow/component/privacy/data_classification.py`。
6. 编写单元测试并运行。
7. 刷新 `secretpad/config/components/secretflow.json` 与 `secretpad/config/i18n/secretflow.json`。
