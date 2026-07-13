# 后端 API 与前端字段对接矩阵

> 本文档将前端页面中的字段、操作与后端 REST API 进行一一映射，便于前后端联调、测试用例编写与接口评审。

## 约定

- 所有接口前缀为 `/api/v1alpha1/`（除 `/api/login`、`/api/logout`）。
- 请求/响应字段名使用后端 DTO/VO 命名风格（驼峰）。
- `←` 表示后端返回给前端的字段；`→` 表示前端提交给后端的字段。

---

## 1. 认证与用户

### 1.1 登录页（/login）

| 前端字段/操作 | 接口 | 请求字段 | 响应字段 | 说明 |
|---|---|---|---|---|
| 账号 | `POST /api/login` | `userName` → | — | 必填，4-32 字符 |
| 密码 | `POST /api/login` | `passwordHash` → | — | 前端 SHA256 后提交 |
| 登录 | `POST /api/login` | — | `← data.token` `← data.userInfo` | 成功后缓存 Token |
| 登出 | `POST /api/v1alpha1/auth/logout` | `token` → | — | 清除本地 Token |

### 1.2 全局 Header

| 前端字段 | 来源 | 说明 |
|---|---|---|
| `User-Token` | `POST /api/login` 返回的 `data.token` | 所有受保护接口放入 Header |
| `kuscia-origin-source` | 后端内部 RPC 自动注入 | 前端无需处理 |

### 1.3 用户菜单（Header 头像下拉）

| 前端字段 | 接口 | 响应字段 | 说明 |
|---|---|---|---|
| 用户名/平台类型 | `POST /api/v1alpha1/user/get` | `← userName` `← platformType` `← deployMode` `← ownerId` | 登录后获取 |
| 修改密码 | `POST /api/v1alpha1/user/updatePwd` | `→ oldPassword` `→ newPassword` | 新密码需复杂度校验 |

---

## 2. Dashboard（/dashboard）

| 前端字段/操作 | 接口 | 请求/响应字段 | 说明 |
|---|---|---|---|
| Projects 数量 | `POST /api/v1alpha1/index/statistic`（或对应统计接口） | `← projectCount` | 点击跳转项目列表 |
| Nodes 数量 | 同上 | `← nodeCount` | 点击跳转节点列表 |
| DataTables 数量 | 同上 | `← datatableCount` | 点击跳转数据表列表 |
| Graphs 数量 | 同上 | `← graphCount` | 点击跳转训练流列表 |
| Recent Projects | `POST /api/v1alpha1/project/list` | `→ pageNum=1, pageSize=5` `← list[].projectId` `← list[].projectName` `← list[].gmtCreate` | 最近创建 |
| Recent Nodes | `POST /api/v1alpha1/node/page` | `→ pageNum=1, pageSize=5` `← list[].nodeId` `← list[].nodeName` `← list[].status` | 最近注册 |
| System Health | 待定监控接口 | `← cpuUsage` `← memoryUsage` `← diskUsage` `← networkStatus` | 后续对接真实监控 |

---

## 3. 节点管理

### 3.1 Center 节点注册（/home?tab=node-management、/nodes）

| 前端字段/操作 | 接口 | 请求/响应字段 | 说明 |
|---|---|---|---|
| 节点列表 | `POST /api/v1alpha1/node/page` | `→ pageNum, pageSize, nodeId?, nodeName?, mode?` `← list[].nodeId` `← list[].nodeName` `← list[].netAddress` `← list[].mode` `← list[].status` | 分页列表 |
| 新增节点 | `POST /api/v1alpha1/node/create` | `→ nodeId, nodeName, netAddress, mode, description, certText?, keyText?` | 创建 Kuscia Domain |
| 编辑节点地址 | `POST /api/v1alpha1/node/update` | `→ nodeId, netAddress` | 更新通讯地址 |
| 刷新状态 | `POST /api/v1alpha1/node/refresh` | `→ nodeId` `← status` | 查询 Kuscia Domain 状态 |
| 删除节点 | `POST /api/v1alpha1/node/delete` | `→ nodeId` | 校验无任务/路由 |
| Token 管理 | `POST /api/v1alpha1/node/token` / `newToken` | `→ nodeId` `← token` | 获取/重新生成 Token |

### 3.2 我的节点（/my-node）

| 前端字段 | 接口 | 响应字段 | 说明 |
|---|---|---|---|
| 节点基础信息 | `POST /api/v1alpha1/node/get` | `← nodeId` `← nodeName` `← netAddress` `← protocol` `← certConfig` `← publicKey` `← authCode` `← token` | 含敏感信息 |
| 节点实例列表 | `POST /api/v1alpha1/inst/node/list` 或 `node/get` 内部 | `← instances[].hostName` `← instances[].status` `← instances[].version` `← instances[].gmtCreate` `← instances[].lastHeartbeat` | 展示实例 |
| 切换节点（AUTONOMY） | 本地切换 `ownerId` 后重载 | — | 重调用上述接口 |

---

## 4. 数据与数据源

### 4.1 数据源管理（/data-source、/edge?tab=data-source）

| 前端字段/操作 | 接口 | 请求/响应字段 | 说明 |
|---|---|---|---|
| 数据源列表 | `POST /api/v1alpha1/datasource/list` | `→ type?, status?` `← list[].datasourceId` `← list[].name` `← list[].type` `← list[].status` `← list[].gmtCreate` `← list[].gmtModified` | 聚合多节点 |
| 数据源详情 | `POST /api/v1alpha1/datasource/detail` | `→ datasourceId` `← datasourceId` `← name` `← type` `← info`（JSON） | 查看完整 Definition |
| 新增数据源 | `POST /api/v1alpha1/datasource/create` | `→ name, type, info` | info 为 JSON |
| 编辑数据源 | `POST /api/v1alpha1/datasource/update`（如存在） | `→ datasourceId, name, info` | 视后端实现 |
| 删除数据源 | `POST /api/v1alpha1/datasource/delete` | `→ datasourceId` | 校验无关联数据表 |

### 4.2 数据表管理（/data-table、/edge?tab=data-management、/node?tab=table）

| 前端字段/操作 | 接口 | 请求/响应字段 | 说明 |
|---|---|---|---|
| 数据表列表 | `POST /api/v1alpha1/datatable/list` | `→ nodeId?, datatableId?, status?` `← list[].datatableId` `← list[].datatableName` `← list[].datasourceType` `← list[].nodeId` `← list[].status` `← list[].authProjects` `← list[].teeUploadStatus` | 含授权项目 |
| 数据表详情 | `POST /api/v1alpha1/datatable/get` | `→ datatableId, nodeId` `← datatableId` `← datatableName` `← schema`（JSON）`← datasourceId` | Schema 展示 |
| 新增数据表 | `POST /api/v1alpha1/datatable/create` | `→ datatableName, datasourceId, nodeId, description, schema` | 基于数据源创建 DomainData |
| 删除数据表 | `POST /api/v1alpha1/datatable/delete` | `→ datatableId, nodeId` | 校验未授权 |
| 授权管理 | `POST /api/v1alpha1/project/datatable/add` / `delete` | `→ projectId, datatableId, nodeId` | 勾选/取消授权 |
| 推送 TEE | `POST /api/v1alpha1/datatable/pushToTee` | `→ datatableId, nodeId` | 仅 LOCAL 类型 |

---

## 5. 项目管理

### 5.1 Center 项目列表（/home?tab=project-management）

| 前端字段/操作 | 接口 | 请求/响应字段 | 说明 |
|---|---|---|---|
| 项目列表 | `POST /api/v1alpha1/project/list` | `→ projectName?, computeMode?` `← list[].projectId` `← list[].projectName` `← list[].computeMode` `← list[].nodeNum` `← list[].graphNum` `← list[].jobNum` `← list[].gmtCreate` | 卡片展示 |
| 项目详情 | `POST /api/v1alpha1/project/get` | `→ projectId` `← projectId` `← projectName` `← computeMode` `← nodes[]` `← datatables[]` | 进入项目空间前加载 |
| 创建项目 | `POST /api/v1alpha1/project/create` | `→ projectName, description, computeMode, templateId?, nodeIds[]` | 直接创建 |
| 更新项目 | `POST /api/v1alpha1/project/update` | `→ projectId, projectName, description` | 编辑信息 |
| 删除项目 | `POST /api/v1alpha1/project/delete` | `→ projectId` | 输入名称二次确认 |

### 5.2 P2P 我的项目（/edge?tab=my-project）

| 前端字段/操作 | 接口 | 请求/响应字段 | 说明 |
|---|---|---|---|
| P2P 项目列表 | `POST /api/v1alpha1/p2p/project/list` | `→ filterType（initiated/processed/all）, status?, computeMode?` `← list[].projectId` `← list[].projectName` `← list[].status` `← list[].authProgress` `← list[].instNum` `← list[].graphNum` `← list[].jobNum` | 含授权进度 |
| P2P 创建项目 | `POST /api/v1alpha1/p2p/project/create` | `→ projectName, description, computeMode, instIds[]` | 创建投票 |
| P2P 更新项目 | `POST /api/v1alpha1/p2p/project/update` | `→ projectId, projectName, description` | 仅发起方 |
| P2P 归档 | `POST /api/v1alpha1/p2p/project/archive` | `→ projectId` | 发起归档投票 |
| 参与方详情 | `POST /api/v1alpha1/p2p/project/participants` | `→ projectId` `← list[].instId` `← list[].instName` `← list[].status` | 展示投票进度 |

---

## 6. DAG 画布（/dag）

### 6.1 页面初始化

| 前端字段 | 接口 | 响应字段 | 说明 |
|---|---|---|---|
| 项目信息 | `POST /api/v1alpha1/project/get` | `← projectId` `← projectName` `← computeMode` | 顶部标题 |
| 项目数据表 | `POST /api/v1alpha1/project/datasource/list` 或 `datatable/get` | `← datatables[]` | 左侧数据集面板 |
| 训练流列表 | `POST /api/v1alpha1/graph/list` | `→ projectId` `← list[].graphId` `← list[].graphName` | 左侧训练流树 |
| 组件列表 | `POST /api/v1alpha1/component/list` | `→ ...` `← list[].codeName` `← list[].label` `← list[].category` `← list[].version` | 左侧组件库 |
| 组件定义 | `POST /api/v1alpha1/component/batch` | `→ codeNames[]` `← list[].codeName` `← list[].attrs[]` `← list[].inputs[]` `← list[].outputs[]` | 渲染节点与表单 |

### 6.2 画布操作

| 前端操作 | 接口 | 请求/响应字段 | 说明 |
|---|---|---|---|
| 保存画布 | `POST /api/v1alpha1/graph/update` | `→ projectId, graphId, nodes[], edges[], maxIndex` | 全量更新 |
| 创建训练流 | `POST /api/v1alpha1/graph/create` | `→ projectId, graphName` | 左侧训练流树 |
| 更新画布元数据 | `POST /api/v1alpha1/graph/meta/update` | `→ projectId, graphId, graphName` | 重命名 |
| 更新单个节点 | `POST /api/v1alpha1/graph/node/update` | `→ projectId, graphId, nodeId, nodeDef, x, y` | 位置/参数 |
| 删除训练流 | `POST /api/v1alpha1/graph/delete` | `→ projectId, graphId` | 校验无运行任务 |
| 运行画布 | `POST /api/v1alpha1/graph/start` | `→ projectId, graphId, selectedNodeIds?` | 返回 jobId |
| 停止画布 | `POST /api/v1alpha1/graph/stop` | `→ projectId, graphId` | 停止关联 Job |
| 画布详情 | `POST /api/v1alpha1/graph/detail` | `→ projectId, graphId` `← graphId` `← graphName` `← nodes[]` `← edges[]` | 加载画布 |

### 6.3 运行状态与日志

| 前端字段 | 接口 | 响应字段 | 说明 |
|---|---|---|---|
| 节点状态 | `POST /api/v1alpha1/graph/node/status` 或轮询 | `→ projectId, graphId, jobId` `← nodes[].nodeId` `← nodes[].status` | 状态色环 |
| 节点日志 | `POST /api/v1alpha1/graph/node/logs` | `→ projectId, jobId, taskId` `← logs` | 日志抽屉 |
| 节点输出 | `POST /api/v1alpha1/graph/node/output` | `→ projectId, jobId, taskId` `← outputSchema` | 结果抽屉 |
| 记录列表 | `POST /api/v1alpha1/project/job/list` | `→ projectId` `← list[].jobId` `← list[].status` `← list[].gmtCreate` | 右侧记录抽屉 |

---

## 7. 消息与审批（/message）

| 前端字段/操作 | 接口 | 请求/响应字段 | 说明 |
|---|---|---|---|
| 消息列表 | `POST /api/v1alpha1/message/list` | `→ type?, status?, filterType（processed/initiated）` `← list[].voteId` `← list[].title` `← list[].initiatorId` `← list[].participantId` `← list[].voteType` `← list[].status` `← list[].gmtCreate` | Tab + 筛选 |
| 待处理消息数 | `POST /api/v1alpha1/message/pending` | — `← pendingCount` | Header 铃铛 |
| 消息详情 | `POST /api/v1alpha1/message/detail` | `→ voteId` `← voteId` `← initiator` `← voteType` `← status` `← participants[].instId` `← participants[].action` | 投票进度 |
| 同意/拒绝 | `POST /api/v1alpha1/message/reply` | `→ voteId, action（APPROVE/REJECT）, reason?, voteParticipantId` | 签名回复 |

---

## 8. 模型与结果

### 8.1 模型管理

| 前端字段/操作 | 接口 | 请求/响应字段 | 说明 |
|---|---|---|---|
| 模型包列表 | `POST /api/v1alpha1/model/page` | `→ projectId, pageNum, pageSize, status?` `← list[].modelId` `← list[].modelName` `← list[].description` `← list[].status` `← list[].gmtCreate` | 状态标签 |
| 模型包详情 | `POST /api/v1alpha1/model/detail` | `→ modelId` `← modelId` `← modelName` `← parties[]` | 参与方 schema |
| 发布模型 | `POST /api/v1alpha1/model/serving/create` | `→ modelId, projectId, resourceConfig` | 状态变为发布中 |
| 服务详情 | `POST /api/v1alpha1/model/serving/detail` | `→ servingId` `← status` `← endpoint` `← resourceConfig` | 服务抽屉 |
| 下线/删除服务 | `POST /api/v1alpha1/model/serving/delete` | `→ servingId` | — |
| 废弃模型包 | `POST /api/v1alpha1/model/discard` | `→ modelId` | 状态流转 |
| 删除模型包 | `POST /api/v1alpha1/model/delete` | `→ modelId` | 校验无服务 |
| 模型提交 | `POST /api/v1alpha1/model/pack` | `→ projectId, graphId, modelNodeIds[]` | 异步打包 |
| 提交状态 | `POST /api/v1alpha1/model/status` | `→ packId` `← status` `← progress` | 轮询 |

### 8.2 结果管理

| 前端字段/操作 | 接口 | 请求/响应字段 | 说明 |
|---|---|---|---|
| 结果列表 | `POST /api/v1alpha1/node/result/list` | `→ nodeId?, projectId?, type?` `← list[].resultId` `← list[].type` `← list[].projectName` `← list[].graphId` `← list[].nodeId` `← list[].gmtCreate` | 按节点/项目过滤 |
| 结果详情 | `POST /api/v1alpha1/node/result/detail` | `→ resultId` `← resultId` `← type` `← projectName` `← graphSnapshot` | DAG 快照 |
| 下载结果 | `POST /api/v1alpha1/data/download` | `→ resultId / datatableId` | 受权限与数据源类型限制 |

---

## 9. 系统与调度

### 9.1 周期任务（/dag → 周期任务）

| 前端字段/操作 | 接口 | 请求/响应字段 | 说明 |
|---|---|---|---|
| 调度列表 | `POST /api/v1alpha1/scheduled/page` | `→ projectId, pageNum, pageSize` `← list[].scheduleId` `← list[].cron` `← list[].status` | UP/DOWN |
| 创建调度 | `POST /api/v1alpha1/scheduled/graph/create` | `→ projectId, graphId, cron, jobRequest` | 需先一次性成功 |
| 下线调度 | `POST /api/v1alpha1/scheduled/offline` | `→ scheduleId` | 暂停 Quartz |
| 删除调度 | `POST /api/v1alpha1/scheduled/del` | `→ scheduleId` | — |
| 调度任务列表 | `POST /api/v1alpha1/scheduled/task/page` | `→ scheduleId` `← list[].taskId` `← list[].status` | 历史执行 |
| 停止任务 | `POST /api/v1alpha1/scheduled/task/stop` | `→ taskId` | — |
| 重跑任务 | `POST /api/v1alpha1/scheduled/task/rerun` | `→ taskId` | 手动触发 |

### 9.2 组件版本

| 前端字段 | 接口 | 响应字段 | 说明 |
|---|---|---|---|
| 组件版本列表 | `POST /api/v1alpha1/version/list` | `← list[].version` `← list[].default` | 画布组件版本选择 |

---

## 10. 文件上传/下载

| 前端操作 | 接口 | 请求/响应字段 | 说明 |
|---|---|---|---|
| 上传本地 CSV | `POST /api/v1alpha1/data/upload` | `multipart/form-data: file, nodeId` `← datatableId` | 本地数据上传 |
| 下载数据/结果 | `POST /api/v1alpha1/data/download` | `→ datatableId 或 resultId` | 浏览器触发下载 |

---

## 11. 跨页面公共状态

| 前端状态 | 来源接口 | 说明 |
|---|---|---|
| 当前用户信息 | `POST /api/v1alpha1/user/get` | platformType、deployMode、ownerId、apiResources |
| 未处理消息数 | `POST /api/v1alpha1/message/pending` | Header 铃铛 |
| 组件解释器 | `POST /api/v1alpha1/component/batch` | DAG 配置表单渲染依赖 |

---

## 12. 对接矩阵速查表

| 前端页面 | 主要接口 | 接口数量 |
|---|---|---|
| /login | `/api/login` | 1 |
| /dashboard | `/index/statistic`, `/project/list`, `/node/page` | 3 |
| /home 节点注册 | `/node/page`, `/node/create`, `/node/update`, `/node/refresh`, `/node/delete` | 5 |
| /nodes | 同上 | 5 |
| /my-node | `/node/get`, `/node/newToken`, `/inst/node/list` | 3 |
| /data-source | `/datasource/list`, `/datasource/detail`, `/datasource/create`, `/datasource/delete` | 4 |
| /data-table | `/datatable/list`, `/datatable/get`, `/datatable/create`, `/datatable/delete`, `/datatable/pushToTee`, `/project/datatable/add` | 6 |
| /home 项目管理 | `/project/list`, `/project/get`, `/project/create`, `/project/update`, `/project/delete` | 5 |
| /edge?tab=my-project | `/p2p/project/list`, `/p2p/project/create`, `/p2p/project/update`, `/p2p/project/archive`, `/p2p/project/participants` | 5 |
| /dag | `/project/get`, `/graph/list`, `/graph/detail`, `/graph/create`, `/graph/update`, `/graph/start`, `/graph/stop`, `/component/list`, `/component/batch`, `/project/job/list`, `/graph/node/status`, `/graph/node/logs`, `/graph/node/output` | 13 |
| /message | `/message/list`, `/message/detail`, `/message/reply`, `/message/pending` | 4 |
| 模型管理 | `/model/page`, `/model/detail`, `/model/serving/create`, `/model/serving/detail`, `/model/serving/delete`, `/model/discard`, `/model/delete`, `/model/pack`, `/model/status` | 9 |
| 结果管理 | `/node/result/list`, `/node/result/detail`, `/data/download` | 3 |
| 周期任务 | `/scheduled/page`, `/scheduled/graph/create`, `/scheduled/offline`, `/scheduled/del`, `/scheduled/task/page`, `/scheduled/task/stop`, `/scheduled/task/rerun` | 7 |
