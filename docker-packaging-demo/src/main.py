#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
一个简单的 Flask 演示服务，作为可执行脚本被打包进 Docker 镜像。

通过 shebang 和可执行权限，容器可以直接运行 demo-server，
而不需要显式调用 python3 main.py。
"""

import json
import os
import socket

from flask import Flask, jsonify

app = Flask(__name__)


@app.route("/")
def hello():
    return jsonify(
        {
            "message": "Hello from docker-packaging-demo!",
            "version": os.getenv("APP_VERSION", "dev"),
            "hostname": socket.gethostname(),
        }
    )


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


def main():
    port = int(os.getenv("PORT", "8080"))
    app.run(host="0.0.0.0", port=port)


if __name__ == "__main__":
    main()
