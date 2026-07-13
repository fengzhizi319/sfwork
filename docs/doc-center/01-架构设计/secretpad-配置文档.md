# SecretPad 隐私计算平台整体配置文档

> **文档版本**: v1.0  
> **最后更新**: 2026-06-27  
> **适用版本**: SecretPad 0.12.0b0+

本文档详细说明 SecretPad 隐私计算平台的整体架构、核心组件及其配置方式，包括 Kuscia、DataMesh、SecretFlow 和 SecretPad 四大核心组件的协同工作机制。

---

## 目录

- [1. 架构概览](#1-架构概览)
- [2. 核心组件说明](#2-核心组件说明)
  - [2.1 SecretPad](#21-secretpad)
  - [2.2 Kuscia](#22-kuscia)
  - [2.3 DataMesh](#23-datamesh)
  - [2.4 SecretFlow](#24-secretflow)
  - [2.5 AppImage 形式详解](#25-appimage-形式详解)
- [3. 部署模式](#3-部署模式)
- [4. Kuscia 配置详解](#4-kuscia-配置详解)
- [5. DataMesh 配置详解](#5-datamesh-配置详解)
- [6. SecretFlow 配置详解](#6-secretflow-配置详解)
- [7. SecretPad 配置详解](#7-secretpad-配置详解)
- [8. 组件间通信机制](#8-组件间通信机制)
- [9. 端口配置总览](#9-端口配置总览)
- [10. 证书与安全配置](#10-证书与安全配置)
- [11. 环境变量配置](#11-环境变量配置)
- [12. 常见问题排查](#12-常见问题排查)

---

## 1. 架构概览

### 1.1 整体架构图

```
┌─────────────────────────────────────────────────────────────┐
│                      用户浏览器                              │
│                  http://localhost:8000                       │
└──────────────────────┬──────────────────────────────────────┘
                       │ HTTP/HTTPS
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                   SecretPad Frontend                         │
│              (React + Umi + Ant Design)                      │
└──────────────────────┬──────────────────────────────────────┘
                       │ API 代理 (PROXY_URL)
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                  SecretPad Backend                           │
│            (Spring Boot + Tomcat)                            │
│  - HTTP Port: 8080                                          │
│  - HTTPS Port: 443/8443                                     │
│  - Internal Port: 9001                                      │
└──────────────────────┬──────────────────────────────────────┘
                       │ gRPC (KusciaAPI)
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                    Kuscia Master                             │
│          (分布式任务调度框架 - k3s)                          │
│  - Gateway: 18080                                           │
│  - KusciaAPI HTTP: 18082                                    │
│  - KusciaAPI gRPC: 18083                                    │
│  - Envoy Internal: 13081                                    │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐                        │
│  │  DataMesh    │  │   AppImage   │                        │
│  │  (数据管理)   │  │  (应用镜像)   │                        │
│  └──────────────┘  └──────────────┘                        │
└──────────┬─────────────────────┬───────────────────────────┘
           │                     │
      ┌────┴────┐          ┌────┴────┐
      │ Alice   │          │  Bob    │
      │ Lite    │          │ Lite    │
      │ Node    │          │ Node    │
      └────┬────┘          └────┬────┘
           │                     │
           ▼                     ▼
    ┌──────────────┐     ┌──────────────┐
    │ SecretFlow   │     │ SecretFlow   │
    │ Container    │     │ Container    │
    │ (由 Kuscia   │     │ (由 Kuscia   │
    │  动态启动)    │     │  动态启动)    │
    └──────────────┘     └──────────────┘
```

### 1.2 组件职责划分

| 组件 | 职责 | 部署方式 | 是否独立容器 |
|------|------|---------|-------------|
| **SecretPad** | Web 管理平台、任务编排、用户界面 | Docker 或源码启动 | ✅ 是 |
| **Kuscia** | 任务调度、资源管理、节点协调 | Docker 容器（Master + Lite） | ✅ 是 |
| **DataMesh** | 数据源注册、元数据管理、数据授权 | Kuscia 内置服务 | ❌ 否（内置） |
| **SecretFlow** | 隐私计算引擎（PSI、MPC、XGB 等） | Kuscia AppImage（动态启动） | ⚠️ 按需启动 |

---

## 2. 核心组件说明

### 2.1 SecretPad

**定位**: 隐私计算平台的 Web 管理界面和任务编排中心

**核心功能**:
- 用户认证与权限管理
- 参与方节点管理
- 数据源管理与授权
- 可视化任务编排（DAG）
- 任务提交与监控
- 模型管理与服务化

**技术栈**:
- 前端: React + Umi + Ant Design + Valtio
- 后端: Spring Boot 3.3.5 + Java 17
- 数据库: SQLite（开发）/ MySQL（生产）

### 2.2 Kuscia

**定位**: 底层分布式任务调度和编排框架（类似 Kubernetes）

**核心功能**:
- 多节点集群管理（Master-Lite 架构）
- 任务生命周期管理（创建、调度、执行、销毁）
- AppImage 管理（应用镜像注册）
- 跨域路由和数据传输
- 安全通信（mTLS/gRPC）

**关键概念**:
- **Domain ID**: 唯一标识参与方节点的身份 ID（如 `kuscia-system`、`alice`、`bob`）
- **AppImage**: 应用镜像定义，描述如何运行某个计算组件
- **Gateway**: 节点间认证鉴权和任务路由网关
- **KusciaAPI**: 提供 HTTP 和 gRPC 接口供外部系统调用

### 2.3 DataMesh

**定位**: Kuscia 内置的数据管理服务

**核心功能**:
- 数据源注册（支持 MySQL、OSS、ODPS、本地文件等）
- 元数据管理（表结构、字段类型、样本数据）
- 数据授权（跨域数据共享审批）
- 数据访问控制

**访问方式**:
- 通过 KusciaAPI 调用 DataMesh 接口
- 默认端口: `8071`（容器内部）

### 2.4 SecretFlow

**定位**: 隐私计算框架，提供多种安全计算协议

**支持的计算类型**:
- **PSI**: 隐私集合求交（Private Set Intersection）
- **MPC**: 安全多方计算（Secure Multi-Party Computation）
- **TEE**: 可信执行环境（Trusted Execution Environment）
- **SCQL**: 安全协作查询语言（Secure Collaborative Query Language）
- **联邦学习**: WOE、SGD、XGB、GLM 等算法

**部署特点**:
- **不是独立部署的 Docker 容器**
- 以 **AppImage** 形式注册到 Kuscia
- 由 Kuscia 根据任务需求**动态启动和销毁**
- 通过 `--config_mode=kuscia` 自动从 Kuscia 获取配置

---

### 2.5 AppImage 形式详解

#### 什么是 AppImage？

**AppImage**（Application Image）是 Kuscia 框架中的核心概念，类似于 Kubernetes 中的 **Deployment + Container Image** 组合。它是一个声明式的应用镜像定义，描述了如何运行某个计算组件。

**核心理念**:
```
传统方式: 手动启动 Docker 容器 → 配置环境变量 → 挂载卷 → 管理生命周期
AppImage:   声明应用定义 → Kuscia 自动调度 → 自动启动/停止 → 自动资源管理
```

#### AppImage vs 传统 Docker 容器

| 特性 | 传统 Docker 容器 | Kuscia AppImage |
|------|-----------------|----------------|
| **部署方式** | 手动 `docker run` | 声明式 YAML 定义 |
| **生命周期管理** | 手动启动/停止 | Kuscia 自动管理 |
| **资源配置** | 手动指定 CPU/内存 | 自动分配和隔离 |
| **跨节点调度** | 需要手动编排 | Kuscia 自动调度 |
| **服务发现** | 需要配置网络 | 自动服务发现和路由 |
| **配置注入** | 环境变量/配置文件 | 模板化配置自动注入 |
| **健康检查** | 需要手动实现 | 内置 readiness/liveness probe |
| **弹性伸缩** | 手动扩缩容 | 支持自动 replicas 调整 |

#### AppImage 的核心组成

一个完整的 AppImage 包含三个关键部分：

```yaml
apiVersion: kuscia.secretflow/v1alpha1
kind: AppImage
metadata:
  name: sf-serving-image              # 应用镜像名称（唯一标识）
spec:
  # 1️⃣ 配置模板（ConfigTemplates）
  configTemplates:
    serving-config.conf: |
      {
        "serving_id": "{{.SERVING_ID}}",
        "input_config": "{{.INPUT_CONFIG}}"
      }
  
  # 2️⃣ 部署模板（DeployTemplates）
  deployTemplates:
    - name: secretflow
      replicas: 1                     # 副本数
      spec:
        containers:
          - command:
              - ./secretflow_serving --config_mode=kuscia
            ports:
              - name: service
                port: 53508
            readinessProbe:           # 健康检查
              httpGet:
                path: /health
                port: brpc-builtin
  
  # 3️⃣ 镜像信息（Image）
  image:
    name: secretflow/serving-anolis8  # 镜像名称
    tag: 0.8.0b0                      # 镜像标签
```

##### （1）ConfigTemplates - 配置模板

**作用**: 定义应用的配置文件模板，支持变量替换

**特点**:
- 使用 Go template 语法（`{{.VAR}}`）
- 运行时由 Kuscia 自动填充实际值
- 支持多个配置文件
- 自动挂载到容器指定路径

**示例**:
```yaml
configTemplates:
  agentConf: |-
    task_config: "{{.TASK_INPUT_CONFIG}}"      # 任务输入配置
    cluster_define: "{{.TASK_CLUSTER_DEFINE}}" # 集群定义
    kuscia:
      endpoint: kusciaapi:8083                 # Kuscia API 端点
      tls_mode: {{.KUSCIA_API_PROTOCOL}}       # TLS 模式
      cert: {{.CLIENT_CERT_FILE}}              # 证书文件
      token: {{.KUSCIA_API_TOKEN}}             # 访问令牌
```

**运行时变量来源**:
- 任务提交时的参数（如 `TASK_INPUT_CONFIG`）
- Kuscia 系统配置（如 `KUSCIA_API_PROTOCOL`）
- 节点证书和密钥（自动注入）
- 动态分配的端口（如 `ALLOCATED_PORTS`）

##### （2）DeployTemplates - 部署模板

**作用**: 定义容器的运行规格和部署策略

**关键字段**:

```yaml
deployTemplates:
  - name: broker                    # 容器角色名称
    role: broker                    # 角色标识（用于服务发现）
    replicas: 1                     # 副本数量
    spec:
      containers:
        - command:                  # 启动命令
            - /home/admin/bin/broker
            - -config=./configs/config.yml
          configVolumeMounts:       # 配置文件挂载
            - mountPath: /work/configs/config.yml
              subPath: brokerConf   # 引用 configTemplates 中的 brokerConf
          ports:                    # 端口定义
            - name: intra
              protocol: HTTP
              scope: Domain         # Domain: 节点内访问
            - name: inter
              protocol: HTTP
              scope: Cluster        # Cluster: 跨节点访问
          readinessProbe:           # 就绪探针
            httpGet:
              path: /health
              port: intra
      restartPolicy: Always         # 重启策略
```

**Port Scope 说明**:
- **Domain**: 同一节点内的容器可以访问（如 alice 节点内的多个容器）
- **Cluster**: 跨节点的容器可以访问（如 alice 和 bob 之间通信）

**RestartPolicy 选项**:
- `Always`: 总是重启（适合长期运行的服务，如 broker）
- `Never`: 从不重启（适合一次性任务，如 agent/engine）

##### （3）Image - 镜像信息

**作用**: 指定容器镜像的来源和版本

```yaml
image:
  id: 91d26a38f00e                  # 镜像 ID（可选）
  name: {{.SECRETFLOW_SERVING_IMAGE_NAME}}  # 镜像名称（支持变量）
  tag: {{.SECRETFLOW_SERVING_IMAGE_TAG}}    # 镜像标签（支持变量）
  sign: abc13mnjh1olkkp1            # 镜像签名（可选，用于安全验证）
```

#### AppImage 的生命周期

```
┌─────────────┐
│  1. 注册     │  kubectl apply -f sf-serving.yaml
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  2. 存储     │  Kuscia 存储 AppImage 定义到 etcd/k3s
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  3. 等待     │  空闲状态，不占用资源
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  4. 触发     │  用户提交任务，引用此 AppImage
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  5. 调度     │  Kuscia Master 选择目标节点
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  6. 渲染     │  填充配置模板变量，生成最终配置
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  7. 启动     │  在目标节点拉取镜像并启动容器
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  8. 执行     │  容器执行业务逻辑（隐私计算）
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  9. 监控     │  健康检查、日志收集、状态上报
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ 10. 销毁     │  任务完成，自动停止并删除容器
└─────────────┘
```

#### AppImage 的实际应用示例

##### 示例 1: SecretFlow Serving（模型服务）

**用途**: 将训练好的模型部署为在线预测服务

**特点**:
- 长期运行（`restartPolicy: Always`）
- 暴露 HTTP 接口供外部调用
- 支持多副本负载均衡

**配置片段**:
```yaml
deployTemplates:
  - name: secretflow
    replicas: 1
    spec:
      containers:
        - command:
            - ./secretflow_serving --config_mode=kuscia
          ports:
            - name: service
              port: 53508
              scope: Domain
```

##### 示例 2: SCQL（安全查询）

**用途**: 执行安全的跨域 SQL 查询

**特点**:
- 三组件架构（agent + broker + engine）
- 临时运行（任务完成后销毁）
- 需要跨节点通信

**配置片段**:
```yaml
deployTemplates:
  - name: agent
    role: agent
    replicas: 1
    spec:
      restartPolicy: Never          # 一次性任务
  
  - name: broker
    role: broker
    replicas: 1
    spec:
      containers:
        - ports:
            - name: intra
              scope: Domain         # 节点内通信
            - name: inter
              scope: Cluster        # 跨节点通信
      restartPolicy: Always
  
  - name: engine
    role: engine
    replicas: 1
    spec:
      restartPolicy: Never
```

#### AppImage 的优势

##### ✅ 对开发者的优势

1. **简化部署**: 无需手动编写 Docker 命令和脚本
2. **配置自动化**: 证书、端口、地址等由 Kuscia 自动注入
3. **资源隔离**: 每个任务在独立容器中运行，互不影响
4. **弹性伸缩**: 支持根据负载自动调整副本数
5. **版本管理**: 通过 tag 管理不同版本的镜像

##### ✅ 对运维的优势

1. **统一调度**: 所有应用由 Kuscia 统一管理
2. **自动恢复**: 容器异常时自动重启或重新调度
3. **资源优化**: 任务完成后自动释放资源
4. **监控集成**: 内置健康检查和日志收集
5. **安全加固**: 自动注入证书和访问令牌

##### ✅ 对系统的优势

1. **按需启动**: 仅在需要时启动容器，节省资源
2. **动态扩展**: 支持横向扩展新增参与方节点
3. **故障隔离**: 单个任务失败不影响其他任务
4. **灰度发布**: 支持新旧版本 AppImage 并存

#### AppImage 与 Kubernetes 对比

| 概念 | Kubernetes | Kuscia AppImage |
|------|-----------|----------------|
| **应用定义** | Deployment/DaemonSet | AppImage |
| **容器镜像** | Container Image | Image |
| **配置管理** | ConfigMap/Secret | ConfigTemplates |
| **服务发现** | Service/Ingress | Port Scope (Domain/Cluster) |
| **健康检查** | readinessProbe/livenessProbe | 相同 |
| **调度器** | kube-scheduler | Kuscia Scheduler |
| **适用场景** | 通用容器编排 | 隐私计算任务调度 |

**关键区别**:
- Kubernetes 是通用的容器编排平台
- Kuscia 是针对隐私计算优化的专用调度框架
- AppImage 针对多方安全计算场景做了特殊优化（如跨域通信、证书管理）

#### 如何查看和管理 AppImage

```bash
# 查看所有已注册的 AppImage
docker exec -it ${USER}-kuscia-master kubectl get appimage

# 输出示例:
# NAME               AGE
# sf-serving-image   10m
# scql-image         10m

# 查看 AppImage 详细信息
docker exec -it ${USER}-kuscia-master kubectl get appimage sf-serving-image -o yaml

# 查看 AppImage 对应的运行实例（Pod）
docker exec -it ${USER}-kuscia-master kubectl get pods

# 删除 AppImage（谨慎操作）
docker exec -it ${USER}-kuscia-master kubectl delete appimage sf-serving-image
```

#### AppImage 注册流程

在 `scripts/install.sh` 中，AppImage 通过以下步骤注册：

```bash
# 1. 从 SecretPad 镜像中提取 YAML 模板
docker run --rm --entrypoint /bin/bash \
  -v $(pwd):/tmp/secretpad "$SECRETPAD_IMAGE" \
  -c 'cp -R /app/scripts/templates/sf-serving.yaml /tmp/secretpad/'

# 2. 替换镜像名称和标签变量
sed "s|{{.SECRETFLOW_SERVING_IMAGE_NAME}}|${SECRETFLOW_SERVING_IMAGE_NAME}|g;
    s|{{.SECRETFLOW_SERVING_IMAGE_TAG}}|${SECRETFLOW_SERVING_IMAGE_TAG}|g" \
  sf-serving.yaml >sf-serving-0.yaml

# 3. 应用到 Kuscia（相当于 kubectl apply）
docker exec -i "$container_id" kubectl apply -f sf-serving-0.yaml
```

#### 总结

**AppImage 的本质**: 
> AppImage = 容器镜像 + 配置模板 + 部署策略 + 服务发现规则

**核心价值**:
- 🎯 **声明式**: 描述"要什么"而非"怎么做"
- 🔄 **自动化**: Kuscia 自动处理调度、配置、生命周期
- 🔒 **安全性**: 自动注入证书和访问控制
- 📦 **标准化**: 统一的應用打包和分发格式
- 🚀 **弹性**: 按需启动、自动扩缩容、资源优化

理解 AppImage 是掌握 SecretPad + Kuscia 架构的关键，它是连接上层业务（SecretPad）和底层计算引擎（SecretFlow）的桥梁。

---

## 3. 部署模式

### 3.1 部署模式对比

| 模式 | 说明 | 适用场景 | 配置文件 |
|------|------|---------|---------|
| **CENTER** | 中心化架构，所有节点连接到 Master | 企业内网、可控环境 | `application-center.yaml` |
| **EDGE** | 边缘计算模式，节点分散部署 | 多地域分布式部署 | `application-edge.yaml` |
| **P2P** | 点对点架构，节点间直接通信 | 去中心化协作 | `application-p2p.yaml` |

### 3.2 部署类型（DEPLOY_MODE）

| 类型 | 说明 | 包含组件 |
|------|------|---------|
| **ALL-IN-ONE** | 一体化部署，单机测试 | SecretPad + Kuscia + SecretFlow + TEE + SCQL |
| **MPC** | 多方安全计算 | SecretPad + Kuscia + SecretFlow |
| **TEE** | 可信执行环境 | SecretPad + Kuscia + TEE Apps |

### 3.3 开发环境部署（推荐）

使用一键脚本部署 Kuscia（不部署容器版 SecretPad）：

```bash
cd /home/charles/code/secretpad
bash scripts/install-kuscia-only.sh master -P notls
```

参数说明：
- `master`: 部署 Master 节点 + Alice/Bob Lite 节点
- `-P notls`: 不使用 mTLS，简化本地开发配置

---

## 4. Kuscia 配置详解

### 4.1 Kuscia 节点配置

**配置文件**: `config/application-dev.yaml`

```yaml
kuscia:
  nodes:
    # ---- 中心节点（Master）配置 ----
    - domainId: ${NODE_ID:kuscia-system}               # 域 ID：唯一标识节点
      mode: master                                     # 节点模式：master（中心调度节点）
      host: ${KUSCIA_API_ADDRESS:root-kuscia-master}   # Kuscia API 服务地址
      port: ${KUSCIA_API_PORT:18083}                   # Kuscia API gRPC 端口
      protocol: ${KUSCIA_PROTOCOL:tls}                 # 通信协议：TLS 加密
      cert-file: config/certs/client.crt               # 客户端证书文件路径
      key-file: config/certs/client.pem                # 客户端私钥文件路径
      token: config/certs/token                        # 访问令牌文件路径

    # ---- 参与方节点 Alice 配置 ----
    - domainId: alice                                  # Alice 参与方的域 ID
      mode: lite                                       # 节点模式：lite（轻量级参与方节点）
      host: ${KUSCIA_API_ADDRESS:root-kuscia-lite-alice}
      port: ${KUSCIA_API_PORT:28083}
      protocol: ${KUSCIA_PROTOCOL:tls}
      cert-file: config/certs/alice/client.crt
      key-file: config/certs/alice/client.pem
      token: config/certs/alice/token

    # ---- 参与方节点 Bob 配置 ----
    - domainId: bob
      mode: lite
      host: ${KUSCIA_API_ADDRESS:root-kuscia-lite-bob}
      port: ${KUSCIA_API_PORT:38083}
      protocol: ${KUSCIA_PROTOCOL:tls}
      cert-file: config/certs/bob/client.crt
      key-file: config/certs/bob/client.pem
      token: config/certs/bob/token
```

### 4.2 Kuscia 端口映射

使用 `install-kuscia-only.sh master` 部署时的默认端口：

| 服务 | 容器端口 | Master 宿主机 | Alice 宿主机 | Bob 宿主机 | 说明 |
|------|---------|--------------|-------------|-----------|------|
| **Gateway** | 1080 | 18080 | 28080 | 38080 | 节点间认证、任务路由 |
| **KusciaAPI HTTP** | 8082 | 18082 | 28082 | 38082 | HTTP 形式的管理 API |
| **KusciaAPI gRPC** | 8083 | 18083 | 28083 | 38083 | SecretPad 后端调用此端口 |
| **Envoy Internal** | 80 | 13081 | 23081 | 33081 | 数据传输、任务调度内部通道 |

### 4.3 Kuscia 环境变量

```bash
# 连接 Master 节点
export KUSCIA_API_ADDRESS=127.0.0.1
export KUSCIA_API_PORT=18083
export KUSCIA_GW_ADDRESS=127.0.0.1:13081
export KUSCIA_PROTOCOL=notls

# 或者使用容器名（需要配置 /etc/hosts）
export KUSCIA_API_ADDRESS=root-kuscia-master
export KUSCIA_API_PORT=8083
export KUSCIA_GW_ADDRESS=root-kuscia-master:80
export KUSCIA_PROTOCOL=tls
```

### 4.4 Kuscia AppImage 注册

SecretFlow 和 SCQL 通过 AppImage 注册到 Kuscia：

```bash
# 查看已注册的 AppImage
docker exec -it ${USER}-kuscia-master kubectl get appimage

# 查看 SecretFlow Serving AppImage 详情
docker exec -it ${USER}-kuscia-master kubectl get appimage sf-serving-image -o yaml

# 查看 SCQL AppImage 详情
docker exec -it ${USER}-kuscia-master kubectl get appimage scql-image -o yaml
```

---

## 5. DataMesh 配置详解

### 5.1 DataMesh 概述

DataMesh 是 Kuscia 内置的数据管理服务，**不需要单独部署**，随 Kuscia 容器一起启动。

**主要功能**:
- 数据源注册和管理
- 元数据存储（表结构、字段信息）
- 跨域数据授权
- 数据访问审计

### 5.2 DataMesh API 端点

DataMesh 通过 KusciaAPI 暴露接口：

```
# HTTP 接口（容器内部）
http://kusciaapi:8070/api/v1/datamesh/...

# 通过宿主机访问（Master 节点）
http://127.0.0.1:18082/api/v1/datamesh/...
```

常用接口：
- `POST /api/v1/datamesh/domaindata/create` - 创建数据源
- `POST /api/v1/datamesh/domaindatagrant/create` - 数据授权
- `GET /api/v1/datamesh/domaindata/list` - 列出数据源
- `DELETE /api/v1/domaindatasource/delete` - 删除数据源

### 5.3 示例数据初始化

`install-kuscia-only.sh master` 会自动创建示例数据：

```bash
# 在 Alice 节点创建 alice-table
docker exec -it ${USER}-kuscia-master scripts/deploy/create_domaindata_alice_table.sh alice

# 在 Bob 节点创建 bob-table
docker exec -it ${USER}-kuscia-master scripts/deploy/create_domaindata_bob_table.sh bob

# 创建跨域授权（Alice → Bob）
docker exec -it ${USER}-kuscia-lite-alice curl https://127.0.0.1:8070/api/v1/datamesh/domaindatagrant/create \
  -X POST \
  -H 'content-type: application/json' \
  -d '{"author":"alice","domaindata_id":"alice-table","grant_domain":"bob"}' \
  --cacert var/certs/ca.crt \
  --cert var/certs/ca.crt \
  --key var/certs/ca.key

# 创建跨域授权（Bob → Alice）
docker exec -it ${USER}-kuscia-lite-bob curl https://127.0.0.1:8070/api/v1/datamesh/domaindatagrant/create \
  -X POST \
  -H 'content-type: application/json' \
  -d '{"author":"bob","domaindata_id":"bob-table","grant_domain":"alice"}' \
  --cacert var/certs/ca.crt \
  --cert var/certs/ca.crt \
  --key var/certs/ca.key
```

### 5.4 DataMesh 与 SecretFlow 集成

SecretFlow 通过 DataMesh 获取数据：

1. **任务提交时指定数据源 ID**（如 `alice-table`）
2. **Kuscia 将数据源 ID 传递给 SecretFlow 容器**
3. **SecretFlow 通过 DataMesh API 获取数据元信息和访问凭证**
4. **SecretFlow 直接读取数据并执行计算**

配置示例（`sf-scql.yaml`）：
```yaml
engineConf: |-
  --datasource_router=kusciadatamesh
  --kuscia_datamesh_endpoint=datamesh:8071
  --kuscia_datamesh_client_cert_path={{.CLIENT_CERT_FILE}}
  --kuscia_datamesh_client_key_path={{.CLIENT_PRIVATE_KEY_FILE}}
  --kuscia_datamesh_cacert_path={{.TRUSTED_CA_FILE}}
```

---

## 6. SecretFlow 配置详解

### 6.1 SecretFlow 集成模式

**重要**: SecretFlow **不是独立部署的 Docker 容器**，而是以 **AppImage** 形式注册到 Kuscia，由 Kuscia 根据任务需求动态启动和销毁。

**工作流程**:
```
1. 用户在 SecretPad 创建任务
       ↓
2. SecretPad 通过 KusciaAPI 提交任务
       ↓
3. Kuscia Master 调度任务到参与方节点
       ↓
4. Kuscia Lite 节点根据 AppImage 启动 SecretFlow 容器
       ↓
5. SecretFlow 容器通过 Kuscia 获取配置和数据
       ↓
6. 参与方的 SecretFlow 执行隐私计算
       ↓
7. 任务完成后容器自动销毁
```

---

### 6.1.1 Kuscia 调用 SecretFlow 的详细机制

#### （1）整体调用流程

Kuscia 调用 SecretFlow 是一个多阶段的自动化过程，涉及任务调度、容器管理、配置注入等多个环节：

```
┌─────────────────────────────────────────────────────────────┐
│ 阶段 1: 任务提交（SecretPad → Kuscia）                       │
└─────────────────────────────────────────────────────────────┘
  用户操作: 点击"运行"按钮
       ↓
  SecretPad Backend:
  - 构建任务定义（JobSpec）
  - 指定参与方（alice, bob）
  - 指定使用的 AppImage（sf-serving-image）
  - 配置输入数据（alice-table, bob-table）
       ↓
  调用 KusciaAPI gRPC:
  - CreateJob(jobSpec)
  - 端点: grpc://127.0.0.1:18083
       ↓
┌─────────────────────────────────────────────────────────────┐
│ 阶段 2: 任务调度（Kuscia Master）                            │
└─────────────────────────────────────────────────────────────┘
  Kuscia Master 接收任务:
  - 验证任务合法性
  - 解析参与方列表
  - 查询各参与方的 Lite 节点地址
       ↓
  调度决策:
  - 选择 alice 节点 (root-kuscia-lite-alice:1080)
  - 选择 bob 节点 (root-kuscia-lite-bob:1080)
       ↓
  分发任务:
  - 通过 Gateway 将任务分发到各 Lite 节点
  - gRPC: grpc://root-kuscia-lite-alice:1080
  - gRPC: grpc://root-kuscia-lite-bob:1080
       ↓
┌─────────────────────────────────────────────────────────────┐
│ 阶段 3: 容器启动（Kuscia Lite 节点）                         │
└─────────────────────────────────────────────────────────────┘
  Kuscia Lite 节点接收任务:
  - 解析 AppImage 名称（sf-serving-image）
  - 从 k3s/etcd 中读取 AppImage 定义
       ↓
  渲染配置模板:
  - 读取 ConfigTemplates（serving-config.conf）
  - 填充变量:
    * {{.SERVING_ID}} → job-xxx-serving-id
    * {{.INPUT_CONFIG}} → {"datasource": "alice-table", ...}
    * {{.CLUSTER_DEFINE}} → {"parties": ["alice", "bob"], ...}
    * {{.ALLOCATED_PORTS}} → {"service": 53508, ...}
    * {{.CLIENT_CERT_FILE}} → /var/certs/client.crt
    * {{.KUSCIA_API_TOKEN}} → xxx-token-xxx
       ↓
  生成最终配置文件:
  - /etc/kuscia/serving-config.conf（挂载到容器）
       ↓
  启动容器:
  - docker run secretflow/serving-anolis8:0.8.0b0 \
      ./secretflow_serving \
        --flagfile=conf/gflags.conf \
        --config_mode=kuscia \
        --serving_config_file=/etc/kuscia/serving-config.conf
       ↓
  容器启动参数:
  - 挂载卷: /etc/kuscia/serving-config.conf
  - 网络: kuscia-exchange（Docker 网络）
  - 环境变量: KUSCIA_DOMAIN_ID=alice
       ↓
┌─────────────────────────────────────────────────────────────┐
│ 阶段 4: SecretFlow 初始化（容器内部）                        │
└─────────────────────────────────────────────────────────────┘
  SecretFlow 容器启动:
  - 读取 /etc/kuscia/serving-config.conf
  - 解析配置:
    * serving_id: 当前服务的唯一标识
    * cluster_def: 集群拓扑（alice ↔ bob）
    * allocated_ports: 端口分配
       ↓
  连接 KusciaAPI:
  - endpoint: kusciaapi:8083（容器内 DNS）
  - tls_mode: notls（或 tls）
  - cert: /var/certs/client.crt
  - token: xxx-token-xxx
       ↓
  注册服务:
  - 向 Kuscia 报告就绪状态
  - 暴露服务端口: 53508（Domain scope）
       ↓
  健康检查:
  - readinessProbe: GET http://localhost:53511/health
  - 返回 200 OK → 容器标记为 Ready
       ↓
┌─────────────────────────────────────────────────────────────┐
│ 阶段 5: 跨节点通信建立（SecretFlow ↔ SecretFlow）            │
└─────────────────────────────────────────────────────────────┘
  Alice 节点的 SecretFlow:
  - 从 cluster_def 获取 Bob 的地址
  - 通过 Kuscia Gateway 建立连接:
    * 目标: grpc://root-kuscia-lite-bob:1080
    * 协议: BRPC over HTTP
       ↓
  Bob 节点的 SecretFlow:
  - 同样连接到 Alice
  - 双向通信通道建立
       ↓
  安全通道:
  - TLS 加密（如果启用）
  - 双向认证（mTLS）
  - 密钥交换完成
       ↓
┌─────────────────────────────────────────────────────────────┐
│ 阶段 6: 数据获取（SecretFlow → DataMesh）                    │
└─────────────────────────────────────────────────────────────┘
  SecretFlow 请求数据:
  - 调用 DataMesh API:
    * endpoint: datamesh:8071（容器内 DNS）
    * API: GET /api/v1/datamesh/domaindata/{id}
    * 参数: domaindata_id=alice-table
       ↓
  DataMesh 响应:
  - 返回数据元信息:
    * 数据源类型: local_file / mysql / oss
    * 文件路径: /home/kuscia/var/storage/data/alice.csv
    * 字段 schema: {"id": "int64", "name": "string", ...}
    * 访问凭证: token / certificate
       ↓
  SecretFlow 读取数据:
  - 直接读取本地文件（如果是 local_file）
  - 或通过 JDBC 连接数据库（如果是 mysql）
  - 加载数据到内存
       ↓
┌─────────────────────────────────────────────────────────────┐
│ 阶段 7: 隐私计算执行（SecretFlow 引擎）                      │
└─────────────────────────────────────────────────────────────┘
  执行隐私计算协议:
  - PSI（隐私集合求交）:
    * Alice 和 Bob 交换加密的哈希值
    * 计算交集，不泄露非交集元素
       ↓
  - MPC（安全多方计算）:
    * 使用 SPU（Secure Processing Unit）
    * 协议: SEMI2K（半诚实敌手模型）
    * 有限域: FM128（128 位）
       ↓
  - 联邦学习:
    * 本地训练梯度
    * 安全聚合（Secure Aggregation）
    * 更新全局模型
       ↓
  中间结果:
  - 保存在容器临时目录: /tmp/secretpad/
  - 加密存储，任务结束后清除
       ↓
┌─────────────────────────────────────────────────────────────┐
│ 阶段 8: 结果回传（SecretFlow → Kuscia → SecretPad）          │
└─────────────────────────────────────────────────────────────┘
  SecretFlow 上报状态:
  - 调用 KusciaAPI:
    * UpdateJobStatus(job_id, "Succeeded")
    * 上传结果元数据
       ↓
  Kuscia Lite 汇总:
  - 收集 alice 和 bob 的执行结果
  - 合并日志和指标
       ↓
  Kuscia Master 通知:
  - 通过 gRPC 流式返回给 SecretPad
  - SSE (Server-Sent Events): /sync 端点
       ↓
  SecretPad 更新界面:
  - 任务状态: Running → Succeeded
  - 显示结果预览
  - 保存结果到数据库
       ↓
┌─────────────────────────────────────────────────────────────┐
│ 阶段 9: 资源清理（Kuscia 自动执行）                          │
└─────────────────────────────────────────────────────────────┘
  停止容器:
  - docker stop <container-id>
  - 等待优雅退出（30s timeout）
       ↓
  删除容器:
  - docker rm <container-id>
  - 清理临时文件和日志
       ↓
  释放资源:
  - 释放端口（53508, 53509, ...）
  - 清理网络规则
  - 更新节点资源使用情况
```

#### （2）关键技术细节

##### A. 配置模板渲染机制

Kuscia 使用 **Go template** 语法渲染配置模板，支持复杂的变量替换：

```yaml
# AppImage 中的配置模板
configTemplates:
  serving-config.conf: |
    {
      "serving_id": "{{.SERVING_ID}}",
      "cluster_def": {{.CLUSTER_DEFINE | toJson}},
      "allocated_ports": {{.ALLOCATED_PORTS | toJson}}
    }

# 运行时 Kuscia 填充的值
SERVING_ID = "job-20260627-abc123-serving"
CLUSTER_DEFINE = {
  "parties": [
    {"name": "alice", "address": "grpc://alice-gateway:1080"},
    {"name": "bob", "address": "grpc://bob-gateway:1080"}
  ],
  "selfPartyIdx": 0
}
ALLOCATED_PORTS = {
  "ports": {
    "service": {"port": 53508, "scope": "Domain"},
    "communication": {"port": 53509, "scope": "Cluster"}
  }
}

# 渲染后的最终配置
{
  "serving_id": "job-20260627-abc123-serving",
  "cluster_def": {
    "parties": [
      {"name": "alice", "address": "grpc://alice-gateway:1080"},
      {"name": "bob", "address": "grpc://bob-gateway:1080"}
    ],
    "selfPartyIdx": 0
  },
  "allocated_ports": {
    "ports": {
      "service": {"port": 53508, "scope": "Domain"},
      "communication": {"port": 53509, "scope": "Cluster"}
    }
  }
}
```

##### B. 容器网络与 Service Discovery

Kuscia 使用 **Docker 网络** + **内部 DNS** 实现服务发现：

```bash
# 创建 Docker 网络
docker network create kuscia-exchange

# 启动容器时加入网络
docker run --network kuscia-exchange \
  --name alice-sf-container \
  secretflow/serving-anolis8:0.8.0b0

# 容器内 DNS 解析
cat /etc/resolv.conf
# nameserver 127.0.0.11  # Docker 内部 DNS

# 容器内可以通过名称访问其他服务
ping kusciaapi        # → 解析到 KusciaAPI 容器 IP
ping datamesh         # → 解析到 DataMesh 容器 IP
ping alice-gateway    # → 解析到 Alice Gateway 容器 IP
```

**DNS 解析规则**:
- `kusciaapi` → KusciaAPI 服务（端口 8083）
- `datamesh` → DataMesh 服务（端口 8071）
- `{domainId}-gateway` → 对应节点的 Gateway（端口 1080）

##### C. 端口分配策略

Kuscia 采用**动态端口分配**机制，避免端口冲突：

```yaml
# AppImage 中声明需要的端口
deployTemplates:
  - name: secretflow
    spec:
      containers:
        - ports:
            - name: service
              port: 53508        # 期望端口（可能被占用）
              scope: Domain
            - name: communication
              port: 53509
              scope: Cluster

# Kuscia 实际分配（如果期望端口被占用，会自动调整）
ALLOCATED_PORTS:
  ports:
    service:
      port: 53508              # 成功分配到期望端口
      hostPort: 53508
    communication:
      port: 53509
      hostPort: 53509
```

**Port Scope 的作用**:
- **Domain**: 只在同一节点内可访问（如 alice 节点内的多个容器）
- **Cluster**: 跨节点可访问（如 alice ↔ bob 之间的通信）

##### D. 证书自动注入机制

Kuscia 自动为每个容器注入 TLS 证书：

```bash
# Kuscia 在启动容器前准备证书
docker cp config/certs/alice/client.crt alice-container:/var/certs/client.crt
docker cp config/certs/alice/client.pem alice-container:/var/certs/client.pem
docker cp config/certs/ca.crt alice-container:/var/certs/ca.crt
docker cp config/certs/token alice-container:/var/certs/token

# 容器内证书路径
ls /var/certs/
# client.crt      # 客户端证书
# client.pem      # 客户端私钥
# ca.crt          # CA 根证书
# token           # 访问令牌
```

**证书用途**:
- `client.crt` + `client.pem`: mTLS 双向认证
- `ca.crt`: 验证服务端证书
- `token`: KusciaAPI 访问令牌

##### E. 健康检查与就绪探针

Kuscia 通过 **readinessProbe** 确保容器完全就绪后才开始流量：

```yaml
deployTemplates:
  - name: secretflow
    spec:
      containers:
        - readinessProbe:
            httpGet:
              path: /health
              port: brpc-builtin    # 53511
            initialDelaySeconds: 5  # 启动后 5 秒开始检查
            periodSeconds: 10       # 每 10 秒检查一次
            timeoutSeconds: 3       # 超时时间 3 秒
            failureThreshold: 3     # 连续失败 3 次标记为未就绪
            successThreshold: 1     # 成功 1 次标记为就绪
```

**健康检查流程**:
```
t=0s:   容器启动
t=5s:   第一次健康检查 → 503 Service Unavailable
t=15s:  第二次健康检查 → 503 Service Unavailable
t=25s:  第三次健康检查 → 200 OK ✅
        容器标记为 Ready
        Kuscia 开始路由流量到此容器
```

#### （3）错误处理与重试机制

##### A. 容器启动失败

```yaml
# 重启策略
deployTemplates:
  - name: broker
    spec:
      restartPolicy: Always    # 总是重启
  
  - name: engine
    spec:
      restartPolicy: Never     # 从不重启（一次性任务）
```

**处理逻辑**:
- `Always`: 容器异常退出后，Kuscia 自动重启（最多 3 次）
- `Never`: 容器失败后，任务标记为 Failed，不再重试

##### B. 网络超时重试

SecretFlow 内部实现了**指数退避重试**：

```json
{
  "link_desc": {
    "connect_retry_times": 60,           // 最多重试 60 次
    "connect_retry_interval_ms": 1000,   // 初始间隔 1 秒
    "recv_timeout_ms": 1200000,          // 接收超时 20 分钟
    "http_timeout_ms": 1200000           // HTTP 超时 20 分钟
  }
}
```

**重试策略**:
- 第 1 次失败: 等待 1 秒后重试
- 第 2 次失败: 等待 2 秒后重试
- 第 3 次失败: 等待 4 秒后重试
- ...
- 第 N 次失败: 等待 min(2^N, 60) 秒后重试

##### C. 任务超时处理

```yaml
configTemplates:
  agentConf: |-
    wait_timeout: 60s           # 任务等待超时 60 秒
    wait_query_timeout: 1h      # 查询等待超时 1 小时
```

**超时处理**:
- 超过 `wait_timeout`: 任务标记为 Timeout，容器停止
- 超过 `wait_query_timeout`: 查询取消，返回错误

#### （4）性能优化机制

##### A. 镜像缓存

Kuscia 使用 **Docker 镜像层缓存**加速容器启动：

```bash
# 首次拉取镜像（较慢）
docker pull secretflow/serving-anolis8:0.8.0b0
# Status: Downloaded newer image

# 后续启动容器（快速，使用本地缓存）
docker run secretflow/serving-anolis8:0.8.0b0
# Status: Image is up to date
```

##### B. 容器预热

对于频繁使用的 AppImage，可以**预先拉取镜像**到所有节点：

```bash
# 在 alice 节点预拉取
docker exec -it root-kuscia-lite-alice docker pull secretflow/serving-anolis8:0.8.0b0

# 在 bob 节点预拉取
docker exec -it root-kuscia-lite-bob docker pull secretflow/serving-anolis8:0.8.0b0
```

##### C. 资源限制

可以为 SecretFlow 容器设置**资源限制**，避免资源竞争：

```yaml
deployTemplates:
  - name: engine
    spec:
      containers:
        - resources:
            requests:
              cpu: "1"           # 请求 1 CPU
              memory: "2Gi"      # 请求 2GB 内存
            limits:
              cpu: "2"           # 最多使用 2 CPU
              memory: "4Gi"      # 最多使用 4GB 内存
```

---

### 6.1.2 调试与监控

#### （1）查看 SecretFlow 容器日志

```bash
# 查看所有运行中的 SecretFlow 容器
docker exec -it root-kuscia-lite-alice kubectl get pods
# NAME                     READY   STATUS    RESTARTS   AGE
# sf-serving-abc123        1/1     Running   0          5m

# 查看容器日志
docker exec -it root-kuscia-lite-alice kubectl logs sf-serving-abc123
# [INFO] Starting SecretFlow Serving...
# [INFO] Connected to KusciaAPI at kusciaapi:8083
# [INFO] Health check passed
# [INFO] Ready to serve requests

# 实时跟踪日志
docker exec -it root-kuscia-lite-alice kubectl logs -f sf-serving-abc123
```

#### （2）检查容器状态

```bash
# 查看容器详细信息
docker exec -it root-kuscia-lite-alice kubectl describe pod sf-serving-abc123
# Name:         sf-serving-abc123
# Status:       Running
# IP:           10.42.0.15
# Containers:
#   secretflow:
#     State:    Running
#     Ready:    True
#     Restart Count: 0

# 进入容器内部调试
docker exec -it root-kuscia-lite-alice kubectl exec -it sf-serving-abc123 -- /bin/bash
# root@sf-serving-abc123:/work# ls /etc/kuscia/
# serving-config.conf
# root@sf-serving-abc123:/work# cat /etc/kuscia/serving-config.conf
# {"serving_id": "job-xxx", ...}
```

#### （3）监控指标

```bash
# 查看 SecretFlow 健康状态
curl http://localhost:53511/health
# {"status": "healthy", "uptime": 300}

# 查看 metrics（如果启用 Prometheus）
curl http://localhost:53511/metrics
# secretpad_job_duration_seconds{job="psi"} 12.5
# secretpad_data_processed_bytes{party="alice"} 1048576
```

---

### 6.2 SecretFlow AppImage 配置

#### （1）SecretFlow Serving AppImage

**模板文件**: `scripts/templates/sf-serving.yaml`

```yaml
apiVersion: kuscia.secretflow/v1alpha1
kind: AppImage
metadata:
  name: sf-serving-image
spec:
  configTemplates:
    serving-config.conf: |
      {
        "serving_id": "{{.SERVING_ID}}",
        "input_config": "{{.INPUT_CONFIG}}",
        "cluster_def": "{{.CLUSTER_DEFINE}}",
        "allocated_ports": "{{.ALLOCATED_PORTS}}",
        "oss_meta": "{{.MODEL_OSS_META}}"
      }
  deployTemplates:
    - name: secretflow
      replicas: 1
      spec:
        containers:
          - command:
              - sh
              - -c
              - ./secretflow_serving --flagfile=conf/gflags.conf --config_mode=kuscia --serving_config_file=/etc/kuscia/serving-config.conf
            name: secretflow
            ports:
              - name: service
                port: 53508
                protocol: HTTP
                scope: Domain
              - name: communication
                port: 53509
                protocol: HTTP
                scope: Cluster
              - name: internal
                port: 53510
                protocol: HTTP
                scope: Domain
              - name: brpc-builtin
                port: 53511
                protocol: HTTP
                scope: Domain
            readinessProbe:
              httpGet:
                path: /health
                port: brpc-builtin
  image:
    id: 91d26a38f00e
    name: {{.SECRETFLOW_SERVING_IMAGE_NAME}}
    tag: {{.SECRETFLOW_SERVING_IMAGE_TAG}}
```

**关键配置项**:
- `--config_mode=kuscia`: 从 Kuscia 获取配置（而非本地文件）
- `port: 53508`: 服务端口（Domain scope，同一节点内访问）
- `port: 53509`: 通信端口（Cluster scope，跨节点访问）
- `readinessProbe`: 健康检查，确保容器就绪

#### （2）SCQL AppImage

**模板文件**: `scripts/templates/sf-scql.yaml`

```yaml
apiVersion: kuscia.secretflow/v1alpha1
kind: AppImage
metadata:
  name: scql-image
spec:
  configTemplates:
    agentConf: |-
      task_config: "{{.TASK_INPUT_CONFIG}}"
      cluster_define: "{{.TASK_CLUSTER_DEFINE}}"
      wait_timeout: 60s
      wait_query_timeout: 1h
      kuscia:
        endpoint: kusciaapi:8083
        tls_mode: {{.KUSCIA_API_PROTOCOL}}
        cert: {{.CLIENT_CERT_FILE}}
        key: {{.CLIENT_PRIVATE_KEY_FILE}}
        cacert: {{.TRUSTED_CA_FILE}}
        token: {{.KUSCIA_API_TOKEN}}
    
    brokerConf: |-
      intra_server:
        protocol: http
        host: 0.0.0.0
        port: {{{.ALLOCATED_PORTS.ports[name=intra].port}}}
      inter_server:
        port: {{{.ALLOCATED_PORTS.ports[name=inter].port}}}
        protocol: http
      party_code: {{.KUSCIA_DOMAIN_ID}}
      discovery:
        type: kuscia
        kuscia:
          endpoint: kusciaapi:8083
      
    engineConf: |-
      --listen_port={{{.ALLOCATED_PORTS.ports[name=engineport].port}}}
      --enable_separate_link_port=true
      --link_port={{{.ALLOCATED_PORTS.ports[name=linkport].port}}}
      --datasource_router=kusciadatamesh
      --kuscia_datamesh_endpoint=datamesh:8071
  deployTemplates:
    - name: agent
      role: agent
      replicas: 1
    - name: broker
      role: broker
      replicas: 1
    - name: engine
      role: engine
      replicas: 1
  image:
    name: {{.SCQL_IMAGE_NAME}}
    tag: {{.SCQL_IMAGE_TAG}}
```

**SCQL 架构**:
- **Agent**: 任务代理，负责任务初始化和清理
- **Broker**: 协调器，管理跨节点通信
- **Engine**: 计算引擎，执行 SQL 查询

### 6.3 SecretFlow 镜像版本配置

**配置文件**: `config/application.yaml`

```yaml
secretpad:
  version:
    secretpad-image: ${SECRETPAD_IMAGE:0.5.0b0}
    kuscia-image: ${KUSCIA_IMAGE:0.6.0b0}
    secretflow-image: ${SECRETFLOW_IMAGE:1.4.0b0}
    secretflow-serving-image: ${SECRETFLOW_SERVING_IMAGE:0.2.0b0}
    tee-app-image: ${TEE_APP_IMAGE:0.1.0b0}
    tee-dm-image: ${TEE_DM_IMAGE:0.1.0b0}
    capsule-manager-sim-image: ${CAPSULE_MANAGER_SIM_IMAGE:0.1.2b0}
    data-proxy-image: ${DATA_PROXY_IMAGE:0.1.0b0}
    scql-image: ${SCQL_IMAGE:0.1.0b0}
```

**默认镜像地址** (`scripts/install.sh`):

```bash
export SECRETFLOW_IMAGE="secretflow-registry.cn-hangzhou.cr.aliyuncs.com/secretflow/secretflow-lite-anolis8:1.11.0b1"
export SECRETFLOW_SERVING_IMAGE="secretflow-registry.cn-hangzhou.cr.aliyuncs.com/secretflow/serving-anolis8:0.8.0b0"
export SCQL_IMAGE="secretflow-registry.cn-hangzhou.cr.aliyuncs.com/secretflow/scql:0.9.2b1"
```

### 6.4 SecretFlow 集群设备配置

**配置文件**: `config/application.yaml`

```yaml
sfclusterDesc:
  # SPU（Secure Processing Unit）安全计算单元配置
  deviceConfig:
    spu: "{\"runtime_config\":{\"protocol\":\"SEMI2K\",\"field\":\"FM128\"},\"link_desc\":{\"connect_retry_times\":60,\"connect_retry_interval_ms\":1000,\"brpc_channel_protocol\":\"http\",\"brpc_channel_connection_type\":\"pooled\",\"recv_timeout_ms\":1200000,\"http_timeout_ms\":1200000}}"
    
    # HEU（Homomorphic Encryption Unit）同态加密单元配置
    heu: "{\"mode\": \"PHEU\", \"schema\": \"paillier\", \"key_size\": 2048}"
  
  # RayFed 分布式计算框架配置
  rayFedConfig:
    crossSiloCommBackend: "brpc_link"
```

**配置说明**:
- **SEMI2K**: 半诚实敌手模型下的安全多方计算协议
- **FM128**: 128 位有限域
- **Paillier**: 加法同态加密算法，密钥长度 2048 位
- **BRPC**: 百度 RPC 框架，高性能跨节点通信

---

## 7. SecretPad 配置详解

### 7.1 服务器配置

**配置文件**: `config/application.yaml`

```yaml
server:
  # Tomcat Web 服务器配置
  tomcat:
    accesslog:
      enabled: true
      directory: /var/log/secretpad
  
  # Servlet 容器配置
  servlet:
    encoding:
      charset: UTF-8
      enabled: true
      force: true
    session:
      timeout: 30m
  
  # 端口配置
  http-port: 8080                            # HTTP 服务端口（非加密）
  http-port-inner: 9001                      # 内部通信端口
  port: 443                                  # HTTPS 服务端口（加密）
  
  # SSL/TLS 安全配置
  ssl:
    enabled: true
    key-store: "file:./config/server.jks"
    key-store-password: ${KEY_PASSWORD:secretpad}
    key-alias: secretpad-server
    key-password: ${KEY_PASSWORD:secretpad}
    key-store-type: JKS
  
  # HTTP 压缩配置
  compression:
    enabled: true
    mime-types: text/html,text/xml,text/plain,text/css,application/javascript,application/json
    min-response-size: 1024
```

### 7.2 数据库配置

#### （1）SQLite（开发环境）

```yaml
spring:
  datasource:
    default:
      driver-class-name: org.sqlite.JDBC
      jdbc-url: jdbc:sqlite:./db/secretpad.sqlite
    
    quartz:
      driver-class-name: org.h2.Driver
      jdbc-url: jdbc:h2:./db/secretpadQuartz.mv.db;DB_CLOSE_ON_EXIT=FALSE
      username: sa
      password: password
```

#### （2）MySQL（生产环境）

```yaml
spring:
  jpa:
    database-platform: org.hibernate.dialect.MySQLDialect
  datasource:
    driver-class-name: com.mysql.cj.jdbc.Driver
    url: jdbc:mysql://localhost:3306/secretpad
    username: your_username
    password: your_password
    hikari:
      idle-timeout: 60000
      maximum-pool-size: 10
      connection-timeout: 5000
```

### 7.3 SecretPad 核心配置

```yaml
secretpad:
  # 日志配置
  logs:
    path: ${SECRETPAD_LOG_PATH:/app/log}
  
  # 部署模式配置
  deploy-mode: ${DEPLOY_MODE:ALL-IN-ONE}     # MPC / TEE / ALL-IN-ONE
  
  # 平台类型配置
  platform-type: CENTER                      # CENTER / EDGE / P2P
  
  # 当前节点标识
  node-id: kuscia-system
  
  # 网关配置
  gateway: ${KUSCIA_GW_ADDRESS:127.0.0.1:18301}
  
  # 身份认证配置
  auth:
    enabled: true
    pad_name: ${SECRETPAD_USER_NAME}
    pad_pwd: ${SECRETPAD_PASSWORD}
  
  # 文件上传配置
  upload-file:
    max-file-size: -1                        # -1 表示无限制
    max-request-size: -1
  
  # 数据存储目录
  data:
    dir-path: /app/data/
  
  # 数据同步配置
  datasync:
    center: true
    p2p: false
  
  # Data Proxy 配置
  data-proxy:
    enabled: ${DATAPROXY_ENABLE:true}
  
  # SCQL 配置
  scql:
    enabled: ${SCQL_ENABLE:true}
    component: secretflow/stats/scql_analysis:1.0.0
```

### 7.4 任务并发控制

```yaml
job:
  max-parallelism: 1                         # 最大并行度：同时只能执行 1 个隐私计算任务
```

**说明**: 设置为 1 可避免资源竞争和数据冲突，适合开发和测试环境。生产环境可根据硬件资源调整。

### 7.5 组件隐藏配置

前端界面不显示的组件（底层实现细节）：

```yaml
secretpad:
  component:
    hide:
      - secretflow/io/read_data:1.0.0
      - secretflow/io/write_data:1.0.0
      - secretflow/io/identity:1.0.0
      - secretflow/io/data_sink:1.0.0
      - secretflow/io/data_source:1.0.0
      - secretflow/model/model_export:1.0.0
      - secretflow/ml.train/slnn_train:0.0.1
      - secretflow/ml.predict/slnn_predict:0.0.2
```

---

## 8. 组件间通信机制

### 8.1 通信流程图

```
┌──────────────┐         ┌──────────────┐         ┌──────────────┐
│  SecretPad   │────────▶│   Kuscia     │────────▶│ SecretFlow   │
│   Backend    │ gRPC    │   Master     │ 调度    │  Container   │
│              │◀────────│              │◀────────│              │
└──────────────┘  响应   └──────────────┘  状态   └──────────────┘
                       │
                       │ gRPC
                       ▼
                ┌──────────────┐
                │ Kuscia Lite  │
                │ (Alice/Bob)  │
                └──────────────┘
```

### 8.2 通信协议

| 通信双方 | 协议 | 端口 | 加密方式 |
|---------|------|------|---------|
| SecretPad → KusciaAPI | gRPC | 18083/28083/38083 | TLS/mTLS |
| Kuscia Master ↔ Lite | gRPC | 1080 | TLS/mTLS |
| SecretFlow ↔ SecretFlow | BRPC/HTTP | 53509 | TLS（可选） |
| SecretFlow → DataMesh | HTTP | 8071 | TLS/mTLS |
| 前端 → SecretPad | HTTP/HTTPS | 8080/443 | HTTPS |

### 8.3 证书认证流程

**mTLS（双向 TLS）认证**:

1. **SecretPad 持有客户端证书** (`config/certs/client.crt`)
2. **Kuscia 持有 CA 证书和服务端证书**
3. **建立连接时双方互相验证证书**
4. **验证通过后建立加密通道**

**证书文件位置**:
```
config/certs/
├── client.crt          # SecretPad 客户端证书
├── client.pem          # SecretPad 客户端私钥
├── token               # 访问令牌
├── ca.crt              # CA 根证书
├── alice/
│   ├── client.crt      # Alice 客户端证书
│   ├── client.pem      # Alice 客户端私钥
│   └── token           # Alice 访问令牌
└── bob/
    ├── client.crt      # Bob 客户端证书
    ├── client.pem      # Bob 客户端私钥
    └── token           # Bob 访问令牌
```

---

## 9. 端口配置总览

### 9.1 SecretPad 端口

| 端口 | 协议 | 用途 | 配置项 |
|------|------|------|--------|
| 8080 | HTTP | API 服务端口 | `server.http-port` |
| 443/8443 | HTTPS | 主服务端口 | `server.port` |
| 9001 | HTTP | 内部通信端口 | `server.http-port-inner` |
| 8000 | HTTP | 前端开发服务器 | 前端 dev server |

### 9.2 Kuscia Master 端口

| 端口 | 协议 | 用途 | 配置项 |
|------|------|------|--------|
| 18080 | HTTP/HTTPS | Gateway（节点间认证） | `-p` 参数 |
| 18082 | HTTP | KusciaAPI HTTP | `-k` 参数 |
| 18083 | gRPC | KusciaAPI gRPC | `-g` 参数 |
| 13081 | HTTP | Envoy Internal（数据传输） | `-q` 参数 |
| 13084 | HTTP | Metrics（监控指标） | `-x` 参数 |

### 9.3 Kuscia Lite 端口

#### Alice 节点

| 端口 | 协议 | 用途 |
|------|------|------|
| 28080 | HTTP/HTTPS | Gateway |
| 28082 | HTTP | KusciaAPI HTTP |
| 28083 | gRPC | KusciaAPI gRPC |
| 23081 | HTTP | Envoy Internal |
| 23084 | HTTP | Metrics |

#### Bob 节点

| 端口 | 协议 | 用途 |
|------|------|------|
| 38080 | HTTP/HTTPS | Gateway |
| 38082 | HTTP | KusciaAPI HTTP |
| 38083 | gRPC | KusciaAPI gRPC |
| 33081 | HTTP | Envoy Internal |
| 33084 | HTTP | Metrics |

### 9.4 SecretFlow 端口

| 端口 | 协议 | Scope | 用途 |
|------|------|-------|------|
| 53508 | HTTP | Domain | 服务端口（节点内访问） |
| 53509 | HTTP | Cluster | 通信端口（跨节点访问） |
| 53510 | HTTP | Domain | 内部端口 |
| 53511 | HTTP | Domain | BRPC 内置端口（健康检查） |

### 9.5 DataMesh 端口

| 端口 | 协议 | 用途 |
|------|------|------|
| 8070 | HTTP/HTTPS | DataMesh API（容器内部） |
| 8071 | HTTP/HTTPS | DataMesh 数据访问（容器内部） |

---

## 10. 证书与安全配置

### 10.1 证书生成

使用项目提供的脚本生成证书：

```bash
cd /home/charles/code/secretpad
bash scripts/test/setup.sh
```

生成的证书：
- `config/certs/` - KusciaAPI 客户端证书
- `config/server.jks` - HTTPS 服务证书

### 10.2 TLS 协议配置

**配置文件**: `config/application-dev.yaml`

```yaml
kusciaapi:
  protocol: ${KUSCIA_PROTOCOL:tls}     # tls / notls / mtls

kuscia:
  nodes:
    - domainId: kuscia-system
      protocol: ${KUSCIA_PROTOCOL:tls}
      cert-file: config/certs/client.crt
      key-file: config/certs/client.pem
      token: config/certs/token
```

**协议选项**:
- `tls`: 单向 TLS（服务端认证）
- `mtls`: 双向 TLS（服务端 + 客户端认证，生产环境推荐）
- `notls`: 无加密（仅用于本地开发）

### 10.3 IP 黑名单配置

防止内网穿透和 SSRF 攻击：

```yaml
ip:
  block:
    enable: true
    list:
      - 0.0.0.0/32
      - 127.0.0.1/8
      - 10.0.0.0/8
      - 172.16.0.0/12
      - 192.168.0.0/16
```

**注意**: 如果 SecretPad 部署在内网，需要允许相应的私有地址段。

### 10.4 内容安全策略（CSP）

```yaml
secretpad:
  response:
    extra-headers:
      Content-Security-Policy: "base-uri 'self';frame-src 'self';worker-src blob: 'self' data:;object-src 'self';"
```

防止 XSS 攻击，限制资源加载来源。

---

## 11. 环境变量配置

### 11.1 核心环境变量

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `KUSCIA_API_ADDRESS` | `root-kuscia-master` | Kuscia API 服务地址 |
| `KUSCIA_API_PORT` | `18083` | Kuscia API gRPC 端口 |
| `KUSCIA_GW_ADDRESS` | `127.0.0.1:18301` | Kuscia Gateway 地址 |
| `KUSCIA_PROTOCOL` | `tls` | 通信协议（tls/notls/mtls） |
| `NODE_ID` | `kuscia-system` | 当前节点 ID |
| `DEPLOY_MODE` | `ALL-IN-ONE` | 部署模式（MPC/TEE/ALL-IN-ONE） |
| `SECRETPAD_IMAGE` | - | SecretPad 镜像地址 |
| `KUSCIA_IMAGE` | - | Kuscia 镜像地址 |
| `SECRETFLOW_IMAGE` | - | SecretFlow 镜像地址 |
| `SECRETFLOW_SERVING_IMAGE` | - | SecretFlow Serving 镜像地址 |
| `SCQL_IMAGE` | - | SCQL 镜像地址 |
| `DATAPROXY_ENABLE` | `true` | 是否启用 Data Proxy |
| `SCQL_ENABLE` | `true` | 是否启用 SCQL |
| `KEY_PASSWORD` | `secretpad` | SSL 证书密码 |
| `SECRETPAD_USER_NAME` | - | 管理员用户名 |
| `SECRETPAD_PASSWORD` | - | 管理员密码 |

### 11.2 开发环境推荐配置

```bash
# 连接本地 Kuscia 容器（install-kuscia-only.sh 部署）
export KUSCIA_API_ADDRESS=127.0.0.1
export KUSCIA_API_PORT=18083
export KUSCIA_GW_ADDRESS=127.0.0.1:13081
export KUSCIA_PROTOCOL=notls

# 启动后端
java -Dspring.profiles.active=dev \
     -Dsun.net.http.allowRestrictedHeaders=true \
     -Dserver.port=8443 \
     -jar target/secretpad.jar
```

### 11.3 前端代理配置

**配置文件**: `frontend-src/apps/platform/.env`

```text
PROXY_URL=http://127.0.0.1:8080
```

如果后端 HTTP 端口不是 8080，需修改此文件。

---

## 12. 常见问题排查

### 12.1 后端端口冲突

**症状**: 启动时报 `Port 8080 was already in use`

**解决**:
```bash
# 查看占用进程
sudo lsof -i :8080

# 结束进程
lsof -t -i:8080 | xargs kill -9

# 或改用其他端口
java -Dserver.http-port=18080 -jar target/secretpad.jar
```

### 12.2 Kuscia 连接失败

**症状**: `UnknownHostException: root-kuscia-master` 或 `Connection refused`

**解决**:
```bash
# 方法 1：使用环境变量指向本地端口
export KUSCIA_API_ADDRESS=127.0.0.1
export KUSCIA_GW_ADDRESS=127.0.0.1:13081

# 方法 2：配置 /etc/hosts
echo "127.0.0.1 root-kuscia-master" >> /etc/hosts

# 检查容器是否运行
docker ps | grep kuscia

# 检查端口映射
docker port ${USER}-kuscia-master
```

### 12.3 SecretFlow 任务执行失败

**症状**: 任务状态为 `Failed`，日志显示 `AppImage not found`

**解决**:
```bash
# 检查 AppImage 是否注册
docker exec -it ${USER}-kuscia-master kubectl get appimage

# 如果没有，重新注册
bash scripts/install-kuscia-only.sh master -P notls

# 查看任务日志
docker exec -it ${USER}-kuscia-lite-alice kubectl logs <pod-name>
```

### 12.4 证书过期或无效

**症状**: `SSL handshake failed` 或 `certificate verify failed`

**解决**:
```bash
# 重新生成证书
bash scripts/test/setup.sh

# 重启后端
# 如果使用 mTLS，确保证书与节点匹配
```

### 12.5 前端无法访问后端

**症状**: 浏览器报 CORS 错误或 404

**解决**:
```bash
# 检查前端代理配置
cat frontend-src/apps/platform/.env

# 确认后端已启动
curl http://127.0.0.1:8080/actuator/health

# 重启前端
cd frontend-src
pnpm --filter secretpad dev
```

### 12.6 DataMesh 数据源不存在

**症状**: 任务执行时报 `DomainData not found`

**解决**:
```bash
# 检查数据源是否存在
docker exec -it ${USER}-kuscia-lite-alice curl http://127.0.0.1:8070/api/v1/datamesh/domaindata/list

# 重新创建示例数据
docker exec -it ${USER}-kuscia-master scripts/deploy/create_domaindata_alice_table.sh alice
docker exec -it ${USER}-kuscia-master scripts/deploy/create_domaindata_bob_table.sh bob
```

---

## 附录 A：快速启动命令

### A.1 一键启动完整开发环境

```bash
cd /home/charles/code/secretpad
bash scripts/dev-start.sh
```

### A.2 仅部署 Kuscia

```bash
bash scripts/install-kuscia-only.sh master -P notls
```

### A.3 手动启动后端

```bash
export KUSCIA_API_ADDRESS=127.0.0.1
export KUSCIA_GW_ADDRESS=127.0.0.1:13081
export KUSCIA_PROTOCOL=notls

java -Dspring.profiles.active=dev \
     -Dsun.net.http.allowRestrictedHeaders=true \
     -Dserver.port=8443 \
     -jar target/secretpad.jar
```

### A.4 启动前端

```bash
cd frontend-src
pnpm --filter secretpad dev
```

### A.5 停止服务

```bash
# 停止前后端（保留 Kuscia）
bash scripts/dev-stop.sh

# 同时停止 Kuscia
bash scripts/dev-stop.sh --kuscia
```

---

## 附录 B：参考文档

- [SecretPad README](../README.md)
- [运行说明](../运行说明.md)
- [Nginx 集成指南](deployment/nginx_integration.md)
- [本地运行指南](development/local_run_guide.md)
- [Kuscia 官方文档](https://www.secretflow.org.cn/docs/kuscia/latest/en-US)
- [SecretFlow 官方文档](https://www.secretflow.org.cn/docs/secretflow/latest/en-US)

---

**文档维护**: 如有配置变更，请及时更新本文档。  
**问题反馈**: 如遇配置问题，请查阅日志文件 `/var/log/secretpad/` 或容器日志 `docker logs <container-name>`。
