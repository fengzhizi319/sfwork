# SecretPad 后端配置说明

## 1. 后端职责

SecretPad 后端不直接执行分类分级算法，只负责：

1. 加载 SecretFlow 组件元数据（`config/components/secretflow.json`）。
2. 加载组件 i18n 文案（`config/i18n/secretflow.json`）。
3. 通过 `/api/v1alpha1/component/list`、`/component/batch`、`/component/i18n` 接口暴露给前端。
4. 在 DAG 运行时，将 `privacy/data_classification` 节点的 `NodeDef` 转换为 `NodeEvalParam` 并提交给 Kuscia。

因此，新增组件后只需刷新上述两个 JSON 文件并重启后端即可。

## 2. 刷新组件元数据

在 SecretFlow 环境已安装且组件代码已就绪后，执行：

```bash
cd /home/charles/code/sfwork/secretflow
source $(conda info --base)/etc/profile.d/conda.sh && conda activate sf310

secretflow component inspect -a \
  > /home/charles/code/sfwork/secretpad/config/components/secretflow.json

secretflow component get_translation \
  > /home/charles/code/sfwork/secretpad/config/i18n/secretflow.json
```

执行后，确认 `secretflow.json` 中包含：

```json
{
  "domain": "privacy",
  "name": "data_classification",
  "version": "1.0.0",
  ...
}
```

## 3. 补充 i18n 文案

`secretflow component get_translation` 会自动生成组件名、描述、参数名的英文/中文文案。若生成不完整，手动补充 `secretpad/config/i18n/secretflow.json`：

```json
"privacy/data_classification:1.0.0": {
  "privacy": "隐私计算",
  "data_classification": "数据分类分级",
  "mode": "模式",
  "auto": "自动模式",
  "default_level": "默认敏感度等级",
  "advanced": "高级模式",
  "enable_rule_engine": "启用规则引擎",
  "enable_small_ner": "启用 Small-NER（v1 未实现）",
  "enable_llm": "启用 LLM（v1 未实现）",
  "icd10_l4_intervals_json": "ICD-10 L4 区间（JSON）",
  "manual_override_json": "字段强制等级覆盖（JSON）",
  "input_ds": "输入数据集",
  "output_ds": "输出数据集",
  "report": "分类报告"
}
```

## 4. 同步测试资源

SecretPad 单元测试使用独立的资源目录，需同步更新：

```bash
cp /home/charles/code/sfwork/secretpad/config/components/secretflow.json \
   /home/charles/code/sfwork/secretpad/secretpad-service/src/test/resources/config/components/secretflow.json

cp /home/charles/code/sfwork/secretpad/config/i18n/secretflow.json \
   /home/charles/code/sfwork/secretpad/secretpad-service/src/test/resources/config/i18n/secretflow.json
```

## 5. 验证后端加载

启动 SecretPad 后端后，调用接口验证：

```bash
curl -X POST http://127.0.0.1:8080/api/v1alpha1/component/list \
  -H "Content-Type: application/json" \
  -d '{}' | grep -o '"privacy/data_classification"'

curl -X POST http://127.0.0.1:8080/api/v1alpha1/component/batch \
  -H "Content-Type: application/json" \
  -d '{"comps":[{"domain":"privacy","name":"data_classification","version":"1.0.0"}]}'
```

若能返回组件定义，说明后端配置成功。

## 6. 注意事项

- 组件隐藏配置：如需默认不在前端面板显示，可在 `config/application.yaml` 的 `secretpad.component.hide` 中增加 `secretflow/privacy/data_classification:1.0.0`。本功能不需要隐藏。
- 后端不感知训练流模板：模板完全由前端管理，后端只保存 DAG 实例。
