# 使用本地可获取的 Anolis OS 作为基础镜像（已内置 Python 3.10）
FROM secretflow-registry.cn-hangzhou.cr.aliyuncs.com/secretflow/anolisos:23

# 镜像元信息
LABEL maintainer="sfwork-demo"
LABEL description="Docker packaging demo for sfwork"

# 构建参数，可在构建时注入版本号
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}

# 配置 pip 使用阿里云镜像，加速依赖安装
RUN python3 -m ensurepip --upgrade && \
    python3 -m pip config set global.index-url https://mirrors.aliyun.com/pypi/simple/ && \
    python3 -m pip install --no-cache-dir --upgrade pip

WORKDIR /app

# 先复制 requirements.txt 并安装依赖。
# 这样可以在源码未变更时复用 Docker 构建缓存，加快后续构建速度。
COPY src/requirements.txt /app/
RUN python3 -m pip install --no-cache-dir -r requirements.txt

# 将 main.py 作为可执行文件复制到系统 PATH 中，并赋予可执行权限。
# 容器启动时直接运行 demo-server，不需要再写 python3 main.py。
COPY src/main.py /usr/local/bin/demo-server
RUN chmod +x /usr/local/bin/demo-server

# 暴露端口
EXPOSE 8080

# 健康检查：使用 Python 标准库发起 HTTP 请求
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health')" || exit 1

# 启动命令：直接运行可执行脚本
CMD ["demo-server"]
