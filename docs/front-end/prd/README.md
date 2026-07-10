# SecretPad 前端 PRD（产品需求文档）

> 版本：v1.0  
> 范围：`secretpad/frontend-src/apps/platform` 全部前端功能  
> 目标：为 UI 设计、前端开发、测试提供可直接执行的详细需求说明。  
> 原型方式：**低保真原型**（文本线框 + Mermaid 流程图），可直接导入飞书文档/墨刀进行可视化。

## 为什么选低保真方案

- 当前 SecretPad 已实现并运行，PRD 的核心价值是**把现有代码反向沉淀为可维护的需求资产**，而非从 0 到 1 探索设计。
- 低保真原型足够表达页面结构、信息层级、交互流程与字段规则，且能在纯文本/Markdown 中直接维护。
- 后续如需高保真，可将本文档中的线框与字段说明快速迁移到 Figma / 墨刀。

## 阅读顺序

| 序号 | 文档 | 说明 |
|---|---|---|
| 1 | [00-全局规范](./00-global-spec.md) | 布局、配色、组件、表单、表格、权限缺省、错误处理 |
| 2 | [10-核心流程](./10-core-flows.md) | 跨页面主流程：登录 → 创建项目 → 授权数据 → 编排 DAG → 运行 → 审批 → 发布模型 |
| 3 | 页面级 PRD | 按模块逐个阅读 |

## 页面级 PRD 清单

| 模块 | 文档 | 关键页面 |
|---|---|---|
| 登录与引导 | [01-登录与引导](./01-login-and-guide.md) | `/login`、`/guide` |
| Dashboard | [02-Dashboard](./02-dashboard.md) | `/dashboard` |
| 节点管理 | [03-节点管理](./03-node-management.md) | `/home?tab=node-management`、`/nodes`、`/my-node` |
| 数据与数据源 | [04-数据与数据源](./04-data-and-datasource.md) | `/data-source`、`/data-table`、`/edge?tab=data-source`、`/edge?tab=data-management` |
| 项目管理 | [05-项目管理](./05-project-management.md) | `/home?tab=project-management`、`/edge?tab=my-project`、创建项目 |
| DAG 画布 | [06-DAG 画布](./06-dag-canvas.md) | `/dag`、`/record`、`/model-submission`、`/periodic-task-detail` |
| 消息与审批 | [07-消息与审批](./07-message-and-approval.md) | `/message` |
| 模型与结果 | [08-模型与结果](./08-model-and-result.md) | 模型管理、结果管理 |

## 变更记录

| 日期 | 版本 | 变更内容 | 作者 |
|---|---|---|---|
| 2026-07-10 | v1.0 | 初稿：基于现有前端代码反推全部页面 PRD | Kimi Code CLI |
