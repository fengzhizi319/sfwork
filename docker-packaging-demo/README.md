# Docker 镜像打包 Demo

这个 Demo 用于学习如何在 `sfwork` 工作区里打包一个 Docker 镜像。它包含：

- 一个简单的 Python Flask 应用
- 一个 `requirements.txt` 依赖文件
- 一个将 Python 脚本作为**可执行文件**打包进镜像的 `Dockerfile`
- 一个支持 `docker buildx` 的构建脚本
- 一个 `Makefile` 快捷命令

## 目录结构

```text
docker-packaging-demo/
├── Dockerfile              # 镜像构建文件
├── Makefile                # 快捷命令
├── README.md               # 本文件
├── .dockerignore           # 排除不需要进入 build context 的文件
├── scripts/
│   └── build.sh            # 构建脚本（支持 buildx / 多平台 / 推送 / 导出 tar）
└── src/
    ├── main.py             # Python 演示服务（带 shebang 的可执行脚本）
    └── requirements.txt    # Python 依赖
```

## 关键改动说明

### 从“源码打包”改为“可执行文件打包”

原来的 `Dockerfile` 直接复制源码到 `/app/main.py`，并通过 `CMD ["python3", "main.py"]` 运行。

现在的 `Dockerfile`：

1. 通过 `requirements.txt` 安装依赖。
2. 将 `src/main.py` 复制到 `/usr/local/bin/demo-server`。
3. 通过 `RUN chmod +x /usr/local/bin/demo-server` 赋予可执行权限。
4. 通过 `CMD ["demo-server"]` 直接运行可执行脚本。

`src/main.py` 顶部包含 shebang：

```python
#!/usr/bin/env python3
```

这样它就是一个标准的 Linux 可执行脚本，可以直接像二进制命令一样运行。

## 快速开始

### 1. 直接构建镜像

```bash
cd /home/charles/code/sfwork/docker-packaging-demo
bash scripts/build.sh
```

默认会构建 `docker-packaging-demo:dev-<datetime>` 镜像，并加载到本地 Docker。

### 2. 使用 Makefile

```bash
# 构建当前平台镜像
make build

# 构建 arm64 镜像
make build-arm64

# 构建并导出 tar
make tar

# 运行容器
make run

# 测试接口
make test

# 停止并清理
make clean
```

### 3. 手动运行容器

```bash
docker run -d -p 8080:8080 --name demo docker-packaging-demo:dev-20260101120000
curl http://localhost:8080
curl http://localhost:8080/health
```

## 构建脚本参数

```bash
bash scripts/build.sh -n demo-name -v 1.0.0 -r registry.example.com/demo --push --tar
```

| 参数 | 说明 |
|---|---|
| `-n, --name` | 镜像名 |
| `-v, --version` | 镜像 Tag |
| `-r, --registry` | 镜像仓库前缀 |
| `-p, --platform` | 目标平台，如 `linux/amd64`、`linux/arm64` |
| `--push` | 构建完成后推送到仓库 |
| `--tar` | 构建完成后导出为 `.tar` 文件 |

## Dockerfile 要点

1. **基础镜像**：使用 `secretflow-registry.cn-hangzhou.cr.aliyuncs.com/secretflow/anolisos:23`，该镜像已内置 Python 3.10，且在工作区网络环境下可正常拉取。
2. **requirements.txt**：通过 `pip install -r requirements.txt` 安装 Flask 等依赖。
3. **可执行脚本**：`main.py` 被复制到 `/usr/local/bin/demo-server` 并赋予可执行权限，容器内可直接运行。
4. **构建参数 `APP_VERSION`**：可在构建时注入版本号，体现在环境变量中。
5. **`.dockerignore`**：避免把 `scripts/`、`README.md` 等无关文件打进镜像。
6. **`HEALTHCHECK`**：容器启动后自动做健康检查。

## 学习建议

1. 先读 `Dockerfile`，理解 `requirements.txt` 先复制以利用缓存、可执行文件复制和 `CMD` 的改动。
2. 运行 `bash scripts/build.sh` 观察 `docker buildx` 的输出。
3. 修改 `src/main.py` 里的返回内容，重新构建并运行，体验“改代码→构建→运行”的完整流程。
4. 进入容器查看可执行文件：`docker exec -it demo ls -l /usr/local/bin/demo-server`。
5. 尝试修改 `--platform` 参数，理解多平台构建。
