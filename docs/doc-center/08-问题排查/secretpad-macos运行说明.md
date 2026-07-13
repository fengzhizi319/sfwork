# SecretPad 开发模式运行说明

本文档说明如何在开发模式下运行 SecretPad 前端、后端，并通过 Docker 部署 Kuscia 集群以支持完整功能验证。

> 适用范围：SecretPad 源码仓库（`/path/to/secretpad`），前端源码位于同一仓库的 `frontend-src/` 目录下。

---

## 目录

- [1. 环境准备](#1-环境准备)
- [2. 一键启动本地开发环境](#2-一键启动本地开发环境)
- [3. 后端服务启动](#3-后端服务启动)
- [4. 前端服务启动](#4-前端服务启动)
- [5. 登录与功能操作](#5-登录与功能操作)
- [6. macOS 无 Kuscia 开发模式](#6-macos-无-kuscia-开发模式)
- [7. Nginx / Tomcat / Kuscia 端口配置逻辑](#7-nginx--tomcat--kuscia-端口配置逻辑)
- [8. 常见问题排查](#8-常见问题排查)
- [9. 附录：端口与文件速查](#9-附录端口与文件速查)

---

## 1. 环境准备

### 1.1 系统要求

| 组件 | 版本要求 | 说明 |
|------|---------|------|
| JDK | 17 | Java 开发环境 |
| Maven | 3.8.8+ | Java 构建工具 |
| Node.js | >= 16.14.0（推荐 v20+） | 前端运行环境 |
| pnpm | 8.8.0 | 前端包管理器 |
| Docker | >= 20.10 | 运行 Kuscia 容器 |
| Git | 任意 | 代码管理 |

验证命令：

```bash
java -version      # openjdk 17
mvn -version       # Apache Maven 3.x
node -v            # v20+ 或 v18+
pnpm -v            # 8.8.0
docker --version   # >= 20.10
```

### 1.2 使用项目内置工具（可选）

如果你不想在系统全局安装 JDK/Maven/Node，可以下载到项目 `.tools` 目录。macOS 请使用对应架构（x64 或 aarch64）的压缩包：

```bash
cd /path/to/secretpad
mkdir -p .tools

# Node.js（以 v20.14.0 aarch64 为例，x64 请选 -x64.tar.gz）
curl -L -o .tools/node.tar.xz 'https://nodejs.org/dist/v20.14.0/node-v20.14.0-darwin-arm64.tar.xz'
tar -xf .tools/node.tar.xz -C .tools
mv .tools/node-v20.14.0-darwin-arm64 .tools/node
rm .tools/node.tar.xz

# JDK 17（以 aarch64 为例，x64 请选 OpenJDK17U-jdk_x64_mac_hotspot_17.0.11_9.tar.gz）
curl -L -o .tools/jdk17.tar.gz 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.11%2B9/OpenJDK17U-jdk_aarch64_mac_hotspot_17.0.11_9.tar.gz'
tar -xzf .tools/jdk17.tar.gz -C .tools
mv .tools/jdk-17.0.11+9 .tools/jdk-17
rm .tools/jdk17.tar.gz

# Maven 3.8.8+
curl -L -o .tools/maven.tar.gz 'https://archive.apache.org/dist/maven/maven-3/3.9.12/binaries/apache-maven-3.9.12-bin.tar.gz'
tar -xzf .tools/maven.tar.gz -C .tools
mv .tools/apache-maven-3.9.12 .tools/maven
rm .tools/maven.tar.gz
```

添加到环境变量（注意 macOS JDK 目录结构包含 `Contents/Home`）：

```bash
export JAVA_HOME=/path/to/secretpad/.tools/jdk-17/Contents/Home
export PATH=$JAVA_HOME/bin:/path/to/secretpad/.tools/maven/bin:/path/to/secretpad/.tools/node/bin:$PATH
```

---

## 2. 一键启动本地开发环境

SecretPad 是隐私计算平台的管理界面，真正的任务执行依赖底层 Kuscia 调度框架。本地开发推荐只部署 Kuscia 容器（Master + Lite alice / bob），然后**从源码启动 SecretPad 后端**，避免容器版 SecretPad 占用 8080 端口。

### 2.1 使用一键脚本（推荐）

项目提供了 `scripts/dev-start.sh`，会自动完成环境检查、安装缺失运行时、编译后端、部署 Kuscia、启动前后端：

```bash
cd /path/to/secretpad
bash scripts/dev-start-mac.sh
```

首次运行会自动：

- 检测 JDK 17 / Maven / Node.js / pnpm / Docker
- 缺失的工具会自动下载到 `.tools/` 目录（不影响系统环境）
- 生成证书、编译后端 fat jar
- 部署 Kuscia master + alice + bob
- 启动后端和前端开发服务器

启动成功后会输出可点击的访问链接：

```text
🌐 前端开发服务器：http://localhost:8000
🔧 后端健康检查：http://localhost:8080/actuator/health
🔒 后端 HTTPS 地址：https://localhost:8443
👤 登录账号：admin / 12345678
```

> 如果终端不支持直接点击链接，可手动复制 `http://localhost:8000` 到浏览器打开。

其他常用命令：

```bash
# 仅检查并自动安装运行时
bash scripts/dev-start.sh --check

# 停止后端和前端（保留 Kuscia）
bash scripts/dev-stop.sh

# 同时停止 Kuscia 容器
bash scripts/dev-stop.sh --kuscia
```

### 2.2 手动部署 Kuscia（不部署容器版 SecretPad）

如果你希望分步操作，也可以直接运行 Kuscia-only 脚本：

```bash
cd /path/to/secretpad
bash scripts/install-kuscia-only.sh master -P notls
```

`-P notls` 表示不使用 mTLS，本地开发更简便。该脚本基于 `scripts/install.sh`，但去掉了 `kuscia-master-secretpad` 容器的部署，仅启动 Kuscia 相关容器。

> 说明：`install-kuscia-only.sh` 仍会从 `SECRETPAD_IMAGE` 中抽取 `/app/scripts/deploy` 下的公共部署脚本（`common/log.sh`、`common/utils.sh`、`common/secretpad.env` 等），这些脚本用于初始化 Kuscia；它本身不会启动 SecretPad 容器。

部署成功后会创建以下容器（假设当前用户为 `charles`）：

| 容器名 | 说明 |
|--------|------|
| `charles-kuscia-master` | Kuscia Master 控制平面 |
| `charles-kuscia-lite-alice` | Lite 节点 alice |
| `charles-kuscia-lite-bob` | Lite 节点 bob |

默认端口映射（`master` 模式由脚本固定，通常无需修改）：

| 服务 | 宿主机端口 | 容器端口 | 说明 |
|------|-----------|---------|------|
| Kuscia master gateway | 18080 | 1080 | 节点间认证鉴权 |
| Kuscia master KusciaAPI HTTP | 18082 | 8082 | HTTP API |
| Kuscia master KusciaAPI gRPC | 18083 | 8083 | SecretPad 后端连接此端口 |
| Kuscia master Envoy 内部端口 | 13081 | 80 | `KUSCIA_GW_ADDRESS` 指向此端口 |
| Kuscia lite alice gateway | 28080 | 1080 | alice 对外网关 |
| Kuscia lite alice KusciaAPI gRPC | 28083 | 8083 | alice API gRPC |
| Kuscia lite bob gateway | 38080 | 1080 | bob 对外网关 |
| Kuscia lite bob KusciaAPI gRPC | 38083 | 8083 | bob API gRPC |

验证容器：

```bash
docker ps | grep kuscia
```

> **关于 k3s 数据提示**：如果脚本询问 `Whether to retain k3s data?(y/n):`，首次部署建议输入 `n` 以获得干净环境；后续重新执行可输入 `y` 复用已有数据。

### 2.3 让源码后端能连上 Kuscia 容器

源码后端默认使用 `root-kuscia-master` 等容器名连接 Kuscia，而 `install-kuscia-only.sh` 实际创建的容器名是 `${USER}-kuscia-*`。推荐通过环境变量直接让后端连接本地端口：

```bash
export KUSCIA_API_ADDRESS=127.0.0.1
export KUSCIA_GW_ADDRESS=127.0.0.1:13081
export KUSCIA_PROTOCOL=notls
```

> 也可以修改 `/etc/hosts` 将 `root-kuscia-master`、`root-kuscia-lite-alice`、`root-kuscia-lite-bob` 指向 `127.0.0.1`，但使用环境变量更简单，不需要 root 权限。

---

## 3. 后端服务启动

> 如果你已经运行过 `scripts/dev-start.sh`，后端已经在运行，无需再执行本节命令。本节用于手动分步启动。

### 3.1 生成证书和初始化数据库

```bash
cd /path/to/secretpad
bash scripts/test/setup.sh
```

执行成功后会生成：

- `config/certs/` — KusciaAPI 客户端证书（含 alice / bob 子目录）
- `config/server.jks` — HTTPS 服务证书
- `db/` — SQLite / H2 数据库目录

> 说明：`scripts/test/setup.sh` 会生成证书到项目根目录的 `config/` 下。如果 `mvn clean` 后证书被清除，重新执行本脚本即可。

### 3.2 构建可执行 JAR

SecretPad 是多模块 Maven 项目，必须从根目录构建生成 **fat jar**：

```bash
cd /path/to/secretpad
mvn clean install -Dmaven.test.skip=true
```

构建产物：

- **可执行 fat jar**：`target/secretpad.jar`
- 子模块 `secretpad-web/target/secretpad-web-*.jar` 是未打包的普通 jar，**不能直接 `java -jar` 运行**。

### 3.3 启动后端

普通用户无法绑定 443 端口，开发模式下建议把 HTTPS 端口改为非特权端口（例如 8443）。HTTP API 端口保持 8080：

```bash
cd /path/to/secretpad

export KUSCIA_API_ADDRESS=127.0.0.1
export KUSCIA_GW_ADDRESS=127.0.0.1:13081
export KUSCIA_PROTOCOL=notls

java -Dspring.profiles.active=dev \
     -Dsun.net.http.allowRestrictedHeaders=true \
     -Dserver.port=8443 \
     -jar target/secretpad.jar
```

**参数说明：**

- `-Dspring.profiles.active=dev` — 使用开发环境配置
- `-Dsun.net.http.allowRestrictedHeaders=true` — Kuscia 通信需要
- `-Dserver.port=8443` — HTTPS 端口改为非特权端口（可选，若使用 root 可保持默认 443）

### 3.4 验证后端启动成功

启动成功后日志会显示：

```text
SecretPad start success, http://xxx.xxx.xxx.xxx:8443 innerHttpPort:9001 Profile:dev
userName:admin password:12345678
```

- **HTTP 端口**：8080（API 访问）
- **HTTPS 端口**：8443（若按上面配置）
- **内部端口**：9001
- **用户名**：`admin`
- **密码**：`12345678`（当前代码已固定为 `12345678`，详见 `docs/development/test-guides/cipher12345678.md`）

健康检查：

```bash
curl http://127.0.0.1:8080/actuator/health
# 正常返回：{"status":"UP"}
```

---

## 4. 前端服务启动

> 如果你已经运行过 `scripts/dev-start.sh`，前端已经在运行，无需再执行本节命令。本节用于手动分步启动。

### 4.1 安装依赖

```bash
cd /path/to/secretpad/frontend-src

# 首次运行：安装依赖并构建 workspace 内部包
pnpm bootstrap
```

`pnpm bootstrap` 等价于 `pnpm install && pnpm run setup`，会安装全部依赖并执行 `umi setup`、构建 `@secretflow/utils` 和 `@secretflow/dag` 等内部包。

如果已经安装过依赖，仅需：

```bash
pnpm install
pnpm run setup
```

### 4.2 配置 API 代理

前端 dev 服务器默认通过 `.env` 文件读取代理地址。`frontend-src/apps/platform/.env` 默认内容为：

```text
PROXY_URL=http://127.0.0.1:8080
```

如果后端 HTTP 端口不是 8080，请修改该文件，例如：

```bash
cd /path/to/secretpad/frontend-src/apps/platform
echo "PROXY_URL=http://127.0.0.1:18080" > .env
```

> 也可以在启动命令前临时覆盖环境变量：`PROXY_URL=http://127.0.0.1:18080 pnpm --filter secretpad dev`

### 4.3 启动前端开发服务器

```bash
cd /path/to/secretpad/frontend-src
pnpm --filter secretpad dev
```

启动成功后输出：

```text
App listening at:
  >   Local: http://localhost:8000
ready -  > Network: http://10.x.x.x:8000

Now you can open browser with the above addresses↑
event - [Webpack] Compiled in XXXXX ms (XXXX modules)
```

浏览器打开：`http://localhost:8000`

如果 8000 端口被占用，可指定其他端口：

```bash
PORT=8001 pnpm --filter secretpad dev
```

---

## 5. 登录与功能操作

### 5.1 登录

1. 打开 `http://localhost:8000`
2. 输入用户名 `admin`
3. 输入密码 `12345678`（当前代码已固定，详见 `docs/development/test-guides/cipher12345678.md`）
4. 点击登录，成功后会进入平台首页

### 5.2 界面功能说明

登录后主要功能模块如下：

| 模块 | 入口 | 功能说明 |
|------|------|---------|
| **节点管理** | 左侧菜单「节点管理」 | 查看和管理参与方节点，如 kuscia-system、alice、bob。安装 Kuscia 后应能看到 alice / bob 节点及其状态。 |
| **数据管理** | 左侧菜单「数据管理」 | 查看、上传、注册数据表。`install-kuscia-only.sh master` 会自动在 alice / bob 节点创建示例数据 `alice-table`、`bob-table`，登录后可直接查看。 |
| **项目管理** | 左侧菜单「项目管理」 | 创建协作项目，邀请 alice / bob 作为参与方，为后续任务编排做准备。 |
| **任务编排** | 进入项目 → 新建任务流 | 在 DAG 编辑器中拖拽组件、连线、配置参数，构建隐私计算工作流。 |
| **任务执行** | DAG 编辑器右上角「运行」 | 提交任务到 Kuscia 执行，随后在「任务管理」中查看状态、日志和结果。 |
| **模型管理** | 左侧菜单「模型管理」 | 查看训练好的模型，进行预测或服务化部署（需 serving 组件支持）。 |
| **消息中心** | 顶部导航「消息」 | 查看审批、通知等系统消息。 |

### 5.3 快速验证数据管理

1. 登录后进入「节点管理」，确认 alice / bob 节点在线。
2. 进入「数据管理」，应能看到 `alice-table` 和 `bob-table`。
3. 点击数据表名称，查看元信息、字段类型、样本数据。

### 5.4 快速验证项目与任务编排

1. 进入「项目管理」→「创建项目」。
2. 填写项目名称，参与方选择 `alice` 和 `bob`，提交。
3. 进入项目 →「新建任务流」。
4. 在 DAG 编辑器中：
   - 从左侧组件面板拖拽「数据读取」组件到画布；
   - 选择 alice 的 `alice-table` 作为数据源；
   - 拖拽「统计分析」或「模型训练」组件，与数据读取组件连线；
   - 配置组件参数；
   - 点击右上角「保存」。
5. 保存后点击「运行」，任务会提交到 Kuscia。
6. 进入「任务管理」查看任务状态、日志和结果。

### 5.5 任务执行成功的标志

- 任务状态从 `Pending` → `Running` → `Succeeded`。
- 可查看任务日志，无报错信息。
- 结果数据或模型会出现在「数据管理」或「模型管理」中。

---

## 6. macOS 无 Kuscia 开发模式

如果你希望在 macOS 上运行 SecretPad 前端与后端，且**不需要部署 Kuscia 容器**，可以使用本仓库 `scripts/dev-start-mac.sh` 一键脚本。该脚本仅启动前后端，不依赖 Docker，适合页面美化验证、接口联调与单元测试等场景。

> **为什么 macOS 不启动 Kuscia？** Kuscia 的 Docker 镜像基于 Ubuntu 构建，在 macOS 上可能因架构、网络或 Docker Desktop 限制出现兼容性问题。因此 macOS 开发模式先保证前后端可独立运行，完整功能验证请在 Ubuntu / Linux 环境或远程 Kuscia 集群上进行。

### 6.1 前置依赖

| 组件 | 版本要求 | 说明 |
|------|---------|------|
| JDK | **17** | 必须使用 JDK 17；JDK 21+ 或 JDK 26+ 会导致 Lombok 注解处理器失效，编译失败 |
| Maven | 3.8.8+ | 需要已在 PATH 中 |
| Node.js | >= 16.14.0（推荐 v20+） | 需要已在 PATH 中 |
| pnpm | 8.8.0 | `npm install -g pnpm@8.8.0` |
| bash / curl / openssl / lsof | 任意 | 用于执行证书生成脚本与端口检测 |

验证命令：

```bash
java -version      # openjdk 17
mvn -version       # Apache Maven 3.x
node -v            # v20+ 或 v18+
pnpm -v            # 8.8.0
```

### 6.2 优先使用项目内置工具链

`scripts/dev-start-mac.sh` 会优先使用项目 `.tools/` 目录下的 JDK 17、Maven、Node（如果存在）。建议把 macOS 对应版本的运行时放到 `.tools/` 中，避免系统 Java 版本变动导致编译失败。参考 [1.2 使用项目内置工具](#12-使用项目内置工具可选) 下载并解压到 `.tools/`。

```bash
# 手动启用 .tools/ 工具链（脚本会自动处理，无需手动执行）
export JAVA_HOME=/path/to/secretpad/.tools/jdk-17/Contents/Home
export PATH=$JAVA_HOME/bin:/path/to/secretpad/.tools/maven/bin:/path/to/secretpad/.tools/node/bin:$PATH
```

### 6.3 一键启动

进入项目根目录后执行：

```bash
cd /path/to/secretpad
bash scripts/dev-start-mac.sh
```

首次运行会依次执行：

1. 环境检查（强制 JDK 17）
2. 编译后端 fat jar（`mvn clean install -Dmaven.test.skip=true`）
3. 生成证书（`bash scripts/test/setup.sh`）
4. 创建前端代理配置 `frontend-src/apps/platform/.env`
5. 启动后端（HTTP 8080 / HTTPS 8443）
6. 启动前端开发服务器（`http://localhost:8000`）

> 注意：脚本先编译再生成证书。因为根目录 `mvn clean` 会清理 `config/` 下的证书文件，如果先生成证书再编译，证书会被删除，导致后端启动失败。

启动成功后会输出：

```text
🌐 前端开发服务器：http://localhost:8000
🔧 后端健康检查：http://localhost:8080/actuator/health
🔒 后端 HTTPS 地址：https://localhost:8443
👤 登录账号：admin / 12345678
```

### 6.4 常用命令

```bash
# 查看帮助
bash scripts/dev-start-mac.sh --help

# 仅检查环境
bash scripts/dev-start-mac.sh --check

# 只启动后端
bash scripts/dev-start-mac.sh --backend-only

# 只启动前端（依赖已编译好的 target/secretpad.jar）
bash scripts/dev-start-mac.sh --frontend-only

# 跳过 Maven 编译（证书已生成、jar 已存在时加速启动）
bash scripts/dev-start-mac.sh --no-build

# 跳过证书生成
bash scripts/dev-start-mac.sh --no-certs

# 运行前后端单元测试
bash scripts/dev-start-mac.sh --test

# 只运行后端测试
bash scripts/dev-start-mac.sh --test-backend

# 只运行前端测试
bash scripts/dev-start-mac.sh --test-frontend

# 停止前后端
bash scripts/dev-stop-mac.sh

# 停止前后端并清理日志/pid 文件
bash scripts/dev-stop-mac.sh --clean
```

### 6.5 手动分步启动（备用）

如果一键脚本在你的环境中无法运行，也可以手动执行：

```bash
cd /path/to/secretpad

# 1. 生成证书
bash scripts/test/setup.sh

# 2. 编译后端
mvn clean install -Dmaven.test.skip=true

# 3. 配置前端代理（后端 HTTP 端口为 8080）
cat > frontend-src/apps/platform/.env <<'EOF'
PROXY_URL=http://127.0.0.1:8080
EOF

# 4. 启动后端（不连接 Kuscia）
export KUSCIA_API_ADDRESS=127.0.0.1
export KUSCIA_GW_ADDRESS=127.0.0.1:13081
export KUSCIA_PROTOCOL=notls
java -Dspring.profiles.active=dev \
     -Dsun.net.http.allowRestrictedHeaders=true \
     -Dserver.port=8443 \
     -jar target/secretpad.jar

# 5. 新打开一个终端，启动前端
cd /path/to/secretpad/frontend-src
pnpm --filter secretpad dev
```

### 6.6 运行单元测试

macOS 无 Kuscia 模式下可以执行单元测试，但**依赖 Kuscia 的集成测试会失败**，这是预期行为。

后端测试：

```bash
mvn test
```

前端测试：

```bash
cd frontend-src
pnpm --filter secretpad test
```

### 6.7 功能限制说明

在无 Kuscia 模式下：

- ✅ 登录、首页、项目管理、菜单导航等页面可正常访问
- ✅ 前端美化效果可直接在浏览器中验证
- ✅ 前后端单元测试可执行（Kuscia 相关测试除外）
- ❌ 节点管理、数据管理、任务编排执行等依赖 Kuscia 的接口会报错或为空
- ❌ 无法提交隐私计算任务到 Kuscia 执行

如需完整功能验证，请参考 [Ubuntu / Linux 一键开发环境](#2-一键启动本地开发环境)部署 Kuscia。

## 7. Nginx / Tomcat / Kuscia 端口配置逻辑

本节说明 SecretPad 本地开发/部署时，Nginx、Spring Boot 内嵌 Tomcat 与 Kuscia 三类服务的端口是如何分工、如何联动配置的。理解这些关系后，遇到端口冲突或需要自定义端口时可以快速定位。

### 7.1 Tomcat：Spring Boot 内嵌三个 Connector

`secretpad-web/src/main/java/org/secretflow/secretpad/web/SecretPadApplication.java` 中手动注册了 **3 个 Tomcat Connector**：

```java
@Bean
public ServletWebServerFactory containerFactory() {
    TomcatServletWebServerFactory tomcat = new TomcatServletWebServerFactory();
    buildConnector(tomcat, httpPort);        // server.http-port，默认 8080
    buildConnector(tomcat, innerHttpPort);   // server.http-port-inner，默认 9001
    tomcat.setUriEncoding(StandardCharsets.UTF_8);
    return tomcat;
}
```

对应 `config/application.yaml` 中的端口：

| 配置项 | 默认端口 | 作用 |
|--------|---------|------|
| `server.port` | 443 | 主 HTTPS 端口（Spring Boot 默认 connector） |
| `server.http-port` | 8080 | HTTP API 端口，前端 dev 代理与 Nginx 都指向这里 |
| `server.http-port-inner` | 9001 | 内部 RPC 端口，用于多节点/Edge 模式下的同步、投票等 |

开发时普通用户无法绑定 443，因此通常用 `-Dserver.port=8443` 把 HTTPS 改到非特权端口；HTTP 8080 保持不变，前端继续通过 `PROXY_URL=http://127.0.0.1:8080` 访问。

### 7.2 Nginx：可选的统一入口网关

SecretPad 官方默认**不依赖 Nginx**，直接用 Tomcat 对外服务。生产环境中常见的做法是在 Tomcat 前加一层 Nginx：

```
浏览器 ──80/443──> Nginx ──8080──> SecretPad Tomcat
                       └─(可选)─> Kuscia Gateway
```

Nginx 的典型职责：

| 职责 | 处理方式 |
|------|---------|
| 对外入口 | 监听 80/443，HTTP 自动 301 到 HTTPS |
| SSL 终止 | 证书配置在 Nginx，后端可关闭 SSL |
| 静态文件 | 直接返回前端 `dist/` 中的 `index.html`、JS、CSS、图片 |
| 动态 API | `location ~ ^/(api\|sync)` 反代到 `http://127.0.0.1:8080` |
| 长连接 | `/sync` 等 SSE 接口需要 `proxy_buffering off; proxy_read_timeout 86400s;` |

若使用 Nginx，后端可关闭 HTTPS：

```bash
java -Dspring.profiles.active=dev \
     -Dserver.port=8080 \
     -Dserver.ssl.enabled=false \
     -Dsun.net.http.allowRestrictedHeaders=true \
     -jar target/secretpad.jar
```

> 完整 Nginx 配置示例请参考 `docs/deployment/nginx_integration.md`。

### 7.3 Kuscia：四层端口映射

`scripts/install-kuscia-only.sh master` 会固定把 Kuscia 容器端口映射到宿主机如下：

| 服务 | 容器端口 | Master 宿主机端口 | Alice 宿主机端口 | Bob 宿主机端口 | 说明 |
|------|---------|------------------|-----------------|---------------|------|
| Gateway | 1080 | 18080 | 28080 | 38080 | 节点间认证、任务路由 |
| KusciaAPI HTTP | 8082 | 18082 | 28082 | 38082 | HTTP 形式的管理 API |
| KusciaAPI gRPC | 8083 | 18083 | 28083 | 38083 | SecretPad 后端调用此端口 |
| Envoy Internal | 80 | 13081 | 23081 | 33081 | 数据传输、任务调度内部通道 |

> 以上端口在 `master` 模式下由 `deploy/common/utils.sh::prepare_environment()` 固定设置，`install-kuscia-only.sh` 的 `-p/-k/-g` 对 `master` 不生效（仅对 autonomy/p2p 生效）。如需修改 master 端口，需直接修改 `prepare_environment` 或改用自定义的 Kuscia 部署。

### 7.4 三者如何对接

1. **前端 → 后端**：`frontend-src/apps/platform/.env` 中的 `PROXY_URL` 指向 Tomcat HTTP 端口（默认 `http://127.0.0.1:8080`）。加了 Nginx 后，可改为 `http://127.0.0.1` 或 `https://127.0.0.1`。
2. **后端 → Kuscia API**：`config/application-dev.yaml` 中的 `kuscia.nodes[*].port` 对应 KusciaAPI gRPC 宿主机端口：
   - master：18083
   - alice：28083
   - bob：38083
3. **后端 → Kuscia Gateway**：`secretpad.gateway`（`KUSCIA_GW_ADDRESS`）对应 Kuscia Envoy Internal 宿主机端口：
   - master：127.0.0.1:13081
   - alice：127.0.0.1:23081
   - bob：127.0.0.1:33081

开发时最常用的环境变量组合（对应 `install-kuscia-only.sh master -P notls`）：

```bash
export KUSCIA_API_ADDRESS=127.0.0.1      # 对应 kuscia.nodes[*].host
export KUSCIA_API_PORT=18083             # 对应 master 的 gRPC 端口（dev 默认值）
export KUSCIA_GW_ADDRESS=127.0.0.1:13081 # 对应 master 的 Envoy Internal 端口
export KUSCIA_PROTOCOL=notls
```

### 7.5 端口冲突排查

| 现象 | 原因 | 解决 |
|------|------|------|
| `Port 8080 was already in use` | Tomcat HTTP 端口被占 | 修改 `server.http-port`，同步修改前端 `PROXY_URL` |
| `Permission denied` 绑定 443 | 非 root 用户绑定特权端口 | 使用 `-Dserver.port=8443` |
| `Connection refused: 127.0.0.1:18083` | Kuscia master 没启动或端口映射不对 | `docker ps` 检查 `charles-kuscia-master` 端口；确认 `KUSCIA_API_PORT` 与映射一致 |
| `Connection refused: 127.0.0.1:13081` | Kuscia Envoy 内部端口未暴露 | 检查 `docker port ${USER}-kuscia-master` 是否包含 `13081->80`；确认 `KUSCIA_GW_ADDRESS` |
| 前端刷新 404 | Nginx 没有把所有非静态路径回退到 `index.html` | Nginx 加 `location / { try_files $uri $uri/ /index.html; }` |

---

## 8. 常见问题排查

### 8.1 后端端口冲突

**症状**：启动时报 `Port 8080 was already in use` 或 `Permission denied`。

**原因与解决**：

- **8080 被占用**：

  先查看占用进程：

  ```bash
  sudo lsof -i :8080
  # 或
  netstat -anv | grep '\.8080 '
  ```

  如果是上次未正常退出的 SecretPad 后端，直接结束：

  ```bash
  lsof -t -i:8080 | xargs kill -9
  ```

  如果不想结束占用进程，可改用其他 HTTP 端口，例如 18080：

  ```bash
  java -Dspring.profiles.active=dev \
       -Dsun.net.http.allowRestrictedHeaders=true \
       -Dserver.port=8443 \
       -Dserver.http-port=18080 \
       -Dserver.http-port-inner=19001 \
       -jar target/secretpad.jar
  ```

  同时修改前端代理：

  ```bash
  echo "PROXY_URL=http://127.0.0.1:18080" > frontend-src/apps/platform/.env
  ```

- **443 权限不足**：非 root 用户无法绑定 443 端口，使用 `-Dserver.port=8443` 即可。

### 8.2 后端启动报 `no main manifest attribute`

**原因**：使用了子模块的普通 jar。

**解决**：使用根目录 fat jar：

```bash
java -jar target/secretpad.jar
```

### 8.3 后端日志出现 `UnknownHostException: root-kuscia-master`

**原因**：源码后端无法解析 Kuscia 容器名。

**解决**：启动后端前设置环境变量：

```bash
export KUSCIA_API_ADDRESS=127.0.0.1
export KUSCIA_GW_ADDRESS=127.0.0.1:13081
export KUSCIA_PROTOCOL=notls
```

### 8.4 前端提示用户名或密码错误

1. 确认后端已启动：`curl http://127.0.0.1:8080/actuator/health`
2. 确认前端代理配置 `apps/platform/.env` 指向正确的后端端口
3. 当前代码已固定密码为 `12345678`，用户名 `admin`
4. 若忘记密码或曾用旧密码启动过，可删除数据库重新生成：

   ```bash
   rm -f db/secretpad.sqlite db/secretpadQuartz.mv.db
   # 重新启动后端
   ```

### 8.5 前端报模块找不到

```bash
cd frontend-src
pnpm run setup
```

### 8.6 Kuscia 容器启动失败

查看容器日志：

```bash
docker logs -f ${USER}-kuscia-master
docker logs -f ${USER}-kuscia-lite-alice
docker logs -f ${USER}-kuscia-lite-bob
```

常见原因：端口冲突、磁盘空间不足、Docker 资源限制。

### 8.7 macOS 后端编译失败：Lombok 找不到符号

**症状**：`mvn clean install` 在 `secretpad-common` 报错，提示 `找不到符号`、`找不到变量 log` 等。

**原因**：macOS 系统可能安装了 JDK 21+ 或 JDK 26+，而当前项目依赖的 Lombok 版本仅支持到 JDK 17。JDK 版本过高会导致 Lombok 注解处理器失效。

**解决**：

1. 确认 Java 版本：

   ```bash
   java -version
   ```

2. 如果输出不是 `openjdk 17`，请使用项目内置 JDK 17：

   ```bash
   export JAVA_HOME=/path/to/secretpad/.tools/jdk-17/Contents/Home
   export PATH=$JAVA_HOME/bin:$PATH
   ```

3. 或者重新下载 JDK 17 for macOS 到 `.tools/jdk-17/`（参考 [1.2 使用项目内置工具](#12-使用项目内置工具可选)）。

4. 再次执行：

   ```bash
   mvn clean install -Dmaven.test.skip=true
   ```

### 8.8 macOS 前端 dev server 停止后端口仍被占用

**症状**：执行 `bash scripts/dev-stop-mac.sh` 后，`lsof -i :8000` 仍能看到 node 进程。

**原因**：`pnpm --filter secretpad dev` 会启动多个子进程，仅 kill 父进程可能残留。

**解决**：

```bash
# 按端口强制结束
lsof -ti :8000 | xargs kill -9

# 或使用脚本自带的清理
bash scripts/dev-stop-mac.sh --clean
```

---

## 9. 附录：端口与文件速查

### 9.1 关键端口

| 服务 | 默认端口 | 说明 |
|------|---------|------|
| 前端 dev 服务器 | 8000 | 开发访问地址 |
| 后端 HTTP | 8080 | API 服务端口（`server.http-port`） |
| 后端内部 HTTP | 9001 | 节点间通信端口（`server.http-port-inner`） |
| 后端 HTTPS | 443 / 8443 | 主端口（`server.port`），普通用户建议 8443 |
| Nginx 入口 | 80 / 443 | 生产环境可选，反代到 Tomcat 8080 |
| Kuscia master gateway | 18080 | 容器 1080，节点间认证鉴权 |
| Kuscia master KusciaAPI HTTP | 18082 | 容器 8082 |
| Kuscia master KusciaAPI gRPC | 18083 | 容器 8083，后端连接此端口 |
| Kuscia master Envoy 内部端口 | 13081 | 容器 80，`KUSCIA_GW_ADDRESS` 指向此端口 |
| Kuscia lite alice gateway | 28080 | 容器 1080 |
| Kuscia lite alice gRPC | 28083 | 容器 8083 |
| Kuscia lite bob gateway | 38080 | 容器 1080 |
| Kuscia lite bob gRPC | 38083 | 容器 8083 |

### 9.2 重要文件

| 文件/目录 | 作用 |
|----------|------|
| `target/secretpad.jar` | 后端可执行 fat jar |
| `config/application.yaml` | 后端主配置文件 |
| `config/application-dev.yaml` | 开发环境配置 |
| `config/certs/` | KusciaAPI 证书 |
| `config/server.jks` | HTTPS 服务证书 |
| `db/secretpad.sqlite` | SQLite 业务数据库 |
| `frontend-src/apps/platform/.env` | 前端代理配置 |
| `scripts/dev-start.sh` | 一键启动完整本地开发环境（Linux/macOS + Kuscia） |
| `scripts/dev-stop.sh` | 停止本地开发环境进程 |
| `scripts/install-kuscia-only.sh` | 仅部署 Kuscia 的脚本 |
| `scripts/dev-start-mac.sh` | macOS 一键启动前后端（无 Kuscia） |
| `scripts/dev-stop-mac.sh` | macOS 停止前后端 |

### 9.3 常用命令

```bash
# 一键启动完整本地开发环境（推荐）
bash scripts/dev-start.sh

# 停止后端和前端（保留 Kuscia）
bash scripts/dev-stop.sh

# 同时停止 Kuscia 容器
bash scripts/dev-stop.sh --kuscia

# 构建后端
mvn clean install -Dmaven.test.skip=true

# 生成证书
bash scripts/test/setup.sh

# 仅部署 Kuscia（不启动容器版 SecretPad）
bash scripts/install-kuscia-only.sh master -P notls

# 启动后端（连接 Docker Kuscia）
export KUSCIA_API_ADDRESS=127.0.0.1
export KUSCIA_GW_ADDRESS=127.0.0.1:13081
export KUSCIA_PROTOCOL=notls
java -Dspring.profiles.active=dev \
     -Dsun.net.http.allowRestrictedHeaders=true \
     -Dserver.port=8443 \
     -jar target/secretpad.jar

# 启动前端
cd frontend-src
pnpm --filter secretpad dev

# 查看 Kuscia 容器
docker ps | grep kuscia

# 查看 Kuscia 日志
docker logs -f ${USER}-kuscia-master

# 停止 Kuscia 容器（如需清理）
docker stop ${USER}-kuscia-master ${USER}-kuscia-lite-alice ${USER}-kuscia-lite-bob
```

### 9.4 macOS 常用命令

```bash
# 一键启动前后端（无 Kuscia）
bash scripts/dev-start-mac.sh

# 查看帮助
bash scripts/dev-start-mac.sh --help

# 仅检查环境
bash scripts/dev-start-mac.sh --check

# 只启动后端
bash scripts/dev-start-mac.sh --backend-only

# 只启动前端
bash scripts/dev-start-mac.sh --frontend-only

# 跳过编译快速启动
bash scripts/dev-start-mac.sh --no-build

# 运行前后端单元测试
bash scripts/dev-start-mac.sh --test

# 只运行后端测试
bash scripts/dev-start-mac.sh --test-backend

# 只运行前端测试
bash scripts/dev-start-mac.sh --test-frontend

# 停止前后端
bash scripts/dev-stop-mac.sh

# 停止前后端并清理日志/pid 文件
bash scripts/dev-stop-mac.sh --clean
```

---

**说明**：本文档基于 SecretPad 源码仓库实际运行经验整理。如遇版本升级导致命令变化，请以仓库最新 README 和 `docs/` 目录下的官方文档为准。
