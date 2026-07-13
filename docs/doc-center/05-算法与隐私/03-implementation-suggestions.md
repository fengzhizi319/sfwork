# 03 代码实现建议

> 面向研发的落地建议，包括目录结构、核心接口、本地 SDK、REST/gRPC Agent、参数解析与 SecretFlow 组件集成示例。

## 1. 目录结构建议

```textnsecretflow/
└── secretflow/
    └── privacy/
        ├── __init__.py
        ├── core/                           # 统一抽象与注册表
        │   ├── primitive.py                # PrivacyPrimitive 基类
        │   ├── registry.py                 # 原语注册表
        │   ├── input_adapter.py            # 数据格式适配
        │   ├── output_adapter.py           # 结果格式还原
        │   ├── parameter_resolver.py       # 参数解析器
        │   └── budget_accountant.py        # 隐私预算台账
        ├── batch/                          # 批量模式（SecretFlow 组件）
        │   ├── dp_component.py
        │   ├── k_anonymity_component.py
        │   ├── sanitization_component.py
        │   └── qol_component.py
        ├── local/                          # 本地模式（SDK + Agent）
        │   ├── __init__.py
        │   ├── api.py                      # 对外 Python API
        │   ├── agent/
        │   │   ├── main.py                 # FastAPI / gRPC 入口
        │   │   ├── routers/
        │   │   │   ├── mask.py
        │   │   │   ├── dp.py
        │   │   │   ├── k_anonymity.py
        │   │   │   └── qol.py
        │   │   └── service.py
        │   └── cli.py                      # sf-privacy 命令行
        ├── algorithms/                     # 算法实现
        │   ├── dp/
        │   │   ├── laplace.py
        │   │   ├── gaussian.py
        │   │   └── exponential.py
        │   ├── k_anonymity/
        │   │   ├── hierarchy.py
        │   │   ├── mondrian.py
        │   │   └── validator.py
        │   ├── sanitization/
        │   │   ├── masking.py
        │   │   ├── hashing.py
        │   │   ├── fpe.py
        │   │   └── substitution.py
        │   └── qol/
        │       └── dummy_query_generator.py
        ├── profiles/                       # 预置模板
        │   ├── medical_research.yaml
        │   ├── medical_stat.yaml
        │   └── financial.yaml
        └── tests/
```

## 2. 核心接口设计

### 2.1 PrivacyPrimitive 基类

```python
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any, Dict, Optional

@dataclass
class PrivacyContext:
    namespace: str = "default"
    project_id: Optional[str] = None
    user_role: Optional[str] = None
    purpose: Optional[str] = None
    sensitivity_tags: Optional[list] = None

@dataclass
class PrivacyRequest:
    primitive: str
    action: str
    data: Any
    params: Dict[str, Any]
    context: PrivacyContext

@dataclass
class PrivacyResult:
    data: Any
    params_used: Dict[str, Any]
    proof: Dict[str, Any]
    warnings: list

class PrivacyPrimitive(ABC):
    name: str
    version: str = "1.0.0"

    @abstractmethod
    def execute(self, request: PrivacyRequest) -> PrivacyResult:
        ...

    @abstractmethod
    def validate_params(self, params: Dict[str, Any]) -> None:
        ...
```

### 2.2 注册表

```python
# secretflow/privacy/core/registry.py
_registry: Dict[str, PrivacyPrimitive] = {}

def register(primitive: PrivacyPrimitive):
    _registry[primitive.name] = primitive

def get(name: str) -> PrivacyPrimitive:
    return _registry[name]
```

## 3. 参数解析器实现建议

```python
# secretflow/privacy/core/parameter_resolver.py
from typing import Any, Dict
import yaml

class ParameterResolver:
    def __init__(self, profile_path: Optional[str] = None):
        self.profile = self._load_profile(profile_path)

    def resolve(
        self,
        primitive: str,
        action: str,
        request_params: Dict[str, Any],
        context: PrivacyContext,
    ) -> Dict[str, Any]:
        # 1. 算法默认值
        params = self._default_params(primitive, action)
        # 2. 预置模板
        template = self._match_template(context)
        params.update(template.get(primitive, {}))
        # 3. Profile 配置
        params.update(self._profile_params(primitive, context))
        # 4. 上下文覆盖
        params.update(self._context_overrides(primitive, context))
        # 5. 请求显式参数（最高优先级）
        params.update(request_params)
        # 6. 校验
        self._validate(primitive, params)
        return params

    def _load_profile(self, path):
        if not path:
            return {}
        with open(path) as f:
            return yaml.safe_load(f)

    def _default_params(self, primitive, action):
        defaults = {
            "dp": {"epsilon": 1.0, "delta": 1e-5, "mechanism": "laplace"},
            "k_anonymity": {"k": 5, "l": 2, "t": 0.2, "max_depth": 10},
            "sanitization": {"engine": "mask"},
            "qol": {"num_dummies": 3},
        }
        return defaults.get(primitive, {})

    def _match_template(self, context: PrivacyContext):
        # 根据 sensitivity_tags + purpose 匹配预置模板
        ...

    def _validate(self, primitive, params):
        if primitive == "dp":
            assert params["epsilon"] > 0
        elif primitive == "k_anonymity":
            assert params["k"] >= 2
```

## 4. 本地 SDK API 示例

```python
# secretflow/privacy/local/api.py
from typing import Any, Dict, List, Optional, Union
import pandas as pd

from secretflow.privacy.core.parameter_resolver import ParameterResolver
from secretflow.privacy.core.registry import get
from secretflow.privacy.core.input_adapter import adapt_input


def _call(
    primitive: str,
    action: str,
    data: Any,
    params: Optional[Dict[str, Any]] = None,
    context: Optional[Dict[str, Any]] = None,
):
    resolver = ParameterResolver()
    resolved = resolver.resolve(
        primitive=primitive,
        action=action,
        request_params=params or {},
        context=context or {},
    )
    request = PrivacyRequest(
        primitive=primitive,
        action=action,
        data=adapt_input(data),
        params=resolved,
        context=context or {},
    )
    primitive_inst = get(primitive)
    return primitive_inst.execute(request)


def mask_value(
    field_name: str,
    value: Any,
    context: Optional[Dict[str, Any]] = None,
    **params,
) -> str:
    result = _call(
        primitive="sanitization",
        action="mask_value",
        data={"field_name": field_name, "value": value},
        params=params,
        context=context,
    )
    return result.data


def k_anonymize_record(
    record: Dict[str, Any],
    qi_cols: List[str],
    sa_cols: Optional[List[str]] = None,
    hierarchies: Optional[Dict[str, Any]] = None,
    context: Optional[Dict[str, Any]] = None,
    **params,
) -> Dict[str, Any]:
    return _call(
        primitive="k_anonymity",
        action="anonymize_record",
        data={"record": record, "qi_cols": qi_cols, "sa_cols": sa_cols, "hierarchies": hierarchies},
        params=params,
        context=context,
    ).data


def dp_count(
    values: Union[List, pd.Series],
    epsilon: float = 1.0,
    mechanism: str = "laplace",
    context: Optional[Dict[str, Any]] = None,
) -> float:
    return _call(
        primitive="dp",
        action="count",
        data=values,
        params={"epsilon": epsilon, "mechanism": mechanism},
        context=context,
    ).data


def obfuscate_query(
    query: str,
    num_dummies: int = 3,
    domain: Optional[str] = None,
    context: Optional[Dict[str, Any]] = None,
) -> List[str]:
    return _call(
        primitive="qol",
        action="obfuscate",
        data=query,
        params={"num_dummies": num_dummies, "domain": domain},
        context=context,
    ).data
```

## 5. Java 本地 SDK 实现建议

### 5.1 模块结构

```textnprivacy-java-sdk/
├── pom.xml
├── src/main/java/com/secretflow/privacy/sdk/
│   ├── PrivacyClient.java
│   ├── PrivacyProfile.java
│   ├── api/
│   │   ├── DpApi.java
│   │   ├── KAnonymityApi.java
│   │   ├── MaskingApi.java
│   │   └── QolApi.java
│   ├── model/
│   │   ├── PrivacyRequest.java
│   │   ├── PrivacyResult.java
│   │   └── ParameterBundle.java
│   ├── exception/
│   │   ├── PrivacyException.java
│   │   └── PrivacyBudgetExhaustedException.java
│   └── util/
│       ├── ParameterResolver.java
│       └── BudgetAccountant.java
└── src/test/java/...
```

### 5.2 调用示例

```java
PrivacyProfile profile = PrivacyProfile.fromYaml("privacy-profile.yaml");
PrivacyClient client = new PrivacyClient(profile);

String masked = client.masking().maskValue("mobile", "13812345678", "doctor_query");

List<Double> values = Arrays.asList(1.0, 0.0, 1.0, 1.0);
double noisyCount = client.dp().count(values, 1.0, "laplace");

Map<String, Object> record = Map.of(
    "age", 28, "zipcode", "518057", "gender", "女", "disease", "胃癌"
);
Map<String, Object> anon = client.kAnonymity().anonymizeRecord(
    record, List.of("age", "zipcode", "gender"), hierarchies, 5
);

List<String> dummies = client.qol().obfuscateQuery("糖尿病患者用药趋势", 3, "diabetes");
```

## 6. Go 本地 SDK 实现建议

### 6.1 模块结构

```textnprivacy-go-sdk/
├── go.mod
├── client.go
├── profile.go
├── dp.go
├── kano.go
├── masking.go
├── qol.go
├── models.go
├── budget.go
└── *_test.go
```

### 6.2 调用示例

```go
client, _ := privacy.NewClientFromFile("privacy-profile.yaml")

masked, _ := client.MaskValue("mobile", "13812345678", "doctor_query")

values := []float64{1, 0, 1, 1}
noisyCount, _ := client.DPCount(values, 1.0, "laplace")

record := map[string]any{"age": 28, "zipcode": "518057", "gender": "女"}
anon, _ := client.KAnonymizeRecord(record, []string{"age", "zipcode", "gender"}, hierarchies, 5)

dummies, _ := client.ObfuscateQuery("糖尿病患者用药趋势", 3, "diabetes")
```

## 7. 本地 Agent（REST/gRPC）实现建议

Agent 适用于无法引入 Java/Go SDK 的场景，需要单独处理请求并发。

### 7.1 技术选型

- Python + FastAPI（REST）
- Python + grpcio（gRPC）
- 部署：本地进程 / Docker Sidecar / K8s DaemonSet

### 7.2 REST 接口示例

```python
# privacy-local-agent/agent/main.py
from fastapi import FastAPI, Request
from pydantic import BaseModel
import uvicorn

from secretflow.privacy.local.api import mask_value, dp_count, k_anonymize_record, obfuscate_query

app = FastAPI(title="SecretFlow Local Privacy Agent")

class MaskRequest(BaseModel):
    field_name: str
    value: str
    context: dict = {}

@app.post("/v1/privacy/mask")
def mask(req: MaskRequest):
    return {"result": mask_value(req.field_name, req.value, context=req.context)}

class DpRequest(BaseModel):
    values: list
    epsilon: float = 1.0
    mechanism: str = "laplace"
    context: dict = {}

@app.post("/v1/privacy/dp/count")
def dp_count_api(req: DpRequest):
    return {"result": dp_count(req.values, req.epsilon, req.mechanism, req.context)}

# 类似地封装 k_anonymize、obfuscate_query

@app.get("/health")
def health():
    return {"status": "ok"}

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8079)
```

### 7.3 gRPC 接口定义

```protobuf
syntax = "proto3";
package privacy.local;

service PrivacyService {
  rpc Mask (MaskRequest) returns (MaskResponse);
  rpc DPCount (DPRequest) returns (DPResponse);
  rpc KAnonymizeRecord (KAnonymizeRequest) returns (KAnonymizeResponse);
  rpc ObfuscateQuery (QolRequest) returns (QolResponse);
}

message MaskRequest {
  string field_name = 1;
  string value = 2;
  map<string, string> context = 3;
}

message MaskResponse {
  string result = 1;
}

// DP/K-Anon/QOL 请求响应类似
```

### 7.4 并发与稳定性设计

- **连接池**：HTTP/2 + gRPC 长连接；业务侧使用连接池。
- **限流**：FastAPI 中间件或 gRPC interceptor 实现 QPS/并发限制。
- **隐私预算并发锁**：使用 `asyncio.Lock` 或线程锁保护预算台账。
- **超时与熔断**：单请求超时 5s，Agent 过载时返回 503 触发客户端降级。
- **优雅关闭**：监听 SIGTERM，停止接收新请求并等待处理中请求完成。

启动方式：

```bash
sf-privacy agent --port 8079 --profile ./privacy-profile.yaml --max-concurrency 100
```

## 8. SecretFlow 批量组件集成建议

### 6.1 K-匿名组件示例

```python
# secretflow/privacy/batch/k_anonymity_component.py
import secretflow as sf
from secretflow.privacy.algorithms.k_anonymity.mondrian import MondrianPartitioner

class KAnonymityComponent:
    def __init__(self, k=5, l=2, t=0.2, hierarchies=None):
        self.k = k
        self.l = l
        self.t = t
        self.hierarchies = hierarchies

    def transform(self, df):
        partitioner = MondrianPartitioner(
            k=self.k, l=self.l, t=self.t, hierarchies=self.hierarchies
        )
        result = partitioner.fit_transform(df, qi_cols=..., sa_cols=...)
        return result.anonymized_df, result.proof


def build_k_anonymity_component(pyu: sf.PYU, **params):
    def _transform(data_dict):
        import pandas as pd
        df = pd.DataFrame(data_dict)
        component = KAnonymityComponent(**params)
        return component.transform(df)

    return pyu(_transform)
```

### 6.2 组件元数据（SecretFlow V2 Component）

```yaml
# secretflow/privacy/batch/component_meta/k_anonymity.yaml
component_name: k_anonymity_transformer
domain: preprocessing
version: 1.0.0
inputs:
  - name: original_data
    type: DataFrame
outputs:
  - name: anonymized_data
    type: DataFrame
  - name: audit_report
    type: JSON
parameters:
  - name: k
    type: int
    default: 5
  - name: l
    type: int
    default: 2
  - name: t
    type: float
    default: 0.2
  - name: qi_columns
    type: list[str]
  - name: sa_columns
    type: list[str]
  - name: hierarchy_config
    type: json
```

## 9. 数据格式适配器建议

```python
# secretflow/privacy/core/input_adapter.py
import json
import pandas as pd
import pyarrow as pa

class PrivacyInputAdapter:
    def adapt(self, data, format_hint='auto'):
        if isinstance(data, pd.DataFrame):
            return data
        if isinstance(data, pd.Series):
            return data.to_frame().T
        if isinstance(data, dict):
            return pd.DataFrame([data])
        if isinstance(data, list) and len(data) > 0 and isinstance(data[0], dict):
            return pd.DataFrame(data)
        if isinstance(data, bytes):
            # Arrow IPC
            return pa.ipc.open_stream(data).read_all().to_pandas()
        if isinstance(data, str):
            # JSON
            return pd.DataFrame(json.loads(data))
        raise TypeError(f"Unsupported input type: {type(data)}")
```

## 10. 隐私预算台账建议

```python
# secretflow/privacy/core/budget_accountant.py
class PrivacyBudgetAccountant:
    def __init__(self, namespace, epsilon_total=10.0, delta_total=1e-4):
        self.namespace = namespace
        self.epsilon_total = epsilon_total
        self.delta_total = delta_total
        self.epsilon_spent = 0.0
        self.delta_spent = 0.0

    def spend(self, epsilon, delta=0.0):
        # 使用 RDP 组合会更精确，此处为简化示例
        self.epsilon_spent += epsilon
        self.delta_spent += delta
        if self.epsilon_spent > self.epsilon_total:
            raise PrivacyBudgetExhausted(
                f"Privacy budget exhausted: {self.epsilon_spent}/{self.epsilon_total}"
            )

    def remaining(self):
        return {
            "epsilon": self.epsilon_total - self.epsilon_spent,
            "delta": self.delta_total - self.delta_spent,
        }
```

## 11. 测试策略

| 测试类型 | 内容 |
|---|---|
| 单元测试 | 每个算法（Laplace、Mondrian、Masking、FPE、QOL）独立测试 |
| 集成测试 | 本地 SDK → Agent → 算法全链路 |
| 批量测试 | SecretFlow Component 在本地 Ray 集群跑通 |
| 参数解析测试 | 模板/Profile/请求参数优先级与覆盖 |
| 预算测试 | 预算耗尽时正确拒绝 |
| 性能测试 | 本地单值 P99 < 50ms，批量 10 万行 < 30s |

## 12. 落地路线图

| 阶段 | 目标 |
|---|---|
| P0 | 实现 `PrivacyPrimitive` 抽象 + Python 本地 SDK（脱敏、K-匿名） |
| P1 | 添加 DP 本地函数 + 本地 Agent（REST） |
| P2 | 批量组件接入 SecretPad DAG（K-匿名、脱敏） |
| P3 | 查询混淆（QOL）+ 隐私预算台账 + 参数模板中心 |
| P4 | 多语言客户端 + gRPC + 企业级 KMS 集成 |
