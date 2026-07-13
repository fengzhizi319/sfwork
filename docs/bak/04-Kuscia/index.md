# 04-Kuscia

> Kuscia 部署、开发、架构、任务调度、组网、教程相关文档。

## 项目总览

| 文档 | 路径 | 说明 |
|---|---|---|
| Kuscia README | `../../kuscia/README.md` | Kuscia 总览（英文） |
| Kuscia README（中文） | `../../kuscia/README.zh-CN.md` | Kuscia 总览（中文） |
| 架构总览 | `../../kuscia/docs/reference/architecture_cn.md` | Kuscia 架构 |
| 设计文档 | `../../kuscia/docs/设计文档.md` | 中文设计文档 |
| 概述 | `../../kuscia/docs/reference/overview.md` | 参考概述 |
| 组网模式 | `../../kuscia/docs/组网模式.md` | 组网模式 |

## 部署

| 文档 | 路径 | 说明 |
|---|---|---|
| 部署说明 | `../../kuscia/docs/deployment/kuscia_deployment_instructions.md` | 部署总说明 |
| 部署检查 | `../../kuscia/docs/deployment/deploy_check.md` | 部署前检查 |
| Kuscia 配置 | `../../kuscia/docs/deployment/kuscia_config_cn.md` | 配置说明 |
| Kuscia 端口 | `../../kuscia/docs/deployment/kuscia_ports_cn.md` | 端口说明 |
| 本地部署 Kuscia + DataMesh | `../../kuscia/docs/deployment/local_deploy_kuscia_datamesh.md` | 本地部署 |
| 本地部署 SecretPad + Kuscia + DataMesh | `../../kuscia/docs/deployment/local_deploy_secretpad_kuscia_datamesh.md` | 联合本地部署 |
| 网络要求 | `../../kuscia/docs/deployment/networkrequirements.md` | 网络要求 |
| 运维操作 | `../../kuscia/docs/deployment/operation_cn.md` | 运维操作 |
| 日志说明 | `../../kuscia/docs/deployment/logdescription.md` | 日志说明 |
| Kuscia 监控 | `../../kuscia/docs/deployment/kuscia_monitor.md` | 监控 |
| 引擎监控 | `../../kuscia/docs/deployment/kuscia_engine_monitor.md` | 引擎监控 |
| RunP 部署 | `../../kuscia/docs/deployment/deploy_with_runp_cn.md` | RunP 模式 |

## 开发

| 文档 | 路径 | 说明 |
|---|---|---|
| 构建 Kuscia | `../../kuscia/docs/development/build_kuscia_cn.md` | 源码构建 |
| Kuscia Kubernetes 架构 | `../../kuscia/docs/development/kuscia_kubernetes_architecture.md` | K8s 架构 |
| 代码生成指南 | `../../kuscia/docs/development/code_generation_guide.md` | 代码生成 |
| Makefile 子模块详解 | `../../kuscia/docs/development/Makefile 子模块详解.md` | Makefile 说明 |
| Cobra 执行解析 | `../../kuscia/docs/development/cobra_execution_explanation.md` | CLI 命令解析 |
| 注册自定义镜像 | `../../kuscia/docs/development/register_custom_image.md` | 自定义镜像 |
| 添加 DataMesh IO | `../../kuscia/docs/development/add_datamesh_io.md` | DataMesh IO 扩展 |
| lint 修复总结 | `../../kuscia/docs/development/lint-fixes-summary.md` | lint 修复 |
| 贡献指南 | `../../kuscia/docs/CONTRIBUTING.md` | 贡献指南 |
| SecretFlow 源码二次开发 Docker 镜像打包指南 | `../../kuscia/SecretFlow 源码二次开发 Docker 镜像打包指南.md` | 镜像打包 |

## 架构与参考

| 文档 | 路径 | 说明 |
|---|---|---|
| 调度架构 | `../../kuscia/docs/reference/kuscia_scheduling_architecture_cn.md` | 调度架构 |
| DomainData 规范 | `../../kuscia/docs/reference/domaindata_specification.md` | DomainData 规范 |
| API 白名单 | `../../kuscia/docs/reference/api_whitelist_config_cn.md` | API 白名单 |
| Scripts 部署指南 | `../../kuscia/docs/reference/scripts_deploy_guide.md` | 脚本部署 |
| 任务调度 | `../../kuscia/docs/任务调度.md` | 任务调度 |
| 通信与数据注册流程 | `../../kuscia/docs/通信与数据注册流程.md` | 通信与注册 |
| 数据代理 | `../../kuscia/docs/数据代理.md` | 数据代理 |
| 联邦逻辑回归全流程 | `../../kuscia/docs/联邦逻辑回归全流程.md` | 联邦逻辑回归 |

## 教程

| 文档 | 路径 | 说明 |
|---|---|---|
| 快速开始 | `../../kuscia/docs/getting_started/quickstart_cn.md` | 快速开始 |
| 本地启动 Kuscia | `../../kuscia/docs/getting_started/如何本地启动Kuscia.md` | 本地启动 |
| 运行 SecretFlow | `../../kuscia/docs/getting_started/run_secretflow_cn.md` | 运行 SecretFlow |
| 通过 API 运行 SF Job | `../../kuscia/docs/tutorial/run_sf_job_with_api_cn.md` | API 运行 Job |
| 通过 API 运行 SF Serving | `../../kuscia/docs/tutorial/run_sf_serving_with_api_cn.md` | API 运行 Serving |
| 运行 SCQL | `../../kuscia/docs/tutorial/run_scql_on_kuscia_cn.md` | SCQL |
| 运行 FATE | `../../kuscia/docs/tutorial/run_fate_cn.md` | FATE |
| 运行 BFIA Job | `../../kuscia/docs/tutorial/run_bfia_job_cn.md` | BFIA |
| 运行 DP | `../../kuscia/docs/tutorial/run_dp_on_kuscia_cn.md` | 差分隐私 |
| 安全配置 | `../../kuscia/docs/tutorial/security_plan_cn.md` | 安全规划 |
| 升级引擎 | `../../kuscia/docs/tutorial/upgrade_engine.md` | 引擎升级 |
| 用户自定义服务路由 | `../../kuscia/docs/tutorial/user_defined_service_route.md` | 自定义路由 |
| Kuscia Gateway Path | `../../kuscia/docs/tutorial/kuscia_gateway_with_path.md` | Gateway Path |
| 自定义镜像仓库 | `../../kuscia/docs/tutorial/custom_registry.md` | 镜像仓库 |
| 配置渲染 | `../../kuscia/docs/tutorial/config_render.md` | 配置渲染 |
