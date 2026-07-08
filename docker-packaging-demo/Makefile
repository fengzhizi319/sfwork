# Makefile 是构建/运行/测试的快捷入口。
# 它本身不直接调用 docker buildx，而是调用 scripts/build.sh 完成实际构建。
#
# 用法示例：
#   make build                        # 构建默认 linux/amd64 镜像
#   make build-arm64                  # 构建 linux/arm64 镜像
#   make run                          # 运行容器
#   make test                         # 测试 HTTP 接口
#   make clean                        # 停止并清理镜像
#
# 覆盖变量示例：
#   make build IMAGE_NAME=myapp VERSION=1.0.0
#   make run HOST_PORT=9000

# .PHONY 声明：这些目标不对应真实文件，避免与同名文件冲突。
.PHONY: build build-arm64 push tar run test stop clean

# 镜像名，可通过命令行覆盖，例如：make build IMAGE_NAME=myapp
IMAGE_NAME ?= docker-packaging-demo

# 镜像 Tag，默认带时间戳，避免重复构建时 tag 冲突。
# 可通过命令行覆盖，例如：make build VERSION=1.0.0
VERSION ?= dev-$(shell date +%Y%m%d%H%M%S)

# 宿主机映射端口，访问 http://localhost:$(HOST_PORT) 即可访问容器服务。
HOST_PORT ?= 8080

# 容器内部监听端口，与 Dockerfile 中的 EXPOSE 以及 src/main.py 中的默认端口保持一致。
CONTAINER_PORT ?= 8080

# 镜像仓库前缀（可选）。推送镜像时必须设置，例如：make push REGISTRY=registry.example.com/demo
REGISTRY ?=

# build: 构建当前宿主机架构（默认 linux/amd64）的镜像，并加载到本地 Docker。
build:
	bash scripts/build.sh -n $(IMAGE_NAME) -v $(VERSION)

# build-arm64: 构建 linux/arm64 架构的镜像，用于体验多平台构建。
# 注意：多平台构建默认使用 --load 加载到本地，但 Docker Desktop 对非宿主架构加载可能有限制。
build-arm64:
	bash scripts/build.sh -n $(IMAGE_NAME) -v $(VERSION) -p linux/arm64

# push: 构建并推送镜像到远程仓库。
# 必须设置 REGISTRY，例如：make push REGISTRY=registry.example.com/demo
push:
	bash scripts/build.sh -n $(IMAGE_NAME) -v $(VERSION) -r $(REGISTRY) --push

# tar: 构建镜像并导出为 tar 包，便于离线传输或备份。
# 导出的文件名形如：docker-packaging-demo-dev-20260101120000.tar
tar:
	bash scripts/build.sh -n $(IMAGE_NAME) -v $(VERSION) --tar

# run: 以后台方式运行容器，并把容器的 CONTAINER_PORT 映射到宿主机的 HOST_PORT。
# 容器名使用 IMAGE_NAME，方便后续 stop/clean 统一管理。
run:
	docker run -d \
	  -p $(HOST_PORT):$(CONTAINER_PORT) \
	  -e PORT=$(CONTAINER_PORT) \
	  --name $(IMAGE_NAME) \
	  $(IMAGE_NAME):$(VERSION)

# test: 访问本地接口并格式化输出 JSON，验证容器是否正常运行。
# 依赖 make run 已经启动容器，并且 HOST_PORT 与 run 时保持一致。
test:
	curl -s http://localhost:$(HOST_PORT) | python -m json.tool
	curl -s http://localhost:$(HOST_PORT)/health | python -m json.tool

# stop: 强制停止并删除名为 IMAGE_NAME 的容器。
# `|| true` 表示即使容器不存在也不报错，保证命令幂等。
stop:
	docker rm -f $(IMAGE_NAME) || true

# clean: 先 stop 容器，再删除本次构建的镜像，最后清理当前目录下的 tar 包。
# 用于恢复干净环境。
clean: stop
	docker rmi $(IMAGE_NAME):$(VERSION) 2>/dev/null || true
	rm -f *.tar
