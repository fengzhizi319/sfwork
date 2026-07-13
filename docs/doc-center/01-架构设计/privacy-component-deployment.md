# SecretFlow `privacy/l_diversity` 组件 — 部署文档

> **目标**：说明如何在本地开发环境、Docker 环境以及生产环境中部署包含 `l_diversity` 组件的 SecretFlow、Kuscia 与 SecretPad。  
> **版本**：1.0  
> **日期**：2026-07-08

---

## 1. 部署形态总览

| 形态 | SecretFlow | Kuscia | SecretPad | 适用场景 |
|---|---|---|---|---|
| **本地非 Docker** | `pip install -e .` 本地包 | `kuscia/scripts/run_local_kuscia.sh` | `mvn` + `pnpm dev` | 开发调试 |
| **本地 Docker** | 自定义镜像 | `make image` 构建镜像 | `make image` 或已有镜像 | 集成测试 |
| **生产 K8s/Docker** | 推送到镜像仓库的 release 镜像 | 推送到镜像仓库的 Kuscia 镜像 | 推送到镜像仓库的 SecretPad 镜像 | 生产部署 |

---

## 2. 前置条件

- Conda 环境 `sf310` 已创建并安装 SecretFlow 开发依赖。
- Docker 可用，且能访问基础镜像仓库（`secretflow-registry.cn-hangzhou.cr.aliyuncs.com`）。
- 工作区已克隆到 `/home/charles/code/sfwork`。

---

## 3. 本地非 Docker 部署（开发调试）

### 3.1 安装 SecretFlow 本地包

```bash
cd /home/charles/code/sfwork/secretflow
source /home/charles/miniconda3/etc/profile.d/conda.sh
conda activate sf310
pip install -e .
```

### 3.2 验证组件注册

```bash
python -c "from secretflow.component.core import Registry; \
           print(Registry.get_definition_by_id('privacy/l_diversity:1.0.0'))"
```

### 3.3 刷新 SecretPad 组件元数据

```bash
cd /home/charles/code/sfwork/secretflow
secretflow component inspect -a | sed '/^\[202[0-9]/d' \
  > /home/charles/code/sfwork/secretpad/config/components/secretflow.json

secretflow component get_translation | sed '/^\[202[0-9]/d' \
  > /home/charles/code/sfwork/secretpad/config/i18n/secretflow.json
```

### 3.4 构建并启动 SecretPad 后端

```bash
cd /home/charles/code/sfwork/secretpad
mvn clean install -Dmaven.test.skip=true

# 生成开发证书（如未生成）
bash scripts/test/setup.sh

# 启动后端
export KUSCIA_API_ADDRESS=127.0.0.1
export KUSCIA_GW_ADDRESS=127.0.0.1:80
export KUSCIA_PROTOCOL=notls
java -Dspring.profiles.active=dev \
     -Dsun.net.http.allowRestrictedHeaders=true \
     -Dserver.port=8443 \
     -jar target/secretpad.jar
```

### 3.5 启动 SecretPad 前端

```bash
cd /home/charles/code/sfwork/secretpad/frontend-src
pnpm --filter secretpad dev
```

前端默认地址：`http://localhost:8000`。

### 3.6 启动 Kuscia Master（本地模式）

```bash
cd /home/charles/code/sfwork/kuscia
export KUSCIA_HOME="/home/charles/code/sfwork/.local-kuscia"
sudo bash scripts/run_local_kuscia.sh master
```

### 3.7 使用一键脚本

```bash
cd /home/charles/code/sfwork
bash scripts/run-all-no-docker.sh
```

停止：

```bash
bash scripts/run-all-no-docker.sh --stop
```

---

## 4. Docker 镜像构建与部署

### 4.1 SecretFlow 镜像

#### 方式 A：快速验证镜像（本地/CI）

基于官方 `secretflow/ubuntu-base-ci` 基础镜像，安装本地构建的 wheel 与运行时依赖：

```bash
# ============================================================
# 阶段 0：环境准备
# ============================================================

# 进入 SecretFlow 源码仓库目录
# secretflow：蚂蚁开源的隐私计算框架，支持 MPC、联邦学习、TEE 等
cd /home/charles/code/sfwork/secretflow

# 加载 Conda 初始化脚本，使当前 shell 支持 conda 命令
# 不直接执行 conda init bash 是为了避免修改 shell 配置文件
source /home/charles/miniconda3/etc/profile.d/conda.sh

# 激活名为 sf310 的 Conda 环境
# sf310 表示 SecretFlow + Python 3.10 的专用开发环境
# 该环境包含构建 wheel 所需的依赖（build、setuptools、wheel 等）
conda activate sf310

# ============================================================
# 阶段 1：构建 Python Wheel 包
# ============================================================

# 清理历史构建产物，确保无缓存干扰
# dist/：wheel 输出目录
# build/：setuptools 构建临时目录
rm -rf dist build

# 使用 PEP 517 标准构建 wheel 包（.whl）
# python -m build 是现代 Python 推荐的标准构建工具
# --wheel 参数：仅构建 wheel（跳过 sdist 源码包）
# 输出：dist/secretflow-{version}-{pyver}-{abi}-{platform}.whl
# 示例：secretflow-1.15.0.dev-cp310-cp310-linux_x86_64.whl
python -m build --wheel

# ============================================================
# 阶段 2：准备 Docker 构建上下文
# ============================================================

# 创建 Dockerfile 所在目录
# privacy-dev：隐私计算开发版镜像的专用构建目录
# 与生产版镜像分离，避免开发依赖污染生产环境
mkdir -p docker/privacy-dev

# Dockerfile 来源说明：
# 本次实现已提供 secretflow/docker/privacy-dev/Dockerfile
# 注意：不要与 secretflow/docker/dev/Dockerfile 混淆
# 如果你之前运行过 docker/dev/build.sh，该目录可能被混入 build.sh / entry.sh /
# .gitignore / README.md 等文件，这些与本 Dockerfile 构建无关，可忽略或删除。
# 如 Dockerfile 被覆盖，请从代码仓库重新获取：secretflow/docker/privacy-dev/Dockerfile

# 复制构建好的 wheel 包到 Docker 构建上下文
# 通配符 secretflow-*.whl 匹配版本号，避免硬编码
# 该 wheel 将被 Dockerfile 中的 COPY 指令安装到镜像内
cp dist/secretflow-*.whl docker/privacy-dev/

# ============================================================
# 阶段 3：构建 Docker 镜像
# ============================================================

# 进入 Docker 构建目录（构建上下文）
cd docker/privacy-dev

# 构建 Docker 镜像
# . ：构建上下文为当前目录（含 wheel 文件、Dockerfile 等）
# -f Dockerfile ：显式指定 Dockerfile（虽然默认就是此名）
# -t secretflow/sf-privacy-dev:1.15.0.dev-privacy ：镜像标签
#   - 仓库名：secretflow/sf-privacy-dev
#   - 版本：1.15.0.dev-privacy（1.15.0 开发版，隐私计算组件）
docker build . -f Dockerfile -t secretflow/sf-privacy-dev:1.15.0.dev-privacy

# 说明：
# Dockerfile 默认使用阿里云 PyPI 镜像源（ARG PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/）。
# 若出现下载中断、Read timed out 或 pip 哈希校验失败，可切换到官方 PyPI：
# docker build . -f Dockerfile \
#   --build-arg PIP_INDEX_URL=https://pypi.org/simple/ \
#   -t secretflow/sf-privacy-dev:1.15.0.dev-privacy
```

```tex
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   源码目录      │     │   构建产物       │     │   Docker 镜像   │
│  /secretflow    │────▶│  dist/*.whl     │────▶│ sf-privacy-dev  │
│                 │     │                 │     │  :1.15.0.dev... │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │                       │
        ▼                       ▼                       ▼
   Conda 环境 sf310        复制到 docker/              包含：
   Python 3.10 +           privacy-dev/                • SecretFlow 1.15.0
   构建依赖                  作为构建上下文               • 隐私计算组件
                                                         • 运行时依赖
```



产物镜像：

```text
secretflow/sf-privacy-dev:1.15.0.dev-privacy
```

验证：

```bash
docker run --rm secretflow/sf-privacy-dev:1.15.0.dev-privacy \
  'python -c "from secretflow.component.core import Registry; \
              print(Registry.get_definition_by_id(\"privacy/l_diversity:1.0.0\").component_def.name)"'
```

> **注意**：`ubuntu-base-ci` 镜像的 `ENTRYPOINT` 是 `/bin/bash -lc`。`docker run` 传入多个参数时，bash 只会把第一个参数当命令字符串，其余参数变成 `$0`、`$1`… 因此必须把整个命令用**单引号**包成一组传入，否则 `python -c "..."` 会被拆开执行，导致没有输出。
>
> 错误示例：`docker run image python -c "print(1)"`  
> 正确示例：`docker run image 'python -c "print(1)"'`

#### 方式 B：官方完整镜像（推荐生产）

```bash
cd /home/charles/code/sfwork/secretflow/docker/dev
bash build.sh -v 1.15.0.dev-privacy -t
```

产物镜像：`secretflow/sf-dev-ubuntu:1.15.0.dev-privacy`，并生成 tar 文件。

### 方式 A 与方式 B 的区别

| 对比项 | 方式 A（快速验证镜像） | 方式 B（官方完整镜像） |
|---|---|---|
| **基础镜像** | `secretflow/ubuntu-base-ci` | `secretflow/release-ci` 构建环境 + 官方运行时基础镜像 |
| **构建入口** | 本地 `python -m build --wheel` + 自定义 Dockerfile | `docker/dev/build.sh`（官方脚本） |
| **编译方式** | 直接 pip 安装 wheel 及其依赖 | 在 `release-ci` 容器内完整编译/打包，可能包含 C++ 扩展的源码编译 |
| **是否包含 nsjail** | 否 | 是（clone 并编译 nsjail，用于沙箱执行） |
| **多平台支持** | 仅当前平台（linux/amd64） | 可配置 `linux/amd64` 和 `linux/arm64` |
| **产物标签** | `secretflow/sf-privacy-dev:1.15.0.dev-privacy` | `secretflow/sf-dev-ubuntu:1.15.0.dev-privacy` |
| **适用场景** | 本地开发、CI 快速验证、功能验证 | 生产环境、正式发布 |
| **构建复杂度** | 简单，约 10 分钟 | 较复杂，依赖 release-ci 镜像，时间更长 |

简单来说：**方式 A 是为了快速验证新组件能否被打成镜像并在 Kuscia 中调度；方式 B 是官方推荐的生产镜像构建流程，更全面、更规范。**

### 4.2 Kuscia 镜像（节点镜像，不含 SecretFlow）

```bash
cd /home/charles/code/sfwork/kuscia
make image
```

产物镜像示例：

```text
secretflow/kuscia:v1.2.0b0-26-g73f3680-20260708150644
```

**注意**：Kuscia 镜像只包含 Kuscia 节点运行时，**不包含 SecretFlow**。SecretFlow 需要作为 AppImage 单独注册到 Kuscia 中。

验证：

```bash
docker run --rm --entrypoint /home/kuscia/bin/kuscia \
  secretflow/kuscia:v1.2.0b0-23-g431fb15-20260708085844 --version
```

注释：

```bash
docker run --rm \
```

- 创建并运行一个容器
- `--rm`：命令执行完毕后**自动删除容器**，不残留垃圾容器

```bash
--entrypoint /home/kuscia/bin/kuscia \
```

- **覆盖镜像默认的入口点**（Entrypoint），**ENTRYPOINT** 配置的是容器启动时**第一个执行的程序/命令**。
- 默认情况下，Kuscia 镜像可能启动的是守护进程或服务脚本
- 这里强制指定直接执行 `/home/kuscia/bin/kuscia` 二进制文件本身

```bash
secretflow/kuscia:v1.2.0b0-26-g73f3680-20260708150644
```

- 镜像名称：`secretflow/kuscia`
- 标签（版本）解析：
  - `v1.2.0b0` — 1.2.0 beta 0 版本
  - `-26` — beta 0 之后第 26 次提交
  - `-g73f3680` — Git 提交哈希前 7 位（`g` 表示 git）
  - `-20260708150644` — **构建时间**：2026年7月8日 15:06:44

```bash
--version
```

- 传递给 Kuscia 二进制文件的**命令行参数**

- 要求打印版本信息后立即退出

  运行时实际执行：/home/kuscia/bin/kuscia --version



### 4.3 加载本地 tar 包（离线场景）

如果已通过 `docker save` 导出 tar，可在目标环境加载：

```bash
# SecretFlow
docker load -i /home/charles/code/sfwork/secretflow/docker/privacy-dev/sf-privacy-dev-1.15.0.dev-privacy.tar

# Kuscia
docker load -i /home/charles/code/sfwork/kuscia/kuscia-v1.2.0b0-26-g73f3680-20260708150644.tar
```

### 4.4 SecretPad 镜像

SecretPad 本次无 Java 代码变更，只需确保镜像构建时包含新生成的 `secretflow.json` 与 `secretflow_i18n.json`。

```bash
cd /home/charles/code/sfwork/secretpad
make image
```

---

## 5. Kuscia 中注册 SecretFlow AppImage（runC 模式关键）

**核心概念**：Kuscia 节点镜像与 SecretFlow 应用镜像是分离的。在 runC/container 模式下，Kuscia 会把 `AppImage` 中指定的 SecretFlow 镜像作为任务容器拉起，并注入 `task-config.conf`。因此必须在 Kuscia 中注册 AppImage，否则后端提交的任务会找不到可用的 SecretFlow 镜像。

### 5.1 推送镜像到仓库（如需多节点）

```bash
# 以 Docker Hub 为例
docker tag secretflow/sf-privacy-dev:1.15.0.dev-privacy your-registry/secretflow:1.15.0.dev-privacy
docker push your-registry/secretflow:1.15.0.dev-privacy
```

### 5.2 更新 AppImage

项目已提供可直接使用的 AppImage 模板：

```text
secretflow/docker/privacy-dev/app_image.yaml
```

其中 `image.name` / `image.tag` 已指向：

```text
secretflow/sf-privacy-dev:1.15.0.dev-privacy
```

应用：

```bash
# 在 Kuscia Master 节点或本地 Kuscia 环境中执行
kubectl apply -f /home/charles/code/sfwork/secretflow/docker/privacy-dev/app_image.yaml

# 确认 AppImage 已创建
kubectl get appimage secretflow-privacy-dev
```

应用后，Kuscia 在调度 `privacy/l_diversity` 任务时就会使用 `secretflow/sf-privacy-dev:1.15.0.dev-privacy` 作为任务容器镜像。

---

## 6. 生产部署 checklist

| 步骤 | 操作 | 验证方式 |
|---|---|---|
| 1 | 构建并推送 SecretFlow 镜像 | `docker images` / 仓库 UI |
| 2 | 构建并推送 Kuscia 镜像 | `make image` + `docker push` |
| 3 | 构建并推送 SecretPad 镜像 | `make image` + `docker push` |
| 4 | 在 Kuscia 中更新 AppImage | `kubectl get appimage` |
| 5 | 部署 Kuscia Master/Lite | 检查 Pod 运行状态 |
| 6 | 部署 SecretPad 后端 | `/actuator/health` |
| 7 | 部署 SecretPad 前端 | 页面可访问 |
| 8 | 验证组件列表 | `/api/v1alpha1/component/list` 包含 `l_diversity` |
| 9 | 运行示例图 | 任务成功，报告正确 |

---

## 7. 常见问题

| 问题 | 原因 | 解决方案 |
|---|---|---|
| SecretPad 看不到 `l_diversity` | 未重新生成或替换 `secretpad/config/components/secretflow.json` 与 `secretpad/config/i18n/secretflow.json`，或未重启后端 | 执行第 3.3 步并重启 |
| Kuscia 任务报找不到 `privacy/l_diversity` | SecretFlow 镜像未包含新组件 | 确认镜像 tag 与 AppImage 一致，容器内执行注册检查 |
| Docker build 中 pip 超时/哈希校验失败 | 网络不稳定导致 PyPI 下载中断 | 切换到官方 PyPI：`docker build ... --build-arg PIP_INDEX_URL=https://pypi.org/simple/ -t ...` |
| 前端组件树/模板不显示 | 未修改 `component-tree-service.ts`、`component-icon.tsx`，或未新增 `quick-config-privacy.tsx`、`pipeline-template-privacy.ts` 等模板 | 检查第 3.5 步对应修改 |

---

## 8. 参考

- `docs/privacy-component-hld.md`
- `docs/privacy-component-lld.md`
- `docs/privacy-component-implementation.md`
- `docs/privacy-component-testing.md`
- `scripts/run-all-no-docker.sh`
