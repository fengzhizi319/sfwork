# 06 业务规则

## 6.1 项目创建与审批

### CENTER 模式
1. 用户填写项目基础信息、选择计算模式与参与节点。
2. 后端校验：
   - 项目名称唯一性。
   - 参与节点存在且类型与计算模式匹配。
   - 当前用户有权限操作这些节点。
3. 直接创建项目，状态为 `APPROVED`。

### P2P 模式
1. 用户填写项目信息并选择参与机构。
2. 后端为每个参与机构生成 `VoteInvite`。
3. 项目状态为 `REVIEWING`。
4. 所有受邀机构同意后，项目状态变为 `APPROVED`。
5. 任一机构拒绝，项目状态变为 `ARCHIVED`（或 `REJECTED`）。

## 6.2 画布运行规则

1. `GraphService.startGraph` 校验：
   - 项目状态正常（未归档）。
   - 节点与路由健康。
   - 选中节点及其上游依赖可构成完整子图。
2. 生成 `ProjectJob` 与 `ProjectTask`。
3. 经 JobChain 转换为 `Job.CreateJobRequest`。
4. 调用 Kuscia 创建 Job。
5. 通过 `watchJob` 回流状态。

### 运行范围
- 未选中任何节点：运行整个画布。
- 选中节点：只运行该节点及其上游依赖。

### 停止规则
- `ProjectJob.stop()` 级联停止所有 `INITIALIZED` 或 `RUNNING` 任务。
- 调用 Kuscia 停止 Job。

## 6.3 数据授权规则

1. 项目添加数据表时，后端调用 `DatatableGrantManager` 在 Kuscia 侧创建/更新 `DomainDataGrant`。
2. 移除项目数据表时取消授权。
3. P2P 模式下数据表查询需通过本地机构节点作为目标节点。
4. 已授权到项目的数据表不可删除。

## 6.4 节点路由规则

1. 创建路由时，后端在 Kuscia 中双向创建 `DomainRoute`。
2. 删除路由前校验：
   - 无运行中项目作业关联该路由。
   - 非内置路由。
3. 删除时双向清理 Kuscia `DomainRoute` 与本地 `NodeRouteDO`。

## 6.5 投票审批通用流程

```mermaid
sequenceDiagram
    actor Initiator as 发起方
    participant BE as SecretPad 后端
    participant Vote as VoteRequest/Invite
    participant K as Kuscia

    Initiator ->> BE: 发起审批
    BE ->> BE: preCheck（身份、状态、资源）
    BE ->> BE: 生成 voteId、签名消息
    BE ->> Vote: 创建 VoteRequest + VoteInvite
    BE -->> Initiator: 返回 voteId

    loop 各参与方回复
        Participant ->> BE: 同意/拒绝 + 签名
        BE ->> BE: 校验签名与身份
        BE ->> Vote: 更新 VoteInvite.action
    end

    alt 达到通过阈值
        BE ->> K: 执行回调（创建项目/路由/授权/允许下载）
        K -->> BE: 成功
        BE ->> Vote: 状态 APPROVED
    else 任一拒绝
        BE ->> Vote: 状态 REJECTED
    end
```

### 投票类型

| 类型 | Handler | 通过后的动作 |
|---|---|---|
| PROJECT_CREATE | `ProjectCreateMessageHandler` | 创建项目 |
| PROJECT_ARCHIVE | `ProjectArchiveHandler` | 归档项目 |
| PROJECT_NODE_ADD | `ProjectNodeAddHandler` | 项目新增节点 |
| NODE_ROUTE | `NodeRouteMessageHandler` | 创建节点路由 |
| TEE_DOWNLOAD | `TeeDownLoadMessageHandler` | 允许 TEE 结果下载 |

## 6.6 模型发布规则

1. 用户从 DAG 画布选择模型组件提交到模型管理。
2. 模型包初始状态为“待发布”。
3. 调用 `/model/serving/create` 后状态变为“发布中”。
4. Kuscia Serving 创建成功后状态变为“已发布”。
5. 已发布模型可下线（状态“已下线”）或废弃（状态“已废弃”）。
6. P2P 模式下仅模型 owner 可发布。
7. 已归档项目不可发布模型。

## 6.7 节点删除规则

1. 校验节点无运行中任务。
2. 校验节点无未删除路由。
3. 内置节点（alice/bob/tee）不可删除。
4. 在 Kuscia 中删除 Domain 后清理本地 `NodeDO`。

## 6.8 数据表删除规则

1. 校验数据表未授权到任何项目。
2. 在 Kuscia 中删除 DomainData。
3. 清理本地 `DatatableDO` 与相关授权记录。

## 6.9 定时调度规则

1. 创建周期任务前，必须有一次性运行成功的记录。
2. 周期任务状态：UP / DOWN。
3. 任务实例状态：INITIALIZED / RUNNING / SUCCEED / FAILED / STOPPED。
4. 下线调度后不再生成新任务实例。
5. 删除调度时清理 Quartz 任务与历史任务实例（视策略）。
