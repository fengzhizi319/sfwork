# SecretPad 运维层详解

本文档介绍 SecretPad 的运维相关内容，包括进程管理（PM2）、Docker 镜像与部署、日志体系、监控与告警、资源限制、证书管理、CI/CD 构建以及日常运维操作。

---

## 1. 运维层概述

SecretPad 官方部署方式完全基于 **Docker**，没有使用 PM2、systemd 或 crontab 等进程管理工具。运维工作的核心围绕以下几个方面展开：

- **容器化部署**：通过 Docker 镜像运行 SecretPad 与 Kuscia。
- **日志管理**：Logback 输出到文件，Tomcat 输出访问日志。
- **监控与告警**：Spring Boot Actuator + Prometheus（可选）+ SLS 云日志（可选）。
- **证书与密钥**：JKS 服务端证书、Kuscia API 客户端证书。
- **资源管理**：JVM 参数、Docker 内存限制。
- **CI/CD**：GitHub Actions / CircleCI 自动构建与镜像推送。

---

## 2. PM2

### 2.1 官方未使用 PM2

SecretPad 是 Java 后端服务，运行方式为 `java -jar`，封装在 Docker 容器中，由 Docker 守护进程负责容器生命周期管理。仓库中：

- 没有 `ecosystem.config.js`
- 没有 `pm2` 命令或配置文件
- 没有 Node.js 进程管理器包装

### 2.2 为什么不使用 PM2

PM2 是 Node.js 生态的进程管理工具，适用于 Node 服务。SecretPad 使用 Docker 的 `--restart=always` 策略实现自动重启，配合 Docker 健康检查即可满足生产需求。

### 2.3 如果需要进程管理怎么办

如果确实需要在宿主机上直接运行 JAR（非 Docker），可以使用：

- **systemd service**：编写 `.service` 文件，使用 `Restart=always`。
- **supervisord**：跨平台进程管理。
- **PM2**：虽然不建议，但也可以通过 PM2 的 `exec_interpreter: none` 直接运行 `java -jar`。

示例 systemd 服务文件（非官方）：

```ini
# /etc/systemd/system/secretpad.service
[Unit]
Description=SecretPad Service
After=network.target

[Service]
Type=simple
User=secretpad
WorkingDirectory=/app/secretpad
ExecStart=/usr/bin/java -server -Xms2048m -Xmx2300m -jar secretpad.jar
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

---

## 3. Docker 镜像与部署

### 3.1 Dockerfile

#### 生产镜像

`build/Dockerfiles/anolis.Dockerfile`：

```dockerfile
ARG BASE_IMAGE=secretflow-registry.cn-hangzhou.cr.aliyuncs.com/secretflow/secretpad-base-lite:0.3
FROM ${BASE_IMAGE}

ARG TARGETPLATFORM

ENV TZ=Asia/Shanghai
ENV LANG=C.UTF-8
WORKDIR /app

RUN mkdir -p /var/log/secretpad && mkdir -p /app/db && mkdir -p /app/config/certs && yum install -y sqlite

COPY config /app/config
COPY scripts /app/scripts
COPY demo/data /app/data
COPY target/secretpad.jar secretpad.jar

ENV JAVA_OPTS="-server -Xms2048m -Xmx2300m -XX:MetaspaceSize=256m -XX:MaxMetaspaceSize=512m" SPRING_PROFILES_ACTIVE="default"

EXPOSE 80
EXPOSE 8080
EXPOSE 9001

ENTRYPOINT java ${JAVA_OPTS} -Dsun.net.http.allowRestrictedHeaders=true -jar -Dspring.profiles.active=${SPRING_PROFILES_ACTIVE} /app/secretpad.jar
```

端口说明：

| 端口 | 用途 |
|---|---|
| 80 | 预留端口，默认未监听 |
| 8080 | 用户 HTTP 入口 |
| 9001 | 内部节点 RPC |

#### 基础镜像

`build/Dockerfiles/lite.Dockerfile` 基于 `openanolis/anolisos:23`，仅安装 OpenJDK 17，供生产镜像作为 base 使用。

### 3.2 构建脚本

#### 构建 JAR

`scripts/build/build.sh`：

```bash
WITH_FRONTEND_FLAG=$1

if [[ $WITH_FRONTEND_FLAG == true ]]; then
    # 下载前端产物并复制到 static/
    FRONTEND_LATEST_TAG=$(git ls-remote --sort='version:refname' --refs --tags https://github.com/fengzhizi319/secretpad-frontend.git | tail -n1 | sed 's/.*\///')
    WORK_DIR="./tmp/frontend"
    mkdir -p $WORK_DIR
    wget -O $WORK_DIR/frontend.tar https://secretflow-public.oss-cn-hangzhou.aliyuncs.com/secretpad-frontend/"${FRONTEND_LATEST_TAG}".tar
    tar -xvf $WORK_DIR/frontend.tar -C ${WORK_DIR} --strip-components=1
    cp -rpf $WORK_DIR/apps/platform/dist/* "${ROOT}/secretpad-web/src/main/resources/static"
fi

mvn clean package -DskipTests -Dfile.encoding=UTF-8
```

#### 构建镜像

`scripts/build/build_image.sh` 使用 `docker buildx` 构建多平台镜像（linux/amd64、linux/arm64）。

#### Makefile

`Makefile` 提供常用命令：

```makefile
test: ## Run tests.
	mvn clean test

build: ## Build SecretPad binary whether to integrate frontend.
	./scripts/build/build.sh true

image: build ## Build docker image with the manager.
	./scripts/build/build_image.sh

docs: ## Build docs.
	cd docs && pip install -r requirements.txt && make html

pack: ## Build pack all in one with tar.gz.
	./scripts/pack/pack_allinone.sh ${platform}
```

### 3.3 部署脚本

#### 一键安装

`scripts/install.sh` 是顶层安装脚本，支持以下模式：

- `master`：中心节点
- `lite`：边缘节点
- `autonomy`：P2P 自治主节点
- `autonomy-node`：P2P 协作节点

默认镜像版本示例：

```bash
export KUSCIA_IMAGE="secretflow-registry.cn-hangzhou.cr.aliyuncs.com/secretflow/kuscia:0.13.0b0"
export SECRETPAD_IMAGE="secretflow-registry.cn-hangzhou.cr.aliyuncs.com/secretflow/secretpad:0.12.0b0"
export SECRETFLOW_IMAGE="secretflow-registry.cn-hangzhou.cr.aliyuncs.com/secretflow/secretflow-lite-anolis8:1.11.0b1"
```

#### SecretPad 容器启动

`scripts/deploy/secretpad.sh` 核心启动命令：

```bash
docker run -itd --init --name="${PAD_CTR}" --restart=always --network="${NETWORK_NAME}" -m "$LITE_MEMORY_LIMIT" \
  --volume="${PAD_INSTALL_DIR}":/app/data \
  --volume="${volume_path}"/log:/app/log \
  --volume="${volume_path}"/config:/app/config \
  --volume="${volume_path}"/db:/app/db \
  -p "${PAD_PORT}":8080 \
  -e SPRING_PROFILES_ACTIVE="${SPRING_PROFILES_ACTIVE}" \
  -e NODE_ID="${NODE_ID}" \
  -e JAVA_OPTS="${JAVA_OPTS}" \
  ...
  "${SECRETPAD_IMAGE}"
```

### 3.4 环境变量默认值

`scripts/deploy/common/secretpad.env`：

```bash
JAVA_OPTS="-server -Xms2048m -Xmx2300m -XX:MetaspaceSize=256m -XX:MaxMetaspaceSize=512m"
SPRING_PROFILES_ACTIVE=${SPRING_PROFILES_ACTIVE:-"center"}
LITE_MEMORY_LIMIT=4G
PAD_PORT=${PAD_PORT:-"8080"}
NETWORK_NAME=${NETWORK_NAME:-"kuscia-exchange"}
METRICS_PORT=${METRICS_PORT:-13084}
DATAPROXY_ENABLE=${DATAPROXY_ENABLE:-"true"}
SCQL_ENABLE=${SCQL_ENABLE:-"true"}
KEY_PASSWORD=${KEY_PASSWORD:-"secretpad"}
```

### 3.5 卸载

`scripts/uninstall.sh` 用于清理容器、卷和网络：

```bash
./scripts/uninstall.sh [center|p2p|all]
```

---

## 4. 日志体系

### 4.1 日志框架

SecretPad 使用 **SLF4J + Logback**。配置文件：`secretpad-common/src/main/resources/logback-spring.xml`。

### 4.2 日志文件

| 文件 | 路径 | 说明 |
|---|---|---|
| `secretpad.log` | `${LOG_HOME}/secretpad.log` | 应用主日志 |
| `error.log` | `${LOG_HOME}/error.log` | 仅 ERROR 级别日志 |
| `data-sync.log` | `${LOG_HOME}/data-sync.log` | 数据同步相关日志 |

默认 `LOG_HOME` 由 `secretpad.logs.path` 决定，默认 `/app/log`。部署时通过 volume 映射到宿主机：

```bash
--volume="${volume_path}"/log:/app/log
```

### 4.3 日志格式

```text
%d{yyyy-MM-dd HH:mm:ss} [%X{Trace-Id}] [%thread] %-5level %logger{36} - %msg%n
```

示例：

```text
2024-06-24 09:15:07 [trace-123] [http-nio-8080-exec-1] INFO  o.s.s.w.c.AuthController - user login success
```

### 4.4 滚动策略

| 文件 | 单文件上限 | 保留天数 | 总容量上限 |
|---|---|---|---|
| `secretpad.log` | 50 MB | 15 天 | 512 MB |
| `error.log` | 1 GB | 7 天 | 5 GB |
| `data-sync.log` | 1 GB | 7 天 | 5 GB |

Logback 配置片段：

```xml
<appender name="rootFile" class="ch.qos.logback.core.rolling.RollingFileAppender">
    <file>${LOG_HOME}/secretpad.log</file>
    <rollingPolicy class="ch.qos.logback.core.rolling.SizeAndTimeBasedRollingPolicy">
        <fileNamePattern>${LOG_HOME}/secretpad.log.%d{yyyy-MM-dd}.%i</fileNamePattern>
        <maxFileSize>50MB</maxFileSize>
        <maxHistory>15</maxHistory>
        <totalSizeCap>512MB</totalSizeCap>
        <cleanHistoryOnStart>true</cleanHistoryOnStart>
    </rollingPolicy>
</appender>
```

### 4.5 Tomcat 访问日志

`config/application.yaml`：

```yaml
server:
  tomcat:
    accesslog:
      enabled: true
      directory: /var/log/secretpad
```

### 4.6 查看日志

进入宿主机日志目录：

```bash
cd /root/kuscia/master/secretpad/kuscia-system/log
ls -al
tail -f secretpad.log
```

或通过 Docker：

```bash
docker logs -f <secretpad-container-id>
```

### 4.7 日志级别调整

可在运行时通过 `application.yaml` 或环境变量调整：

```yaml
logging:
  level:
    org.secretflow.secretpad: DEBUG
    org.springframework.web: WARN
```

---

## 5. 监控与告警

### 5.1 Spring Boot Actuator

SecretPad 引入 `spring-boot-starter-actuator` 和 `micrometer-registry-prometheus`：

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

### 5.2 Actuator 配置

`config/application.yaml`：

```yaml
management:
  endpoint:
    shutdown:
      enabled: false
    health:
      show-details: always
  endpoints:
    web:
      exposure:
        include:
          # - prometheus   # 默认关闭，需要时打开
          - health
  metrics:
    tags:
      application: ${spring.application.name}
```

默认只暴露 `/actuator/health`，`prometheus` 端点被注释。如需 Prometheus 监控，取消注释并配置抓取：

```yaml
management:
  endpoints:
    web:
      exposure:
        include:
          - prometheus
          - health
```

### 5.3 健康检查端点

- 应用健康：`GET /actuator/health`
- Prometheus 指标：`GET /actuator/prometheus`
- Kuscia 健康：通过 gRPC `HealthService.healthZ`

### 5.4 部署脚本中的探针

`scripts/deploy/common/utils.sh` 提供 HTTP 探针：

```bash
function do_http_probe() { ... }
function probe_kuscia() { do_http_probe "$kuscia_ctr" "https://127.0.0.1:1080" 60; }
function probe_secret_pad() { do_http_probe "$secretpad_ctr" "http://127.0.0.1:8080" 60; }
```

### 5.5 Prometheus 监控（可选）

`docs/development/prometheus_usage.md` 介绍了 Prometheus 的使用，但仓库中未包含 `metrics/prometheus.yml` 与 `metrics/start.sh`，需要用户自行搭建。

示例 Prometheus 配置：

```yaml
scrape_configs:
  - job_name: 'secretpad'
    static_configs:
      - targets: ['secretpad:8080']
    metrics_path: '/actuator/prometheus'
```

### 5.6 SLS 云日志（可选）

SecretPad 支持阿里云 SLS 云日志：

- 配置项：`secretpad.cloud-log.sls.{host, ak, sk, project}`
- 配置类：`secretpad-service/.../properties/LogConfigProperties.java`
- 接口：`POST /api/v1alpha1/cloud_log/sls`
- 文档：`docs/development/support_sls_cloud_log.md`

环境变量示例：

```bash
SECRETPAD_CLOUD_LOG_SLS_AK=<ak>
SECRETPAD_CLOUD_LOG_SLS_SK=<sk>
SECRETPAD_CLOUD_LOG_SLS_HOST=<host>
SECRETPAD_CLOUD_LOG_SLS_PROJECT=<project>
```

### 5.7 推荐监控指标

| 指标类型 | 示例 |
|---|---|
| 应用指标 | JVM 内存、GC、线程数、HTTP 请求量/延迟 |
| 业务指标 | 任务成功/失败率、节点在线状态、消息待处理数 |
| 日志监控 | ERROR 日志条数、特定异常关键词 |
| 基础设施 | CPU、内存、磁盘、容器重启次数 |

---

## 6. 证书管理

### 6.1 服务端 JKS 证书

脚本：`scripts/cert/gen_secretpad_serverkey.sh`

生成 `config/server.jks`，用于 Spring Boot HTTPS：

```bash
keytool -genkeypair -alias secretpad-server -keyalg RSA -keysize 2048 \
  -validity 3650 -keystore server.jks -storepass secretpad -keypass secretpad
```

### 6.2 Kuscia API 客户端证书

脚本：`scripts/cert/init_kusciaapi_certs.sh`

生成 CA、客户端证书、私钥、token，存放于 `config/certs/`：

```text
config/certs/
├── client.crt
├── client.pem
└── token
```

### 6.3 测试证书生成

`scripts/test/setup.sh` 为本地测试生成完整证书集，包括 `config/certs/alice/` 和 `config/certs/bob/`。

### 6.4 证书更新

- 服务端 JKS 过期前重新执行 `gen_secretpad_serverkey.sh` 并重启容器。
- Kuscia 客户端证书由 Kuscia 控制，SecretPad 部署脚本会自动从 Kuscia 容器复制。

---

## 7. 资源限制与 JVM 调优

### 7.1 默认 JVM 参数

```bash
JAVA_OPTS="-server -Xms2048m -Xmx2300m -XX:MetaspaceSize=256m -XX:MaxMetaspaceSize=512m"
```

### 7.2 Docker 内存限制

默认 `LITE_MEMORY_LIMIT=4G`，容器启动时限制为 4GB：

```bash
docker run ... -m "$LITE_MEMORY_LIMIT" ...
```

### 7.3 资源需求建议

`docs/deployment/request.md`：

| 组件 | CPU | 内存 | 磁盘 |
|---|---|---|---|
| SecretPad（含 Kuscia） | 8 核 | 16 GB | 200 GB |

### 7.4 JVM 调优建议

生产环境可考虑增加以下参数：

```bash
JAVA_OPTS="-server -Xms8g -Xmx8g -XX:MetaspaceSize=512m -XX:MaxMetaspaceSize=1g \
  -XX:+HeapDumpOnOutOfMemoryError \
  -XX:HeapDumpPath=/app/log/oom.hprof \
  -XX:+UseG1GC \
  -XX:MaxGCPauseMillis=200"
```

> 注意：当前官方脚本未开启 HeapDump 与 GC 日志，需要自行修改 `scripts/deploy/common/secretpad.env` 或容器启动命令。

---

## 8. CI/CD

### 8.1 GitHub Actions

`.github/workflows/test.yml`：

- 触发条件：PR、push
- 执行 `mvn clean test`
- 生成 JaCoCo 覆盖率报告

### 8.2 CircleCI

`.circleci/config.yml`：

- 执行 `make build` 构建 JAR
- 使用 `docker buildx` 构建多平台镜像
- 推送到 Docker Hub 与阿里云镜像仓库

### 8.3 测试报告合并

`scripts/ci/merge_test.sh`：

- 聚合各模块 Surefire XML 报告到 `test/target/TEST-secretpad.xml`

---

## 9. 日常运维操作

### 9.1 查看容器状态

```bash
docker ps | grep secretpad
docker stats <secretpad-container-id>
```

### 9.2 重启服务

```bash
docker restart <secretpad-container-id>
```

### 9.3 进入容器排查

```bash
docker exec -it <secretpad-container-id> /bin/bash
# 查看进程
ps aux
# 查看端口
ss -tlnp
```

### 9.4 更新组件

`scripts/update_components.sh`：

```bash
./scripts/update_components.sh <secretflow-image-tag>
```

用于拉取新版 SecretFlow 镜像并更新 `config/components/secretflow.json`。

### 9.5 用户管理

`scripts/user/register_account.sh`：

```bash
./scripts/user/register_account.sh -n <username> -p <password>
```

### 9.6 数据库维护

- 重建 SQLite：`scripts/sql/update-sql.sh`
- Flyway 修复：进入容器手动执行 `flyway repair` / `flyway info`
- 迁移 MySQL：参考 `docs/development/SUPPORT_MYSQL.md`

---

## 10. 关键文件索引

| 文件 | 说明 |
|---|---|
| `build/Dockerfiles/anolis.Dockerfile` | 生产 Docker 镜像 |
| `build/Dockerfiles/lite.Dockerfile` | 基础 JDK 镜像 |
| `scripts/build/build.sh` | 构建 JAR（可选前端） |
| `scripts/build/build_image.sh` | 构建 Docker 镜像 |
| `scripts/pack/pack_allinone.sh` | 打包 all-in-one 离线包 |
| `scripts/install.sh` | 一键安装脚本 |
| `scripts/deploy/secretpad.sh` | SecretPad 容器部署脚本 |
| `scripts/deploy/common/secretpad.env` | 环境变量默认值 |
| `scripts/deploy/common/utils.sh` | 部署工具函数、探针 |
| `scripts/uninstall.sh` | 卸载清理脚本 |
| `scripts/cert/gen_secretpad_serverkey.sh` | 服务端 JKS 证书 |
| `scripts/cert/init_kusciaapi_certs.sh` | Kuscia API 客户端证书 |
| `secretpad-common/src/main/resources/logback-spring.xml` | Logback 日志配置 |
| `config/application.yaml` | Actuator、Tomcat 访问日志配置 |
| `.github/workflows/test.yml` | GitHub Actions 测试工作流 |
| `.circleci/config.yml` | CircleCI 镜像构建工作流 |
| `Makefile` | 常用构建命令 |
| `docs/deployment/log.md` | 日志查看指南 |
| `docs/development/prometheus_usage.md` | Prometheus 使用说明 |
| `docs/development/support_sls_cloud_log.md` | SLS 云日志说明 |

---

## 11. 总结

- SecretPad 官方**不使用 PM2**，完全基于 Docker 部署，由 Docker 守护进程管理容器生命周期。
- **Docker** 镜像使用 Anolis OS + OpenJDK 17，暴露 8080（HTTP）和 9001（内部 RPC），默认 JVM 堆内存约 2GB。
- **日志**通过 Logback 输出到 `/app/log`，包含主日志、ERROR 日志、数据同步日志，支持按大小/时间滚动。
- **监控**基于 Spring Boot Actuator，默认只暴露 health，可手动开启 Prometheus；同时支持阿里云 SLS 云日志。
- **证书**分为服务端 JKS 和 Kuscia API 客户端证书，由独立脚本生成和维护。
- 生产运维需关注：容器资源限制、日志滚动与清理、证书续期、数据库备份、Actuator 安全暴露。
