# 04 API 产品需求

> 本节按业务域梳理后端需要暴露的 REST API 能力。所有接口前缀为 `/api/v1alpha1/`，返回统一结构 `SecretPadResponse<T>`。

## 4.1 认证与用户

### 4.1.1 认证

| 方法 | 端点 | 功能 | 关键需求 |
|---|---|---|---|
| POST | `/api/login` | 用户登录 | 校验账号密码，生成 Token，密码需哈希 |
| POST | `/api/v1alpha1/auth/logout` | 登出 | 销毁 Token 会话 |

### 4.1.2 用户

| 方法 | 端点 | 功能 | 关键需求 |
|---|---|---|---|
| POST | `/api/v1alpha1/user/get` | 当前用户信息 | 返回平台类型、部署模式、ownerId、权限 |
| POST | `/api/v1alpha1/user/updatePwd` | 修改密码 | 校验原密码，新密码复杂度 |
| POST | `/api/v1alpha1/user/node/resetPassword` | 重置节点用户密码 | 仅限机构管理员 |
| POST | `/api/v1alpha1/user/remote/resetPassword` | 远程转发重置密码 | EDGE 转发到 CENTER |

## 4.2 项目与作业

基路径：`/api/v1alpha1/project`

| 方法 | 端点 | 功能 | 关键需求 |
|---|---|---|---|
| POST | `/create` | 创建项目 | 校验名称唯一、模式合法、参与方存在 |
| POST | `/list` | 项目列表 | 按用户/节点权限过滤 |
| POST | `/get` | 项目详情 | 返回项目基础信息、参与节点、数据表 |
| POST | `/update` | 更新项目 | 仅发起方/管理员可编辑 |
| POST | `/delete` | 删除项目 | 校验无画布/任务 |
| POST | `/inst/add` | 添加机构 | 项目-机构关联 |
| POST | `/node/add` | 添加节点 | 项目-节点关联，校验节点类型匹配 |
| POST | `/datatable/add` | 添加数据表 | 同时创建 Kuscia DomainDataGrant |
| POST | `/datatable/delete` | 移除数据表 | 同时取消授权 |
| POST | `/datatable/get` | 数据表详情 | 含列配置 |
| POST | `/job/list` | 作业列表 | 分页 |
| POST | `/job/get` | 作业详情 | 含任务 Map 与状态 |
| POST | `/job/stop` | 停止作业 | 级联停止运行中任务 |
| POST | `/job/task/logs` | 任务日志 | 支持 Kuscia 日志或外部日志 |
| POST | `/job/task/output` | 任务输出 | 返回节点输出 schema |
| POST | `/tee/list` | TEE 节点列表 | 供枢纽模式选择 |
| POST | `/getOutTable` | 画布输出派生表 | 查询训练产生的派生表 |
| POST | `/update/tableConfig` | 更新列配置 | 修改项目数据表列信息 |
| POST | `/datasource/list` | 项目可用数据源 | 聚合参与方可用的数据源 |

### P2P 项目

基路径：`/api/v1alpha1/p2p/project`

| 方法 | 端点 | 功能 | 关键需求 |
|---|---|---|---|
| POST | `/create` | P2P 创建项目 | 创建投票请求 |
| POST | `/list` | P2P 项目列表 | 按发起/参与过滤 |
| POST | `/update` | P2P 项目更新 | 仅发起方 |
| POST | `/archive` | 项目归档 | 创建归档投票 |
| POST | `/participants` | 参与方详情 | 返回各机构状态 |

## 4.3 DAG / 训练流

| 方法 | 端点 | 功能 | 关键需求 |
|---|---|---|---|
| POST | `/component/i18n` | 组件国际化 | 返回组件名/参数翻译 |
| POST | `/component/list` | 组件分类 | 按分类返回组件树 |
| POST | `/component/batch` | 批量查询组件定义 | 用于画布渲染 |
| POST | `/graph/create` | 创建画布 | 校验项目存在 |
| POST | `/graph/delete` | 删除画布 | 校验无运行中任务 |
| POST | `/graph/list` | 列出画布 | 按项目过滤 |
| POST | `/graph/meta/update` | 更新画布元数据 | 名称等 |
| POST | `/graph/update` | 全量更新画布 | 节点与边列表 |
| POST | `/graph/node/update` | 更新单个节点 | 节点位置、参数 |
| POST | `/graph/start` | 运行画布 | 拓扑排序、生成 Job、提交 Kuscia |
| POST | `/graph/node/status` | 节点状态 | 查询运行中节点状态 |
| POST | `/graph/stop` | 停止画布 | 停止关联 Job |
| POST | `/graph/detail` | 画布详情 | 返回节点、边、元数据 |
| POST | `/graph/node/output` | 节点输出 | 返回输出 schema |
| POST | `/graph/node/logs` | 节点日志 | 查询日志 |
| POST | `/graph/node/max_index` | 刷新节点最大序号 | 生成新节点 ID 时使用 |

## 4.4 数据与数据源

### 文件上传/下载

| 方法 | 端点 | 功能 | 关键需求 |
|---|---|---|---|
| POST | `/api/v1alpha1/data/upload` | 上传本地 CSV | 支持 multipart，落盘到节点 |
| POST | `/api/v1alpha1/data/download` | 下载数据 | 受数据权限控制 |

### 数据表

| 方法 | 端点 | 功能 | 关键需求 |
|---|---|---|---|
| POST | `/api/v1alpha1/datatable/create` | 创建数据表 | 基于数据源创建 DomainData |
| POST | `/api/v1alpha1/datatable/list` | 数据表列表 | 按节点过滤 |
| POST | `/api/v1alpha1/datatable/get` | 数据表详情 | 含 schema |
| POST | `/api/v1alpha1/datatable/delete` | 删除数据表 | 校验未授权 |
| POST | `/api/v1alpha1/datatable/pushToTee` | 推送 TEE | 仅 LOCAL 类型 |

### 数据源

| 方法 | 端点 | 功能 | 关键需求 |
|---|---|---|---|
| POST | `/api/v1alpha1/datasource/create` | 创建数据源 | OSS/ODPS/MySQL/HTTP |
| POST | `/api/v1alpha1/datasource/delete` | 删除数据源 | 校验无关联数据表 |
| POST | `/api/v1alpha1/datasource/list` | 数据源列表 | 聚合多节点 |
| POST | `/api/v1alpha1/datasource/detail` | 数据源详情 | 脱敏展示连接信息 |
| POST | `/api/v1alpha1/datasource/nodes` | 归属节点 | 查询哪些节点有该数据源 |

## 4.5 节点与路由

### 节点

| 方法 | 端点 | 功能 | 关键需求 |
|---|---|---|---|
| POST | `/api/v1alpha1/node/create` | 创建节点 | 在 Kuscia 创建 Domain |
| POST | `/api/v1alpha1/node/update` | 更新节点地址 | 同步 Kuscia |
| POST | `/api/v1alpha1/node/page` | 分页查询节点 | 按平台类型过滤 |
| POST | `/api/v1alpha1/node/get` | 节点详情 | 含状态、token、证书 |
| POST | `/api/v1alpha1/node/delete` | 删除节点 | 校验无任务/路由 |
| POST | `/api/v1alpha1/node/token` | 获取现有 Token | 管理用途 |
| POST | `/api/v1alpha1/node/newToken` | 生成新 Token | 使旧 Token 失效 |
| POST | `/api/v1alpha1/node/refresh` | 刷新节点状态 | 查询 Kuscia Domain 状态 |
| POST | `/api/v1alpha1/node/list` | 节点列表 | 简化列表 |
| POST | `/api/v1alpha1/node/result/list` | 节点结果产物 | 按节点过滤 |
| POST | `/api/v1alpha1/node/result/detail` | 结果详情 | 元数据与 DAG 快照 |

### 节点路由

| 方法 | 端点 | 功能 | 关键需求 |
|---|---|---|---|
| POST | `/api/v1alpha1/nodeRoute/page` | 路由分页 | 合作节点列表 |
| POST | `/api/v1alpha1/nodeRoute/get` | 路由详情 | 含状态 |
| POST | `/api/v1alpha1/nodeRoute/update` | 更新路由地址 | 同步 Kuscia |
| POST | `/api/v1alpha1/nodeRoute/listNode` | 可建路由节点 | 过滤已有路由 |
| POST | `/api/v1alpha1/nodeRoute/refresh` | 刷新路由状态 | 查询 DomainRoute |
| POST | `/api/v1alpha1/nodeRoute/delete` | 删除路由 | 校验无运行中作业 |

### 机构

| 方法 | 端点 | 功能 | 关键需求 |
|---|---|---|---|
| POST | `/api/v1alpha1/inst/get` | 当前机构详情 | 含节点列表 |
| POST | `/api/v1alpha1/inst/node/list` | 机构下节点 | 按机构过滤 |
| POST | `/api/v1alpha1/inst/node/add` | 机构创建节点 | 带证书上传 |
| POST | `/api/v1alpha1/inst/node/token` | 节点 Token | 管理 |
| POST | `/api/v1alpha1/inst/node/newToken` | 刷新 Token | 管理 |
| POST | `/api/v1alpha1/inst/node/delete` | 删除节点 | 校验 |
| POST | `/api/v1alpha1/inst/node/register` | Kuscia 节点注册 | multipart 证书 |

## 4.6 审批与消息

### 审批

| 方法 | 端点 | 功能 | 关键需求 |
|---|---|---|---|
| POST | `/api/v1alpha1/approval/create` | 发起审批/投票 | 生成签名消息 |
| POST | `/api/v1alpha1/approval/pull/status` | 查询资源审批状态 | TEE 下载等 |

### 消息

| 方法 | 端点 | 功能 | 关键需求 |
|---|---|---|---|
| POST | `/api/v1alpha1/message/reply` | 投票回复 | 签名验证、状态流转 |
| POST | `/api/v1alpha1/message/list` | 消息列表 | 按我处理的/发起的过滤 |
| POST | `/api/v1alpha1/message/detail` | 消息详情 | 投票进度 |
| POST | `/api/v1alpha1/message/pending` | 待处理数 | Header 铃铛展示 |

### 投票同步

| 方法 | 端点 | 功能 | 关键需求 |
|---|---|---|---|
| POST | `/api/v1alpha1/vote_sync/create` | EDGE 向 CENTER 同步投票 | 推送本地投票 |

## 4.7 模型管理

| 方法 | 端点 | 功能 | 关键需求 |
|---|---|---|---|
| POST | `/api/v1alpha1/model/page` | 模型包分页 | 按项目过滤 |
| POST | `/api/v1alpha1/model/detail` | 模型包详情 | 参与方 schema |
| POST | `/api/v1alpha1/model/info` | 模型信息 | 训练图、样本表、Serving |
| POST | `/api/v1alpha1/model/serving/create` | 创建在线服务 | 调用 Kuscia Serving |
| POST | `/api/v1alpha1/model/serving/detail` | 服务详情 | 地址、资源 |
| POST | `/api/v1alpha1/model/serving/delete` | 删除服务 | 级联清理 |
| POST | `/api/v1alpha1/model/discard` | 废弃模型包 | 状态流转 |
| POST | `/api/v1alpha1/model/delete` | 删除模型包 | 校验无服务 |
| POST | `/api/v1alpha1/model/pack` | 导出模型包 | 异步打包 |
| POST | `/api/v1alpha1/model/status` | 查询导出状态 | 轮询用 |
| POST | `/api/v1alpha1/model/modelPartyPath` | 参与方路径 | 多机构下载 |

## 4.8 系统、调度、同步与日志

### 组件版本

| 方法 | 端点 | 功能 | 关键需求 |
|---|---|---|---|
| POST | `/api/v1alpha1/version/list` | 组件版本列表 | SecretFlow 组件版本 |

### 定时调度

| 方法 | 端点 | 功能 | 关键需求 |
|---|---|---|---|
| POST | `/api/v1alpha1/scheduled/id` | 生成调度 ID | 幂等 |
| POST | `/api/v1alpha1/scheduled/graph/once/success` | 验证一次性运行成功 | 创建周期任务前置条件 |
| POST | `/api/v1alpha1/scheduled/graph/create` | 创建周期任务 | Cron 表达式 |
| POST | `/api/v1alpha1/scheduled/page` | 调度列表 | 分页 |
| POST | `/api/v1alpha1/scheduled/offline` | 下线调度 | 暂停 Quartz |
| POST | `/api/v1alpha1/scheduled/del` | 删除调度 | 清理 Quartz |
| POST | `/api/v1alpha1/scheduled/info` | 调度详情 | Cron、参数 |
| POST | `/api/v1alpha1/scheduled/task/page` | 调度任务分页 | 历史执行 |
| POST | `/api/v1alpha1/scheduled/task/stop` | 停止任务 | 停止运行中实例 |
| POST | `/api/v1alpha1/scheduled/task/rerun` | 重跑任务 | 手动触发 |
| POST | `/api/v1alpha1/scheduled/task/info` | 任务详情 | 状态、日志 |
| POST | `/api/v1alpha1/scheduled/job/list` | 调度关联作业 | 追踪血缘 |

### 数据同步

| 方法 | 端点 | 功能 | 关键需求 |
|---|---|---|---|
| GET | `/sync` | CENTER → EDGE SSE | Server-Sent Events |
| POST | `/api/v1alpha1/data/sync` | P2P 数据同步 | 接收对端 SyncDataDTO |
| POST | `/api/v1alpha1/vote_sync/create` | 投票同步 | EDGE → CENTER |

### 云日志

| 方法 | 端点 | 功能 | 关键需求 |
|---|---|---|---|
| POST | `/api/v1alpha1/cloud_log/sls` | 查询外部日志 | 对接 SLS/ELK |

## 4.9 API 设计原则

1. **统一返回结构**：`{ data, status, message }`。
2. **业务错误码**：通过 `status.message` 携带可读业务错误，HTTP 状态码保持 200（除认证异常）。
3. **分页规范**：请求 `{ pageNum, pageSize, ...filter }`，返回 `{ list, total, pageNum, pageSize }`。
4. **幂等性**：创建类接口支持客户端传入唯一键或返回冲突提示。
5. **权限注解**：所有业务接口使用 `@ApiResource` 或 `@DataResource` 声明。
