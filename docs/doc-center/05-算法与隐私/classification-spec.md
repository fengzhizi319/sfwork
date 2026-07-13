# Data Classification Primitive — Cross-Language Implementation Spec

## 1. Terminology

| Term | Meaning |
|------|---------|
| `SensitivityLevel` | L1 (公开), L2 (低风险), L3 (中风险), L4 (高风险), L5 (极高风险) |
| `SecurityTag` | 一个标签，包含 level、category、confidence、sourceEngine、ruleId、version、needsHumanReview |
| `FieldClassificationResult` | 单个字段的分类结果 |
| `RecordClassificationResult` | 单条记录（多个字段）的分类结果 |
| `TableClassificationResult` | 整张表/批次的分类结果，取字段最高等级 |
| `EngineLayer` | L1_RULE, L2_SMALL_NER, L3_LLM |

## 2. Data Model

### 2.1 SensitivityLevel

String/enum values: `L1`, `L2`, `L3`, `L4`, `L5`.

Ordering: `L1 < L2 < L3 < L4 < L5`.

### 2.2 SecurityTag

```
SecurityTag {
  level: SensitivityLevel
  category: string       // e.g. "PII_ID_CARD", "MEDICAL_ICD10", "GENOMIC_BRCA1"
  confidence: double     // 0.0 ~ 1.0
  sourceEngine: string   // "RULE", "SMALL_NER", "LLM", "MANUAL"
  ruleId: string         // e.g. "RULE_ID_001"
  version: string        // default "1.0.0"
  needsHumanReview: bool // default false
}
```

Tag string representation: `{level}_{category}` e.g. `L3_PII_ID_CARD`.

### 2.3 FieldClassificationResult

```
FieldClassificationResult {
  fieldName: string
  fieldValue: string (optional, may be masked in output)
  tags: List<SecurityTag>
  finalLevel: SensitivityLevel
  confidence: double     // max confidence among tags, or computed aggregate
  engineLayer: EngineLayer
  needsHumanReview: bool
  reasoning: string      // human-readable explanation
}
```

### 2.4 RecordClassificationResult

```
RecordClassificationResult {
  recordIndex: int
  fieldResults: Map<string, FieldClassificationResult>
  aggregatedTags: List<SecurityTag>
  finalLevel: SensitivityLevel  // highest level among fields
  confidence: double
  needsHumanReview: bool
}
```

### 2.5 TableClassificationResult

```
TableClassificationResult {
  schema: List<string>          // column names in order
  recordResults: List<RecordClassificationResult>
  aggregatedTags: List<SecurityTag>
  finalLevel: SensitivityLevel  // highest level in table
  confidence: double
  needsHumanReview: bool
}
```

### 2.6 ClassificationResult

Union/wrapper that can hold either a record result or table result.

```
ClassificationResult {
  recordResult: RecordClassificationResult (optional)
  tableResult: TableClassificationResult (optional)
  auditInfo: AuditInfo
}
```

### 2.7 AuditInfo

```
AuditInfo {
  version: string          // primitive version, default "1.0.0"
  profileVersion: string   // from profile or "default"
  timestamp: string/ISO-8601
  ruleEngineVersion: string
  parameterSource: string  // e.g. "default", "profile", "request", "manual"
}
```

## 3. API Surface

Each SDK exposes a primitive API with these methods at minimum:

```
classifyField(fieldName, value, params) -> FieldClassificationResult
classifyRecord(record, params) -> RecordClassificationResult
classifyTable(schema, rows, params) -> TableClassificationResult
classifyJson(jsonString, params) -> ClassificationResult   // convenience
classifyArrow(arrowBytes, params) -> ClassificationResult  // optional
```

And on the client facade (Java `PrivacyClient`, Go `Client`, Python Agent service):

```
classification().classifyField(...)
classification().classifyRecord(...)
classification().classifyTable(...)
```

## 4. Rule Engine (Layer 1)

Default rule engine must implement these rules. Rules are evaluated per field. A field may match multiple rules; collect all tags. Final level = max(level of tags). Confidence = 1.0 for rule hits. `engineLayer` = `L1_RULE`.

### 4.1 Field-Name Based Rules (applies before value inspection)

For each field name (case-insensitive, strip underscores/spaces):

| Pattern | Category | Level | Rule ID |
|---------|----------|-------|---------|
| contains "brca1" or "brca2" or "tp53" | GENOMIC_BRCA_TP53 | L5 | RULE_ID_G_001 |
| matches `rs\d+` or contains "snp" or "cnv" or "genome" or "genomic" | GENOMIC_VARIANT | L5 | RULE_ID_G_002 |
| contains "gene" or "mutation" or "variant" | GENOMIC_HINT | L5 | RULE_ID_G_003 |
| contains "bam" or "vcf" or "fastq" | GENOMIC_FILE | L5 | RULE_ID_G_004 |

If a field name triggers L5, still continue value rules to collect additional evidence, but final level remains L5 unless manually overridden.

### 4.2 Value-Based Rules

| Data Type | Rule | Category | Level | Rule ID |
|-----------|------|----------|-------|---------|
| 中国大陆身份证号 | regex `^[1-9]\d{5}(18|19|20)\d{2}(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])\d{3}[\dXx]$` AND 加权校验和通过（示例 `110101199001011237` 为合法号码） | PII_ID_CARD | L3 | RULE_ID_001 |
| 手机号 | regex `^1[3-9]\d{9}$` | PII_MOBILE | L3 | RULE_ID_002 |
| 上海医保卡号 | regex `^\d{9}$` 且最后一位校验通过（见下方） | PII_MEDICAL_CARD | L3 | RULE_ID_003 |
| ICD-10 编码 | regex `^[A-Z][0-9]{2}(\.?[0-9]{0,2})?$`；区间映射见 4.3 | MEDICAL_ICD10 | L3/L4 | RULE_ID_004 |
| BAM 文件头 | value starts with magic `BAM\x01` or header starts with `@SQ` | GENOMIC_BAM | L5 | RULE_ID_G_010 |
| VCF 文件头 | value starts with `##fileformat=VCF` | GENOMIC_VCF | L5 | RULE_ID_G_011 |
| FASTQ 文件头 | value starts with `@` and contains `SRR`/`ERR`/`DRR` or third line is `+` | GENOMIC_FASTQ | L5 | RULE_ID_G_012 |
| 基因序列片段 | regex `[ATCGNatcgn]{50,}` | GENOMIC_SEQUENCE | L5 | RULE_ID_G_013 |
| 公开报表字段白名单 | contains "public_report", "annual_summary", "科普" | PUBLIC_REPORT | L1 | RULE_ID_L1_001 |
| 运营统计字段 | contains "turnover_rate", "device_usage", "inventory" | OPERATIONAL_STAT | L2 | RULE_ID_L2_001 |

**上海医保卡号校验**：9 位数字，前 8 位数字，第 9 位校验码。校验码 = 前 8 位按权重 `7,9,10,5,8,4,2,1` 乘积之和模 10，结果取 `(10 - sum%10) % 10`。若通过则为上海医保卡号。

**身份证校验和**：18 位，前 17 位数字，第 18 位校验码。权重 `[7,9,10,5,8,4,2,1,6,3,7,9,10,5,8,4,2]`，校验字符 `['1','0','X','9','8','7','6','5','4','3','2']`。`sum = Σ weight[i] * digit[i]`；校验码 = chars[sum % 11]。大小写不敏感。

### 4.3 ICD-10 Interval Mapping

Given a normalized ICD-10 code (first char + 2 digits, ignore dot):

- `B20`~`B24` → L4, category `MEDICAL_ICD10_HIV`
- `F20`~`F29` → L4, category `MEDICAL_ICD10_PSYCHIATRIC`
- `C00`~`C97` → L4, category `MEDICAL_ICD10_CANCER`
- Any other `^[A-Z]\d{2}` → L3, category `MEDICAL_ICD10_GENERAL`

Comparison: compare the letter and two-digit number lexicographically/numerically. For example `B20 <= code <= B24`.

### 4.4 Rule Priority & Confidence

- All matched tags are collected.
- `finalLevel = max(tag.level)`.
- `confidence = 1.0` if any rule hit; otherwise 0.0.
- `needsHumanReview = false` for rule hits.
- `reasoning = "命中规则: " + ruleIds` (or localized equivalent).

## 5. Small-NER Engine (Layer 2) — Placeholder

Interface only. Default implementation returns no tags and sets `engineLayer` unchanged.

If a custom NER engine is plugged in:

- It runs only when rule engine returns level <= L3 or no rule hit.
- It returns entities with labels: `PII_NAME`, `PII_ID`, `SENSITIVE_DISEASE`, `GENOMIC_HINT`, `MEDICATION`.
- If `SENSITIVE_DISEASE` co-occurs with `PII_NAME` or `PII_ID` in same text/record → upgrade to L4, category `SENSITIVE_DISEASE_WITH_PII`, confidence = avg(entity confidences).
- If `GENOMIC_HINT` → tag `L5_GENOMIC_HINT`, confidence = entity confidence, `needsHumanReview = true`.
- If confidence > 0.9 → adopt; 0.7~0.9 → `needsHumanReview = true`; <0.7 → pass to LLM.

Default no-op: returns empty list.

## 6. LLM Classifier (Layer 3) — Placeholder

Interface only. Default implementation:

- If upstream max confidence < 0.6, fallback to upstream highest level or L3.
- `needsHumanReview = true` when fallback.
- `reasoning = "LLM 未启用，按上游最高等级降级/保守处理"`.

If custom LLM plugged in, it returns structured output with `finalLevel`, `subCategory`, `confidence`, `reasoning`, `suggestedAction`, `needsHumanReview`.

## 7. Parameter Governance

Parameters resolve in strict priority (later overrides earlier):

1. SDK built-in defaults.
2. YAML profile under `primitives.classification`.
3. Method-level `params` argument / request params.
4. Per-field `manualOverride` map `{fieldName: SensitivityLevel}`.

Supported params:

```yaml
primitives:
  classification:
    version: "1.0.0"
    default_level: "L3"          # fallback when no engine hits
    enable_rule_engine: true
    enable_small_ner: false
    enable_llm: false
    icd10_l4_intervals:
      - { start: "B20", end: "B24" }
      - { start: "F20", end: "F29" }
      - { start: "C00", end: "C97" }
    genomic_keywords:
      - "brca1"
      - "brca2"
      - "tp53"
      - "rs"
      - "snp"
      - "cnv"
      - "genome"
      - "genomic"
      - "gene"
      - "mutation"
      - "variant"
    public_field_whitelist:
      - "public_report"
      - "annual_summary"
    operational_field_patterns:
      - "turnover_rate"
      - "device_usage"
      - "inventory"
    manual_override: {}          # field name -> level
```

## 8. Multi-Format Input Handling

### 8.1 Java

- `Map<String, Object> record` → `classifyRecord`.
- `List<String> schema + List<Map<String, Object>> rows` → `classifyTable`.
- JSON string → parse to table/record.
- `java.sql.ResultSet` → optional adapter method `classifyResultSet(ResultSet)`.
- Apache Arrow → optional adapter, no required external dependency.

### 8.2 Go

- `map[string]any record` → `ClassifyRecord`.
- `[]string schema + []map[string]any rows` → `ClassifyTable`.
- JSON bytes/string → `ClassifyJSON`.
- `*sql.Rows` → optional adapter.
- Arrow → optional adapter.

### 8.3 Python

- `dict` record → `classify_record`.
- `list[str] schema + list[dict] rows` → `classify_table`.
- JSON string/dict → `classify_json`.
- `pandas.DataFrame` → `classify_dataframe`.
- `pyarrow.Table` → `classify_arrow`.
- SQL result set (list of dicts) → `classify_sql_result`.

All format adapters convert to the internal `schema + rows` representation before classification.

## 9. Dual-Mode Execution

### 9.1 Local SDK / Function Mode

Direct in-process call:

```java
PrivacyClient client = new PrivacyClient();
FieldClassificationResult r = client.classification().classifyField("id_card", "110101199001011237", null);
```

### 9.2 SecretFlow Component Mode (Design Only)

Define an output schema that can be consumed as a SecretFlow component artifact:

```
component: metadata_classifier
domain: discovery
input_artifacts:
  - table: Table (Arrow/CSV)
parameters:
  - profile_path: str
  - sample_size: int
output_artifacts:
  - classification_report: JSON  # ClassificationResult serialized
```

SDK provides `toComponentJson()` / `toComponentOutput()` serialization helper.

## 10. Common Test Cases

All SDKs must pass these cases (values may be strings in JSON-friendly form):

| # | Input field | Value | Expected final level | Expected category (one of tags) |
|---|-------------|-------|----------------------|---------------------------------|
| 1 | id_card | 110101199001011237 | L3 | PII_ID_CARD |
| 2 | id_card | 110101199001011234 | L3 or lower | (invalid checksum → no PII_ID_CARD; may fall back) |
| 3 | mobile | 13800138000 | L3 | PII_MOBILE |
| 4 | mobile | 12800138000 | L1/L2 fallback | no PII_MOBILE |
| 5 | medical_card | 123456789 (valid Shanghai checksum) | L3 | PII_MEDICAL_CARD |
| 6 | diagnosis | B21.1 | L4 | MEDICAL_ICD10_HIV |
| 7 | diagnosis | F25 | L4 | MEDICAL_ICD10_PSYCHIATRIC |
| 8 | diagnosis | C78.0 | L4 | MEDICAL_ICD10_CANCER |
| 9 | diagnosis | J18.9 | L3 | MEDICAL_ICD10_GENERAL |
| 10 | brca1_status | positive | L5 | GENOMIC_BRCA_TP53 |
| 11 | rs_number | rs12345 | L5 | GENOMIC_VARIANT |
| 12 | file_content | BAM\x01... | L5 | GENOMIC_BAM |
| 13 | file_content | ##fileformat=VCFv4.2 | L5 | GENOMIC_VCF |
| 14 | file_content | @SQ SN:chr1 LN:1000 | L5 | GENOMIC_BAM |
| 15 | sequence | ATCGATCGATCG... (>=50 chars) | L5 | GENOMIC_SEQUENCE |
| 16 | public_report | 2023 annual summary | L1 | PUBLIC_REPORT |
| 17 | turnover_rate | 0.85 | L2 | OPERATIONAL_STAT |
| 18 | name | Alice | L1/L2 fallback | no high-sensitivity tag |
| 19 | record {id_card, mobile, diagnosis=B21.1} | - | L4 | aggregated final level L4 |
| 20 | table [id_card, brca1_status, diagnosis] | rows with L3/L5/L4 | L5 | final level L5 |

## 11. File Naming Conventions

### Java

- Model classes under `com.github.fengzhizi319.privacy.sdk.model.classification.*`
- API class: `com.github.fengzhizi319.privacy.sdk.api.DataClassificationApi`
- Rule engine interfaces/implementations under `com.github.fengzhizi319.privacy.sdk.api.classification.*`
- Utility validators under `com.github.fengzhizi319.privacy.sdk.util.*`

### Go

- `internal/classification/api.go`
- `internal/classification/rule_engine.go`
- `internal/classification/interfaces.go`
- `internal/classification/validators.go`
- `internal/classification/formats.go`
- `sdk/classification_models.go` (shared model structs)

### Python

- `privacy_local_agent/privacy/classification.py`
- `privacy_local_agent/privacy/classification_models.py`
- Extend `privacy_local_agent/service.py`, `main.py`, `grpc_server.py`, `proto/privacy.proto`.

## 12. Documentation Files

Each SDK must deliver:

- `docs/classification-prd.md`
- `docs/classification-design.md`
- `docs/classification-ops.md`
- `docs/classification-testing.md`
- Update `README.md` with classification examples.

These documents should be aligned in structure; language can be Chinese or bilingual as per project convention.
