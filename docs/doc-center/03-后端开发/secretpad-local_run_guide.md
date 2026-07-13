# SecretPad 本地运行完整指南（前后端联调版）

> 说明：SecretPad 主仓库（`secretpad`）本身不包含前端源码，前端代码位于独立仓库 [secretpad-frontend](https://github.com/fengzhizi319/secretpad-frontend)。本指南描述如何在本地完整搭建 SecretPad **后端 Java 服务**和**前端 React 应用**，并完成前后端联调登录。

如果你只想运行前端开发服务器，可直接跳到第 5 章；如果你已经搭好了后端，想了解如何与前端配合，可跳到第 8 章。

## 1. 环境要求

| 名称 | 推荐版本 | 说明 |
|------|---------|------|
| Node.js | >= 16.14.0（本环境使用 v20.14.0） | 前端运行基础 |
| pnpm | 8.8.0（由 `packageManager` 字段锁定） | 使用 corepack 激活 |
| Git | 任意 | 克隆前端仓库 |
| OpenJDK | 17 | 后端 Spring Boot 3 最低要求 |
| Maven | 3.8.8 | 后端编译打包工具 |
| Docker | ≥ 20.10 | 如需完整运行 Kuscia 隐私计算任务（可选） |

## 2. 一键准备本地运行时

以下脚本将 Node.js、pnpm、JDK 17、Maven 安装在项目内的 `.tools` 目录，避免污染系统环境。

```bash
# 进入项目根目录
cd /home/charles/code/secretpad

# 1. 下载 Node.js 20.14.0 到 .tools/node
mkdir -p .tools
curl -L -o .tools/node.tar.xz 'https://nodejs.org/dist/v20.14.0/node-v20.14.0-linux-x64.tar.xz'
tar -xf .tools/node.tar.xz -C .tools
mv .tools/node-v20.14.0-linux-x64 .tools/node
rm .tools/node.tar.xz

# 2. 激活 pnpm 8.8.0
export PATH=/home/charles/code/secretpad/.tools/node/bin:$PATH
corepack enable
corepack prepare pnpm@8.8.0 --activate

# 3. 下载 JDK 17 与 Maven 3.8.8（后端测试/运行需要）
curl -L -o .tools/jdk17.tar.gz 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.11%2B9/OpenJDK17U-jdk_x64_linux_hotspot_17.0.11_9.tar.gz'
tar -xzf .tools/jdk17.tar.gz -C .tools
mv .tools/jdk-17.0.11+9 .tools/jdk-17
rm .tools/jdk17.tar.gz

curl -L -o .tools/maven.tar.gz 'https://archive.apache.org/dist/maven/maven-3/3.8.8/binaries/apache-maven-3.8.8-bin.tar.gz'
tar -xzf .tools/maven.tar.gz -C .tools
mv .tools/apache-maven-3.8.8 .tools/maven
rm .tools/maven.tar.gz
```

设置环境变量（可加入 `~/.bashrc` 或每次执行前 source）：

```bash
export JAVA_HOME=/home/charles/code/secretpad/.tools/jdk-17
export PATH=$JAVA_HOME/bin:/home/charles/code/secretpad/.tools/maven/bin:/home/charles/code/secretpad/.tools/node/bin:$PATH
```

验证：

```bash
java -version      # openjdk 17.0.11
mvn -version       # Apache Maven 3.8.8
node -v            # v20.14.0
pnpm -v            # 8.8.0
```

## 3. 拉取前端源码

```bash
cd /home/charles/code/secretpad
# 快速拉取（浅克隆 --depth=1，仅最新 1 个提交) SecretPad 前端最新代码到 #frontend-src 文件夹
git clone --depth=1 https://github.com/fengzhizi319/secretpad-frontend.git frontend-src
```

## 4. 安装依赖并构建 workspace 包

前端使用 pnpm workspace + nx，platform 应用依赖 `@secretflow/dag` 和 `@secretflow/utils` 两个 workspace 包，需要先执行 `setup`。

```bash
cd /home/charles/code/secretpad/frontend-src

# 安装所有依赖（约 2271 个包）
pnpm install

# 构建 workspace 内部包（utils / dag）并执行 umi setup
pnpm run setup
```

## 5. 运行前端开发服务器

### 5.1 仅启动 platform 应用（推荐）

#### 什么是 platform 应用？

`platform` 应用就是 SecretPad 的**主站 Web 应用**，也就是用户日常登录和操作的那个平台页面。在前端仓库 `secretpad-frontend` 的目录结构里：

```text
frontend-src/
├── apps/
│   ├── platform/     ← SecretPad 平台主站（你要运行的就是这个）
│   └── docs/         ← 前端内部文档站点
├── packages/
│   ├── dag/          ← 工作流 DAG 画布组件
│   └── utils/        ← 通用工具函数
```

- `apps/platform` 是一个基于 **Umi 4 + React + Ant Design** 的独立应用，它的 `package.json` 中 `name` 字段是 `secretpad`。
- 因为 `pnpm --filter secretpad dev` 里的 `secretpad` 就是这个应用的包名，所以这条命令实际启动的就是 `apps/platform`。
- 我们平时说的“启动 SecretPad 前端”，本质上就是启动 `platform` 这个应用。它负责登录页、项目管理、节点管理、数据管理、任务流编排等所有用户界面。
- `apps/docs` 是前端团队内部的技术文档站点，普通用户开发时不需要启动；`packages/dag` 和 `packages/utils` 是 platform 依赖的共享包，已经在第 4 步通过 `pnpm run setup` 构建好了。

因此，**“仅启动 platform 应用”就是“只启动 SecretPad 主站前端”的意思**，这是本地开发最常用的方式。

```bash
pnpm --filter secretpad dev
```

成功后会输出：

```text
App listening at:
  >   Local: http://localhost:8000
ready -  > Network: http://10.6.25.148:8000

Now you can open browser with the above addresses↑
event - [Webpack] Compiled in 10383 ms (8451 modules)
```

### 5.2 配置后端 API 代理（可选）

#### 什么是后端 API 代理？

“后端 API 代理”指的是：**让前端开发服务器帮你把请求转发到真正的后端服务**。可以理解成：

- 你在浏览器里访问的地址是 `http://localhost:8000`（前端 dev 服务器）。
- 但前端页面里所有调用 `/api/xxx` 的接口，实际上是由后端的 SecretPad Java 服务提供的，通常跑在 `http://localhost:8080`。
- 直接让浏览器去请求 `localhost:8080` 会因为**浏览器的跨域安全策略（CORS）**被拦截，导致接口报错。
- 配置代理后，Umi 开发服务器会把浏览器发过来的 `/api/xxx` 请求**原样转发**到 `localhost:8080/api/xxx`，再后端返回结果后再返回给浏览器。对浏览器来说，它始终只和 `localhost:8000` 通信，不会出现跨域问题。

简单类比：

> 前端 dev 服务器 = 公司前台；后端服务 = 某个办公室。你（浏览器）不知道办公室在哪，但你可以把请求交给前台，前台帮你把请求转交给办公室，再把办公室的回执交还给你。

#### 如何配置代理？

在 `frontend-src/apps/platform/` 下创建 `.env` 文件：

```text
PROXY_URL=http://127.0.0.1:8080
```

这样所有以 `/api` 开头的请求都会被代理到本地 SecretPad 后端服务。若未配置代理，前端页面可正常加载，但调用 `/api/*` 接口时会因无法连接后端而报错。

> 代理规则由 `frontend-src/apps/platform/config/config.ts` 读取 `.env` 并注入到 Umi 的 `proxy` 配置中实现。如果你需要代理到其他地址，只要修改 `PROXY_URL` 即可。

### 5.3 启动全部前端应用

```bash
pnpm dev
```

该命令会并行启动 workspace 中所有非 `demo-*` 应用的 dev 服务器。

### 5.4 关于登录用户名/密码

仅启动前端开发服务器时，打开 `http://localhost:8000` 会进入登录页面。这里的用户名和密码**不是由前端生成的，而是由 SecretPad 后端服务决定**的。因此解决登录问题需要两步：

1. **先启动 SecretPad 后端服务**：参考后端运行文档，把 Java 服务跑起来（默认端口通常是 8080）。
2. **在前端配置后端 API 代理**：按 5.2 节配置 `PROXY_URL=http://127.0.0.1:8080`，让前端能把登录请求发到后端。

完成以上两步后，即可使用后端提供的账号密码登录。

#### 默认账号密码是什么？

- **默认用户名**：`admin`
- **默认密码**：第一次部署/启动后端时，系统会**随机生成一个 8 位左右的强密码**（通常包含大小写字母、数字和特殊字符），不会固定为 `admin/123456` 之类的弱口令。

随机密码的查看方式取决于你的部署方式：

- 如果通过部署脚本/安装脚本启动，密码会打印在安装日志或终端输出中，形如：

  ```text
  The login name:'admin' ,The login password:'5owyT0U$' .
  ```

- 如果是通过 IDE 或 `make` 等方式启动，可以在服务日志中搜索 `login password` 或 `The login name` 找到默认密码。

- 更多找回默认密码的方法可参考：[SecretPad 默认密码查看](../deployment/log.md#secretpad默认密码查看)。

> 注意：本地开发环境中，如果你没有实际启动后端，也没有配置代理，即使输入任何用户名密码也无法登录，因为前端本身不保存账号信息。

## 6. 构建并集成到 SecretPad 后端

#### 这是什么意思？

SecretPad 的前端和后端是**独立开发、独立构建**的：

- 前端代码编译后得到的是一堆静态文件（HTML、CSS、JS、图片等），位于 `frontend-src/apps/platform/dist/`。
- 后端是一个 Spring Boot 项目，最终打包成可运行的 `secretpad-web-*.jar`。

“构建并集成到 SecretPad 后端”就是把前端编译好的静态文件**拷贝到后端项目的资源目录中**，这样当后端 JAR 启动时，访问对应的 Web 地址就会直接由后端把这些静态页面返回给浏览器。换句话说：

> 集成后，你只需要启动后端一个 JAR 包，就能同时提供 Web 页面和 API 服务，不需要再单独运行前端 dev 服务器。

#### 集成逻辑是怎样的？

执行：

```bash
cd /home/charles/code/secretpad
make build
```

其中 `make build` 实际调用的是 `scripts/build/build.sh true`，关键逻辑如下：

1. **获取前端最新 tag**：脚本从远程仓库 `https://github.com/fengzhizi319/secretpad-frontend.git` 拉取最新的 tag 名称。
2. **下载对应 tag 的前端产物**：从阿里云 OSS 下载名为 `<tag>.tar` 的预编译产物。
3. **解压产物**：解压后得到 `dist/` 目录。
4. **拷贝到后端资源目录**：把 `dist/` 下的所有静态文件复制到 `secretpad-web/src/main/resources/static/`。
5. **执行 Maven 打包**：运行 `mvn clean package -DskipTests`，把后端代码和刚刚拷进去的静态资源一起打成 JAR 包。

打包完成后，运行 `java -jar secretpad-web/target/secretpad-web-*.jar`，Spring Boot 会自动把 `static/` 目录作为静态资源对外提供，浏览器访问服务端口即可打开平台页面。

> 在本地开发调试时，通常不需要执行这步。只有在准备发布、部署或验证完整 JAR 包时才需要构建并集成。

## 7. 后端本地运行完整指南

> 本章介绍如何从零开始把 SecretPad 的 Java 后端服务在本地跑起来。只有后端跑起来了，前端输入用户名密码才能真正的“登录进去”。

### 7.1 后端是什么？和前端是什么关系？

SecretPad 后端是一个 **Spring Boot 3 + Java 17** 的 Web 服务，核心职责包括：

- 提供 RESTful API（路径都以 `/api` 开头），供前端调用。
- 用户认证与权限管理（登录、token、角色等）。
- 项目管理、节点管理、数据表管理、任务调度。
- 通过 KusciaAPI 与底层隐私计算引擎 Kuscia 交互。

前端（React + Umi）只负责展示页面和收集用户输入，**所有业务逻辑和数据都存储在后端**。因此本地开发时，必须同时启动后端服务，前端页面上的登录、创建项目、运行任务等操作才会真正生效。

可以把前后端关系理解为：

> 前端 = 餐厅点餐界面；后端 = 厨房和收银系统。顾客（你）在界面上点菜、结账，真正出餐和扣款都在后端完成。

### 7.2 环境要求

| 名称 | 推荐版本 | 说明 |
|------|---------|------|
| OpenJDK | 17 | Spring Boot 3 最低要求 Java 17 |
| Maven | 3.8.8 | 编译打包工具 |
| Docker | ≥ 20.10 | 如需完整运行 Kuscia/MVP 隐私计算任务（本地调试可不启动） |
| SQLite | 3.4.2+ | 默认内置数据库，无需单独安装 |

> 如果你已经按第 2 章准备好 `.tools` 目录，JDK 17 和 Maven 3.8.8 已经可用，只需要设置环境变量即可。

### 7.3 后端配置文件说明

后端所有配置都集中在项目根目录的 `config/` 文件夹下：

| 文件 | 作用 |
|------|------|
| `config/application.yaml` | 默认配置，定义端口、SQLite/H2 数据源、Kuscia 节点、Flyway 迁移路径等 |
| `config/application-dev.yaml` | **本地开发推荐** profile，覆盖 `platform-type`、`gateway`、Kuscia 端口、日志路径 |
| `config/application-edge.yaml` | Edge 模式专用配置 |
| `config/application-p2p.yaml` | P2P / Autonomy 模式专用配置 |
| `config/application-test.yaml` | 测试 profile，关闭认证、使用临时目录 |
| `config/schema/` | Flyway 数据库迁移 SQL 文件 |
| `config/certs/` | KusciaAPI 客户端证书（`client.crt`、`client.pem`、`token`） |
| `config/server.jks` | HTTPS 服务证书 |

#### 7.3.1 关键配置项解读

打开 `config/application.yaml`，重点关注以下几项：

```yaml
server:
  http-port: 8080        # 对外 HTTP 端口，前端默认访问这个端口
  http-port-inner: 9001  # 内部 HTTP 端口，节点间通信/内部调用使用
  port: 443              # HTTPS 端口
  ssl:
    enabled: true
    key-store: "file:./config/server.jks"
    key-store-password: ${KEY_PASSWORD:secretpad}

spring:
  datasource:
    default:
      driver-class-name: org.sqlite.JDBC
      jdbc-url: jdbc:sqlite:./db/secretpad.sqlite   # 默认 SQLite 数据库文件
    quartz:
      driver-class-name: org.h2.Driver
      jdbc-url: jdbc:h2:./db/secretpadQuartz.mv.db;DB_CLOSE_ON_EXIT=FALSE

secretpad:
  platform-type: CENTER  # 平台模式：CENTER（中心化）、EDGE、AUTONOMY（P2P）
  node-id: kuscia-system # 当前节点标识
  gateway: ${KUSCIA_GW_ADDRESS:127.0.0.1:80}       # Kuscia Gateway 地址
  auth:
    enabled: true
    pad_name: ${SECRETPAD_USER_NAME}               # 可指定默认登录用户名
    pad_pwd: ${SECRETPAD_PASSWORD}                 # 可指定默认登录密码
```

本地开发时，`config/application-dev.yaml` 会覆盖上述部分配置：

```yaml
secretpad:
  platform-type: CENTER
  node-id: ${NODE_ID:kuscia-system}
  gateway: ${KUSCIA_GW_ADDRESS:127.0.0.1:18301}   # dev 模式下指向本机 master 的 envoy 端口
  logs:
    path: ../log

kuscia:
  nodes:
    - domainId: ${NODE_ID:kuscia-system}
      mode: master
      host: ${KUSCIA_API_ADDRESS:root-kuscia-master}
      port: ${KUSCIA_API_PORT:18083}              # dev 模式 Kuscia master API 端口
      protocol: ${KUSCIA_PROTOCOL:tls}
      cert-file: config/certs/client.crt
      key-file: config/certs/client.pem
      token: config/certs/token
    # ... alice / bob lite 节点配置
```

> **本地调试一般使用 `dev` profile + CENTER 模式**，不需要修改太多配置。如果你要对接真实的 Kuscia 环境，才需要修改 `gateway` 和 `kuscia.nodes` 中的地址/端口。

#### 7.3.2 指定固定用户名密码（可选）

默认情况下，用户名固定为 `admin`，密码由后端**随机生成**（见 7.7 节如何在日志中查看）。如果你想在开发阶段使用固定密码，可以通过环境变量指定：

```bash
export SECRETPAD_USER_NAME=admin
export SECRETPAD_PASSWORD=YourP@ssw0rd
```

启动时 Spring 会读取这两个环境变量，并将其写入 `user_accounts` 表。注意密码需要满足复杂度要求（至少 8 位，包含大小写字母、数字和特殊字符）。

### 7.4 生成证书与数据库目录

SecretPad 通过 **mTLS** 与 Kuscia 通信，需要客户端证书；同时 HTTPS 需要 `server.jks`。项目已经提供了脚本一键生成：

```bash
cd /home/charles/code/secretpad

# 生成 KusciaAPI 客户端证书（config/certs/、config/certs/alice/、config/certs/bob/）
# 以及 HTTPS 服务证书 config/server.jks，并创建 db/ 目录
bash scripts/test/setup.sh
```

执行成功后会看到：

```text
start to generate kusciaapi certs
cert path is: /home/charles/code/secretpad/config/certs
...
generate kusciaapi certs successfully
```

生成的关键文件：

```text
config/
├── certs/
│   ├── client.crt      # 当前节点客户端证书
│   ├── client.pem      # 当前节点客户端私钥
│   ├── token           # KusciaAPI 访问 token
│   ├── ca.crt          # CA 证书
│   ├── alice/          # alice lite 节点证书
│   └── bob/            # bob lite 节点证书
├── server.jks          # HTTPS 服务证书
└── ...
db/
```

> 这些证书在本地开发时仅用于让服务正常启动。如果你要对接真实 Kuscia 集群，需要用真实证书替换 `config/certs/` 下的文件。

### 7.5 编译后端

SecretPad 是一个多模块 Maven 项目，模块之间互相依赖，因此需要先 `install` 到本地 Maven 仓库：

```bash
cd /home/charles/code/secretpad

# 编译并安装所有模块到本地仓库（跳过测试以节省时间）
mvn clean install -Dmaven.test.skip=true

# 再执行一次 compile，确保 proto 等代码生成完毕
mvn compile
```

关键模块说明：

| 模块 | 作用 |
|------|------|
| `secretpad-common` | 公共常量、枚举、工具类、DTO |
| `secretpad-persistence` | 数据库实体、Repository、Flyway 迁移 |
| `secretpad-manager` | Kuscia 交互、数据源/数据表处理 |
| `secretpad-service` | 业务逻辑：用户、认证、项目、任务等 |
| `secretpad-scheduled` | Quartz 定时任务 |
| `secretpad-api` | 聚合 KusciaAPI / SecretPad API 的客户端 SDK |
| `secretpad-web` | Spring Boot Web 入口，含 Controller、启动类 |

编译成功后，`secretpad-web/target/` 下会生成 `secretpad-web-*.jar`。

### 7.6 启动后端

#### 方式一：命令行启动（推荐，最简单）

```bash
cd /home/charles/code/secretpad

java -Dspring.profiles.active=dev \
     -Dsun.net.http.allowRestrictedHeaders=true \
     -jar secretpad-web/target/secretpad-web-*.jar
```

参数说明：

- `-Dspring.profiles.active=dev`：激活 `dev` 配置文件，使用本地开发参数。
- `-Dsun.net.http.allowRestrictedHeaders=true`：允许设置受限 HTTP 头，Kuscia 通信需要。
- `-jar secretpad-web/target/secretpad-web-*.jar`：运行编译好的 Spring Boot JAR。

启动成功后，会看到类似日志：

```text
INFO  o.secretflow.secretpad.web.SecretPadApplication : SecretPad start success, http://192.168.x.x:443 innerHttpPort:9001 Profile:dev
INFO  o.secretflow.secretpad.web.SecretPadApplication : userName:admin password:5owyT0U$
```

> 注意：虽然日志里打印的是 `http://...:443`，但实际对外 HTTP 端口是 `8080`（`server.http-port`）。本地浏览器访问 `http://localhost:8080/login` 即可。

#### 方式二：IDEA / Eclipse 中启动（便于断点调试）

1. 在 IDEA 中打开 SecretPad 项目，等待 Maven 导入完成。
2. 找到启动类：`secretpad-web/src/main/java/org/secretflow/secretpad/web/SecretPadApplication.java`
3. 右键 `main` 方法 → `Run 'SecretPadApplication.main()'` 的 Edit Configurations。
4. 在 **VM options** 中填入：
   ```text
   -Dspring.profiles.active=dev
   -Dsun.net.http.allowRestrictedHeaders=true
   ```
5. 点击运行。

> 本地调试如果要真正跑隐私计算任务，还需要先通过 [MVP 安装包](https://secretflow-public.oss-cn-hangzhou.aliyuncs.com/mvp-packages/secretflow-allinone-linux-x86_64-latest.tar.gz) 启动 Kuscia 容器，然后停止其中的 SecretPad 容器，只保留 Kuscia 容器。详细可参考：[SecretPad 本地调试](../development/ru_in_idea_cn.md)。

#### 方式三：构建完整 JAR 后启动（含前端静态资源）

如果你已经按第 6 章执行过 `make build`，会得到一个已经包含前端产物的 `target/secretpad.jar`，直接运行即可：

```bash
cd /home/charles/code/secretpad
java -Dspring.profiles.active=dev \
     -Dsun.net.http.allowRestrictedHeaders=true \
     -jar target/secretpad.jar
```

此时打开 `http://localhost:8080`，浏览器会直接加载集成在 JAR 内的前端页面，不需要单独启动前端 dev 服务器。

### 7.7 验证后端启动成功

1. **查看日志**：找到 `SecretPad start success` 和 `userName:admin password:xxxxx`。
2. **访问健康检查接口**：
   ```bash
   curl http://localhost:8080/actuator/health
   ```
   正常返回：
   ```json
   {"status":"UP"}
   ```
3. **浏览器直接访问**：打开 `http://localhost:8080/login`，如果看到登录页面，说明后端已启动。

### 7.8 后端启动常见问题

#### 7.8.1 端口被占用

如果 8080 被其他程序占用，会报错：

```text
Port 8080 was already in use
```

解决方式：

- 结束占用 8080 的进程，或
- 修改 `config/application.yaml` 中的 `server.http-port` 为其他端口（如 8081）。如果改了后端端口，前端的 `PROXY_URL` 也要同步修改。

#### 7.8.2 证书文件不存在导致启动失败

如果日志出现 `config/certs/client.crt (No such file or directory)`，说明没有执行 `bash scripts/test/setup.sh`。执行该脚本生成证书即可。

#### 7.8.3 数据库迁移失败

如果启动时报 Flyway 校验错误，可能是之前用不同版本代码生成过 `db/secretpad.sqlite`。解决：

```bash
# 删除旧数据库，让 Flyway 重新初始化（会丢失本地测试数据）
rm -f db/secretpad.sqlite db/secretpadQuartz.mv.db
```

然后重新启动后端。

#### 7.8.4 Kuscia 连接报错

本地开发时如果没有启动 Kuscia，日志中可能会有连接 `127.0.0.1:18083` 失败的警告。**这不影响登录和基础页面浏览**，只会影响需要真正调用 Kuscia 的功能（如创建项目、运行训练任务）。如果只做前后端联调测试，可以忽略。

## 8. 前后端联调与登录流程

### 8.1 前后端如何配合？

把前后端都启动后，整个访问链路如下：

```text
浏览器 http://localhost:8000
        ↓
前端 dev 服务器（Umi，端口 8000）
        ↓  页面渲染、静态资源返回
用户看到登录页
        ↓  输入 admin / 密码，点击登录
前端把请求发到 /api/v1alpha1/user/login
        ↓  Umi proxy 转发（因为配置了 PROXY_URL）
后端 SecretPad 服务（端口 8080）
        ↓  校验用户名密码，生成 token
返回 token 给前端
        ↓
前端保存 token，跳转到首页
```

关键点：

- **浏览器始终只和 `localhost:8000` 通信**，不会出现跨域问题。
- **`/api` 开头的请求**会被前端 dev 服务器代理到后端 `localhost:8080`。
- **用户名密码由后端生成并校验**，前端只是“传话筒”。

### 8.2 完整登录步骤演示

按照以下顺序操作，即可实现从前端到后端的完整登录：

#### 步骤 1：启动后端

```bash
cd /home/charles/code/secretpad
export JAVA_HOME=/home/charles/code/secretpad/.tools/jdk-17
export PATH=$JAVA_HOME/bin:/home/charles/code/secretpad/.tools/maven/bin:$PATH

bash scripts/test/setup.sh
mvn clean install -Dmaven.test.skip=true

java -Dspring.profiles.active=dev \
     -Dsun.net.http.allowRestrictedHeaders=true \
     -jar secretpad-web/target/secretpad-web-*.jar
```

等待日志出现：

```text
SecretPad start success, http://...:443 innerHttpPort:9001 Profile:dev
userName:admin password:5owyT0U$
```

记下密码，例如 `5owyT0U$`。

#### 步骤 2：配置前端代理并启动前端

在 `frontend-src/apps/platform/` 下创建 `.env`：

```text
PROXY_URL=http://127.0.0.1:8080
```

然后启动前端：

```bash
cd /home/charles/code/secretpad/frontend-src
pnpm --filter secretpad dev
```

#### 步骤 3：浏览器访问并登录

1. 打开 `http://localhost:8000`。
2. 看到登录页面。
3. 用户名输入 `admin`。
4. 密码输入后端日志中打印的随机密码（如 `5owyT0U$`）。
5. 点击登录。

#### 步骤 4：验证登录成功

如果登录成功，页面会跳转到平台首页；如果失败，页面会提示“用户名或密码错误”。

你可以在浏览器开发者工具（按 F12 → Network）中观察到：

- 请求 URL：`http://localhost:8000/api/v1alpha1/user/login`
- 请求方法：`POST`
- 请求体：`{"name":"admin","passwordHash":"..."}`
- 响应体：`{"data":{"token":"..."}}`

这说明前端把登录请求发到了后端，后端校验通过后返回了 token。

### 8.3 前后端联调验证清单

| 检查项 | 期望结果 |
|--------|---------|
| 后端日志出现 `SecretPad start success` | ✅ 后端启动成功 |
| 后端日志出现 `userName:admin password:xxx` | ✅ 已生成默认账号 |
| `curl http://localhost:8080/actuator/health` 返回 `{"status":"UP"}` | ✅ 后端健康 |
| 前端 dev 服务器输出 `http://localhost:8000` | ✅ 前端启动成功 |
| 前端 `.env` 中 `PROXY_URL=http://127.0.0.1:8080` | ✅ 代理已配置 |
| 浏览器访问 `http://localhost:8000` 看到登录页 | ✅ 前端页面加载正常 |
| 输入 admin + 后端密码后成功进入首页 | ✅ 前后端联调成功 |

如果其中任何一步失败，请按对应章节的“常见问题”排查。

## 9. 本次运行验证（前端快速检查）

> 本章只验证前端 dev 服务器本身是否启动成功。完整的前后端正向登录验证请参见第 8.3 节“前后端联调验证清单”。

按上述步骤执行后，platform 应用成功启动：

```text
> secretpad@ dev /home/charles/code/secretpad/frontend-src/apps/platform
> umi dev

info  - Umi v4.3.18
info  - Preparing...
        ╔════════════════════════════════════════════════════╗
        ║ App listening at:                                  ║
        ║  >   Local: http://localhost:8000                  ║
ready - ║  > Network: http://10.6.25.148:8000                ║
        ║                                                    ║
        ║ Now you can open browser with the above addresses↑ ║
        ╚════════════════════════════════════════════════════╝
event - [Webpack] Compiled in 10383 ms (8451 modules)
```

- 访问地址：`http://localhost:8000`
- 编译成功：8451 个模块
- 未配置 `PROXY_URL` 时页面可正常加载，调用 `/api/*` 接口需自行启动后端并配置代理。

## 10. 常见问题

### 10.1 报错 `Module not found: Can't resolve '@secretflow/dag'`

原因：没有先执行 `pnpm run setup` 构建 workspace 包。  
解决：按第 4 步执行 `pnpm run setup` 后再运行 dev。

### 10.2 前端端口被占用

Umi 默认使用 `8000` 端口。若被占用，可在 `apps/platform/config/config.ts` 中增加 `port` 配置，或使用环境变量：

```bash
PORT=8001 pnpm --filter secretpad dev
```

### 10.3 浏览器提示 `caniuse-lite is outdated`

不影响运行。如需消除提示，可执行：

```bash
npx update-browserslist-db@latest
```

### 10.4 后端启动报证书或 `server.jks` 相关错误

原因：没有执行 `bash scripts/test/setup.sh` 生成证书，或证书被误删。  
解决：重新执行：

```bash
cd /home/charles/code/secretpad
bash scripts/test/setup.sh
```

### 10.5 后端日志在哪里看？

- 命令行启动时，日志直接输出在终端。
- 使用 `dev` profile 时，日志默认写入 `secretpad-web/log/`（因为 `application-dev.yaml` 中 `logs.path: ../log`，相对于 `secretpad-web` 模块目录）。
- 也可以在启动命令后追加重定向，方便事后查看：
  ```bash
  java -Dspring.profiles.active=dev \
       -Dsun.net.http.allowRestrictedHeaders=true \
       -jar secretpad-web/target/secretpad-web-*.jar > secretpad.log 2>&1
  ```

### 10.6 登录时提示“用户名或密码错误”

1. 确认后端已经启动。
2. 确认前端 `.env` 中 `PROXY_URL` 指向了正确的后端地址（如 `http://127.0.0.1:8080`）。
3. 确认输入的用户名是 `admin`，密码是后端日志中打印的随机密码（不是你自己随便输入的）。
4. 如果之前用 `SECRETPAD_USER_NAME` / `SECRETPAD_PASSWORD` 指定过固定密码，后来又删掉了环境变量，后端会重新生成随机密码，请以最新一次启动日志为准。
5. 如果仍然失败，可以停止后端、删除 `db/secretpad.sqlite` 后重新启动，让后端重新初始化账号。

### 10.7 前端页面能打开，但所有 `/api/*` 请求都 404/502

原因：前端 dev 服务器没有正确代理到后端。  
排查步骤：

1. 检查 `frontend-src/apps/platform/.env` 是否存在且内容正确：
   ```text
   PROXY_URL=http://127.0.0.1:8080
   ```
2. 检查后端是否运行在 8080 端口：
   ```bash
   curl http://localhost:8080/actuator/health
   ```
3. 检查浏览器开发者工具 Network 面板，确认请求 URL 是 `http://localhost:8000/api/...` 而不是 `http://localhost:8080/api/...`。如果是后者，说明前端代码里写死了后端地址，应该统一使用相对路径 `/api/...`。
