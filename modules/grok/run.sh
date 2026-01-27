#!/bin/bash
# [TAV-X Grok Runtime Wrapper]
# 作用：设置环境变量，计算路径映射，调用 boot.py

# 1. 进入模块目录
cd "$(dirname "$0")"

# 2. 补全环境变量 (sv 环境通常为空)
if [ -z "$HOME" ]; then
    export HOME="/data/data/com.termux/files/home"
fi

# 3. 加载 .env 配置 (端口、TOKEN等)
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# 4. 计算路径映射 (关键)
# 将当前物理路径 (e.g. .../home/tav_apps/grok) 转换为容器内路径 (e.g. /root/tav_apps/grok)
# 前提：Proot 启动时使用了 --bind $HOME:/root
export INNER_DIR="${PWD/$HOME/\/root}"

# 5. 启动 Python PTY 引导器
exec python3 boot.py
