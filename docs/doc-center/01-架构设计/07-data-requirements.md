# 07 数据与持久化需求

## 7.1 持久化策略

- 默认使用 SQLite，生产环境可选 MySQL。
- 使用 JPA + Hibernate 进行 ORM 映射。
- 使用 Flyway 管理数据库迁移脚本。
- Quartz 调度器使用 JDBC JobStore。

## 7.2 数据一致性要求

| 场景 | 一致性要求 | 实现方式 |
|---|---|---|
| 项目创建 | 本地 DB + Kuscia Domain 最终一致 | 创建失败后重试或告警 |
| 数据授权 | SecretPad DB + Kuscia DomainDataGrant 最终一致 | 授权回调确认 |
| 作业状态 | SecretPad DB 与 Kuscia Job 状态最终一致 | watchJob 事件驱动 |
| 多节点同步 | CENTER/EDGE/AUTONOMY 间最终一致 | SSE / 主动 Push + 增量同步 |
| 投票状态 | 多方最终一致 | 签名消息 + 同步 |

## 7.3 核心数据表（按域）

### 项目与组织
- `project`
- `project_inst`
- `project_node`
- `inst`
- `node`
- `node_route`

### 画布与作业
- `project_graph`
- `project_graph_node`
- `project_graph_node_kuscia_params`
- `project_job`
- `project_task`

### 数据
- `project_datatable`
- `project_fed_table`
- `project_read_data`
- `feature_table`
- `project_feature_table`
- `project_graph_domain_datasource`
- `tee_node_datatable_management`

### 结果与模型
- `project_result`
- `project_report`
- `project_model`
- `project_model_pack`
- `project_model_serving`
- `project_rule`

### 审批与投票
- `vote_request`
- `vote_invite`
- `project_approval_config`
- `node_route_approval_config`
- `tee_download_audit_config`

### 用户与权限
- `accounts`
- `tokens`
- `sys_role`
- `sys_resource`
- `sys_user_permission_rel`
- `sys_user_node_rel`

### 调度与同步
- `project_schedule`
- `project_schedule_job`
- `project_schedule_task`
- `edge_data_sync_log`

## 7.4 数据隔离要求

- **项目级隔离**：用户只能看到自己有权限的项目。
- **节点级隔离**：EDGE 模式下只能看到本地节点的数据表与结果。
- **机构级隔离**：P2P 模式下各方数据独立存储，通过同步共享元数据。
- **数据级权限**：通过 `@DataResource` 控制对特定项目/节点数据的访问。

## 7.5 审计与日志

- 关键操作（创建项目、授权、发布模型、删除节点）需记录操作日志。
- 投票请求与回复需保存原始签名消息，便于事后审计。
- Token 使用记录保存最后使用时间，用于会话管理。

## 7.6 备份与恢复

- 生产环境需定期备份数据库。
- 节点证书、Token 等敏感信息需加密存储或接入 KMS。
- 备份恢复后需重新建立与 Kuscia 的 gRPC 连接与 watchJob。
