# 03-后端开发

> SecretPad 后端（Spring Boot）开发相关文档，包括产品需求、API 设计、存储、集成、本地运行。

## 项目总览

| 文档 | 路径 | 说明 |
|---|---|---|
| SecretPad README | `../../secretpad/README.md` | 后端仓库总览（英文） |
| SecretPad README（中文） | `../../secretpad/README.zh-CN.md` | 后端仓库总览（中文） |
| SecretPad 设计文档 | `../../secretpad/docs/SecretPad设计文档.md` | 后端总体设计 |
| 运行说明 | `../../secretpad/运行说明.md` | 后端运行说明 |
| macOS 运行说明 | `../../secretpad/macos运行说明.md` | macOS 下运行说明 |

## 产品需求

| 文档 | 路径 | 说明 |
|---|---|---|
| 01 产品定位 | `../../docs/back-end/01-product-positioning.md` | 后端产品定位 |
| 02 部署与角色 | `../../docs/back-end/02-deployment-and-roles.md` | 部署模式与角色 |
| 03 领域模型 | `../../docs/back-end/03-domain-model.md` | 领域模型 |
| 04 API 需求 | `../../docs/back-end/04-api-requirements.md` | API 需求 |
| 05 集成需求 | `../../docs/back-end/05-integration-requirements.md` | 外部集成需求 |
| 06 业务规则 | `../../docs/back-end/06-business-rules.md` | 业务规则 |
| 07 数据需求 | `../../docs/back-end/07-data-requirements.md` | 数据需求 |
| 08 非功能需求 | `../../docs/back-end/08-non-functional-requirements.md` | 非功能需求 |
| 后端 README | `../../docs/back-end/README.md` | 后端文档目录说明 |

## 核心模块与技术文档

| 文档 | 路径 | 说明 |
|---|---|---|
| 存储说明 | `../../secretpad/docs/development/SecretPad存储说明.md` | 数据库与存储 |
| 数据层 | `../../secretpad/docs/development/data_layer.md` | 数据访问层 |
| 操作层 | `../../secretpad/docs/development/operations_layer.md` | 业务操作层 |
| API 与 Kuscia/DataMesh 集成 | `../../secretpad/docs/development/api_and_kuscia_datamesh_integration.md` | 与 Kuscia/DataMesh 集成 |
| client-java-kusciaapi 模块 | `../../secretpad/docs/development/client-java-kusciaapi模块技术文档.md` | Kuscia API Java 客户端 |
| 前端接口自动生成说明 | `../../secretpad/docs/development/前端接口自动生成说明.md` | 接口生成 |
| 流程图 | `../../secretpad/docs/流程图.md` | 后端流程图 |
| 配置文档 | `../../secretpad/docs/配置文档.md` | 后端配置说明 |

## 本地开发

| 文档 | 路径 | 说明 |
|---|---|---|
| 本地运行指南 | `../../secretpad/docs/development/local_run_guide.md` | 本地运行 SecretPad |
| 构建 MVP | `../../secretpad/docs/development/build_mvp.md` | MVP 构建 |
| 构建 SecretPad | `../../secretpad/docs/development/build_secretpad_cn.md` | 中文构建指南 |
| IDEA 运行说明 | `../../secretpad/docs/development/ru_in_idea_cn.md` | IntelliJ IDEA 配置 |
| 支持 MySQL | `../../secretpad/docs/development/SUPPORT_MYSQL.md` | MySQL 适配 |
| 数据库版本 | `../../secretpad/docs/development/db_version.md` | Flyway 版本管理 |
| 部署检查 | `../../secretpad/docs/development/deploy_check.md` | 部署前检查 |
| 部署 SecretPad | `../../secretpad/docs/development/deploy_secretpad.md` | 部署指南 |

## 关键流程

| 文档 | 路径 | 说明 |
|---|---|---|
| Kuscia / SecretFlow / DataMesh 集成 | `../../secretpad/docs/KUSCIA_SECRETFLOW_INTEGRATION.md` | 集成总览 |
| Kuscia Task 到 SecretFlow Flow 转换 | `../../secretpad/docs/KUSCIA_TASK_TO_SECRETFLOW_FLOW.md` | 任务转换 |
| Kuscia-To-SecretFlow Task Conversion | `../../secretpad/docs/Kuscia-To-SecretFlow-Task-Conversion.md` | 英文版转换说明 |
| SecretPad-DataMesh-FL-Flow | `../../secretpad/docs/SecretPad-DataMesh-FL-Flow.md` | DataMesh 联邦学习流程 |
| 联邦学习流程 | `../../secretpad/docs/FEDERATED_LEARNING_FLOW.md` | 联邦学习流程 |
| 前后端 Kuscia 及 SecretFlow 算法模块联调与 Bug 定位指南 | `../../docs/前后端Kuscia及SecretFlow算法模块联调与Bug定位指南.md` | 联调与问题定位 |

## 可观测与运维

| 文档 | 路径 | 说明 |
|---|---|---|
| Prometheus 使用 | `../../secretpad/docs/development/prometheus_usage.md` | 监控指标 |
| 支持 SLS 云日志 | `../../secretpad/docs/development/support_sls_cloud_log.md` | 日志服务接入 |
