# 01-架构设计

> 系统整体架构、模块设计、数据模型、接口映射、HLD/LLD 相关文档。

## 项目级架构

| 文档 | 路径 | 说明 |
|---|---|---|
| 项目总结 | `../../PROJECT_SUMMARY.md` | sfwork 整体架构英文概述 |
| 项目总结（中文） | `../../项目总结.md` | sfwork 整体架构中文概述 |
| c-life 隐私计算平台白皮书 | `../00-项目总览/数据分类分级与本地隐私原语-团队汇报与落地白皮书.md` | 识别 → 处理 → 协同 三层能力体系 |
| 隐私计算平台开发计划 | `../../docs/隐私计算平台开发计划.md` | 开发阶段与里程碑规划 |
| 前后端 Kuscia 及 SecretFlow 算法模块联调与 Bug 定位指南 | `../../docs/前后端Kuscia及SecretFlow算法模块联调与Bug定位指南.md` | 跨模块联调与问题定位 |
| API 与前端映射 | `../../docs/api-frontend-mapping.md` | 前端页面与后端 API 的映射关系 |
| CI/CD 设计 | `../../docs/ci-cd-design.md` | 持续集成与持续部署设计 |

## SecretPad 后端架构

| 文档 | 路径 | 说明 |
|---|---|---|
| SecretPad 设计文档 | `../../secretpad/docs/SecretPad设计文档.md` | 后端总体设计 |
| 01 产品定位 | `../../docs/back-end/01-product-positioning.md` | 后端产品定位 |
| 03 领域模型 | `../../docs/back-end/03-domain-model.md` | 领域模型设计 |
| 04 API 需求 | `../../docs/back-end/04-api-requirements.md` | API 设计需求 |
| 05 集成需求 | `../../docs/back-end/05-integration-requirements.md` | 与 Kuscia/DataMesh 集成 |
| 06 业务规则 | `../../docs/back-end/06-business-rules.md` | 业务规则说明 |
| 07 数据需求 | `../../docs/back-end/07-data-requirements.md` | 数据需求 |
| 08 非功能需求 | `../../docs/back-end/08-non-functional-requirements.md` | 性能、安全等非功能需求 |
| Kuscia / SecretFlow / DataMesh 集成 | `../../secretpad/docs/KUSCIA_SECRETFLOW_INTEGRATION.md` | 后端与 Kuscia 集成 |
| Kuscia Task 到 SecretFlow Flow 转换 | `../../secretpad/docs/KUSCIA_TASK_TO_SECRETFLOW_FLOW.md` | 任务转换流程 |
| DataMesh FL Flow | `../../secretpad/docs/SecretPad-DataMesh-FL-Flow.md` | DataMesh 联邦学习流程 |
| 存储说明 | `../../secretpad/docs/development/SecretPad存储说明.md` | 数据库与存储设计 |
| 数据层 | `../../secretpad/docs/development/data_layer.md` | 数据访问层 |
| 操作层 | `../../secretpad/docs/development/operations_layer.md` | 业务操作层 |
| API 与 Kuscia/DataMesh 集成 | `../../secretpad/docs/development/api_and_kuscia_datamesh_integration.md` | 后端集成细节 |
| 流程图 | `../../secretpad/docs/流程图.md` | 后端流程图汇总 |

## SecretPad 前端架构

| 文档 | 路径 | 说明 |
|---|---|---|
| 前端设计文档 | `../../secretpad/docs/前端设计文档.md` | 前端总体设计 |
| 01 产品定位 | `../../docs/front-end/01-product-positioning.md` | 前端产品定位 |
| 02 用户角色与权限 | `../../docs/front-end/02-user-roles-and-permissions.md` | 权限模型 |
| 03 信息架构 | `../../docs/front-end/03-information-architecture.md` | 信息架构 |
| 05 UI 线框图 | `../../docs/front-end/05-ui-wireframes.md` | 线框图 |
| 06 交互规范 | `../../docs/front-end/06-interaction-spec.md` | 交互规范 |
| DAG SDK 架构（中文） | `../../secretpad-frontend/packages/dag/README.md` | DAG 图引擎 SDK |
| DAG SDK 架构（英文） | `../../secretpad-frontend/packages/dag/README.en-US.md` | DAG SDK English |

## Kuscia 架构

| 文档 | 路径 | 说明 |
|---|---|---|
| 架构总览 | `../../kuscia/docs/reference/architecture_cn.md` | Kuscia 架构总览 |
| Kuscia Kubernetes 架构 | `../../kuscia/docs/development/kuscia_kubernetes_architecture.md` | K8s 架构 |
| 调度架构 | `../../kuscia/docs/reference/kuscia_scheduling_architecture_cn.md` | 任务调度架构 |
| 设计文档 | `../../kuscia/docs/设计文档.md` | 中文设计文档汇总 |
| 组网模式 | `../../kuscia/docs/组网模式.md` | 组网模式说明 |
| 通信与数据注册流程 | `../../kuscia/docs/通信与数据注册流程.md` | 通信与注册 |
| 数据代理 | `../../kuscia/docs/数据代理.md` | 数据代理机制 |
| 任务调度 | `../../kuscia/docs/任务调度.md` | 任务调度机制 |
| DomainData 规范 | `../../kuscia/docs/reference/domaindata_specification.md` | DomainData 定义 |

## 隐私组件架构

| 文档 | 路径 | 说明 |
|---|---|---|
| 隐私组件 HLD | `../../docs/privacy-component-hld.md` | 高层设计 |
| 隐私组件 LLD | `../../docs/privacy-component-lld.md` | 低层设计 |
| 隐私组件实现 | `../../docs/privacy-component-implementation.md` | 实现细节 |
| 隐私组件开发指南 | `../../docs/privacy-component-development-guide.md` | 开发指南 |
| 隐私组件部署 | `../../docs/privacy-component-deployment.md` | 部署说明 |
| 隐私组件测试 | `../../docs/privacy-component-testing.md` | 测试方案 |
