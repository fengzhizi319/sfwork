# SecretPad Nginx 反向代理与入口网关实践

本文档介绍如何在 SecretPad 前面引入 **Nginx** 作为统一的入口网关，让它承担“对外收请求、对内做分发、自己处理静态文件与 SSL”的职责，使后端 SecretPad 服务只需专注于业务逻辑，不再关心端口、证书、静态资源等杂活。

> 说明：SecretPad 官方仓库默认**不携带 Nginx 配置**，而是直接使用 Spring Boot 内嵌 Tomcat 对外提供服务。本文档给出的是在生产环境中常见的 **Nginx + SecretPad** 部署方案与推荐配置。

---

## 1. 现状：没有 Nginx 时 SecretPad 如何工作

在默认构建与部署流程中，SecretPad 是一个标准的 Spring Boot 3 + Java 17 应用，内嵌 Tomcat 同时承担以下角色：

| 角色 | 默认实现 | 关键配置/代码 |
|---|---|---|
| HTTP 服务 | 内嵌 Tomcat 额外 connector | `server.http-port=8080` |
| HTTPS 服务 | 内嵌 Tomcat SSL | `server.port=443` + `server.ssl.*` |
| 内部 RPC | 内嵌 Tomcat 额外 connector | `server.http-port-inner=9001` |
| 静态文件服务 | Spring Boot `src/main/resources/static/` | `IndexController` SPA 回退 |
| 压缩 | Tomcat connector 压缩 | `server.compression.*` |
| Edge 模式转发 | 应用层 `RestTemplate` 转发 | `EdgeRequestFilter` |

### 1.1 多端口 Tomcat 配置

`secretpad-web/src/main/java/org/secretflow/secretpad/web/SecretPadApplication.java` 中手动注册了两个额外 connector：

```java
@Bean
public ServletWebServerFactory containerFactory() {
    TomcatServletWebServerFactory tomcat = new TomcatServletWebServerFactory();
    buildConnector(tomcat, httpPort);        // 8080，用户 HTTP
    buildConnector(tomcat, innerHttpPort);   // 9001，内部节点 RPC
    tomcat.setUriEncoding(StandardCharsets.UTF_8);
    return tomcat;
}
```

### 1.2 默认端口与 SSL

`config/application.yaml`：

```yaml
server:
  http-port: 8080
  http-port-inner: 9001
  port: 443
  ssl:
    enabled: true
    key-store: "file:./config/server.jks"
    key-store-password: ${KEY_PASSWORD:secretpad}
    key-alias: secretpad-server
    key-password: ${KEY_PASSWORD:secretpad}
    key-store-type: JKS
  compression:
    enabled: true
    mime-types: text/html,text/xml,text/plain,text/css,application/javascript,application/json
    min-response-size: 1024
```

### 1.3 静态文件集成方式

前端产物在打包时通过 `scripts/build/build.sh` 下载并复制到 `secretpad-web/src/main/resources/static/`，最终随 JAR 一起发布：

```bash
if [[ $WITH_FRONTEND_FLAG == true ]]; then
    FRONTEND_LATEST_TAG=$(git ls-remote --sort='version:refname' --refs --tags https://github.com/fengzhizi319/secretpad-frontend.git | tail -n1 | sed 's/.*\///')
    WORK_DIR="./tmp/frontend"
    mkdir -p $WORK_DIR
    wget -O $WORK_DIR/frontend.tar https://secretflow-public.oss-cn-hangzhou.aliyuncs.com/secretpad-frontend/"${FRONTEND_LATEST_TAG}".tar
    tar -xvf $WORK_DIR/frontend.tar -C ${WORK_DIR} --strip-components=1
    DIST_DIR="$WORK_DIR/apps/platform/dist"
    TARGET_DIR="${ROOT}/secretpad-web/src/main/resources/static"
    mkdir -p "${TARGET_DIR}"
    cp -rpf $DIST_DIR/* "${TARGET_DIR}"
fi
```

`IndexController` 把所有前端路由回退到 `index.html`：

```java
@Controller
public class IndexController {
    @RequestMapping(value = {"/", "/dag/**", "/home/**", "/node/**", "/guide/**",
                             "/record/**", "/login/**", "/logout/**", "/my-node/**",
                             "/message/**", "/edge/**", "/edge", "/model-submission/**"},
                    method = RequestMethod.GET)
    public String index() {
        return "index";
    }
}
```

### 1.4 Docker 部署映射

`build/Dockerfiles/anolis.Dockerfile` 暴露了 80、8080、9001：

```dockerfile
EXPOSE 80
EXPOSE 8080
EXPOSE 9001
ENTRYPOINT java ${JAVA_OPTS} -Dsun.net.http.allowRestrictedHeaders=true  -jar -Dspring.profiles.active=${SPRING_PROFILES_ACTIVE} /app/secretpad.jar
```

`scripts/deploy/secretpad.sh` 把宿主机 `PAD_PORT`（默认 8088）映射到容器 8080：

```bash
docker run -itd --init --name="${PAD_CTR}" --restart=always --network="${NETWORK_NAME}" \
    -p "${PAD_PORT}":8080 \
    -e SPRING_PROFILES_ACTIVE="${SPRING_PROFILES_ACTIVE}" \
    ...
    "${SECRETPAD_IMAGE}"
```

---

## 2. 为什么要引入 Nginx

虽然 Spring Boot 内嵌 Tomcat 可以“开箱即用”，但在生产环境中通常希望把以下职责从 Java 进程剥离出来：

| 职责 | 交给 Nginx 的好处 |
|---|---|
| **统一入口** | 所有用户只访问 80/443，隐藏后端 8080/9001 等端口 |
| **SSL 终止** | 证书管理、TLS 版本、HSTS、OCSP 等在 Nginx 层统一处理，无需改动 JKS |
| **静态文件加速** | Nginx 直接返回 JS/CSS/图片，不占用 Tomcat 线程 |
| **反向代理/负载均衡** | 支持多实例、健康检查、灰度发布 |
| **安全防护** | 限制请求体大小、防慢攻击、IP 白名单、WAF 规则 |
| **日志与监控** | Nginx access log 更轻量，便于接入 Prometheus/Loki |
| **URL 重写与转发** | 统一处理 API 前缀、跨域、SSE 长连接 |

---

## 3. Nginx 在 SecretPad 中的三层角色

```
                        ┌─────────────────────────────────────┐
                        │           公网用户 / 浏览器           │
                        └─────────────┬───────────────────────┘
                                      │ 80 / 443
                        ┌─────────────▼───────────────────────┐
                        │              Nginx                  │
                        │  • SSL 终止                          │
                        │  • 静态文件 (JS/CSS/图片/index.html)  │
                        │  • 反向代理 /api、/sync、SSE 等       │
                        └─────────────┬───────────────────────┘
                                      │
              ┌───────────────────────┼───────────────────────┐
              │                       │                       │
    ┌─────────▼─────────┐  ┌──────────▼──────────┐  ┌─────────▼─────────┐
    │ SecretPad (8080)  │  │ SecretPad internal  │  │ 可选：Kuscia GW   │
    │ 业务 API + SPA    │  │       (9001)        │  │   (Envoy)         │
    └───────────────────┘  └─────────────────────┘  └───────────────────┘
```

### 3.1 对外：接收所有用户请求（80/443）

Nginx 监听标准 HTTP/HTTPS 端口，所有流量先到达 Nginx。HTTP 自动 301 跳转到 HTTPS。

### 3.2 对内：分发到正确的后端服务

- `/api/**`、`/sync` 等动态请求 → 转发到 SecretPad 8080。
- 内部节点 RPC（如果需要从外部访问）→ 转发到 9001；通常 9001 只对内网或容器间开放，不暴露到公网。
- Kuscia Gateway 相关流量 → 视部署模式决定是否由 Nginx 代发。

### 3.3 自己：直接处理静态文件、SSL 加密

- 把前端构建产物（`dist/` 目录）放到 Nginx 的 `root` 目录。
- 为静态资源设置长期缓存、gzip/brotli 压缩。
- SSL 证书挂载到 Nginx，Java 后端可以关闭 HTTPS，只保留 HTTP。

### 3.4 后端：专心处理业务逻辑

SecretPad 启动时关闭 SSL（或只监听 8080），不再关心：

- 证书路径与续期
- 静态资源缓存
- 公网端口映射
- HTTPS 重定向

---

## 4. 推荐 Nginx 配置

### 4.1 基础反向代理配置

```nginx
# /etc/nginx/nginx.conf 或 /etc/nginx/conf.d/secretpad.conf

server {
    listen 80;
    server_name secretpad.example.com;

    # HTTP 统一跳 HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name secretpad.example.com;

    # SSL 证书
    ssl_certificate     /etc/nginx/ssl/secretpad.crt;
    ssl_certificate_key /etc/nginx/ssl/secretpad.key;

    # 推荐 TLS 配置
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:...;
    ssl_prefer_server_ciphers on;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;

    # 静态文件根目录（前端 dist 产物）
    root /var/www/secretpad;
    index index.html;

    # 静态资源长期缓存
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|otf|map)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }

    # 前端路由回退：所有非 API 路径返回 index.html
    location / {
        try_files $uri $uri/ /index.html;
    }

    # API / SSE 转发到 SecretPad
    location ~ ^/(api|sync) {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;

        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Port  $server_port;

        # SSE / WebSocket 支持
        proxy_set_header Connection "";
        proxy_read_timeout 86400s;
        proxy_buffering off;

        # 允许较大请求体（上传 CSV 等）
        client_max_body_size 500m;
    }
}
```

### 4.2 静态文件独立目录版

如果你希望 Nginx 完全接管静态文件，而 SecretPad 只跑 API：

```nginx
server {
    listen 443 ssl http2;
    server_name secretpad.example.com;

    root /var/www/secretpad;
    index index.html;

    # 静态文件 Nginx 直接处理
    location / {
        try_files $uri $uri/ /index.html;
    }

    # API 全部走后端
    location /api/ {
        proxy_pass http://127.0.0.1:8080/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 500m;
    }

    # SSE 同步接口
    location /sync {
        proxy_pass http://127.0.0.1:8080/sync;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_read_timeout 86400s;
    }
}
```

### 4.3 内网 9001 端口处理

9001 是 SecretPad 内部节点间 RPC 端口，通常**不需要**暴露到公网。如果确实有需求（例如多容器环境下 Nginx 统一代理内部流量），可以这样配置，但建议通过防火墙限制来源：

```nginx
server {
    listen 9001;
    server_name _;

    # 强烈限制来源 IP
    allow 10.0.0.0/8;
    allow 172.16.0.0/12;
    allow 192.168.0.0/16;
    deny all;

    location / {
        proxy_pass http://127.0.0.1:9001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### 4.4 多 SecretPad 实例负载均衡

生产环境可部署多个 SecretPad 实例，Nginx 做 upstream：

```nginx
upstream secretpad_backend {
    least_conn;
    server 10.0.1.11:8080 weight=5;
    server 10.0.1.12:8080 weight=5;
    keepalive 32;
}

server {
    listen 443 ssl http2;
    server_name secretpad.example.com;

    location /api/ {
        proxy_pass http://secretpad_backend/api/;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

> 注意：SecretPad 默认使用本地 SQLite 文件数据库和本地缓存/会话。多实例部署前需要先切换到共享数据库（如 MySQL）和共享会话存储，否则会出现数据不一致。

---

## 5. SecretPad 侧需要做的调整

### 5.1 关闭 HTTPS，只保留 HTTP

当 Nginx 负责 SSL 终止后，SecretPad 可以只监听 8080，关闭 443：

```yaml
# config/application.yaml 或对应 profile
server:
  http-port: 8080
  http-port-inner: 9001
  port: 8080          # 与 http-port 相同，不再启用 HTTPS
  ssl:
    enabled: false
```

或者在 Docker 环境中通过环境变量覆盖：

```bash
-e SERVER_SSL_ENABLED=false \
-e SERVER_PORT=8080 \
```

### 5.2 让 SecretPad 感知真实客户端 IP

Nginx 会添加 `X-Forwarded-*` 头，SecretPad 的 `LoginInterceptor` 与日志可以读取这些头来获取真实 IP。如果后续有自定义代码需要真实 IP，请使用 `X-Forwarded-For` 而不是直接取 `remoteAddr`。

### 5.3 静态文件相关调整

如果 Nginx 完全托管静态文件，可删除 JAR 中的 `secretpad-web/src/main/resources/static/` 内容（或保留作为 fallback）。

前端产物路径：

```
frontend-src/apps/platform/dist/
```

部署时把该目录复制到 Nginx 的 `root`：

```bash
cp -r frontend-src/apps/platform/dist/* /var/www/secretpad/
```

### 5.4 端口映射调整

Docker 部署时，如果 Nginx 与 SecretPad 在同一宿主机：

```bash
# SecretPad 只暴露给本机或容器网络
docker run -d \
  -p 127.0.0.1:8080:8080 \
  -p 127.0.0.1:9001:9001 \
  ...
  secretpad-image

# Nginx 暴露 80/443 到公网
docker run -d \
  -p 80:80 \
  -p 443:443 \
  -v /var/www/secretpad:/var/www/secretpad:ro \
  -v /etc/nginx/ssl:/etc/nginx/ssl:ro \
  -v /etc/nginx/conf.d/secretpad.conf:/etc/nginx/conf.d/default.conf:ro \
  nginx:alpine
```

---

## 6. Docker Compose 示例

```yaml
version: "3.8"

services:
  secretpad:
    image: secretpad:latest
    container_name: secretpad
    restart: always
    environment:
      - SPRING_PROFILES_ACTIVE=center
      - SERVER_SSL_ENABLED=false
      - SERVER_PORT=8080
      - SERVER_HTTP_PORT=8080
      - SERVER_HTTP_PORT_INNER=9001
    volumes:
      - ./data/db:/app/db
      - ./data/config:/app/config
    ports:
      - "127.0.0.1:8080:8080"
      - "127.0.0.1:9001:9001"
    networks:
      - secretpad-net

  nginx:
    image: nginx:alpine
    container_name: secretpad-nginx
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/secretpad.conf:/etc/nginx/conf.d/default.conf:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
      - ./frontend-dist:/var/www/secretpad:ro
    depends_on:
      - secretpad
    networks:
      - secretpad-net

networks:
  secretpad-net:
    driver: bridge
```

---

## 7. 不同部署模式下的 Nginx 注意事项

### 7.1 Center 模式

Center 节点是用户主要访问的入口，最需要 Nginx 做 SSL 与静态资源加速。

- Nginx 443 → SecretPad 8080
- 9001 不需要对外暴露
- 如需高可用，Nginx 后接多个 Center SecretPad 实例，但需共享 MySQL 数据库

### 7.2 Edge 模式

Edge 节点通常部署在参与方侧，访问入口较少，但仍可用 Nginx 统一入口。

- Edge 模式的 `EdgeRequestFilter` 会把部分请求转发到 `secretpad.gateway`（Kuscia Lite Gateway）。
- Nginx 只代理到 SecretPad 8080 即可，不需要额外处理 Kuscia Gateway 的转发逻辑。

### 7.3 P2P / Autonomy 模式

P2P 模式下每个节点既是 Center 又是 Edge，各自对外暴露服务。

- 每个节点前可独立部署 Nginx。
- 注意 `server.http-port-inner=9001` 通常只用于本机/内网，不要通过 Nginx 暴露到公网。

---

## 8. 安全加固建议

### 8.1 限制请求体大小

```nginx
client_max_body_size 500m;   # 根据上传文件大小调整
client_body_timeout 60s;
client_header_timeout 60s;
```

### 8.2 隐藏版本号

```nginx
server_tokens off;
```

### 8.3 启用 HSTS

```nginx
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
```

### 8.4 限制特定路径访问

```nginx
location ~ ^/(actuator|env|metrics) {
    deny all;
}
```

### 8.5 日志格式增强

```nginx
log_format secretpad '$remote_addr - $remote_user [$time_local] '
                     '"$request" $status $body_bytes_sent '
                     '"$http_referer" "$http_user_agent" '
                     '$request_time $upstream_response_time $http_x_trace_id';

access_log /var/log/nginx/secretpad.access.log secretpad;
```

---

## 9. 常见问题排查

### 9.1 前端刷新 404

原因：Nginx 没有把所有非静态路径回退到 `index.html`。

解决：

```nginx
location / {
    try_files $uri $uri/ /index.html;
}
```

### 9.2 SSE `/sync` 连接断开

原因：Nginx 默认缓冲或超时设置导致长连接被关闭。

解决：

```nginx
location /sync {
    proxy_pass http://127.0.0.1:8080/sync;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_buffering off;
    proxy_read_timeout 86400s;
}
```

### 9.3 文件上传 413 Request Entity Too Large

原因：`client_max_body_size` 默认太小。

解决：

```nginx
location /api/v1alpha1/data/upload {
    client_max_body_size 2g;
    proxy_pass http://127.0.0.1:8080;
}
```

### 9.4 HTTPS 后 SecretPad 仍认为请求是 HTTP

原因：SecretPad 读取的是 Nginx 到后端的 HTTP 请求。

解决：确保 Nginx 传递 `X-Forwarded-Proto https`，且 SecretPad 若有相关判断逻辑使用该头。

### 9.5 9001 端口被扫描/攻击

建议：

- 不暴露 9001 到公网。
- 如果必须暴露，用防火墙或 Nginx `allow/deny` 严格限制来源 IP。
- 在云平台安全组中关闭 9001 公网入方向。

---

## 10. 与官方部署的对比

| 能力 | 官方默认（Spring Boot Tomcat） | Nginx 前置方案 |
|---|---|---|
| 用户入口 | 8080 / 443 | 80 / 443（标准端口） |
| SSL 证书 | JKS (`config/server.jks`) | PEM（Nginx 挂载） |
| 静态文件 | JAR 内 static/ | Nginx root 目录 |
| 压缩 | Tomcat connector | Nginx gzip/brotli |
| 负载均衡 | 单实例 | 多实例 upstream |
| 日志 | Tomcat access log | Nginx access log |
| 额外依赖 | 无 | 需维护 Nginx 配置 |

---

## 11. 总结

- SecretPad 官方默认使用 Spring Boot 内嵌 Tomcat 处理所有流量，无需 Nginx 即可运行。
- 在生产环境中，推荐在 SecretPad 前增加 **Nginx 作为统一入口网关**：
  - **对外**：监听 80/443，做 HTTPS 终止与重定向。
  - **对内**：把 `/api/**`、`/sync` 等动态请求反向代理到 SecretPad 8080；静态文件由 Nginx 直接返回。
  - **自己**：管理 SSL 证书、压缩、缓存、日志、安全策略。
  - **后端**：SecretPad 关闭 SSL，只监听 8080/9001，专心处理业务逻辑。
- 引入 Nginx 后，需要同步调整 SecretPad 的 `server.ssl.enabled`、`server.port` 以及前端静态资源的部署方式。
- 9001 内部 RPC 端口建议仅在内网或本机使用，不要通过 Nginx 暴露到公网。

---

## 12. 附录：关键文件索引

| 文件 | 说明 |
|---|---|
| `secretpad-web/src/main/java/org/secretflow/secretpad/web/SecretPadApplication.java` | 多端口 Tomcat 配置 |
| `secretpad-web/src/main/java/org/secretflow/secretpad/web/controller/IndexController.java` | SPA 路由回退 |
| `secretpad-web/src/main/java/org/secretflow/secretpad/web/filter/EdgeRequestFilter.java` | Edge 模式应用层转发 |
| `config/application.yaml` | 默认端口与 SSL 配置 |
| `config/application-edge.yaml` | Edge 模式配置 |
| `config/application-p2p.yaml` | P2P 模式配置 |
| `scripts/build/build.sh` | 前端产物打包入 JAR |
| `scripts/deploy/secretpad.sh` | Docker 部署脚本 |
| `build/Dockerfiles/anolis.Dockerfile` | 生产镜像 |
| `scripts/cert/gen_secretpad_serverkey.sh` | 服务端 JKS 证书生成 |
