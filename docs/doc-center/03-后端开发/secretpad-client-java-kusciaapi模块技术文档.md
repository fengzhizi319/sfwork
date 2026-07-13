# client-java-kusciaapi 模块技术文档

## 一、模块概述

`client-java-kusciaapi` 是 SecretPad 项目中用于与 Kuscia API 进行通信的 Java gRPC 客户端模块。该模块提供了动态管理多个 Kuscia 节点连接的能力，支持 TLS/mTLS 安全认证，为上层业务提供统一的 Kuscia API 调用接口。

### 1.1 核心定位

- **协议层封装**：基于 gRPC 实现与 Kuscia 框架的通信
- **多节点管理**：支持动态注册/注销多个 Kuscia 节点
- **安全通信**：支持 TLS、mTLS、NoTLS 三种通信协议
- **服务抽象**：提供统一的业务服务接口，屏蔽底层 gRPC 细节
- **高性能传输**：利用 HTTP/2 多路复用、头部压缩、二进制帧等特性

### 1.2 技术栈

- **Java 17**：开发语言
- **gRPC 1.62.2**：RPC 框架（基于 HTTP/2）
- **Protobuf 3.25.5**：数据序列化（比 JSON 快 3-10 倍，体积小 30%-70%）
- **Netty**：网络通信底层（异步事件驱动）
- **Spring Boot 3.3.5**：依赖注入和生命周期管理
- **OpenSSL**：SSL/TLS 加密（性能优于 JDK 默认实现）
- **HTTP/2**：传输协议（多路复用、头部压缩、服务器推送）

---

## 二、gRPC 核心原理

### 2.1 gRPC 概述

gRPC（gRPC Remote Procedure Calls）是一个由 Google 开发的开源高性能 RPC 框架，基于 HTTP/2 协议传输，使用 Protocol Buffers 作为接口定义语言和数据序列化格式。

#### 核心特性

1. **高性能**：基于 HTTP/2 多路复用、二进制帧传输
2. **强类型**：通过 .proto 文件定义服务接口和消息结构
3. **跨语言**：支持 Java、Go、Python、C++ 等 10+ 种语言
4. **双向流**：支持 Unary、Server Streaming、Client Streaming、Bidirectional Streaming 四种调用模式
5. **内置功能**：负载均衡、健康检查、追踪、认证等

### 2.2 gRPC 通信架构

```
┌─────────────────────────────────────────────────────────────┐
│                      Client Side                             │
│  ┌──────────┐    ┌──────────┐    ┌──────────────────┐      │
│  │ Stub     │───▶│ Channel  │───▶│ Transport(HTTP/2)│      │
│  │ (Proxy)  │    │ (LB/Poll)│    │ + TLS/mTLS       │      │
│  └──────────┘    └──────────┘    └────────┬─────────┘      │
└───────────────────────────────────────────┼────────────────┘
                                            │ HTTP/2 Stream
                                            │ (Binary Frame)
┌───────────────────────────────────────────┼────────────────┐
│                      Server Side           ▼                │
│  ┌──────────┐    ┌──────────┐    ┌──────────────────┐      │
│  │ Service  │◀───│ Channel  │◀───│ Transport(HTTP/2)│      │
│  │ Impl     │    │ (Accept) │    │ + TLS/mTLS       │      │
│  └──────────┘    └──────────┘    └──────────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

#### 关键组件说明

**客户端组件：**
- **Stub（桩）**：根据 .proto 生成的代理类，提供类型安全的 RPC 调用接口
  - `BlockingStub`：同步阻塞调用
  - `FutureStub`：异步 Future 调用
  - `StreamStub`：流式调用
- **Channel**：管理连接、负载均衡、重试等
  - `ManagedChannel`：自动管理连接生命周期
  - 支持连接池、DNS 解析、服务发现
- **Transport**：底层传输层，基于 Netty 实现 HTTP/2
  - 多路复用：单个 TCP 连接承载多个并发请求
  - 头部压缩：HPACK 算法减少开销
  - 二进制帧：高效的数据编码

**服务端组件：**
- **Service**：业务逻辑实现类，继承自生成的 `*ImplBase`
- **Channel**：接收客户端连接，分发请求到对应的 Service
- **Transport**：处理 HTTP/2 协议细节

### 2.3 HTTP/2 核心优势

#### 1. 多路复用（Multiplexing）
- **HTTP/1.1**：每个请求需要一个 TCP 连接（或队头阻塞）
- **HTTP/2**：单个 TCP 连接可同时处理多个请求/响应
- **优势**：减少连接建立开销，提高并发性能

#### 2. 头部压缩（HPACK）
- **问题**：HTTP 头部通常较大且重复（Cookie、User-Agent 等）
- **解决**：HPACK 算法动态维护头部表，只传输差异部分
- **效果**：头部体积减少 50%-80%

#### 3. 二进制分帧（Binary Framing）
- **HTTP/1.1**：文本协议，解析复杂
- **HTTP/2**：二进制帧，结构化传输
- **帧类型**：
  - `HEADERS`：携带头部信息
  - `DATA`：携带请求/响应体
  - `RST_STREAM`：中断流
  - `SETTINGS`：配置参数
  - `PING`：心跳检测

#### 4. 服务器推送（Server Push）
- 服务器可以主动向客户端推送资源
- gRPC 中用于 Server Streaming 和 Bidirectional Streaming

### 2.4 Protocol Buffers 序列化

#### 对比 JSON/XML

| 特性 | Protobuf | JSON | XML |
|------|----------|------|-----|
| 序列化速度 | ⚡⚡⚡ 快 3-10 倍 | ⚡ 基准 | 🐢 慢 |
| 数据体积 | 📦 小 30%-70% | 📦📦 基准 | 📦📦📦 大 |
| 强类型 | ✅ 编译时检查 | ❌ 运行时检查 | ❌ 运行时检查 |
| 向后兼容 | ✅ 字段可选 | ⚠️ 需手动处理 | ⚠️ 需手动处理 |
| 可读性 | ❌ 二进制 | ✅ 文本 | ✅ 文本 |

#### .proto 文件示例

```protobuf
syntax = "proto3";

package kuscia.proto.api.v1alpha1.kusciaapi;

// 服务定义
service DomainService {
  rpc CreateDomain(CreateDomainRequest) returns (CreateDomainResponse);
  rpc QueryDomain(QueryDomainRequest) returns (QueryDomainResponse);
}

// 消息定义
message CreateDomainRequest {
  RequestHeader header = 1;    // 字段编号 1
  string domain_id = 2;        // 字段编号 2
  string role = 3;             // 字段编号 3
  string cert = 4;             // 字段编号 4
}

message CreateDomainResponse {
  Status status = 1;
}
```

#### 字段编号规则
- **1-15**：高频字段（占用 1 字节编码）
- **16-2047**：低频字段（占用 2 字节编码）
- **保留字段**：删除的字段应标记为 `reserved`，避免重用编号

### 2.5 gRPC 四种调用模式

#### 1. Unary RPC（一元调用）
**特点**：客户端发送一个请求，服务端返回一个响应（类似传统 HTTP）

```java
// 客户端
CreateDomainRequest request = CreateDomainRequest.newBuilder()
    .setDomainId("alice")
    .setRole("partner")
    .build();

CreateDomainResponse response = stub.createDomain(request);
```

**适用场景**：简单的请求-响应交互

#### 2. Server Streaming RPC（服务端流式）
**特点**：客户端发送一个请求，服务端返回多个响应（流）

```java
// 服务端定义
rpc WatchJob(WatchJobRequest) returns (stream WatchJobEventResponse);

// 客户端
WatchJobRequest request = WatchJobRequest.newBuilder()
    .setTimeoutSeconds(300)
    .build();

Iterator<WatchJobEventResponse> iterator = stub.watchJob(request);
while (iterator.hasNext()) {
    WatchJobEventResponse event = iterator.next();
    log.info("Job event: {}", event.getType());
}
```

**适用场景**：实时监控、日志流、进度推送

#### 3. Client Streaming RPC（客户端流式）
**特点**：客户端发送多个请求，服务端返回一个响应

```protobuf
rpc UploadData(stream DataChunk) returns (UploadResponse);
```

**适用场景**：大文件上传、批量数据提交

#### 4. Bidirectional Streaming RPC（双向流式）
**特点**：客户端和服务端都可以发送多个消息，完全异步

```protobuf
rpc Chat(stream ChatMessage) returns (stream ChatMessage);
```

**适用场景**：实时聊天、协作编辑、游戏同步

### 2.6 gRPC 拦截器机制

#### 拦截器链

```
Client Call
    │
    ▼
┌──────────────────────┐
│ Interceptor 1        │  ← TokenAuthClientInterceptor（添加 Token）
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ Interceptor 2        │  ← KusciaGrpcLoggingInterceptor（记录日志）
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ Transport Layer      │  ← HTTP/2 传输
└──────────────────────┘
```

#### 客户端拦截器示例

```java
public class TokenAuthClientInterceptor implements ClientInterceptor {
    @Override
    public <ReqT, RespT> ClientCall<ReqT, RespT> interceptCall(
            MethodDescriptor<ReqT, RespT> method,
            CallOptions callOptions,
            Channel next) {
        
        ClientCall<ReqT, RespT> call = next.newCall(method, callOptions);
        
        return new ForwardingClientCall.SimpleForwardingClientCall<>(call) {
            @Override
            public void start(Listener<RespT> responseListener, Metadata headers) {
                // 在请求发送前添加 Token 到 Header
                headers.put(
                    Metadata.Key.of("Authorization", Metadata.ASCII_STRING_MARSHALLER),
                    token
                );
                super.start(responseListener, headers);
            }
        };
    }
}
```

#### 服务端拦截器示例

```java
public class TokenAuthServerInterceptor implements ServerInterceptor {
    @Override
    public <ReqT, RespT> ServerCall.Listener<ReqT> interceptCall(
            ServerCall<ReqT, RespT> call,
            Metadata headers,
            ServerCallHandler<ReqT, RespT> next) {
        
        // 从 Header 中提取 Token 并验证
        String token = headers.get(
            Metadata.Key.of("Authorization", Metadata.ASCII_STRING_MARSHALLER)
        );
        
        if (!validateToken(token)) {
            call.close(Status.UNAUTHENTICATED, new Metadata());
            return new ServerCall.Listener<ReqT>() {};
        }
        
        return next.startCall(call, headers);
    }
}
```

### 2.7 连接管理与生命周期

#### ManagedChannel 状态机

```
IDLE ──▶ CONNECTING ──▶ READY ──▶ TRANSIENT_FAILURE
  ▲                                    │
  └────────────────────────────────────┘
              (自动重连)
               
READY/TRANSIENT_FAILURE ──▶ SHUTDOWN
```

**状态说明：**
- **IDLE**：空闲状态，没有活跃请求
- **CONNECTING**：正在建立连接
- **READY**：连接就绪，可以发送请求
- **TRANSIENT_FAILURE**：临时失败，会自动重试
- **SHUTDOWN**：已关闭，不再接受新请求

#### 优雅关闭流程

```java
// 1. 停止接受新请求
channel.shutdown();

// 2. 等待正在进行的请求完成（最多等待 30 秒）
try {
    if (!channel.awaitTermination(30, TimeUnit.SECONDS)) {
        // 3. 超时后强制关闭
        channel.shutdownNow();
    }
} catch (InterruptedException e) {
    channel.shutdownNow();
    Thread.currentThread().interrupt();
}
```

---

## 三、Kuscia API 通信接口详解

### 3.1 接口概览

Kuscia API 定义了 9 个核心 gRPC 服务，涵盖域管理、数据管理、任务管理等隐私计算场景。

#### 服务清单

| 服务名称 | Proto 文件 | 主要功能 | RPC 方法数 |
|---------|-----------|---------|----------|
| DomainService | domain.proto | 域（参与方）管理 | 5 |
| DomainDataService | domaindata.proto | 域数据管理 | 6 |
| DomainDataSourceService | domaindatasource.proto | 数据源管理 | 5 |
| DomainDataGrantService | domaindatagrant.proto | 数据授权管理 | 4 |
| DomainRouteService | domain_route.proto | 域路由管理 | 4 |
| JobService | job.proto | 隐私计算任务管理 | 10 |
| ServingService | serving.proto | 在线推理服务管理 | 6 |
| HealthService | health.proto | 健康检查 | 1 |
| CertificateService | certificate.proto | 证书管理 | 3 |

### 3.2 DomainService（域管理服务）

**Proto 定义：** `proto/kuscia/proto/api/v1alpha1/kusciaapi/domain.proto`

#### 业务概念
**域（Domain）**：代表隐私计算中的一个参与方（如 Alice、Bob），每个域有唯一的 ID、角色和证书。

#### RPC 方法

##### 1. CreateDomain - 创建域
```protobuf
rpc CreateDomain(CreateDomainRequest) returns (CreateDomainResponse);
```

**请求参数：**
```protobuf
message CreateDomainRequest {
  RequestHeader header = 1;      // 请求头（自定义元数据）
  string domain_id = 2;          // 域唯一标识（如 "alice"）
  string role = 3;               // 域角色（"partner" 或 "master"）
  string cert = 4;               // 域证书（PEM 格式）
  AuthCenter auth_center = 5;    // 认证中心配置
  string master_domain_id = 6;   // 主域 ID（仅 partner 需要）
}
```

**响应：**
```protobuf
message CreateDomainResponse {
  Status status = 1;  // 操作状态
}
```

**使用示例：**
```java
CreateDomainRequest request = CreateDomainRequest.newBuilder()
    .setDomainId("alice")
    .setRole("partner")
    .setCert(certPemContent)
    .setMasterDomainId("kuscia-master")
    .build();

CreateDomainResponse response = domainServiceStub.createDomain(request);
if (response.getStatus().getCode() == 0) {
    log.info("Domain created successfully");
}
```

##### 2. QueryDomain - 查询域
```protobuf
rpc QueryDomain(QueryDomainRequest) returns (QueryDomainResponse);
```

**响应数据结构：**
```protobuf
message QueryDomainResponseData {
  string domain_id = 1;
  string role = 2;
  string cert = 3;
  repeated NodeStatus node_statuses = 4;      // 节点状态列表
  repeated DeployTokenStatus deploy_token_statuses = 5;  // 部署令牌状态
  map<string, string> annotations = 6;        // 注解（键值对）
  AuthCenter auth_center = 7;
  string master_domain_id = 8;
}
```

##### 3. UpdateDomain - 更新域
```protobuf
rpc UpdateDomain(UpdateDomainRequest) returns (UpdateDomainResponse);
```

**用途**：更新域的证书、角色或认证配置

##### 4. DeleteDomain - 删除域
```protobuf
rpc DeleteDomain(DeleteDomainRequest) returns (DeleteDomainResponse);
```

**注意**：删除前需确保该域没有运行中的任务

##### 5. BatchQueryDomain - 批量查询域
```protobuf
rpc BatchQueryDomain(BatchQueryDomainRequest) returns (BatchQueryDomainResponse);
```

**适用场景**：一次性获取多个域的信息，减少网络往返

### 3.3 JobService（任务管理服务）

**Proto 定义：** `proto/kuscia/proto/api/v1alpha1/kusciaapi/job.proto`

#### 业务概念
**Job（任务）**：隐私计算任务的抽象，包含多个 Task（子任务），涉及多个参与方协同计算。

#### 任务状态机

```
Pending ──▶ AwaitingApproval ──▶ Running ──▶ Succeeded
                │                   │
                ▼                   ├──▶ Failed
          ApprovalReject            ├──▶ Suspended
                                    └──▶ Cancelled
```

**状态说明：**
- **Pending**：任务已创建，等待调度
- **AwaitingApproval**：等待其他参与方审批
- **Running**：任务正在执行
- **Succeeded**：任务成功完成
- **Failed**：任务执行失败
- **Suspended**：任务被暂停
- **Cancelled**：任务被取消
- **ApprovalReject**：审批被拒绝

#### RPC 方法

##### 1. CreateJob - 创建任务
```protobuf
rpc CreateJob(CreateJobRequest) returns (CreateJobResponse);
```

**请求参数：**
```protobuf
message CreateJobRequest {
  RequestHeader header = 1;
  string job_id = 2;                  // 任务唯一标识
  string initiator = 3;               // 发起方域 ID
  int32 max_parallelism = 4;          // 最大并行度
  repeated Task tasks = 5;            // 子任务列表
  map<string, string> custom_fields = 6;  // 自定义字段
}

message Task {
  string app_image = 1;               // 应用镜像（如 PSI、联邦学习）
  repeated Party parties = 2;         // 参与方列表
  string alias = 3;                   // 任务别名
  string task_id = 4;                 // 子任务 ID
  repeated string dependencies = 5;   // 依赖的子任务 ID
  string task_input_config = 6;       // 任务输入配置（JSON）
  int32 priority = 7;                 // 优先级
}

message Party {
  string domain_id = 1;               // 参与方域 ID
  string role = 2;                    // 角色（"server" 或 "client"）
  JobResource resources = 3;          // 资源配置
}

message JobResource {
  string cpu = 1;                     // CPU 限制（如 "2" 表示 2 核）
  string memory = 2;                  // 内存限制（如 "4Gi"）
}
```

**使用示例：**
```java
// 构建 PSI 任务
Party alice = Party.newBuilder()
    .setDomainId("alice")
    .setRole("client")
    .setResources(JobResource.newBuilder()
        .setCpu("2")
        .setMemory("4Gi")
        .build())
    .build();

Party bob = Party.newBuilder()
    .setDomainId("bob")
    .setRole("server")
    .setResources(JobResource.newBuilder()
        .setCpu("2")
        .setMemory("4Gi")
        .build())
    .build();

Task psiTask = Task.newBuilder()
    .setAppImage("secretflow/psi:latest")
    .addParties(alice)
    .addParties(bob)
    .setTaskId("psi-task-001")
    .setTaskInputConfig(psiConfigJson)
    .build();

CreateJobRequest request = CreateJobRequest.newBuilder()
    .setJobId("psi-job-001")
    .setInitiator("alice")
    .setMaxParallelism(1)
    .addTasks(psiTask)
    .build();

CreateJobResponse response = jobServiceStub.createJob(request);
String jobId = response.getData().getJobId();
log.info("Job created: {}", jobId);
```

##### 2. QueryJob - 查询任务
```protobuf
rpc QueryJob(QueryJobRequest) returns (QueryJobResponse);
```

**响应数据：**
```protobuf
message QueryJobResponseData {
  string job_id = 1;
  string initiator = 2;
  int32 max_parallelism = 3;
  repeated TaskConfig tasks = 4;
  JobStatusDetail status = 5;         // 任务状态详情
  map<string, string> custom_fields = 6;
}

message JobStatusDetail {
  string state = 1;                   // 当前状态
  string err_msg = 2;                 // 错误信息（如有）
  string create_time = 3;             // 创建时间
  string start_time = 4;              // 开始时间
  string end_time = 5;                // 结束时间
  repeated TaskStatus tasks = 6;      // 子任务状态列表
  repeated PartyStageStatus stage_status_list = 7;   // 阶段状态
  repeated PartyApproveStatus approve_status_list = 8; // 审批状态
}
```

##### 3. StopJob - 停止任务
```protobuf
rpc StopJob(StopJobRequest) returns (StopJobResponse);
```

**用途**：优雅停止正在运行的任务（等待当前步骤完成）

##### 4. SuspendJob - 暂停任务
```protobuf
rpc SuspendJob(SuspendJobRequest) returns (SuspendJobResponse);
```

**用途**：暂停任务执行，后续可通过 RestartJob 恢复

##### 5. RestartJob - 重启任务
```protobuf
rpc RestartJob(RestartJobRequest) returns (RestartJobResponse);
```

**用途**：从暂停状态恢复任务执行

##### 6. CancelJob - 取消任务
```protobuf
rpc CancelJob(CancelJobRequest) returns (CancelJobResponse);
```

**用途**：立即取消任务（不可恢复）

##### 7. DeleteJob - 删除任务
```protobuf
rpc DeleteJob(DeleteJobRequest) returns (DeleteJobResponse);
```

**注意**：只能删除已完成或已取消的任务

##### 8. ApproveJob - 审批任务
```protobuf
rpc ApproveJob(ApproveJobRequest) returns (ApproveJobResponse);
```

**请求参数：**
```protobuf
message ApproveJobRequest {
  string job_id = 1;
  ApproveResult result = 2;  // ACCEPT 或 REJECT
  string reason = 3;         // 审批原因
}

enum ApproveResult {
  APPROVE_RESULT_UNKNOWN = 0;
  APPROVE_RESULT_ACCEPT = 1;
  APPROVE_RESULT_REJECT = 2;
}
```

**业务流程**：
1. Alice 创建任务并发送给 Bob
2. Bob 收到审批请求（任务状态：AwaitingApproval）
3. Bob 调用 ApproveJob 进行审批
4. 如果接受，任务进入 Running 状态；如果拒绝，任务状态变为 ApprovalReject

##### 9. WatchJob - 监听任务事件（服务端流式）
```protobuf
rpc WatchJob(WatchJobRequest) returns (stream WatchJobEventResponse);
```

**请求参数：**
```protobuf
message WatchJobRequest {
  RequestHeader header = 1;
  int64 timeout_seconds = 2;  // 超时时间（秒）
}
```

**响应流：**
```protobuf
message WatchJobEventResponse {
  EventType type = 1;    // 事件类型
  JobStatus object = 2;  // 任务状态
}

enum EventType {
  ADDED = 0;      // 任务创建
  MODIFIED = 1;   // 任务状态变更
  DELETED = 2;    // 任务删除
  ERROR = 3;      // 错误事件
  HEARTBEAT = 4;  // 心跳（保持连接）
}
```

**使用示例：**
```java
WatchJobRequest request = WatchJobRequest.newBuilder()
    .setTimeoutSeconds(300)  // 监听 5 分钟
    .build();

Iterator<WatchJobEventResponse> events = jobServiceStub.watchJob(request);
while (events.hasNext()) {
    WatchJobEventResponse event = events.next();
    
    switch (event.getType()) {
        case ADDED:
            log.info("Job created: {}", event.getObject().getJobId());
            break;
        case MODIFIED:
            JobStatusDetail status = event.getObject().getStatus();
            log.info("Job {} state changed to: {}", 
                event.getObject().getJobId(), status.getState());
            
            if ("Succeeded".equals(status.getState())) {
                log.info("Job completed successfully!");
                return;
            }
            break;
        case ERROR:
            log.error("Watch error occurred");
            break;
        case HEARTBEAT:
            // 忽略心跳，保持连接活跃
            break;
    }
}
```

**典型应用场景**：
- 前端实时显示任务进度
- 任务完成后触发通知
- 监控任务异常并告警

##### 10. BatchQueryJobStatus - 批量查询任务状态
```protobuf
rpc BatchQueryJobStatus(BatchQueryJobStatusRequest) returns (BatchQueryJobStatusResponse);
```

**适用场景**：一次性查询多个任务的状态，减少网络请求次数

### 3.4 DomainDataService（域数据管理服务）

**Proto 定义：** `proto/kuscia/proto/api/v1alpha1/kusciaapi/domaindata.proto`

#### 业务概念
**DomainData（域数据）**：描述参与方的数据集元信息，包括数据类型、列结构、存储位置等。

#### RPC 方法

##### 1. CreateDomainData - 创建域数据
```protobuf
rpc CreateDomainData(CreateDomainDataRequest) returns (CreateDomainDataResponse);
```

**请求参数：**
```protobuf
message CreateDomainDataRequest {
  RequestHeader header = 1;
  string domain_data_id = 2;    // 数据唯一标识
  string name = 3;              // 数据名称
  DomainDataType type = 4;      // 数据类型（TABLE、MODEL 等）
  repeated DataColumn columns = 5;  // 列定义
  string vendor_type = 6;       // 供应商类型（如 "csv"、"odps"）
  map<string, string> attributes = 7;  // 属性（键值对）
  string relative_uri = 8;      // 相对 URI（数据存储路径）
}

enum DomainDataType {
  UNKNOWN = 0;
  TABLE = 1;      // 表格数据
  MODEL = 2;      // 模型文件
  RULE = 3;       // 规则文件
  REPORT = 4;     // 报告文件
}
```

**使用示例：**
```java
// 定义数据列
DataColumn idColumn = DataColumn.newBuilder()
    .setName("id")
    .setType("string")
    .setComment("用户 ID")
    .build();

DataColumn ageColumn = DataColumn.newBuilder()
    .setName("age")
    .setType("int64")
    .setComment("年龄")
    .build();

CreateDomainDataRequest request = CreateDomainDataRequest.newBuilder()
    .setDomainDataId("alice_user_data")
    .setName("Alice 用户数据")
    .setType(DomainDataType.TABLE)
    .addColumns(idColumn)
    .addColumns(ageColumn)
    .setVendorType("csv")
    .setRelativeUri("/data/alice/users.csv")
    .build();

CreateDomainDataResponse response = domainDataServiceStub.createDomainData(request);
```

##### 2. QueryDomainData - 查询域数据
```protobuf
rpc QueryDomainData(QueryDomainDataRequest) returns (QueryDomainDataResponse);
```

##### 3. UpdateDomainData - 更新域数据
```protobuf
rpc UpdateDomainData(UpdateDomainDataRequest) returns (UpdateDomainDataResponse);
```

##### 4. DeleteDomainData - 删除域数据
```protobuf
rpc DeleteDomainData(DeleteDomainDataRequest) returns (DeleteDomainDataResponse);
```

##### 5. ListDomainData - 列出域数据
```protobuf
rpc ListDomainData(ListDomainDataRequest) returns (ListDomainDataResponse);
```

**支持分页和过滤**：
```protobuf
message ListDomainDataRequest {
  RequestHeader header = 1;
  int32 page_number = 2;    // 页码
  int32 page_size = 3;      // 每页数量
  string keyword = 4;       // 搜索关键词
}
```

##### 6. BatchQueryDomainData - 批量查询域数据
```protobuf
rpc BatchQueryDomainData(BatchQueryDomainDataRequest) returns (BatchQueryDomainDataResponse);
```

### 3.5 其他服务简介

#### DomainDataSourceService（数据源管理）
- **功能**：管理外部数据源连接（如 MySQL、OSS、HDFS）
- **核心方法**：CreateDataSource、QueryDataSource、UpdateDataSource、DeleteDataSource、ListDataSource

#### DomainDataGrantService（数据授权管理）
- **功能**：控制哪些域可以访问特定的数据
- **核心方法**：CreateGrant、QueryGrant、DeleteGrant、ListGrant
- **应用场景**：Alice 授权 Bob 访问她的用户数据进行 PSI 计算

#### DomainRouteService（域路由管理）
- **功能**：配置域之间的通信路由规则
- **核心方法**：CreateRoute、QueryRoute、UpdateRoute、DeleteRoute

#### ServingService（在线推理服务）
- **功能**：部署和管理在线推理服务
- **核心方法**：CreateServing、QueryServing、UpdateServing、DeleteServing、ListServing、StartServing
- **应用场景**：将训练好的模型部署为实时推理 API

#### HealthService（健康检查）
- **功能**：检查 Kuscia API 服务的健康状态
- **核心方法**：Check（Unary RPC）

```protobuf
rpc Check(HealthCheckRequest) returns (HealthCheckResponse);

message HealthCheckRequest {
  string service = 1;  // 服务名称（留空检查整体健康）
}

message HealthCheckResponse {
  enum ServingStatus {
    UNKNOWN = 0;
    SERVING = 1;        // 正常服务
    NOT_SERVING = 2;    // 停止服务
    SERVICE_UNKNOWN = 3; // 未知服务
  }
  ServingStatus status = 1;
}
```

#### CertificateService（证书管理）
- **功能**：管理 TLS/mTLS 证书
- **核心方法**：CreateCertificate、QueryCertificate、DeleteCertificate

### 3.6 通用消息结构

#### RequestHeader（请求头）
```protobuf
message RequestHeader {
  map<string, string> custom_headers = 1;  // 自定义头部
}
```

**用途**：携带追踪 ID、租户信息、审计日志等元数据

#### Status（响应状态）
```protobuf
message Status {
  int32 code = 1;              // 状态码（0 表示成功）
  string message = 2;          // 错误消息
  repeated google.protobuf.Any details = 3;  // 详细错误信息
}
```

**状态码约定：**
- `0`：成功
- `1-999`：Kuscia 自定义错误码
- `1000+`：gRPC 标准错误码（参考 `google.rpc.Code`）

---

## 四、核心功能

### 4.1 动态通道管理（Dynamic Channel Management）

#### 功能说明
支持在运行时动态注册和注销 Kuscia 节点，每个节点维护独立的 gRPC 连接通道。

#### 核心类
- `DynamicKusciaChannelProvider`：通道提供者，管理所有节点的连接工厂
- `KusciaApiChannelFactory`：通道工厂接口
- `GrpcKusciaApiChannelFactory`：gRPC 通道工厂实现

#### 关键特性
1. **线程安全**：使用 `ConcurrentHashMap` 存储通道工厂
2. **懒加载**：通道在首次使用时创建
3. **状态监控**：通过 `ManagedChannelStateListener` 监听连接状态
4. **优雅关闭**：支持 `shutdown()` 和 `shutdownNow()` 两种关闭方式

### 4.2 多协议支持（Multi-Protocol Support）

#### 支持的协议类型
```java
public enum KusciaProtocolEnum {
    TLS,    // TLS 加密通信
    MTLS,   // 双向 TLS 认证
    NOTLS   // 明文通信（仅用于测试）
}
```

#### 协议配置
- **TLS/mTLS**：需要配置证书文件（certFile、keyFile）和认证令牌（token）
- **NoTLS**：使用明文传输，无需证书

### 4.3 认证与授权（Authentication & Authorization）

#### Token 认证机制
通过 `TokenAuthClientInterceptor` 在每个 gRPC 请求中自动添加 Token 头：

```java
headers.put(Metadata.Key.of(KusciaAPIConstants.TOKEN_HEADER, Metadata.ASCII_STRING_MARSHALLER), token);
```

#### mTLS 双向认证
- 客户端持有证书和私钥
- 服务端验证客户端证书
- 客户端验证服务端证书（使用 `InsecureTrustManagerFactory` 跳过验证）

### 4.4 服务接口抽象（Service Abstraction）

#### 提供的服务接口
模块封装了 9 个核心 Kuscia API 服务：

1. **DomainService**：域管理服务（创建、更新、删除、查询域）
2. **DomainDataService**：域数据管理服务
3. **DomainDataSourceService**：数据源管理服务
4. **DomainDataGrantService**：数据授权管理服务
5. **DomainRouteService**：域路由管理服务
6. **KusciaJobService**：任务管理服务（创建、查询、停止、监控任务）
7. **ServingService**：在线服务管理服务
8. **HealthService**：健康检查服务
9. **CertificateService**：证书管理服务

#### 适配器模式
`KusciaGrpcClientAdapter` 实现了所有服务接口，作为统一入口：
- 每个方法提供两个重载版本：
  - 使用默认 nodeId
  - 指定 domainId 调用特定节点

### 4.5 Mock 服务器（Mock Server）

#### 用途
用于本地开发和单元测试，模拟 Kuscia API 服务端行为。

#### 核心类
- `MockKusciaGrpcServer`：Mock gRPC 服务器
- `mock.service.*`：各个服务的 Mock 实现
- `TokenAuthServerInterceptor`：服务端 Token 验证拦截器

#### 启动方式
```java
MockKusciaGrpcServer server = new MockKusciaGrpcServer();
server.start(); // 默认端口 50051，NoTLS 协议
```

---

## 五、核心代码详解

### 5.1 DynamicKusciaChannelProvider（动态通道提供者）

**文件路径**：`src/main/java/org/secretflow/secretpad/kuscia/v1alpha1/DynamicKusciaChannelProvider.java`

#### 核心职责
1. 管理所有 Kuscia 节点的通道工厂
2. 提供创建 gRPC Stub 的方法
3. 处理节点注册/注销事件
4. 从配置文件加载节点信息

#### 关键数据结构
```java
private static final Map<String, KusciaApiChannelFactory> CHANNEL_FACTORIES = new ConcurrentHashMap<>();
```
- Key: domainId（节点标识）
- Value: 对应的通道工厂

#### 核心方法

##### 1. 注册节点
```java
public void registerKuscia(KusciaGrpcConfig config) {
    Assert.notNull(config, "KusciaGrpcConfig must not be null");
    config.validateAndProcess();
    
    if (isInitialized || dynamicKusciaGrpcConfig.getNodes().add(config)) {
        synchronized (lock) {
            // 创建并注册通道工厂
            registerChannelFactory(config.getDomainId(), 
                new GrpcKusciaApiChannelFactory(config));
            
            // 发布注册事件
            if (!ObjectUtils.isEmpty(publisher)) {
                publisher.publishEvent(new RegisterKusciaEvent(this, config));
            }
        }
    }
}
```

##### 2. 创建 Stub
```java
public <T extends AbstractStub<T>> T createStub(String domainId, Class<T> clazz) {
    checkChannelFactoryExist(domainId);
    String serviceName = getServiceName(clazz.getEnclosingClass());
    
    // 根据服务名称和 Stub 类型创建对应的实例
    switch (serviceName) {
        case DomainServiceGrpc.SERVICE_NAME -> {
            if (clazz.equals(DomainServiceGrpc.DomainServiceBlockingStub.class)) {
                t = DomainServiceGrpc.newBlockingStub(CHANNEL_FACTORIES.get(domainId).getChannel())
                        .withDeadlineAfter(BLOCKING_TIMEOUT_MILLISECOND, TimeUnit.MILLISECONDS);
            }
            // ... 其他 Stub 类型
        }
        // ... 其他服务
    }
    return (T) t;
}
```

**超时配置**：
- BlockingStub：5000ms
- FutureStub：5000ms
- StreamStub：365天

##### 3. 初始化流程
```java
@PostConstruct
public void init() {
    isInitialized = true;
    
    // 从配置文件中加载节点
    if (!CollectionUtils.isEmpty(dynamicKusciaGrpcConfig.getNodes())) {
        for (KusciaGrpcConfig config : dynamicKusciaGrpcConfig.getNodes()) {
            registerKuscia(config);
        }
    }
    
    isInitialized = false;
    
    // 从序列化文件加载节点配置
    serializableKusciaConfigFileInit();
}
```

### 5.2 GrpcKusciaApiChannelFactory（gRPC 通道工厂）

**文件路径**：`src/main/java/org/secretflow/secretpad/kuscia/v1alpha1/factory/impl/GrpcKusciaApiChannelFactory.java`

#### 核心职责
1. 创建和管理 gRPC ManagedChannel
2. 配置 SSL/TLS 安全连接
3. 添加拦截器（日志、认证）
4. 监控通道状态

#### 通道创建流程
```java
private void initChannel() {
    NettyChannelBuilder nettyChannelBuilder = NettyChannelBuilder
            .forAddress(kusciaGrpcConfig.getHost(), kusciaGrpcConfig.getPort())
            .intercept(loggingInterceptor)  // 日志拦截器
            .maxInboundMessageSize(MAX_INBOUND_MESSAGE_SIZE);  // 256MB

    if (kusciaGrpcConfig.getProtocol() == KusciaProtocolEnum.NOTLS) {
        // 明文通信
        nettyChannelBuilder.usePlaintext();
    } else {
        // TLS/mTLS 加密通信
        SslContextBuilder clientContextBuilder = SslContextBuilder.forClient();
        GrpcSslContexts.configure(clientContextBuilder, SslProvider.OPENSSL);

        SslContext sslContext = null;
        try {
            File cert = FileUtils.readFile(kusciaGrpcConfig.getCertFile());
            File key = FileUtils.readFile(kusciaGrpcConfig.getKeyFile());
            sslContext = clientContextBuilder
                    .keyManager(cert, key)  // 客户端证书
                    .trustManager(InsecureTrustManagerFactory.INSTANCE)  // 信任所有服务端证书
                    .build();
        } catch (SSLException | FileNotFoundException e) {
            log.error("Failed to create ssl context", e);
        }

        nettyChannelBuilder
                .sslContext(sslContext)
                .intercept(tokenAuthClientInterceptor)  // Token 认证拦截器
                .useTransportSecurity();
    }
    
    channel = nettyChannelBuilder.build();
    
    // 启动通道状态监听器
    new ManagedChannelStateListener(channel, kusciaGrpcConfig.getDomainId(), state);
}
```

#### 关键参数
- **MAX_INBOUND_MESSAGE_SIZE**：256 * 1024 * 1024 (256MB)
- **SSL Provider**：OpenSSL（性能优于 JDK 默认实现）
- **Trust Manager**：InsecureTrustManagerFactory（生产环境应替换为严格验证）

### 5.3 KusciaGrpcConfig（节点配置）

**文件路径**：`src/main/java/org/secretflow/secretpad/kuscia/v1alpha1/model/KusciaGrpcConfig.java`

#### 配置项
```java
@NotNull private String domainId;          // 节点标识
@NotNull private String host;              // 主机地址
@Min(0) @Max(65535) private int port;      // 端口号
@NotNull private KusciaProtocolEnum protocol;  // 协议类型
@NotNull private KusciaModeEnum mode;      // 运行模式（P2P/CENTER）
private String token;                      // 认证令牌
private String certFile;                   // 证书文件路径
private String keyFile;                    // 私钥文件路径
```

#### 配置验证
```java
public void validateAndProcess() {
    // 1. JSR-303 注解验证
    ValidatorFactory factory = Validation.buildDefaultValidatorFactory();
    Validator validator = factory.getValidator();
    Set<ConstraintViolation<KusciaGrpcConfig>> violations = validator.validate(this);
    
    for (ConstraintViolation<KusciaGrpcConfig> violation : violations) {
        throw new IllegalArgumentException("Invalid KusciaGrpcConfig: " + violation.getMessage());
    }

    // 2. 解析 host:port 格式
    if (this.host.contains(":")) {
        this.port = Integer.parseInt(host.split(":")[1]);
        this.host = host.split(":")[0];
    }
    
    // 3. 根据协议类型验证必需字段
    switch (protocol) {
        case MTLS, TLS -> {
            if (StringUtils.isEmpty(certFile) || StringUtils.isEmpty(keyFile) 
                || StringUtils.isEmpty(token)) {
                throw new IllegalArgumentException(
                    "certFile,keyFile,token cannot be null when protocol is TLS or MTLS");
            }
            // 如果 token 是文件路径，读取文件内容
            if (new File(this.token).exists()) {
                this.token = FileUtils.readFile2String(token);
            }
        }
        case NOTLS -> {
            // 无需额外验证
        }
    }
}
```

### 5.4 KusciaGrpcClientAdapter（客户端适配器）

**文件路径**：`src/main/java/org/secretflow/secretpad/kuscia/v1alpha1/service/impl/KusciaGrpcClientAdapter.java`

#### 设计模式
**适配器模式**：将底层的 gRPC Stub 调用适配为统一的业务接口。

#### 接口实现示例
```java
@Service
public class KusciaGrpcClientAdapter implements
        DomainService, DomainRouteService, DomainDataService, 
        DomainDataSourceService, DomainDataGrantService,
        HealthService, KusciaJobService, ServingService, CertificateService {

    @Resource
    private DynamicKusciaChannelProvider dynamicKusciaChannelProvider;

    // 使用默认 nodeId
    @Override
    public Domaindata.CreateDomainDataResponse createDomainData(
            Domaindata.CreateDomainDataRequest request) {
        return dynamicKusciaChannelProvider
            .currentStub(DomainDataServiceGrpc.DomainDataServiceBlockingStub.class)
            .createDomainData(request);
    }

    // 指定 domainId
    @Override
    public Domaindata.CreateDomainDataResponse createDomainData(
            Domaindata.CreateDomainDataRequest request, String domainId) {
        return dynamicKusciaChannelProvider
            .createStub(domainId, DomainDataServiceGrpc.DomainDataServiceBlockingStub.class)
            .createDomainData(request);
    }
    
    // ... 其他方法类似
}
```

#### 方法数量统计
每个服务接口提供约 6-10 个方法，每个方法有 2 个重载版本，总计约 **150+ 个方法**。

### 5.5 TokenAuthClientInterceptor（Token 认证拦截器）

**文件路径**：`src/main/java/org/secretflow/secretpad/kuscia/v1alpha1/interceptor/TokenAuthClientInterceptor.java`

#### 工作原理
```java
public class TokenAuthClientInterceptor implements ClientInterceptor {
    private final String token;
    private final String domainId;

    @Override
    public <ReqT, RespT> ClientCall<ReqT, RespT> interceptCall(
            MethodDescriptor<ReqT, RespT> method, 
            CallOptions callOptions, 
            Channel next) {
        
        ClientCall<ReqT, RespT> call = next.newCall(method, callOptions);

        return new ForwardingClientCall.SimpleForwardingClientCall<>(call) {
            @Override
            public void start(Listener<RespT> responseListener, Metadata headers) {
                // 在请求头中添加 Token
                headers.put(
                    Metadata.Key.of(KusciaAPIConstants.TOKEN_HEADER, Metadata.ASCII_STRING_MARSHALLER), 
                    token
                );
                log.info("[{}] add token header: {} {}", domainId, 
                    KusciaAPIConstants.TOKEN_HEADER, token);
                super.start(responseListener, headers);
            }
        };
    }
}
```

### 5.6 ManagedChannelStateListener（通道状态监听器）

**文件路径**：`src/main/java/org/secretflow/secretpad/kuscia/v1alpha1/listener/ManagedChannelStateListener.java`

#### 功能
异步监控 gRPC 通道的连接状态变化（IDLE、CONNECTING、READY、TRANSIENT_FAILURE、SHUTDOWN）。

#### 实现逻辑
```java
public class ManagedChannelStateListener implements Runnable {
    private final ManagedChannel channel;
    private final String domainId;
    private final AtomicReference<ConnectivityState> state;

    public ManagedChannelStateListener(ManagedChannel channel, String domainId, 
                                      AtomicReference<ConnectivityState> state) {
        this.channel = channel;
        this.domainId = domainId;
        this.state = state;
        
        // 启动监听线程
        new Thread(this).start();
    }

    @Override
    public void run() {
        while (!channel.isShutdown()) {
            ConnectivityState newState = channel.getState(true);  // true 表示主动触发连接
            state.set(newState);
            log.debug("[{}] Channel state changed to: {}", domainId, newState);
            
            if (newState == ConnectivityState.SHUTDOWN) {
                break;
            }
            
            try {
                Thread.sleep(1000);  // 每秒检查一次
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                break;
            }
        }
    }
}
```

---

## 六、架构设计

### 6.1 整体架构图

```
┌─────────────────────────────────────────────────────────────┐
│                   Business Layer (业务层)                     │
│              KusciaJobService, DomainService, etc.           │
└──────────────────────────┬──────────────────────────────────┘
                           │ 调用
┌──────────────────────────▼──────────────────────────────────┐
│              KusciaGrpcClientAdapter (适配器层)               │
│         统一接口，屏蔽底层 gRPC Stub 细节                      │
└──────────────────────────┬──────────────────────────────────┘
                           │ 委托
┌──────────────────────────▼──────────────────────────────────┐
│          DynamicKusciaChannelProvider (通道管理层)            │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  CHANNEL_FACTORIES (ConcurrentHashMap)               │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐          │   │
│  │  │ alice    │  │ bob      │  │ tee      │  ...     │   │
│  │  └────┬─────┘  └────┬─────┘  └────┬─────┘          │   │
│  └───────┼─────────────┼─────────────┼────────────────┘   │
└──────────┼─────────────┼─────────────┼────────────────────┘
           │             │             │
┌──────────▼─────────────▼─────────────▼────────────────────┐
│         GrpcKusciaApiChannelFactory (工厂层)               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │ ManagedChan  │  │ ManagedChan  │  │ ManagedChan  │    │
│  │ +Interceptors│  │ +Interceptors│  │ +Interceptors│    │
│  └──────────────┘  └──────────────┘  └──────────────┘    │
└──────────┬────────────────┬────────────────┬─────────────┘
           │                │                │
           ▼                ▼                ▼
      ┌────────┐      ┌────────┐      ┌────────┐
      │ Alice  │      │  Bob   │      │  Tee   │
      │Kuscia  │      │Kuscia  │      │Kuscia  │
      └────────┘      └────────┘      └────────┘
```

### 6.2 设计模式应用

#### 1. 工厂模式（Factory Pattern）
- `KusciaApiChannelFactory` 接口定义通道创建规范
- `GrpcKusciaApiChannelFactory` 实现具体的 gRPC 通道创建逻辑

#### 2. 适配器模式（Adapter Pattern）
- `KusciaGrpcClientAdapter` 将 gRPC Stub 适配为业务友好的接口

#### 3. 单例模式（Singleton Pattern）
- `DynamicKusciaChannelProvider` 作为 Spring Bean，全局唯一
- `CHANNEL_FACTORIES` 静态变量，所有实例共享

#### 4. 观察者模式（Observer Pattern）
- `ManagedChannelStateListener` 监听通道状态变化
- Spring Event：`RegisterKusciaEvent`、`UnRegisterKusciaEvent`

#### 5. 代理模式（Proxy Pattern）
- `TokenAuthClientInterceptor` 代理 gRPC 调用，添加认证逻辑
- `KusciaGrpcLoggingInterceptor` 代理 gRPC 调用，添加日志记录

---

## 七、使用示例

### 7.1 配置节点

#### 方式一：YAML 配置
```yaml
secretpad:
  node-id: alice
  kuscia-path: ./config/kuscia/
  
dynamic-kuscia-grpc-config:
  nodes:
    - domain-id: alice
      host: 192.168.1.100
      port: 8080
      protocol: TLS
      mode: P2P
      token: /path/to/token
      cert-file: /path/to/cert.pem
      key-file: /path/to/key.pem
    
    - domain-id: bob
      host: 192.168.1.101
      port: 8080
      protocol: MTLS
      mode: P2P
      token: /path/to/token
      cert-file: /path/to/cert.pem
      key-file: /path/to/key.pem
```

#### 方式二：编程式注册
```java
@Resource
private DynamicKusciaChannelProvider channelProvider;

public void registerNode() {
    KusciaGrpcConfig config = KusciaGrpcConfig.builder()
        .domainId("alice")
        .host("192.168.1.100")
        .port(8080)
        .protocol(KusciaProtocolEnum.TLS)
        .mode(KusciaModeEnum.P2P)
        .token("/path/to/token")
        .certFile("/path/to/cert.pem")
        .keyFile("/path/to/key.pem")
        .build();
    
    channelProvider.registerKuscia(config);
}
```

### 7.2 调用 Kuscia API

```java
@Service
public class MyBusinessService {
    
    @Resource
    private KusciaGrpcClientAdapter kusciaClient;
    
    /**
     * 创建域数据
     */
    public void createDomainData(String domainId) {
        Domaindata.CreateDomainDataRequest request = 
            Domaindata.CreateDomainDataRequest.newBuilder()
                .setDomainDataId("data-001")
                .setName("test_data")
                .setType(Domaindata.DomainDataType.TABLE)
                .build();
        
        // 指定 domainId 调用
        Domaindata.CreateDomainDataResponse response = 
            kusciaClient.createDomainData(request, domainId);
        
        log.info("Create domain data result: {}", response.getStatus());
    }
    
    /**
     * 创建隐私计算任务
     */
    public void createJob(String domainId) {
        Job.CreateJobRequest request = 
            Job.CreateJobRequest.newBuilder()
                .setJobId("job-001")
                .setJobType(Job.JobType.PSI)
                .addAllParties(/* 参与方列表 */)
                .build();
        
        Job.CreateJobResponse response = 
            kusciaClient.createJob(request, domainId);
        
        log.info("Create job result: {}", response.getStatus());
    }
    
    /**
     * 查询任务状态
     */
    public Job.QueryJobResponse queryJobStatus(String domainId, String jobId) {
        Job.QueryJobRequest request = 
            Job.QueryJobRequest.newBuilder()
                .setJobId(jobId)
                .build();
        
        return kusciaClient.queryJob(request, domainId);
    }
}
```

### 7.3 使用 Mock 服务器进行测试

```java
@SpringBootTest
public class KusciaClientTest {
    
    private MockKusciaGrpcServer mockServer;
    
    @Autowired
    private KusciaGrpcClientAdapter kusciaClient;
    
    @BeforeEach
    public void setUp() throws Exception {
        // 启动 Mock 服务器
        mockServer = new MockKusciaGrpcServer();
        mockServer.start();
        
        // 注册 Mock 节点
        KusciaGrpcConfig config = mockServer.buildKusciaGrpcConfig("test-node");
        // ... 注册逻辑
    }
    
    @Test
    public void testCreateDomainData() {
        Domaindata.CreateDomainDataRequest request = /* ... */;
        Domaindata.CreateDomainDataResponse response = 
            kusciaClient.createDomainData(request, "test-node");
        
        assertNotNull(response);
        assertEquals(Status.Code.OK, response.getStatus().getCode());
    }
    
    @AfterEach
    public void tearDown() {
        if (mockServer != null) {
            mockServer.shutdown();
        }
    }
}
```

---

## 八、Kuscia 节点配置详解

### 8.1 配置文件位置

SecretPad 中的 Kuscia 节点配置位于以下文件中：

**主配置文件：**
```
config/application.yaml
```

**环境特定配置：**
- `config/application-dev.yaml` - 开发环境
- `config/application-edge.yaml` - 边缘模式
- `config/application-p2p.yaml` - P2P 模式
- `config/application-test.yaml` - 测试环境

### 8.2 节点配置结构

#### YAML 配置格式

```yaml
# ------------------------------------------------------------
# Kuscia API 通信协议配置
# ------------------------------------------------------------
kusciaapi:
  protocol: ${KUSCIA_PROTOCOL:tls}  # 通信协议：tls（加密）或 grpc（明文）

# ------------------------------------------------------------
# Kuscia 节点集群配置
# ------------------------------------------------------------
kuscia:
  nodes:
    # ---- 中心节点（Master）配置 ----
    - domainId: ${NODE_ID:kuscia-system}               # 域 ID：唯一标识节点
      mode: master                                     # 节点模式：master（中心调度节点）
      host: ${KUSCIA_API_ADDRESS:root-kuscia-master}   # Kuscia API 服务地址
      port: ${KUSCIA_API_PORT:8083}                    # Kuscia API 服务端口
      protocol: ${KUSCIA_PROTOCOL:tls}                 # 通信协议：TLS 加密
      cert-file: config/certs/client.crt               # 客户端证书文件路径
      key-file: config/certs/client.pem                # 客户端私钥文件路径
      token: config/certs/token                        # 访问令牌文件路径

    # ---- 参与方节点 Alice 配置 ----
    - domainId: alice                                  # Alice 参与方的域 ID
      mode: lite                                       # 节点模式：lite（轻量级参与方节点）
      host: ${KUSCIA_API_LITE_ALICE_ADDRESS:root-kuscia-lite-alice}
      port: ${KUSCIA_API_PORT:8083}
      protocol: ${KUSCIA_PROTOCOL:tls}
      cert-file: config/certs/alice/client.crt
      key-file: config/certs/alice/client.pem
      token: config/certs/alice/token

    # ---- 参与方节点 Bob 配置 ----
    - domainId: bob
      mode: lite
      host: ${KUSCIA_API_LITE_BOB_ADDRESS:root-kuscia-lite-bob}
      port: ${KUSCIA_API_PORT:8083}
      protocol: ${KUSCIA_PROTOCOL:tls}
      cert-file: config/certs/bob/client.crt
      key-file: config/certs/bob/client.pem
      token: config/certs/bob/token
```

### 8.3 配置项详解

#### 节点配置字段说明

| 字段 | 类型 | 必填 | 说明 | 示例值 |
|------|------|------|------|--------|
| `domainId` | String | ✅ | 域唯一标识符，在整个系统中必须唯一 | `alice`, `bob`, `kuscia-system` |
| `mode` | Enum | ✅ | 节点模式 | `master`（中心节点）, `lite`（参与方） |
| `host` | String | ✅ | Kuscia API 服务地址（IP 或域名） | `192.168.1.100`, `kuscia-master.svc` |
| `port` | Integer | ✅ | API 端口号 | `8083` |
| `protocol` | Enum | ✅ | 通信协议 | `tls`（加密）, `mtls`（双向认证）, `notls`（明文） |
| `cert-file` | String | TLS/MTLS | TLS 证书文件路径（PEM 格式） | `config/certs/client.crt` |
| `key-file` | String | TLS/MTLS | TLS 私钥文件路径（PEM 格式） | `config/certs/client.pem` |
| `token` | String | TLS/MTLS | 访问令牌文件路径或内容 | `config/certs/token` |

#### 节点模式说明

**1. Master 模式（中心节点）**
- **用途**：作为隐私计算网络的中心调度节点
- **职责**：
  - 协调多个参与方节点的任务执行
  - 管理任务调度和资源分配
  - 维护全局状态和元数据
- **典型场景**：中心化部署架构

**2. Lite 模式（参与方节点）**
- **用途**：作为隐私计算的参与方
- **职责**：
  - 执行具体的计算任务（PSI、联邦学习等）
  - 管理本地数据和模型
  - 与其他节点协同完成隐私计算
- **典型场景**：Alice、Bob 等数据持有方

### 8.4 环境变量支持

所有关键配置都支持通过环境变量覆盖，方便在不同环境中部署：

```bash
# 设置当前节点 ID
export NODE_ID=alice

# 设置 Kuscia API 地址
export KUSCIA_API_ADDRESS=192.168.1.100
export KUSCIA_API_LITE_ALICE_ADDRESS=192.168.1.101
export KUSCIA_API_LITE_BOB_ADDRESS=192.168.1.102

# 设置 API 端口
export KUSCIA_API_PORT=8083

# 设置通信协议
export KUSCIA_PROTOCOL=tls

# 设置网关地址
export KUSCIA_GW_ADDRESS=192.168.1.100:80

# 启动应用
java -jar secretpad.jar
```

**优先级：**
1. 环境变量（最高优先级）
2. YAML 配置文件中的默认值
3. 代码中的硬编码默认值

#### 8.4.1 Spring Boot 占位符机制详解

SecretPad 使用 Spring Boot 的**占位符（Placeholder）**机制实现配置的灵活注入。

##### 语法格式

在 `application.yaml` 中，配置项使用以下语法：

```yaml
host: ${KUSCIA_API_ADDRESS:root-kuscia-master}
     ^^^^^^^^^^^^^^^^^^^^ ^^^^^^^^^^^^^^^^^^
             |                    |
             |                    └─ 默认值（当环境变量不存在时使用）
             |
             └─ 环境变量名称
```

**语法规则：**
```
${环境变量名:默认值}
```

- **如果环境变量存在** → 使用环境变量的值
- **如果环境变量不存在** → 使用冒号后面的默认值

##### 赋值流程（优先级从高到低）

**方式 1：操作系统环境变量（最高优先级）**

```bash
# 在启动应用前设置环境变量
export KUSCIA_API_ADDRESS=192.168.1.100

# 或者在命令行中直接传递
KUSCIA_API_ADDRESS=192.168.1.100 java -jar secretpad.jar
```

**结果：** `host = "192.168.1.100"`

---

**方式 2：Docker/Kubernetes 环境变量**

**Docker Compose 示例：**
```yaml
version: '3'
services:
  secretpad:
    image: secretpad:latest
    environment:
      - KUSCIA_API_ADDRESS=kuscia-master.svc.cluster.local
```

**Kubernetes 示例：**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secretpad
spec:
  containers:
    - name: secretpad
      image: secretpad:latest
      env:
        - name: KUSCIA_API_ADDRESS
          value: "kuscia-master.production.svc"
```

**结果：** `host = "kuscia-master.svc.cluster.local"` 或 `"kuscia-master.production.svc"`

---

**方式 3：使用默认值（最常见）**

如果没有设置任何环境变量，Spring Boot 会使用 YAML 中定义的默认值：

```yaml
host: ${KUSCIA_API_ADDRESS:root-kuscia-master}
                              ^^^^^^^^^^^^^^^^^^
                              这就是默认值
```

**结果：** `host = "root-kuscia-master"`

##### 代码层面的处理

**步骤 1：Spring Boot 自动绑定**

`DynamicKusciaGrpcConfig` 类使用 `@ConfigurationProperties` 注解：

```java
@Configuration
@ConfigurationProperties(prefix = "kuscia")
public class DynamicKusciaGrpcConfig {
    private CopyOnWriteArraySet<KusciaGrpcConfig> nodes;
}
```

**工作原理：**
1. Spring Boot 读取 `application.yaml` 中的 `kuscia.nodes` 配置
2. 自动解析 `${KUSCIA_API_ADDRESS:root-kuscia-master}` 占位符
3. 根据环境变量是否存在，决定使用哪个值
4. 将最终值注入到 `KusciaGrpcConfig.host` 字段

---

**步骤 2：配置验证和处理**

`KusciaGrpcConfig.validateAndProcess()` 方法会进一步处理：

```java
public void validateAndProcess() {
    // 1. 参数校验（domainId、host、port 等不能为空）
    ValidatorFactory factory = Validation.buildDefaultValidatorFactory();
    Validator validator = factory.getValidator();
    Set<ConstraintViolation<KusciaGrpcConfig>> violations = validator.validate(this);
    
    for (ConstraintViolation<KusciaGrpcConfig> violation : violations) {
        throw new IllegalArgumentException("Invalid KusciaGrpcConfig: " + violation.getMessage());
    }
    
    // 2. 支持 host:port 格式自动拆分
    if (this.host.contains(":")) {
        this.port = Integer.parseInt(host.split(":")[1]);
        this.host = host.split(":")[0];
    }
    
    // 3. 根据协议类型处理证书和令牌
    switch (protocol) {
        case MTLS, TLS -> {
            // 读取证书文件和令牌文件内容
            if (new File(this.token).exists()) {
                this.token = FileUtils.readFile2String(token);
            }
        }
        case NOTLS -> {
            // 无需证书
        }
    }
}
```

##### 实际应用场景对比

| 场景 | 环境变量设置 | 最终 host 值 | 说明 |
|------|-------------|-------------|------|
| **本地开发** | 未设置 | `root-kuscia-master` | 使用默认值（通常是 Docker 容器名） |
| **Docker 部署** | `KUSCIA_API_ADDRESS=kuscia-master` | `kuscia-master` | Docker 内部网络域名 |
| **K8s 生产环境** | `KUSCIA_API_ADDRESS=kuscia-master.prod.svc` | `kuscia-master.prod.svc` | Kubernetes Service 名称 |
| **测试环境** | `KUSCIA_API_ADDRESS=192.168.1.100` | `192.168.1.100` | 直接指定 IP 地址 |

##### 为什么默认值是 `root-kuscia-master`？

这个命名遵循了 **Kuscia 框架的约定**：

1. **`root-`**：表示根节点/主节点
2. **`kuscia`**：框架名称
3. **`master`**：节点角色（中心调度节点）

在 Docker Compose 或 Kubernetes 部署时，Kuscia Master 节点的服务名称通常就是 `root-kuscia-master`，这样可以通过**容器内部 DNS** 自动解析。

##### 如何验证当前使用的值？

**方法 1：查看应用日志**

启动应用时会输出配置信息：

```java
// DynamicKusciaChannelProvider.init() 方法
log.info("Init kuscia node, config={}", config);
```

日志输出示例：
```
Init kuscia node, config=KusciaGrpcConfig(domainId=kuscia-system, 
                                          host=root-kuscia-master, 
                                          port=8083, 
                                          protocol=TLS, 
                                          mode=MASTER)
```

---

**方法 2：通过 API 查询**

可以添加一个调试接口返回当前配置：

```java
@RestController
@RequestMapping("/api/debug")
public class DebugController {
    
    @Autowired
    private DynamicKusciaGrpcConfig config;
    
    @GetMapping("/kuscia-nodes")
    public List<KusciaGrpcConfig> getNodes() {
        return new ArrayList<>(config.getNodes());
    }
}
```

访问 `http://localhost:8080/api/debug/kuscia-nodes` 即可查看。

##### 修改默认值的方法

**场景 1：修改为其他容器名**

编辑 `config/application.yaml`：

```yaml
kuscia:
  nodes:
    - domainId: kuscia-system
      host: ${KUSCIA_API_ADDRESS:my-kuscia-master}  # 改为自定义名称
```

---

**场景 2：强制使用环境变量**

删除默认值，要求必须设置环境变量：

```yaml
kuscia:
  nodes:
    - domainId: kuscia-system
      host: ${KUSCIA_API_ADDRESS}  # 没有默认值，必须设置环境变量
```

**注意：** 如果未设置环境变量，应用启动会失败！

---

**场景 3：不同环境使用不同默认值**

创建环境特定的配置文件：

**`config/application-dev.yaml`（开发环境）：**
```yaml
kuscia:
  nodes:
    - domainId: kuscia-system
      host: localhost  # 本地开发直接使用 localhost
```

**`config/application-prod.yaml`（生产环境）：**
```yaml
kuscia:
  nodes:
    - domainId: kuscia-system
      host: ${KUSCIA_API_ADDRESS:kuscia-master.production.svc}
```

启动时指定环境：
```bash
java -jar secretpad.jar --spring.profiles.active=prod
```

##### 完整的环境变量列表

以下是 SecretPad 支持的所有与 Kuscia 相关的环境变量：

| 环境变量 | 默认值 | 说明 | 示例值 |
|---------|--------|------|--------|
| `NODE_ID` | `kuscia-system` | 当前节点的唯一标识 | `alice`, `bob` |
| `KUSCIA_API_ADDRESS` | `root-kuscia-master` | 中心节点 API 地址 | `192.168.1.100` |
| `KUSCIA_API_LITE_ALICE_ADDRESS` | `root-kuscia-lite-alice` | Alice 节点 API 地址 | `alice.kuscia.svc` |
| `KUSCIA_API_LITE_BOB_ADDRESS` | `root-kuscia-lite-bob` | Bob 节点 API 地址 | `bob.kuscia.svc` |
| `KUSCIA_API_PORT` | `8083` | Kuscia API 端口 | `8083` |
| `KUSCIA_PROTOCOL` | `tls` | 通信协议 | `tls`, `mtls`, `notls` |
| `KUSCIA_GW_ADDRESS` | `127.0.0.1:80` | Kuscia 网关地址 | `kuscia-gw:80` |
| `SECRETPAD_LOG_PATH` | `/app/log` | 日志文件路径 | `/var/log/secretpad` |
| `DEPLOY_MODE` | `ALL-IN-ONE` | 部署模式 | `MPC`, `TEE`, `ALL-IN-ONE` |
| `SECRETPAD_USER_NAME` | - | 管理员用户名 | `admin` |
| `SECRETPAD_PASSWORD` | - | 管理员密码 | `secret123` |
| `DATAPROXY_ENABLE` | `true` | 启用数据代理 | `true`, `false` |
| `SCQL_ENABLE` | `true` | 启用 SCQL | `true`, `false` |

**使用示例：**

```bash
# 完整的 Docker 启动命令
docker run -d \
  --name secretpad \
  -e NODE_ID=alice \
  -e KUSCIA_API_ADDRESS=kuscia-master.svc \
  -e KUSCIA_API_PORT=8083 \
  -e KUSCIA_PROTOCOL=tls \
  -e SECRETPAD_LOG_PATH=/var/log/secretpad \
  -e DEPLOY_MODE=MPC \
  -p 8080:8080 \
  secretpad:latest
```

### 8.7 证书文件配置

#### 证书目录结构

```
config/certs/
├── client.crt          # 中心节点客户端证书
├── client.pem          # 中心节点客户端私钥
├── token               # 中心节点访问令牌
├── alice/
│   ├── client.crt      # Alice 节点证书
│   ├── client.pem      # Alice 节点私钥
│   └── token           # Alice 节点令牌
└── bob/
    ├── client.crt      # Bob 节点证书
    ├── client.pem      # Bob 节点私钥
    └── token           # Bob 节点令牌
```

#### 证书生成（示例）

```bash
# 1. 生成 CA 私钥和证书
openssl genrsa -out ca.key 2048
openssl req -x509 -new -nodes -key ca.key -sha256 -days 365 -out ca.crt

# 2. 为 Alice 节点生成证书
openssl genrsa -out alice/client.key 2048
openssl req -new -key alice/client.key -out alice/client.csr
openssl x509 -req -in alice/client.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out alice/client.crt -days 365 -sha256

# 3. 生成访问令牌
echo "your-token-content" > alice/token
chmod 600 alice/token  # 设置权限，仅所有者可读写
```

#### 证书格式要求

**证书文件（.crt）：**
```
-----BEGIN CERTIFICATE-----
MIID...（Base64 编码的证书内容）
-----END CERTIFICATE-----
```

**私钥文件（.pem）：**
```
-----BEGIN PRIVATE KEY-----
MIIE...（Base64 编码的私钥内容）
-----END PRIVATE KEY-----
```

**令牌文件（token）：**
```
your-access-token-string
```

### 8.8 编程式节点注册

除了静态配置文件，还支持运行时动态注册节点：

#### Java 代码示例

```java
@Service
public class NodeRegistrationService {
    
    @Resource
    private DynamicKusciaChannelProvider channelProvider;
    
    /**
     * 动态注册新的 Kuscia 节点
     */
    public void registerNode(String domainId, String host, int port) {
        // 1. 构建节点配置
        KusciaGrpcConfig config = KusciaGrpcConfig.builder()
            .domainId(domainId)                    // 域 ID
            .host(host)                            // API 地址
            .port(port)                            // API 端口
            .protocol(KusciaProtocolEnum.TLS)      // 通信协议
            .mode(KusciaModeEnum.LITE)             // 节点模式
            .token("/path/to/token")               // 令牌文件路径
            .certFile("/path/to/cert.crt")         // 证书文件路径
            .keyFile("/path/to/key.pem")           // 私钥文件路径
            .build();
        
        // 2. 验证配置（自动检查必需字段）
        config.validateAndProcess();
        
        // 3. 注册节点
        channelProvider.registerKuscia(config);
        
        log.info("Successfully registered node: {}", domainId);
    }
    
    /**
     * 注销节点
     */
    public void unregisterNode(String domainId) {
        channelProvider.unRegisterKuscia(domainId);
        log.info("Successfully unregistered node: {}", domainId);
    }
    
    /**
     * 检查节点是否已注册
     */
    public boolean isNodeRegistered(String domainId) {
        return channelProvider.isChannelExist(domainId);
    }
}
```

#### 使用场景

**场景 1：动态添加新参与方**
```java
// 当新的数据方加入时，动态注册节点
nodeRegistrationService.registerNode(
    "charlie",              // 新参与方 ID
    "192.168.1.103",        // API 地址
    8083                    // API 端口
);
```

**场景 2：从数据库加载节点配置**
```java
@Service
public class DatabaseNodeLoader {
    
    @Resource
    private NodeRepository nodeRepository;
    
    @Resource
    private DynamicKusciaChannelProvider channelProvider;
    
    @PostConstruct
    public void loadNodesFromDatabase() {
        // 从数据库查询所有节点配置
        List<NodeConfig> nodes = nodeRepository.findAll();
        
        for (NodeConfig node : nodes) {
            KusciaGrpcConfig config = KusciaGrpcConfig.builder()
                .domainId(node.getDomainId())
                .host(node.getHost())
                .port(node.getPort())
                .protocol(KusciaProtocolEnum.valueOf(node.getProtocol()))
                .mode(KusciaModeEnum.valueOf(node.getMode()))
                .token(node.getTokenPath())
                .certFile(node.getCertPath())
                .keyFile(node.getKeyPath())
                .build();
            
            channelProvider.registerKuscia(config);
        }
        
        log.info("Loaded {} nodes from database", nodes.size());
    }
}
```

**场景 3：节点健康检查与自动重连**
```java
@Service
public class NodeHealthChecker {
    
    @Resource
    private DynamicKusciaChannelProvider channelProvider;
    
    @Scheduled(fixedRate = 30000)  // 每 30 秒检查一次
    public void checkNodeHealth() {
        List<KusciaGrpcConfig> nodes = getAllConfiguredNodes();
        
        for (KusciaGrpcConfig node : nodes) {
            String domainId = node.getDomainId();
            
            // 检查节点是否已注册
            if (!channelProvider.isChannelExist(domainId)) {
                log.warn("Node {} is not registered, attempting to register...", domainId);
                try {
                    channelProvider.registerKuscia(node);
                    log.info("Successfully re-registered node: {}", domainId);
                } catch (Exception e) {
                    log.error("Failed to register node: {}", domainId, e);
                }
            }
        }
    }
}
```

### 8.9 SecretPad 核心配置关联

在 `application.yaml` 中，还有以下与节点相关的配置：

```yaml
secretpad:
  # 当前节点标识
  node-id: kuscia-system                               # 当前 SecretPad 实例所属的节点 ID
  
  # 平台类型配置
  platform-type: CENTER                                # 平台架构类型：CENTER/EDGE/P2P
  
  # 中心平台服务地址（仅在 CENTER 模式下使用）
  center-platform-service: secretpad.master.svc        # Kubernetes Service 名称
  
  # 网关配置
  gateway: ${KUSCIA_GW_ADDRESS:127.0.0.1:80}          # Kuscia 网关地址
  
  # 组件镜像版本
  version:
    kuscia-image: ${KUSCIA_IMAGE:0.6.0b0}              # Kuscia 框架镜像版本
```

**配置说明：**

| 配置项 | 说明 | 取值 |
|--------|------|------|
| `secretpad.node-id` | 当前 SecretPad 实例的节点 ID | 必须与 `kuscia.nodes` 中的某个 `domainId` 匹配 |
| `secretpad.platform-type` | 平台架构类型 | `CENTER`（中心化）、`EDGE`（边缘）、`P2P`（点对点） |
| `secretpad.center-platform-service` | 中心服务地址 | 仅在 CENTER 模式下使用 |
| `secretpad.gateway` | Kuscia 网关地址 | 用于数据传输和任务调度 |

### 8.10 多节点管理最佳实践

#### 1. 节点命名规范

```yaml
# ✅ 推荐：使用有意义的名称
kuscia:
  nodes:
    - domainId: alice-data-center      # 清晰表达节点角色和位置
    - domainId: bob-cloud-region-1
    - domainId: tee-secure-node

# ❌ 避免：使用无意义的名称
kuscia:
  nodes:
    - domainId: node1
    - domainId: node2
```

#### 2. 证书安全管理

```bash
# ✅ 推荐：设置严格的文件权限
chmod 600 config/certs/*.pem
chmod 600 config/certs/*/client.pem
chmod 644 config/certs/*.crt  # 证书可以公开读取

# ✅ 推荐：使用环境变量传递敏感信息
export TOKEN_CONTENT="your-secret-token"
export CERT_PATH="/secure/path/to/cert"

# ❌ 避免：将令牌内容硬编码在配置文件中
```

#### 3. 网络隔离

```yaml
# 生产环境建议：使用内网地址
kuscia:
  nodes:
    - domainId: alice
      host: 10.0.1.100  # 内网 IP
      # host: alice.example.com  # 或使用内网域名
```

#### 4. 超时配置

```java
// 根据网络状况调整超时时间
KusciaGrpcConfig config = KusciaGrpcConfig.builder()
    .domainId("remote-node")
    .host("192.168.1.100")
    .port(8083)
    .protocol(KusciaProtocolEnum.TLS)
    // ... 其他配置
    .build();

// 注意：超时时间在 DynamicKusciaChannelProvider 中统一配置
// BLOCKING_TIMEOUT_MILLISECOND = 5000ms（同步调用）
// FUTURE_TIMEOUT_MILLISECOND = 5000ms（异步调用）
// StubSCRIPTION_TIMEOUT_DAY = 365天（流式调用）
```

#### 5. 日志与监控

```java
// 启用 gRPC 日志以便调试
logging:
  level:
    io.grpc: DEBUG
    org.secretflow.secretpad.kuscia: DEBUG

// 监控节点连接状态
@Component
public class NodeConnectionMonitor {
    
    @Resource
    private DynamicKusciaChannelProvider channelProvider;
    
    @Scheduled(fixedRate = 60000)  // 每分钟检查一次
    public void monitorConnections() {
        List<KusciaGrpcConfig> nodes = getAllNodes();
        
        for (KusciaGrpcConfig node : nodes) {
            String domainId = node.getDomainId();
            boolean connected = channelProvider.isChannelExist(domainId);
            
            // 上报监控指标
            Metrics.counter("kuscia.node.connection",
                "domainId", domainId,
                "status", connected ? "connected" : "disconnected"
            ).increment();
            
            if (!connected) {
                log.warn("Node {} is disconnected", domainId);
                // 触发告警
                alertService.sendAlert("Node disconnected: " + domainId);
            }
        }
    }
}
```

### 8.11 常见问题排查

#### Q1: 连接被拒绝（Connection Refused）

**可能原因：**
1. Kuscia API 服务未启动
2. 主机地址或端口配置错误
3. 防火墙阻止了连接

**解决方法：**
```bash
# 1. 检查 Kuscia 服务是否运行
kubectl get pods -n kuscia

# 2. 测试网络连通性
telnet 192.168.1.100 8083

# 3. 检查防火墙规则
sudo iptables -L -n | grep 8083
```

#### Q2: TLS 握手失败

**可能原因：**
1. 证书过期
2. 证书与私钥不匹配
3. 证书链不完整

**解决方法：**
```bash
# 1. 检查证书有效期
openssl x509 -in config/certs/client.crt -noout -dates

# 2. 验证证书和私钥是否匹配
openssl x509 -noout -modulus -in config/certs/client.crt | openssl md5
openssl rsa -noout -modulus -in config/certs/client.pem | openssl md5
# 两个 MD5 值应该相同

# 3. 检查证书链
openssl verify -CAfile ca.crt config/certs/client.crt
```

#### Q3: Token 认证失败

**可能原因：**
1. Token 文件路径错误
2. Token 内容不正确
3. Token 已过期

**解决方法：**
```bash
# 1. 检查 Token 文件是否存在
ls -l config/certs/token

# 2. 查看 Token 内容
cat config/certs/token

# 3. 确保文件权限正确
chmod 600 config/certs/token
```

#### Q4: 节点未找到（No such kuscia instance）

**错误信息：**
```
IllegalArgumentException: No such kuscia instance domain id: charlie
```

**原因：**
尝试使用未注册的节点 ID

**解决方法：**
```java
// 方法 1: 在配置文件中添加节点
// config/application.yaml
kuscia:
  nodes:
    - domainId: charlie
      # ... 其他配置

// 方法 2: 运行时动态注册
KusciaGrpcConfig config = /* ... */;
channelProvider.registerKuscia(config);

// 方法 3: 检查节点是否已注册
if (!channelProvider.isChannelExist("charlie")) {
    log.error("Node 'charlie' is not registered!");
}
```

### 8.12 `config/kuscia` 文件夹作用详解

#### 📁 文件夹位置与结构

```
config/kuscia/
├── alice              # Alice 节点的序列化配置
├── bob                # Bob 节点的序列化配置
├── kuscia-system      # 中心节点的序列化配置
└── tee                # TEE 节点的序列化配置
```

**注意：** 这些文件是 **Java 序列化二进制文件**，不能用文本编辑器直接查看或修改。

---

#### 🎯 核心功能

`config/kuscia` 文件夹用于**持久化存储动态注册的 Kuscia 节点配置**。它是一个基于 Java 对象序列化的轻量级配置存储机制。

**主要作用：**
1. **持久化动态配置**：运行时动态添加的节点不会在重启后丢失
2. **自动加载**：应用启动时自动读取并注册这些节点
3. **配置分离**：静态配置放在 `application.yaml`，动态配置放在此文件夹
4. **热插拔支持**：支持不修改配置文件的情况下动态添加/删除节点

---

#### 🔄 工作原理

##### 1️⃣ 配置加载流程（应用启动时）

在 `DynamicKusciaChannelProvider.init()` 方法中：

```java
@Value("${secretpad.kuscia-path:./config/kuscia/}")
private String kusciaPath;

@PostConstruct
public void init() {
    // 步骤 1: 先从 application.yaml 加载节点配置
    if (!CollectionUtils.isEmpty(dynamicKusciaGrpcConfig.getNodes())) {
        for (KusciaGrpcConfig config : dynamicKusciaGrpcConfig.getNodes()) {
            registerKuscia(config);
        }
    }
    
    // 步骤 2: 再从 config/kuscia 文件夹加载序列化配置
    serializableKusciaConfigFileInit();
}

private void serializableKusciaConfigFileInit() throws IOException, ClassNotFoundException {
    ObjectInputStream in = null;
    KusciaGrpcConfig config;
    File file = ResourceUtils.getFile(kusciaPath);
    if (Files.exists(file.toPath())) {
        // 遍历文件夹中的所有文件
        for (File f : Objects.requireNonNull(file.listFiles())) {
            // 反序列化读取每个文件
            in = new ObjectInputStream(new FileInputStream(f));
            config = (KusciaGrpcConfig) in.readObject();
            log.info("Load kuscia config by config file, config={}", config);
            // 注册节点
            registerKuscia(config);
        }
    }
    IOUtils.closeQuietly(in);
}
```

**加载顺序：**
1. 从 `application.yaml` 的 `kuscia.nodes` 配置项加载
2. 从 `config/kuscia` 文件夹中的序列化文件加载

**注意：** 如果两个地方有相同的 `domainId`，后加载的配置会覆盖先加载的配置。

---

##### 2️⃣ 配置保存流程（动态注册节点时）

在 `KusciaRegisterListener.onApplicationEvent()` 方法中：

```java
@Component
public class KusciaRegisterListener implements ApplicationListener<RegisterKusciaEvent> {

    @Setter
    @Value("${secretpad.kuscia-path:./config/kuscia/}")
    private String kusciaPath;

    @Override
    public void onApplicationEvent(RegisterKusciaEvent event) {
        KusciaGrpcConfig config = event.getConfig();
        log.info("KusciaRegisterListener: {}", config);
        
        // 业务逻辑处理...
        jobManager.startSync(config.getDomainId());
        
        // 将新注册的节点配置序列化保存到 config/kuscia 文件夹
        serializableWrite(config);
    }

    public void serializableWrite(KusciaGrpcConfig config) {
        ObjectOutputStream os = null;
        try {
            // 文件名 = domainId（如 "alice", "bob"）
            File file = ResourceUtils.getFile(kusciaPath + config.getDomainId());
            if (!Files.exists(file.toPath().getParent())) {
                Files.createDirectories(file.toPath().getParent());
            }
            if (!Files.exists(file.toPath())) {
                Files.createFile(file.toPath());
            }
            // 序列化写入配置对象
            os = new ObjectOutputStream(new FileOutputStream(file));
            os.writeObject(config);
        } catch (Exception e) {
            log.error("KusciaRegisterListener serializableWrite error: {}", e.getMessage(), e);
        } finally {
            IOUtils.closeQuietly(os);
        }
    }
}
```

**保存时机：**
- 当通过 `DynamicKusciaChannelProvider.registerKuscia()` 动态注册新节点时
- 触发 `RegisterKusciaEvent` 事件
- 监听器自动将配置序列化到 `config/kuscia/{domainId}` 文件

---

#### 📊 当前文件夹内容示例

根据实际文件分析，当前有 4 个节点配置文件：

| 文件名 | Domain ID | Mode | Host | Port | Protocol | Cert Path |
|--------|-----------|------|------|------|----------|-----------|
| `alice` | alice | LITE | 127.0.0.1 | 8083 | NOTLS | config/certs/alice/client.crt |
| `bob` | bob | LITE | 127.0.0.1 | 8083 | NOTLS | config/certs/bob/client.crt |
| `kuscia-system` | kuscia-system | MASTER | 127.0.0.1 | 8083 | NOTLS | config/certs/client.crt |
| `tee` | tee | LITE | root-kuscia-lite-tee | 8083 | NOTLS | config/certs/tee/client.crt |

**文件格式：** Java 序列化二进制文件（不可直接阅读）

---

#### 💡 设计优势

##### ✅ 优势

1. **持久化动态配置**
   - 运行时动态添加的节点不会在重启后丢失
   - 类似“热插拔”机制

2. **配置分离**
   - 静态配置放在 `application.yaml`
   - 动态配置放在 `config/kuscia/` 文件夹

3. **简单高效**
   - 无需数据库支持
   - 直接使用 Java 序列化机制

4. **灵活性**
   - 支持多种配置来源
   - 可以混合使用 YAML 配置和序列化配置

---

##### ⚠️ 注意事项

**1. 文件格式是二进制的**

这些文件是 Java 序列化对象，不能用文本编辑器直接查看或修改。如果需要查看内容，需要：

```java
// 读取序列化文件
ObjectInputStream in = new ObjectInputStream(new FileInputStream("config/kuscia/alice"));
KusciaGrpcConfig config = (KusciaGrpcConfig) in.readObject();
System.out.println(config);
// 输出：KusciaGrpcConfig(domainId=alice, host=127.0.0.1, port=8083, ...)
```

**2. 可能的配置冲突**

如果 `application.yaml` 和 `config/kuscia` 中有相同的 `domainId`，会发生什么？

从代码看：
```java
public void registerKuscia(KusciaGrpcConfig config) {
    // 如果已存在，先注销再注册（覆盖）
    if (dynamicKusciaGrpcConfig.getNodes().contains(config)) {
        log.info("KusciaGrpcConfig already exists, unRegisterKuscia config={}", config);
        unRegisterKuscia(config);
    }
    // ...
}
```

**结论：** 后加载的配置会覆盖先加载的配置。

**3. 清理建议**

如果需要重置配置，可以：

```bash
# 删除所有序列化配置文件
rm -rf config/kuscia/*

# 或者保留 application.yaml 中的配置，只删除动态添加的
rm config/kuscia/alice config/kuscia/bob
```

---

#### 🔧 实际应用场景

##### 场景 1：开发环境调试

```bash
# 1. 启动应用，从 application.yaml 加载基础配置
java -jar secretpad.jar

# 2. 运行时通过 API 动态添加测试节点
curl -X POST http://localhost:8080/api/node/register \
  -d '{"domainId":"test-node","host":"192.168.1.100","port":8083}'

# 3. 配置自动保存到 config/kuscia/test-node

# 4. 重启应用，test-node 会自动加载
```

---

##### 场景 2：生产环境动态扩容

```java
@Service
public class NodeExpansionService {
    
    @Resource
    private DynamicKusciaChannelProvider channelProvider;
    
    /**
     * 新参与方加入时，无需修改配置文件，直接调用 API
     */
    public void addNewParticipant(String domainId, String host, int port) {
        KusciaGrpcConfig config = KusciaGrpcConfig.builder()
            .domainId(domainId)
            .host(host)
            .port(port)
            .protocol(KusciaProtocolEnum.TLS)
            .mode(KusciaModeEnum.LITE)
            .certFile("config/certs/" + domainId + "/client.crt")
            .keyFile("config/certs/" + domainId + "/client.pem")
            .token("config/certs/" + domainId + "/token")
            .build();
        
        // 注册节点（自动持久化到 config/kuscia/）
        channelProvider.registerKuscia(config);
        
        log.info("New participant added: {}", domainId);
    }
}
```

**使用示例：**

```java
// 添加新的参与方 Charlie
nodeExpansionService.addNewParticipant("charlie", "10.0.1.200", 8083);

// 配置文件 config/kuscia/charlie 自动创建
// 重启应用后，Charlie 节点会自动加载
```

---

##### 场景 3：临时节点测试

```java
@Test
public void testTemporaryNode() {
    // 1. 创建临时节点配置
    KusciaGrpcConfig tempConfig = KusciaGrpcConfig.builder()
        .domainId("temp-test-node")
        .host("localhost")
        .port(8083)
        .protocol(KusciaProtocolEnum.NOTLS)
        .mode(KusciaModeEnum.LITE)
        .build();
    
    // 2. 注册节点（会持久化到 config/kuscia/temp-test-node）
    channelProvider.registerKuscia(tempConfig);
    
    // 3. 执行测试...
    assertTrue(channelProvider.isChannelExist("temp-test-node"));
    
    // 4. 测试完成后删除临时节点
    channelProvider.unRegisterKuscia("temp-test-node");
    
    // 5. 手动删除配置文件（可选）
    new File("config/kuscia/temp-test-node").delete();
}
```

---

#### 📝 总结

`config/kuscia` 文件夹的作用是：

1. **持久化存储**：保存运行时动态注册的 Kuscia 节点配置
2. **自动加载**：应用启动时自动读取并注册这些节点
3. **配置备份**：作为 `application.yaml` 配置的补充和扩展
4. **热插拔支持**：支持不修改配置文件的情况下动态添加/删除节点

这是一种**轻量级的配置持久化方案**，避免了引入数据库的复杂性，同时保证了配置的灵活性和持久性。

---

## 九、关键技术点

### 9.1 线程安全

#### ConcurrentHashMap
```java
private static final Map<String, KusciaApiChannelFactory> CHANNEL_FACTORIES 
    = new ConcurrentHashMap<>();
```
- 保证多线程环境下通道工厂的读写安全
- 避免同步锁的性能开销

#### 双重检查锁定
```java
public ManagedChannel getChannel() {
    synchronized (this) {
        if (!state.get().equals(ConnectivityState.SHUTDOWN)) {
            return channel;  // 已初始化，直接返回
        }
        assertInitialized();
        initChannel();  // 首次访问时初始化
        return channel;
    }
}
```

### 9.2 资源管理

#### 优雅关闭
```java
@PreDestroy
public void destroy() {
    CHANNEL_FACTORIES.forEach((key, value) -> value.shutdown());
}
```

#### 通道状态管理
```java
@Override
public void shutdown() {
    if (channel != null && !channel.isShutdown()) {
        channel.shutdown();  // 等待正在进行的请求完成
    }
}

@Override
public void shutdownNow() {
    if (channel != null && !channel.isShutdown()) {
        channel.shutdownNow();  // 立即关闭，取消所有请求
    }
}
```

### 9.3 错误处理

#### 配置验证
```java
public void validateAndProcess() {
    ValidatorFactory factory = Validation.buildDefaultValidatorFactory();
    Validator validator = factory.getValidator();
    Set<ConstraintViolation<KusciaGrpcConfig>> violations = validator.validate(this);

    for (ConstraintViolation<KusciaGrpcConfig> violation : violations) {
        throw new IllegalArgumentException("Invalid KusciaGrpcConfig: " + violation.getMessage());
    }
    // ...
}
```

#### 异常传播
- gRPC 调用异常直接抛出 `StatusRuntimeException`
- 业务层捕获并转换为自定义异常

### 9.4 性能优化

#### 连接复用
- 每个 domainId 只创建一个 `ManagedChannel`
- 多个 Stub 共享同一个 Channel

#### 消息大小限制
```java
private final static int MAX_INBOUND_MESSAGE_SIZE = 256 * 1024 * 1024; // 256MB

NettyChannelBuilder nettyChannelBuilder = NettyChannelBuilder
    .forAddress(host, port)
    .maxInboundMessageSize(MAX_INBOUND_MESSAGE_SIZE);
```

#### OpenSSL 加速
```java
GrpcSslContexts.configure(clientContextBuilder, SslProvider.OPENSSL);
```
- 使用 OpenSSL 替代 JDK 默认 SSL 实现
- 提升 TLS 握手和加解密性能

---

## 十、目录结构

```
client-java-kusciaapi/
├── src/
│   ├── main/java/org/secretflow/secretpad/kuscia/v1alpha1/
│   │   ├── DynamicKusciaChannelProvider.java          # 核心：动态通道提供者
│   │   ├── aspect/
│   │   │   └── KusciaApiServiceAspect.java            # AOP 切面
│   │   ├── configuration/
│   │   │   └── KusciaApiFutureThreadPoolConfig.java   # 线程池配置
│   │   ├── constant/
│   │   │   ├── KusciaAPIConstants.java                # 常量定义
│   │   │   ├── KusciaApiChannelType.java              # 通道类型
│   │   │   ├── KusciaModeEnum.java                    # 运行模式枚举
│   │   │   └── KusciaProtocolEnum.java                # 协议类型枚举
│   │   ├── event/
│   │   │   ├── RegisterKusciaEvent.java               # 注册事件
│   │   │   └── UnRegisterKusciaEvent.java             # 注销事件
│   │   ├── factory/
│   │   │   ├── KusciaApiChannelFactory.java           # 通道工厂接口
│   │   │   └── impl/
│   │   │       └── GrpcKusciaApiChannelFactory.java   # gRPC 通道工厂实现
│   │   ├── interceptor/
│   │   │   ├── KusciaGrpcLoggingInterceptor.java      # 日志拦截器
│   │   │   └── TokenAuthClientInterceptor.java        # Token 认证拦截器
│   │   ├── listener/
│   │   │   └── ManagedChannelStateListener.java       # 通道状态监听器
│   │   ├── model/
│   │   │   ├── DynamicKusciaGrpcConfig.java           # 动态配置
│   │   │   └── KusciaGrpcConfig.java                  # 节点配置
│   │   ├── mock/
│   │   │   ├── MockKusciaGrpcServer.java              # Mock 服务器
│   │   │   ├── interceptor/
│   │   │   │   └── TokenAuthServerInterceptor.java    # 服务端 Token 验证
│   │   │   └── service/
│   │   │       ├── CommonService.java                 # Mock 公共服务
│   │   │       ├── DomainDataService.java             # Mock 数据服务
│   │   │       ├── DomainDataGrantService.java        # Mock 授权服务
│   │   │       ├── DomainDatasourceService.java       # Mock 数据源服务
│   │   │       ├── DomainRouteService.java            # Mock 路由服务
│   │   │       ├── DomainService.java                 # Mock 域服务
│   │   │       ├── HealthService.java                 # Mock 健康检查
│   │   │       ├── JobService.java                    # Mock 任务服务
│   │   │       └── ServingService.java                # Mock 在线服务
│   │   └── service/
│   │       ├── CertificateService.java                # 证书服务接口
│   │       ├── DomainDataService.java                 # 数据服务接口
│   │       ├── DomainDataGrantService.java            # 授权服务接口
│   │       ├── DomainDataSourceService.java           # 数据源服务接口
│   │       ├── DomainRouteService.java                # 路由服务接口
│   │       ├── DomainService.java                     # 域服务接口
│   │       ├── HealthService.java                     # 健康检查接口
│   │       ├── KusciaJobService.java                  # 任务服务接口
│   │       ├── ServingService.java                    # 在线服务接口
│   │       └── impl/
│   │           └── KusciaGrpcClientAdapter.java       # 客户端适配器（核心）
│   └── test/java/
│       └── org/secretflow/secretpad/kuscia/v1alpha1/test/
│           ├── DynamicKusciaChannelProviderTest.java  # 通道提供者测试
│           ├── KusciaApiChannelFactoryTest.java       # 通道工厂测试
│           └── KusciaGrpcConfigTest.java              # 配置测试
├── pom.xml                                             # Maven 配置
└── README.md                                           # 模块说明
```

---

## 十一、常见问题与最佳实践

### 11.1 常见问题

#### Q1: 连接超时如何处理？
**A**: 检查以下配置：
- 网络连通性（ping 目标主机）
- 防火墙规则（端口是否开放）
- Kuscia 服务是否正常运行
- 超时时间配置是否合理（默认 5000ms）

#### Q2: TLS 证书验证失败？
**A**: 确保：
- 证书文件格式正确（PEM 格式）
- 证书未过期
- 证书链完整
- 客户端和服务端使用相同的 CA

#### Q3: Token 认证失败？
**A**: 检查：
- Token 是否正确读取（如果是文件路径）
- Token 是否过期
- 服务端 Token 验证逻辑是否一致

#### Q4: 内存泄漏问题？
**A**: 注意：
- 节点注销时调用 `unRegisterKuscia()` 释放通道
- 应用关闭时调用 `destroy()` 关闭所有通道
- 避免频繁注册/注销同一节点

### 11.2 最佳实践

#### 1. 生产环境配置
```yaml
secretpad:
  node-id: ${NODE_ID:alice}
  kuscia-path: /etc/secretpad/kuscia/  # 使用绝对路径
  
dynamic-kuscia-grpc-config:
  nodes:
    - domain-id: alice
      host: ${ALICE_HOST}
      port: ${ALICE_PORT:8080}
      protocol: MTLS  # 生产环境使用 mTLS
      mode: P2P
      token: /etc/secretpad/certs/alice.token
      cert-file: /etc/secretpad/certs/alice.crt
      key-file: /etc/secretpad/certs/alice.key
```

#### 2. 日志配置
```yaml
logging:
  level:
    org.secretflow.secretpad.kuscia: DEBUG  # 开发环境
    # org.secretflow.secretpad.kuscia: INFO  # 生产环境
```

#### 3. 监控指标
建议监控以下指标：
- 通道状态（READY/TRANSIENT_FAILURE）
- gRPC 请求延迟
- gRPC 请求成功率
- 活跃连接数

#### 4. 重试策略
对于临时性故障（如网络抖动），建议实现重试逻辑：
```java
@Retryable(value = StatusRuntimeException.class, maxAttempts = 3, backoff = @Backoff(delay = 1000))
public Domaindata.QueryDomainDataResponse queryWithRetry(
        Domaindata.QueryDomainDataRequest request, String domainId) {
    return kusciaClient.queryDomainData(request, domainId);
}
```

---

## 十二、总结

### 12.1 模块优势

1. **灵活性**：支持动态注册/注销节点，适应不同的部署拓扑
2. **安全性**：提供 TLS/mTLS 多层安全防护
3. **易用性**：统一的接口抽象，降低使用门槛
4. **可测试性**：内置 Mock 服务器，方便本地开发
5. **高性能**：连接复用、OpenSSL 加速、合理的超时配置

### 12.2 适用场景

- **中心化部署**：多个节点连接到中心 Kuscia Master
- **P2P 部署**：节点之间点对点通信
- **混合部署**：部分节点中心化，部分节点 P2P

### 12.3 未来优化方向

1. **连接池优化**：支持单个节点的多连接池
2. **负载均衡**：同一节点多个实例的负载均衡
3. **熔断降级**：集成 Resilience4j 或 Hystrix
4. **指标采集**：集成 Micrometer/Prometheus
5. **证书热更新**：支持不重启更新 TLS 证书

---

## 十三、Kuscia 节点配置详解

### 13.1 配置文件位置

SecretPad 中的 Kuscia 节点配置位于以下文件中：

**主配置文件：**
```
config/application.yaml
```

**环境特定配置：**
- `config/application-dev.yaml` - 开发环境
- `config/application-edge.yaml` - 边缘模式
- `config/application-p2p.yaml` - P2P 模式
- `config/application-test.yaml` - 测试环境

### 13.2 节点配置结构

#### YAML 配置格式（application.yaml）

```yaml
# ------------------------------------------------------------
# Kuscia API 通信协议配置
# ------------------------------------------------------------
kusciaapi:
  protocol: ${KUSCIA_PROTOCOL:tls}                     # 通信协议：tls（加密）或 grpc（明文）

# ------------------------------------------------------------
# Kuscia 节点集群配置
# ------------------------------------------------------------
kuscia:
  nodes:
    # ---- 中心节点（Master）配置 ----
    - domainId: ${NODE_ID:kuscia-system}               # 域 ID：唯一标识节点，支持环境变量 NODE_ID 覆盖
      mode: master                                     # 节点模式：master（中心调度节点）
      host: ${KUSCIA_API_ADDRESS:root-kuscia-master}   # Kuscia API 服务地址，支持环境变量覆盖
      port: ${KUSCIA_API_PORT:8083}                    # Kuscia API 服务端口
      protocol: ${KUSCIA_PROTOCOL:tls}                 # 通信协议：TLS 加密
      cert-file: config/certs/client.crt               # 客户端证书文件路径（双向 TLS 认证）
      key-file: config/certs/client.pem                # 客户端私钥文件路径
      token: config/certs/token                        # 访问令牌文件路径

    # ---- 参与方节点 Alice 配置 ----
    - domainId: alice                                  # Alice 参与方的域 ID
      mode: lite                                       # 节点模式：lite（轻量级参与方节点）
      host: ${KUSCIA_API_LITE_ALICE_ADDRESS:root-kuscia-lite-alice}
      port: ${KUSCIA_API_PORT:8083}
      protocol: ${KUSCIA_PROTOCOL:tls}
      cert-file: config/certs/alice/client.crt
      key-file: config/certs/alice/client.pem
      token: config/certs/alice/token

    # ---- 参与方节点 Bob 配置 ----
    - domainId: bob                                    # Bob 参与方的域 ID
      mode: lite                                       # 节点模式：lite
      host: ${KUSCIA_API_LITE_BOB_ADDRESS:root-kuscia-lite-bob}
      port: ${KUSCIA_API_PORT:8083}
      protocol: ${KUSCIA_PROTOCOL:tls}
      cert-file: config/certs/bob/client.crt
      key-file: config/certs/bob/client.pem
      token: config/certs/bob/token
```

### 13.3 配置项详解

#### 节点配置字段说明

| 字段 | 类型 | 必填 | 说明 | 示例值 |
|------|------|------|------|--------|
| `domainId` | String | ✅ | 域唯一标识符，在整个系统中必须唯一 | `alice`, `bob`, `kuscia-system` |
| `mode` | Enum | ✅ | 节点模式 | `master`（中心节点）, `lite`（参与方） |
| `host` | String | ✅ | Kuscia API 服务地址（IP 或域名） | `192.168.1.100`, `kuscia-master.svc` |
| `port` | Integer | ✅ | API 端口号 | `8083` |
| `protocol` | Enum | ✅ | 通信协议 | `tls`（加密）, `mtls`（双向认证）, `notls`（明文） |
| `cert-file` | String | TLS/MTLS | TLS 证书文件路径（PEM 格式） | `config/certs/client.crt` |
| `key-file` | String | TLS/MTLS | TLS 私钥文件路径（PEM 格式） | `config/certs/client.pem` |
| `token` | String | TLS/MTLS | 访问令牌文件路径或内容 | `config/certs/token` |

#### 节点模式说明

**1. Master 模式（中心节点）**
- **用途**：作为隐私计算网络的中心调度节点
- **职责**：
  - 协调多个参与方节点的任务执行
  - 管理任务调度和资源分配
  - 维护全局状态和元数据
- **典型场景**：中心化部署架构

**2. Lite 模式（参与方节点）**
- **用途**：作为隐私计算的参与方
- **职责**：
  - 执行具体的计算任务（PSI、联邦学习等）
  - 管理本地数据和模型
  - 与其他节点协同完成隐私计算
- **典型场景**：Alice、Bob 等数据持有方

### 13.4 环境变量支持

所有关键配置都支持通过环境变量覆盖，方便在不同环境中部署：

```bash
# 设置当前节点 ID
export NODE_ID=alice

# 设置 Kuscia API 地址
export KUSCIA_API_ADDRESS=192.168.1.100
export KUSCIA_API_LITE_ALICE_ADDRESS=192.168.1.101
export KUSCIA_API_LITE_BOB_ADDRESS=192.168.1.102

# 设置 API 端口
export KUSCIA_API_PORT=8083

# 设置通信协议
export KUSCIA_PROTOCOL=tls

# 设置网关地址
export KUSCIA_GW_ADDRESS=192.168.1.100:80

# 启动应用
java -jar secretpad.jar
```

**优先级：**
1. 环境变量（最高优先级）
2. YAML 配置文件中的默认值
3. 代码中的硬编码默认值

### 13.5 证书文件配置

#### 证书目录结构

```
config/certs/
├── client.crt          # 中心节点客户端证书
├── client.pem          # 中心节点客户端私钥
├── token               # 中心节点访问令牌
├── alice/
│   ├── client.crt      # Alice 节点证书
│   ├── client.pem      # Alice 节点私钥
│   └── token           # Alice 节点令牌
└── bob/
    ├── client.crt      # Bob 节点证书
    ├── client.pem      # Bob 节点私钥
    └── token           # Bob 节点令牌
```

#### 证书生成（示例）

```bash
# 1. 生成 CA 私钥和证书
openssl genrsa -out ca.key 2048
openssl req -x509 -new -nodes -key ca.key -sha256 -days 365 -out ca.crt

# 2. 为 Alice 节点生成证书
openssl genrsa -out alice/client.key 2048
openssl req -new -key alice/client.key -out alice/client.csr
openssl x509 -req -in alice/client.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out alice/client.crt -days 365 -sha256

# 3. 生成访问令牌
echo "your-token-content" > alice/token
chmod 600 alice/token  # 设置权限，仅所有者可读写
```

#### 证书格式要求

**证书文件（.crt）：**
```
-----BEGIN CERTIFICATE-----
MIID...（Base64 编码的证书内容）
-----END CERTIFICATE-----
```

**私钥文件（.pem）：**
```
-----BEGIN PRIVATE KEY-----
MIIE...（Base64 编码的私钥内容）
-----END PRIVATE KEY-----
```

**令牌文件（token）：**
```
your-access-token-string
```

### 13.6 SecretPad 核心配置关联

在 `application.yaml` 中，还有以下与节点相关的配置：

```yaml
secretpad:
  # 当前节点标识
  node-id: kuscia-system                               # 当前 SecretPad 实例所属的节点 ID
  
  # 平台类型配置
  platform-type: CENTER                                # 平台架构类型：CENTER（中心化）、EDGE（边缘）、P2P（点对点）
  
  # 中心平台服务地址（仅在 CENTER 模式下使用）
  center-platform-service: secretpad.master.svc        # Kubernetes Service 名称
  
  # 网关配置
  gateway: ${KUSCIA_GW_ADDRESS:127.0.0.1:80}          # Kuscia 网关地址，用于数据传输和任务调度
  
  # 组件镜像版本
  version:
    kuscia-image: ${KUSCIA_IMAGE:0.6.0b0}              # Kuscia 框架镜像版本
```

**配置说明：**

| 配置项 | 说明 | 取值 |
|--------|------|------|
| `secretpad.node-id` | 当前 SecretPad 实例的节点 ID | 必须与 `kuscia.nodes` 中的某个 `domainId` 匹配 |
| `secretpad.platform-type` | 平台架构类型 | `CENTER`（中心化）、`EDGE`（边缘）、`P2P`（点对点） |
| `secretpad.center-platform-service` | 中心服务地址 | 仅在 CENTER 模式下使用 |
| `secretpad.gateway` | Kuscia 网关地址 | 用于数据传输和任务调度 |

### 13.7 编程式节点注册

除了静态配置文件，还支持运行时动态注册节点：

#### Java 代码示例

```java
@Service
public class NodeRegistrationService {
    
    @Resource
    private DynamicKusciaChannelProvider channelProvider;
    
    /**
     * 动态注册新的 Kuscia 节点
     */
    public void registerNode(String domainId, String host, int port) {
        // 1. 构建节点配置
        KusciaGrpcConfig config = KusciaGrpcConfig.builder()
            .domainId(domainId)                    // 域 ID
            .host(host)                            // API 地址
            .port(port)                            // API 端口
            .protocol(KusciaProtocolEnum.TLS)      // 通信协议
            .mode(KusciaModeEnum.LITE)             // 节点模式
            .token("/path/to/token")               // 令牌文件路径
            .certFile("/path/to/cert.crt")         // 证书文件路径
            .keyFile("/path/to/key.pem")           // 私钥文件路径
            .build();
        
        // 2. 验证配置（自动检查必需字段）
        config.validateAndProcess();
        
        // 3. 注册节点
        channelProvider.registerKuscia(config);
        
        log.info("Successfully registered node: {}", domainId);
    }
    
    /**
     * 注销节点
     */
    public void unregisterNode(String domainId) {
        channelProvider.unRegisterKuscia(domainId);
        log.info("Successfully unregistered node: {}", domainId);
    }
    
    /**
     * 检查节点是否已注册
     */
    public boolean isNodeRegistered(String domainId) {
        return channelProvider.isChannelExist(domainId);
    }
}
```

#### 使用场景

**场景 1：动态添加新参与方**
```java
// 当新的数据方加入时，动态注册节点
nodeRegistrationService.registerNode(
    "charlie",              // 新参与方 ID
    "192.168.1.103",        // API 地址
    8083                    // API 端口
);
```

**场景 2：从数据库加载节点配置**
```java
@Service
public class DatabaseNodeLoader {
    
    @Resource
    private NodeRepository nodeRepository;
    
    @Resource
    private DynamicKusciaChannelProvider channelProvider;
    
    @PostConstruct
    public void loadNodesFromDatabase() {
        // 从数据库查询所有节点配置
        List<NodeConfig> nodes = nodeRepository.findAll();
        
        for (NodeConfig node : nodes) {
            KusciaGrpcConfig config = KusciaGrpcConfig.builder()
                .domainId(node.getDomainId())
                .host(node.getHost())
                .port(node.getPort())
                .protocol(KusciaProtocolEnum.valueOf(node.getProtocol()))
                .mode(KusciaModeEnum.valueOf(node.getMode()))
                .token(node.getTokenPath())
                .certFile(node.getCertPath())
                .keyFile(node.getKeyPath())
                .build();
            
            channelProvider.registerKuscia(config);
        }
        
        log.info("Loaded {} nodes from database", nodes.size());
    }
}
```

**场景 3：节点健康检查与自动重连**
```java
@Service
public class NodeHealthChecker {
    
    @Resource
    private DynamicKusciaChannelProvider channelProvider;
    
    @Scheduled(fixedRate = 30000)  // 每 30 秒检查一次
    public void checkNodeHealth() {
        List<KusciaGrpcConfig> nodes = getAllConfiguredNodes();
        
        for (KusciaGrpcConfig node : nodes) {
            String domainId = node.getDomainId();
            
            // 检查节点是否已注册
            if (!channelProvider.isChannelExist(domainId)) {
                log.warn("Node {} is not registered, attempting to register...", domainId);
                try {
                    channelProvider.registerKuscia(node);
                    log.info("Successfully re-registered node: {}", domainId);
                } catch (Exception e) {
                    log.error("Failed to register node: {}", domainId, e);
                }
            }
        }
    }
}
```

### 13.8 多节点管理最佳实践

#### 1. 节点命名规范

```yaml
# ✅ 推荐：使用有意义的名称
kuscia:
  nodes:
    - domainId: alice-data-center      # 清晰表达节点角色和位置
    - domainId: bob-cloud-region-1
    - domainId: tee-secure-node

# ❌ 避免：使用无意义的名称
kuscia:
  nodes:
    - domainId: node1
    - domainId: node2
```

#### 2. 证书安全管理

```bash
# ✅ 推荐：设置严格的文件权限
chmod 600 config/certs/*.pem
chmod 600 config/certs/*/client.pem
chmod 644 config/certs/*.crt  # 证书可以公开读取

# ✅ 推荐：使用环境变量传递敏感信息
export TOKEN_CONTENT="your-secret-token"
export CERT_PATH="/secure/path/to/cert"

# ❌ 避免：将令牌内容硬编码在配置文件中
```

#### 3. 网络隔离

```yaml
# 生产环境建议：使用内网地址
kuscia:
  nodes:
    - domainId: alice
      host: 10.0.1.100  # 内网 IP
      # host: alice.example.com  # 或使用内网域名
```

#### 4. 超时配置

```java
// 根据网络状况调整超时时间
KusciaGrpcConfig config = KusciaGrpcConfig.builder()
    .domainId("remote-node")
    .host("192.168.1.100")
    .port(8083)
    .protocol(KusciaProtocolEnum.TLS)
    // ... 其他配置
    .build();

// 注意：超时时间在 DynamicKusciaChannelProvider 中统一配置
// BLOCKING_TIMEOUT_MILLISECOND = 5000ms（同步调用）
// FUTURE_TIMEOUT_MILLISECOND = 5000ms（异步调用）
// StubSCRIPTION_TIMEOUT_DAY = 365天（流式调用）
```

#### 5. 日志与监控

```java
// 启用 gRPC 日志以便调试
logging:
  level:
    io.grpc: DEBUG
    org.secretflow.secretpad.kuscia: DEBUG

// 监控节点连接状态
@Component
public class NodeConnectionMonitor {
    
    @Resource
    private DynamicKusciaChannelProvider channelProvider;
    
    @Scheduled(fixedRate = 60000)  // 每分钟检查一次
    public void monitorConnections() {
        List<KusciaGrpcConfig> nodes = getAllNodes();
        
        for (KusciaGrpcConfig node : nodes) {
            String domainId = node.getDomainId();
            boolean connected = channelProvider.isChannelExist(domainId);
            
            // 上报监控指标
            Metrics.counter("kuscia.node.connection",
                "domainId", domainId,
                "status", connected ? "connected" : "disconnected"
            ).increment();
            
            if (!connected) {
                log.warn("Node {} is disconnected", domainId);
                // 触发告警
                alertService.sendAlert("Node disconnected: " + domainId);
            }
        }
    }
}
```

### 13.9 常见问题排查

#### Q1: 连接被拒绝（Connection Refused）

**可能原因：**
1. Kuscia API 服务未启动
2. 主机地址或端口配置错误
3. 防火墙阻止了连接

**解决方法：**
```bash
# 1. 检查 Kuscia 服务是否运行
kubectl get pods -n kuscia

# 2. 测试网络连通性
telnet 192.168.1.100 8083

# 3. 检查防火墙规则
sudo iptables -L -n | grep 8083
```

#### Q2: TLS 握手失败

**可能原因：**
1. 证书过期
2. 证书与私钥不匹配
3. 证书链不完整

**解决方法：**
```bash
# 1. 检查证书有效期
openssl x509 -in config/certs/client.crt -noout -dates

# 2. 验证证书和私钥是否匹配
openssl x509 -noout -modulus -in config/certs/client.crt | openssl md5
openssl rsa -noout -modulus -in config/certs/client.pem | openssl md5
# 两个 MD5 值应该相同

# 3. 检查证书链
openssl verify -CAfile ca.crt config/certs/client.crt
```

#### Q3: Token 认证失败

**可能原因：**
1. Token 文件路径错误
2. Token 内容不正确
3. Token 已过期

**解决方法：**
```bash
# 1. 检查 Token 文件是否存在
ls -l config/certs/token

# 2. 查看 Token 内容
cat config/certs/token

# 3. 确保文件权限正确
chmod 600 config/certs/token
```

#### Q4: 节点未找到（No such kuscia instance）

**错误信息：**
```
IllegalArgumentException: No such kuscia instance domain id: charlie
```

**原因：**
尝试使用未注册的节点 ID

**解决方法：**
```java
// 方法 1: 在配置文件中添加节点
// config/application.yaml
kuscia:
  nodes:
    - domainId: charlie
      # ... 其他配置

// 方法 2: 运行时动态注册
KusciaGrpcConfig config = /* ... */;
channelProvider.registerKuscia(config);

// 方法 3: 检查节点是否已注册
if (!channelProvider.isChannelExist("charlie")) {
    log.error("Node 'charlie' is not registered!");
}
```

---

## 附录

### A. gRPC 学习资源

#### 官方文档
- [gRPC 官方网站](https://grpc.io/)
- [gRPC Java 文档](https://grpc.io/docs/languages/java/)
- [gRPC 核心概念](https://grpc.io/docs/what-is-grpc/core-concepts/)
- [Protocol Buffers 语言指南](https://developers.google.com/protocol-buffers/docs/proto3)

#### 深入理解
- [HTTP/2 规范 RFC 7540](https://httpwg.github.io/specs/rfc7540.html)
- [HPACK 头部压缩 RFC 7541](https://httpwg.github.io/specs/rfc7541.html)
- [Netty 用户指南](https://netty.io/wiki/user-guide-for-4.x.html)

#### 最佳实践
- [gRPC 性能调优指南](https://grpc.io/docs/guides/performance/)
- [gRPC 错误处理](https://grpc.io/docs/guides/error/)
- [gRPC 负载均衡](https://grpc.io/docs/guides/load-balancing/)

### B. Kuscia 相关文档
- [Kuscia 官方仓库](https://github.com/secretflow/kuscia)
- [Kuscia API 文档](https://github.com/secretflow/kuscia/tree/master/docs)
- [SecretFlow 框架](https://github.com/secretflow/secretflow)
- [SecretPad 项目文档](../docs/)

### C. Proto 文件位置
本项目中使用的 Proto 文件位于：
```
proto/
├── kuscia/proto/api/v1alpha1/
│   ├── common.proto                  # 通用消息定义
│   └── kusciaapi/
│       ├── domain.proto              # 域管理服务
│       ├── domaindata.proto          # 域数据管理
│       ├── domaindatasource.proto    # 数据源管理
│       ├── domaindatagrant.proto     # 数据授权管理
│       ├── domain_route.proto        # 域路由管理
│       ├── job.proto                 # 任务管理
│       ├── serving.proto             # 在线服务管理
│       ├── health.proto              # 健康检查
│       └── certificate.proto         # 证书管理
├── scql/                             # SCQL 相关定义
├── secretflow/                       # SecretFlow 相关定义
└── secretflow_serving/               # Serving 配置定义
```

### D. 常用 gRPC 命令

#### 生成 Java 代码
```bash
# 使用 Maven 插件生成
cd secretpad-api/client-java-kusciaapi
mvn protobuf:compile
mvn protobuf:compile-custom

# 生成的代码位于 target/generated-sources/protobuf/
```

#### 使用 grpcurl 测试
```bash
# 安装 grpcurl
brew install grpcurl  # macOS
# 或
go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest

# 测试 Unary RPC
grpcurl -plaintext \
  -d '{"domain_id": "alice", "role": "partner"}' \
  localhost:8080 \
  kuscia.proto.api.v1alpha1.kusciaapi.DomainService/CreateDomain

# 测试 Server Streaming RPC
grpcurl -plaintext \
  -d '{"timeout_seconds": 60}' \
  localhost:8080 \
  kuscia.proto.api.v1alpha1.kusciaapi.JobService/WatchJob

# 列出所有服务
grpcurl -plaintext localhost:8080 list

# 查看服务详情
grpcurl -plaintext localhost:8080 describe kuscia.proto.api.v1alpha1.kusciaapi.DomainService
```

#### 使用 BloomRPC 图形化工具
1. 下载 [BloomRPC](https://github.com/bloomrpc/bloomrpc)
2. 导入 `.proto` 文件
3. 输入服务端地址和端口
4. 可视化调用 gRPC 接口

### E. 调试技巧

#### 1. 启用 gRPC 日志
```yaml
logging:
  level:
    io.grpc: DEBUG
    io.netty: DEBUG
```

#### 2. 捕获网络包
```bash
# 使用 tcpdump 捕获 HTTP/2 流量
sudo tcpdump -i any port 8080 -w grpc_capture.pcap

# 使用 Wireshark 分析
wireshark grpc_capture.pcap
# 过滤器：http2
```

#### 3. 监控连接状态
```java
// 注册通道状态监听器
channel.getState(true);  // 主动触发状态检查

// 定期检查
ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(1);
scheduler.scheduleAtFixedRate(() -> {
    ConnectivityState state = channel.getState(false);
    log.info("Channel state: {}", state);
}, 0, 5, TimeUnit.SECONDS);
```

#### 4. 性能分析
```java
// 启用 gRPC 统计信息
io.grpc.util.TransmitStatusRuntimeExceptionInterceptor

// 使用 Micrometer 监控
@Bean
public MetricsServerInterceptor metricsInterceptor(MeterRegistry registry) {
    return new MetricsServerInterceptor(registry);
}
```
