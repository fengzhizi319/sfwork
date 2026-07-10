# SecretPad 后端产品需求文档

> 本文档基于当前 `secretpad/` 后端代码，从产品经理视角反推后端产品需求、领域模型、接口需求、集成需求与业务规则。面向后端开发、测试、架构师与产品经理。

## 文档结构

| 文件 | 内容 |
|---|---|
| [01-产品定位与边界](./01-product-positioning.md) | 后端在 SecretFlow 生态中的定位、目标、边界 |
| [02-部署模式与角色](./02-deployment-and-roles.md) | CENTER/EDGE/AUTONOMY/TEST 模式差异 |
| [03-领域模型](./03-domain-model.md) | 核心实体、关系、状态机 |
| [04-API 产品需求](./04-api-requirements.md) | 按业务域组织的 REST API 需求 |
| [05-集成需求](./05-integration-requirements.md) | Kuscia、SSE、P2P 同步、认证授权、签名 |
| [06-业务规则](./06-business-rules.md) | 审批流程、DAG 运行、数据授权、路由删除等 |
| [07-数据与持久化需求](./07-data-requirements.md) | 数据一致性、同步、备份、权限数据 |
| [08-非功能性需求](./08-non-functional-requirements.md) | 性能、安全、可观测性、兼容性 |

## 核心目标

SecretPad 后端是隐私计算平台的**业务编排与治理中心**，向上为前端提供 REST API，向下对接 Kuscia 调度引擎与 SecretFlow 算法运行时。它需要：

1. **多租户/多机构隔离**：项目、节点、数据、结果按机构和节点隔离。
2. **跨机构协作编排**：项目创建、数据授权、节点路由、模型发布都需要多方投票审批。
3. **DAG 到 Kuscia Job 的转换**：把前端画布翻译为 Kuscia 可执行的 Job。
4. **状态同步**：把 Kuscia 任务状态回流到 SecretPad，并同步给 CENTER/EDGE/P2P 各方。
5. **安全与审计**：登录鉴权、接口权限、投票签名、操作日志。
