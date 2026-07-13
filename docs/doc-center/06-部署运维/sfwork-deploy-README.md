# sfwork 部署模板

本目录提供 sfwork 二次开发工作区的部署模板，用于本地验证和测试环境快速启动。

## 目录结构

```text
deploy/
├── .env.example          # 环境变量示例（敏感信息模板）
├── docker-compose.yml    # Docker Compose 本地/测试部署模板
└── README.md             # 本文件
```

## 快速开始

```bash
cd deploy
cp .env.example .env
# 编辑 .env，修改默认密码和镜像版本
docker compose up -d
```

启动后访问：

- SecretPad Web UI：`http://localhost:8080`
- SecretPad HTTPS：`https://localhost:8443`
- Kuscia API HTTP：`http://localhost:8082`
- Kuscia API gRPC：`localhost:8083`

## 安全提示

- `.env` 文件已加入 `.gitignore`，请勿将真实密码提交到版本控制。
- 生产环境请使用 Kubernetes + Helm，并接入外部密钥管理（Vault、AWS Secrets Manager 等）。
- 默认镜像 tag 为 `latest`，生产环境请固定到具体版本号。

## 与开发脚本的关系

- `scripts/dev-start.sh`：基于本地源码一键启动完整 Docker 开发环境（推荐日常开发使用）。
- `scripts/run-all-no-docker.sh`：无 Docker 源码级启动（需要 sudo 和本地 JDK/Maven/Node/conda）。
- `deploy/docker-compose.yml`：使用官方镜像快速部署，适合验证和测试。

## 后续规划

- [ ] 提供 Helm Chart 用于 Kubernetes 生产部署
- [ ] 提供 ArgoCD / Flux GitOps 示例
- [ ] 接入外部密钥管理，移除默认密码
