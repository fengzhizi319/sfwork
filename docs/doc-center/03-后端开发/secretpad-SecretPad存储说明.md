# SecretPad 存储说明

## 概述

SecretPad 采用了双存储架构，结合了传统关系型数据库和 Kubernetes CRD（Custom Resource Definition）系统。这种架构设计既满足了业务数据的持久化需求，又支持了分布式协调和弹性扩展能力。

## 存储架构

### 1. SecretPad 数据库 (关系型数据库)

#### 存储内容
- **项目元数据**: 项目基本信息、配置、权限设置
- **任务执行记录**: 任务状态、执行时间、错误日志、进度信息（结构化存储，非简单log文件）
- **数据资产信息**: 数据表元数据、数据源配置、数据授权关系
- **模型输出**: 训练结果、预测结果、评估指标等
- **调度配置**: 任务调度策略、资源分配、依赖关系
- **用户信息**: 用户账户、角色权限、审计日志
- **系统配置**: 全局配置参数、系统设置

#### 任务执行日志详细说明

**1. 存储机制**
- **数据库表**: `project_job_task_log`
- **字段结构**:
  - `id`: 自增主键
  - `project_id`: 项目ID
  - `job_id`: 作业ID
  - `task_id`: 任务ID
  - `log`: 日志内容（TEXT类型，格式化文本）
  - `gmt_create`: 创建时间（自动记录）

**2. 日志格式示例**
```
2023-05-30 10:00:00 INFO the jobId=xxx, taskId=yyy start ...
2023-05-30 10:05:00 INFO the jobId=xxx, taskId=yyy succeed
2023-05-30 10:05:00 INFO the jobId=xxx, taskId=yyy failed: error message details
```

**3. 记录触发时机**（事件驱动）
- 任务状态转换时自动记录：
  - `STAGING/INITIALIZED` → `RUNNING`: 任务开始
  - `RUNNING` → `SUCCEED`: 任务成功
  - `RUNNING` → `FAILED`: 任务失败（包含错误信息）
  - `RUNNING` → `STOPPED`: 任务停止
- 通过 `JobTaskLogEventListener` 监听 `TaskStatusTransformEvent` 事件

**4. 查询方式**
- **Repository接口**: `ProjectJobTaskLogRepository.findAllByJobTaskId(jobId, taskId)`
- **查询条件**: 按 `jobId` + `taskId` 组合查询
- **排序**: 按创建时间升序排列
- **返回**: 完整的任务执行历史日志列表

**5. 前后端实现**

**后端API实现**:
- **Controller**: [ProjectController.getJobLog()](file://\\wsl.localhost\Ubuntu\home\charles\code\sfwork\secretpad\secretpad-web\src\main\java\org\secretflow\secretpad\web\controller\ProjectController.java#L265-L271)
  - 路径: `POST /api/v1alpha1/project/job/task/logs`
  - 请求参数: `{ projectId, jobId, taskId }`
  - 返回: `GraphNodeTaskLogsVO { status, logs[] }`

- **Service实现**: [ProjectServiceImpl.getProjectJobTaskLogs()](file://\\wsl.localhost\Ubuntu\home\charles\code\sfwork\secretpad\secretpad-service\src\main\java\org\secretflow\secretpad\service\impl\ProjectServiceImpl.java#L574-L585)
  - 验证项目和作业权限
  - 从数据库查询日志记录
  - 去重处理（去除重复的start/succeed日志）
  - 返回任务状态和日志列表

**前端实现**:
- **服务层**: [dag-log.service.ts](file:///home/charles/code/sfwork/secretpad/frontend-src/apps/platform/src/modules/dag-log/dag-log.service.ts)
  - `getLogContent()`: 获取日志内容
  - 支持两种模式:
    - `from='pipeline'`: 调用 `getGraphNodeLogs()` (图节点日志)
    - `from='record'`: 调用 `getJobLog()` (历史记录日志)
  - 自动轮询: 对于running/pending状态，每2秒刷新一次
  - 日志格式化: 将 `\n` 转换为换行符

- **UI组件**:
  - [log-viewer.view.tsx](file:///home/charles/code/sfwork/secretpad/frontend-src/apps/platform/src/modules/dag-log/log-viewer.view.tsx): 日志查看器（基于Monaco Editor）
  - [log.drawer.layout.tsx](file:///home/charles/code/sfwork/secretpad/frontend-src/apps/platform/src/modules/dag-log/log.drawer.layout.tsx): 日志抽屉布局
  - 功能特性:
    - 语法高亮（log语言）
    - 只读模式
    - 自动换行
    - 折叠支持
    - 实时刷新

- **使用场景**:
  1. **DAG编排页面**: 点击节点查看当前执行日志
  2. **历史记录页面**: 查看已完成任务的执行日志
  3. **周期性任务**: 查看定时任务的执行历史

#### 数据库表结构示例
- `project_job`: 项目作业信息
- `project_task`: 项目任务信息
- `project_job_task_log`: 任务执行日志
- `project_result`: 项目结果数据
- `data_source`: 数据源配置
- `data_table`: 数据表信息
- `node_info`: 节点信息
- `job_result_summary`: 任务结果摘要
- `user_audit_log`: 用户操作审计日志

#### 存储接口
- **DAO 层接口**: 基于 MyBatis 的数据访问接口
  - `ProjectJobMapper`: 项目作业数据访问
  - `ProjectTaskMapper`: 项目任务数据访问
  - `DataTableMapper`: 数据表数据访问
  - `DataSourceMapper`: 数据源数据访问
- **Service 层接口**: 业务逻辑封装
  - `ProjectJobService`: 项目作业服务
  - `ProjectTaskService`: 项目任务服务
  - `DataTableService`: 数据表服务
  - `DataSourceService`: 数据源服务
- **API 接口**: RESTful 接口
  - `/api/v1alpha1/project/job`: 项目作业管理接口
  - `/api/v1alpha1/data/datasource`: 数据源管理接口
  - `/api/v1alpha1/data/datatable`: 数据表管理接口

#### 数据生命周期
- **短期数据** (1-7天): 临时任务日志、调试信息
- **中期数据** (1-6个月): 任务执行记录、中间结果
- **长期数据** (6个月以上): 项目元数据、最终结果、审计日志
- **归档数据** (1年以上): 历史项目数据、统计报告

#### 数据清理策略详解

**1. 软删除机制**
- **实现方式**: 所有核心表均包含 `is_deleted` 字段（tinyint(1)，默认值为0）
- **删除操作**: 不物理删除数据，仅将 `is_deleted` 标记为 1
- **查询过滤**: 所有查询自动过滤 `is_deleted = 1` 的记录
- **优势**: 
  - 支持数据恢复和审计追溯
  - 保持外键引用完整性
  - 避免级联删除风险

**2. 自动清理任务**
- **定时任务调度**: 基于 Spring `@Scheduled` 注解实现
- **同步监听器**: [DbChangeEventListener](file://\\wsl.localhost\Ubuntu\home\charles\code\sfwork\secretpad\secretpad-service\src\main\java\org\secretflow\secretpad\service\listener\DbChangeEventListener.java#L106-L114)
  - 执行频率: 每 3 秒检查一次（`fixedRate = 3000`）
  - 初始延迟: 1 秒后开始执行（`initialDelay = 1000`）
  - 功能: 监听数据库变更事件，触发数据同步
- **投票状态监控**: 
  - `VoteInviteStatusMonitor`: 监控投票邀请状态（每 1 秒检查）
  - `VoteRequestStatusMonitor`: 监控投票请求状态（每 1 秒检查）
- **边缘节点同步**: `EdgeSyncTask` 每 5 秒同步一次边缘节点数据

**3. Kuscia CRD 自动清理**
- **TTL 机制**: Kubernetes 原生 TTL（Time-To-Live）支持
- **GC 策略**: 
  - 已完成任务自动垃圾回收
  - 失败任务保留一定时间供排查
  - 可通过配置调整保留期限
- **状态同步后清理**: SecretPad 同步任务状态到本地数据库后，可安全清理 Kuscia CRD

**4. 手动清理接口**
- **管理员权限**: 仅提供给系统管理员使用
- **清理范围**: 
  - 指定时间范围的历史任务日志
  - 已归档项目的关联数据
  - 过期的投票和审批记录
- **安全措施**: 
  - 操作前强制备份
  - 记录审计日志
  - 支持事务回滚

**5. 归档机制**
- **归档条件**: 
  - 项目状态为 ARCHIVED
  - 任务完成超过指定天数（可配置）
  - 用户主动申请归档
- **归档流程**:
  1. 将数据从主表迁移到归档表（如 `project_job_archive`）
  2. 更新原记录的 `is_deleted` 标记
  3. 可选：导出到外部存储（OSS、S3等）
- **归档查询**: 提供专门的归档数据查询接口，性能较低但可访问历史数据

### 2. Kuscia CRD 存储 (Kubernetes etcd)

#### 存储内容
- **KusciaJob**: 联邦学习作业定义（包含任务模板、参与方、调度配置等）
- **KusciaTask**: 具体任务实例（包含任务输入配置、参与方信息、调度配置等）
- **DomainData**: 数据资产定义（数据表元数据、列定义、文件格式等）
- **DomainDataSource**: 数据源定义（数据源类型、连接信息、访问方式等）
- **DomainDataGrant**: 数据授权关系（授权域、使用限制、过期时间等）
- **KusciaDeployment**: 部署配置信息
- **Domain**: 参与方域信息

#### 存储接口
- **gRPC 接口**:
  - `kuscia.proto.api.v1alpha1.kusciaapi.job.JobService`: 作业管理服务
  - `kuscia.proto.api.v1alpha1.kusciaapi.datasource.DataSourceService`: 数据源管理服务
  - `kuscia.proto.api.v1alpha1.kusciaapi.domaindata.DomainDataService`: 数据资产管理服务
- **Kubernetes API**:
  - `GET /apis/kuscia.secretflow/v1alpha1/namespaces/{namespace}/kusciajobs`: 获取作业列表
  - `POST /apis/kuscia.secretflow/v1alpha1/namespaces/{namespace}/kusciajobs`: 创建作业
  - `GET /apis/kuscia.secretflow/v1alpha1/namespaces/{namespace}/domaindatasources`: 获取数据源
- **SecretPad 内部接口**:
  - `KusciaGrpcClientAdapter`: gRPC 客户端适配器
  - `DomainDataSourceRpc`: 数据源远程调用接口
  - `DomainDataRpc`: 数据资产远程调用接口

#### 数据生命周期
- **瞬时数据**: 任务执行期间的临时状态信息
- **运行时数据**: 任务运行期间的配置和状态 (几小时到几天)
- **短期保留**: 任务完成后立即删除的临时数据
- **中期保留**: 任务历史记录 (几周到几个月)
- **长期保留**: 重要的配置信息和元数据 (几个月到几年)

#### 数据清理策略
- **自动 GC**: Kuscia 自动清理已完成的任务资源
- **TTL 机制**: 为不同类型的 CRD 设置生存时间
- **手动清理**: 通过 Kubectl 或 API 手动删除资源
- **状态同步**: 定期同步状态到 SecretPad 数据库后清理 CRD

## 数据流向

### 1. 任务创建流程
```
前端提交任务 → SecretPad 后端 → 保存到后端数据库 → 转发到 Kuscia → Kuscia CRD 存储
```
**详细步骤**:
1. **前端请求**: 用户通过 DAG 编辑器配置任务，点击“执行”按钮
2. **参数校验**: SecretPad 后端验证项目权限、节点状态、数据表可用性
3. **持久化**: 将 Job/Task 元数据写入 `project_job` 和 `project_task` 表
4. **Kuscia 转发**: 调用 Kuscia gRPC API 创建 KusciaJob/KusciaTask CRD
5. **状态初始化**: 设置任务状态为 STAGING/INITIALIZED
6. **事件发布**: 发布 `TaskStatusTransformEvent` 事件，触发日志记录
7. **返回响应**: 向前端返回 jobId 和 taskId

### 2. 数据存储层次
```
真实数据文件 (底层存储) → DataMesh 抽象 → DomainData/DomainDataSource → Kubernetes etcd
```
**存储层级说明**:
- **L0 - 原始数据层**: CSV、Parquet、数据库表等实际数据文件
- **L1 - DataMesh 层**: 统一数据访问接口，屏蔽底层存储差异
- **L2 - 元数据层**: DomainData（数据表定义）、DomainDataSource（数据源配置）
- **L3 - 编排层**: KusciaJob/KusciaTask（任务调度和执行）
- **L4 - 业务层**: SecretPad 数据库（项目管理、审计、统计）

### 3. 状态同步机制
- **定期同步**: SecretPad 定期从 Kuscia 同步任务状态到本地数据库
  - 同步频率: 可配置（默认每 5-10 秒）
  - 同步内容: 任务状态、错误信息、完成时间
- **事件通知**: 通过 webhook 机制接收 Kuscia 的状态变更通知
  - 实时性高，但可能存在丢包风险
  - 作为定期同步的补充
- **补偿机制**: 如果状态不同步，会触发补偿同步流程
  - 检测不一致: 对比本地数据库和 Kuscia CRD 状态
  - 自动修复: 以 Kuscia 为准更新本地状态
  - 告警通知: 记录异常并通知管理员

### 4. 数据同步架构（多节点场景）

#### CENTER 模式（中心化）
```
边缘节点 A --SSE--> 中心节点 <--SSE-- 边缘节点 B
                  (SecretPad Master)
```
- **同步方式**: Server-Sent Events (SSE) 长连接
- **同步方向**: 中心节点向边缘节点推送变更
- **同步实体**: 项目、节点、数据表、投票等（见 `data.sync` 配置）
- **失败重试**: 使用缓冲区 `DataSyncDataBufferTemplate` 存储失败事件
- **监听器**: [DbChangeEventListener](file://\\wsl.localhost\Ubuntu\home\charles\code\sfwork\secretpad\secretpad-service\src\main\java\org\secretflow\secretpad\service\listener\DbChangeEventListener.java)
  - 监听 JPA 实体变更事件
  - 过滤需要同步的表
  - 推送到对应节点的 SSE 会话

#### P2P 模式（点对点）
```
节点 A <--> 节点 B <--> 节点 C
```
- **同步方式**: 节点间直接通信（gRPC/HTTP）
- **同步方向**: 双向同步
- **冲突解决**: 基于时间戳的最后写入获胜（Last-Write-Wins）
- **适用场景**: 去中心化部署，无单点故障

## 存储组件

### 1. SecretPad Persistence 模块

#### 主要职责
- 数据库实体定义（Entity/DO）
- 数据访问层实现（Repository/Mapper）
- 事务管理（@Transactional）
- 数据库迁移（Flyway）
- 软删除逻辑封装
- 数据同步事件发布

#### 技术实现
- **ORM 框架**: 
  - Spring Data JPA（主要使用 Repository 模式）
  - MyBatis（部分复杂查询场景）
- **连接池**: HikariCP（Spring Boot 默认，高性能 JDBC 连接池）
- **事务管理**: Spring 声明式事务（@Transactional）
  - 传播行为: REQUIRED（默认）
  - 隔离级别: READ_COMMITTED
  - 回滚策略: RuntimeException 自动回滚
- **缓存**: 
  - Ehcache（本地缓存，配置文件 `ehcache.xml`）
  - Caffeine（代码级缓存，用于高频小数据）
  - Redis（分布式缓存，可选配置）
- **数据库迁移**: Flyway
  - 迁移脚本位置: `config/schema/{center|edge|p2p}/`
  - 版本控制: V1__xxx.sql, V2__xxx.sql
  - 基线策略: baseline-on-migrate = true

#### 核心 Repository 示例
```java
// 任务日志仓库
ProjectJobTaskLogRepository extends BaseRepository<ProjectJobTaskLogDO, String>
  - findAllByJobTaskId(jobId, taskId): 按任务和作业查询日志
  - saveAll(logs): 批量保存日志

// 项目作业仓库  
ProjectJobRepository extends JpaRepository<ProjectJobDO, String>
  - findByProjectId(projectId): 查询项目下所有作业
  - countByProjectId(projectId): 统计项目作业数量

// 数据表仓库
DataTableRepository extends JpaRepository<DataTableDO, String>
  - findByNodeId(nodeId): 按节点查询数据表
  - findByDomainDataId(domainDataId): 按域数据ID查询
```

#### 索引优化策略
- **唯一索引**: 业务主键组合（如 `upk_project_job_task_id` on project_id, job_id, task_id）
- **普通索引**: 常用查询字段（如 `key_project_name` on project.name）
- **复合索引**: 多字段联合查询（如 `idx_project_job_task_log` on project_id, job_id, task_id）
- **覆盖索引**: 减少回表查询，提升性能

### 2. Kuscia API 客户端

#### 主要职责
- 与 Kuscia API 服务器通信
- CRD 资源的 CRUD 操作
- 资源状态监听

#### 技术实现
- **gRPC 客户端**: 与 Kuscia API 服务器通信
- **协议缓冲区**: 使用 Protobuf 进行数据序列化
- **资源监听**: Watch 机制监听资源变化

## 故障处理与补偿机制

### 1. 失败回滚
- 如果 Kuscia 创建失败，数据库事务回滚
- 确保数据的一致性和完整性

### 2. 状态同步
- 定期从 Kuscia 同步任务状态到本地数据库
- 保持两个存储系统之间的一致性

### 3. 异常处理
- 捕获异常并记录详细错误信息
- 提供重试机制和降级策略

## 性能优化

### 1. 数据库优化
- **索引优化**: 
  - 为常用查询字段建立索引（如 project_id, job_id, task_id）
  - 复合索引覆盖多字段查询场景
  - 避免过度索引影响写入性能
- **分区表**: 对大数据量表进行分区（可选）
  - 按时间分区: 适合日志类数据
  - 按项目分区: 适合多租户场景
- **读写分离**: 支持主从数据库分离（MySQL 场景）
  - 主库: 处理写操作
  - 从库: 处理读操作，提升并发能力
- **连接池优化**: HikariCP 参数调优
  ```yaml
  spring:
    datasource:
      hikari:
        maximum-pool-size: 10        # 最大连接数
        minimum-idle: 5              # 最小空闲连接
        connection-timeout: 5000     # 连接超时 5 秒
        idle-timeout: 60000          # 空闲超时 60 秒
        max-lifetime: 1800000        # 连接最大生命周期 30 分钟
  ```
- **批量操作**: 使用 `saveAll()` 而非循环 `save()`
- **懒加载**: 避免 N+1 查询问题

### 2. 缓存策略
- **本地缓存**: 
  - Ehcache: 配置文件 `ehcache.xml`，适合集群内共享
  - Caffeine: 代码级注解 `@Cacheable`，高性能本地缓存
  - 缓存内容: 组件列表、国际化配置、节点信息
- **分布式缓存**: Redis（可选配置）
  - 适用场景: 多实例部署，需要跨实例共享缓存
  - 缓存内容: 用户会话、热点数据
- **查询缓存**: 
  - JPA 二级缓存: 缓存实体对象
  - 自定义缓存: 复杂查询结果缓存
- **缓存失效策略**: 
  - TTL（Time-To-Live）: 固定过期时间
  - LRU（Least Recently Used）: 最近最少使用淘汰
  - 主动失效: 数据更新时清除相关缓存

### 3. 异步处理
- **消息队列**: （预留扩展，当前未实现）
  - RocketMQ / Kafka: 处理异步任务
  - 应用场景: 大规模任务调度、事件驱动架构
- **Spring Event**: 当前使用的轻量级异步机制
  - `TaskStatusTransformEvent`: 任务状态变更事件
  - `@EventListener`: 异步监听器处理
- **线程池配置**: 
  ```yaml
  spring:
    task:
      scheduling:
        pool:
          size: 10  # 定时任务线程池大小
  ```
- **批量操作**: 
  - 批量保存日志: `logRepository.saveAll(logs)`
  - 批量查询: 使用 `IN` 查询替代多次单次查询

### 4. 前端性能优化
- **Monaco Editor 优化**: 
  - 只读模式: 禁用编辑功能，减少内存占用
  - 虚拟滚动: 大日志文件按需渲染
  - 语法高亮: log 语言定义，提升可读性
- **轮询优化**: 
  - 智能轮询: 仅对 running/pending 状态的任务轮询
  - 轮询间隔: 2 秒，平衡实时性和服务器压力
  - 自动停止: 任务完成后立即停止轮询
- **懒加载**: 日志抽屉按需加载，不阻塞主页面

## 安全性考虑

### 1. 数据加密
- **传输加密**: 
  - TLS/HTTPS: 所有 HTTP 通信使用 SSL/TLS 加密
  - gRPC over TLS: Kuscia API 通信加密
  - 证书管理: JKS 密钥库，支持环境变量配置密码
- **存储加密**: 
  - 用户密码: BCrypt 哈希算法，不可逆加密
  - 敏感字段: AES-256 对称加密（可选）
  - 密钥管理: KMS（密钥管理系统）或环境变量
- **证书配置**:
  ```yaml
  server:
    ssl:
      enabled: true
      key-store: "file:./config/server.jks"
      key-store-password: ${KEY_PASSWORD:secretpad}
      key-alias: secretpad-server
  ```

### 2. 访问控制
- **身份认证**: 
  - 用户名/密码登录
  - Session 管理: 30 分钟超时
  - Token 机制: 登录成功后生成会话 Token
- **权限验证**: 
  - RBAC（Role-Based Access Control）: 基于角色的访问控制
  - 资源权限: `@ApiResource` 注解标记接口权限
  - 数据权限: `@DataResource` 注解标记数据级权限
  - 权限码示例:
    - `PRJ_CREATE`: 创建项目
    - `PRJ_JOB_LIST`: 查询作业列表
    - `PRJ_TASK_LOGS`: 查看任务日志
- **审计日志**: 
  - 记录所有数据访问操作
  - 包括: 操作人、操作时间、操作类型、影响数据
  - 存储表: `user_audit_log`
- **数据脱敏**: 
  - 前端展示时隐藏敏感信息
  - 日志输出时脱敏处理

### 3. IP 黑名单（SSRF 防护）
- **启用配置**: `ip.block.enable: true`
- **阻止地址段**:
  - `127.0.0.1/8`: 本地回环地址
  - `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`: 私有地址
  - `100.64.0.0/10`: CGNAT 地址
- **目的**: 防止 SSRF（Server-Side Request Forgery）攻击

### 4. 内容安全策略（CSP）
```yaml
secretpad:
  response:
    extra-headers:
      Content-Security-Policy: "base-uri 'self'; frame-src 'self'; worker-src blob: 'self' data:; object-src 'self';"
```
- **作用**: 限制资源加载来源，防止 XSS 攻击
- **策略说明**:
  - `base-uri 'self'`: 限制基础 URL
  - `frame-src 'self'`: 限制 iframe 来源
  - `worker-src blob: 'self' data:`: 允许 Web Worker

### 5. 内部端口白名单
- **内部端口**: 9001（用于节点间同步）
- **白名单路径**:
  - `/api/v1alpha1/vote_sync/create`: 投票同步
  - `/sync`: 数据同步
  - `/api/v1alpha1/data/sync`: 数据同步
- **安全措施**: 仅允许这些路径通过内部端口访问，其他请求需经过外部认证

## 监控与运维

### 1. 监控指标

#### 数据库性能监控
- **查询延迟**: 平均响应时间、P95/P99 延迟
- **连接数**: 活跃连接数、空闲连接数、等待队列长度
- **TPS/QPS**: 每秒事务数、每秒查询数
- **慢查询**: 执行时间超过阈值的 SQL 语句
- **锁等待**: 行锁/表锁等待时间

#### 存储容量监控
- **数据库大小**: 
  - SQLite: 文件大小（`db/secretpad.sqlite`）
  - MySQL: 表空间大小、索引大小
- **磁盘使用率**: 警告阈值 80%，危险阈值 90%
- **增长趋势**: 预测未来存储空间需求

#### 同步状态监控
- **Kuscia 同步延迟**: SecretPad 数据库与 Kuscia CRD 状态差异时间
- **SSE 连接数**: 中心模式下边缘节点连接状态
- **同步失败率**: 同步失败次数 / 总同步次数
- **缓冲区积压**: `DataSyncDataBufferTemplate` 中待处理事件数量

#### 应用性能监控
- **JVM 指标**: 堆内存使用、GC 频率、线程数
- **HTTP 请求**: QPS、响应时间、错误率
- **定时任务**: 执行时长、失败次数
- **缓存命中率**: Ehcache/Caffeine 命中/未命中比例

#### Actuator 端点
```yaml
management:
  endpoints:
    web:
      exposure:
        include:
          - health  # /actuator/health 健康检查
          # - prometheus  # Prometheus 指标（生产环境建议内网使用）
  endpoint:
    health:
      show-details: always  # 显示详细健康信息
```

### 2. 日志管理

#### 日志分类
- **应用日志**: SecretPad 业务逻辑日志
  - 位置: `/var/log/secretpad` 或 `${SECRETPAD_LOG_PATH}`
  - 级别: INFO, WARN, ERROR, DEBUG
- **访问日志**: Tomcat HTTP 请求日志
  - 格式: Apache Combined Log Format
  - 内容: IP、时间、请求方法、URL、状态码、响应时间
- **审计日志**: 用户操作审计
  - 存储: 数据库表 `user_audit_log`
  - 内容: 操作人、操作对象、操作结果

#### 日志轮转
- **策略**: 按大小和时间轮转
- **保留期限**: 默认 30 天
- **压缩**: 旧日志自动压缩为 .gz 格式

#### 日志查询
- **本地查询**: `tail -f /var/log/secretpad/backend.log`
- **集中式日志**: （可选）集成 ELK Stack 或 SLS
  - Elasticsearch: 日志存储和索引
  - Logstash: 日志收集和解析
  - Kibana: 日志可视化和搜索

### 3. 备份策略

#### 数据库备份
- **全量备份**: 
  - 频率: 每日凌晨 2 点
  - 方式: SQLite 文件拷贝 / MySQL mysqldump
  - 保留: 最近 7 天的全量备份
- **增量备份**: 
  - 频率: 每小时
  - 方式: binlog（MySQL）或 WAL（SQLite）
  - 保留: 最近 24 小时的增量备份
- **备份验证**: 定期恢复测试，确保备份可用

#### CRD 备份
- **Kubernetes 资源导出**: 
  ```bash
  kubectl get kusciajobs -o yaml > kusciajobs-backup.yaml
  kubectl get domaindatasources -o yaml > datasources-backup.yaml
  ```
- **etcd 快照**: Kubernetes 集群级别的 etcd 快照

#### 灾难恢复
- **RTO（Recovery Time Objective）**: 目标恢复时间 < 30 分钟
- **RPO（Recovery Point Objective）**: 目标数据丢失 < 1 小时
- **恢复流程**:
  1. 停止 SecretPad 服务
  2. 恢复数据库备份
  3. 恢复 Kuscia CRD（如需要）
  4. 启动服务并验证
  5. 检查数据一致性

### 4. 告警配置

#### 告警规则
- **数据库连接池耗尽**: 活跃连接数 > 最大连接数 * 90%
- **磁盘空间不足**: 使用率 > 85%
- **同步失败**: 连续 3 次同步失败
- **任务执行失败**: 任务失败率 > 10%
- **响应时间过长**: P95 延迟 > 5 秒

#### 告警渠道
- **邮件**: 发送告警通知到运维团队
- **短信**: 严重告警触发短信通知
- **Webhook**: 集成钉钉、企业微信等 IM 工具
- **Prometheus Alertmanager**: 统一告警管理

### 5. 运维最佳实践

#### 日常巡检
- 检查数据库连接数和慢查询
- 监控磁盘空间使用情况
- 查看错误日志和异常堆栈
- 验证备份任务执行状态

#### 版本升级
- **数据库迁移**: Flyway 自动执行 SQL 脚本
- **向后兼容**: 新版本兼容旧版本数据格式
- **灰度发布**: 先在测试环境验证，再逐步推广到生产
- **回滚方案**: 保留旧版本镜像和数据库备份

#### 性能调优
- **定期分析**: 使用 EXPLAIN 分析慢查询
- **索引优化**: 根据查询模式调整索引
- **缓存预热**: 系统启动时预加载热点数据
- **连接池调优**: 根据实际负载调整 HikariCP 参数

## 总结

| 维度 | SecretPad 后端数据库 | Kuscia (Kubernetes) |
|------|---------------------|---------------------|
| **数据类型** | 业务数据、历史记录、参数快照、结果索引 | 运行时编排、任务定义、数据资产定义 |
| **存储介质** | MySQL/SQLite | etcd |
| **持久性** | 长期保存 | 主要面向运行时和资源管理 |
| **用途** | 查询、审计、统计、展示 | 调度、执行、协调 |
| **查询性能** | 高（支持复杂查询） | 中（K8s API限制） |
| **可靠性** | 高（独立于K8s） | 依赖K8s集群 |
| **数据量** | 累积增长 | 相对较小 |
| **生命周期** | 数年到永久 | 数天到数月 |
| **接口类型** | RESTful API, JDBC | gRPC, Kubernetes API |
| **清理策略** | 基于业务规则的自动/手动清理 | TTL, 自动GC, 状态同步后清理 |

SecretPad 不是简单的转发层。它负责校验、组装、参数渲染、持久化、状态追踪和结果索引；Kuscia 负责运行时编排和数据资产注册；真实输入输出文件通常位于 DataMesh 所连接的底层存储中。三者共同构成完整的隐私计算执行链路。