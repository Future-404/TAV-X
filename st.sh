#!/bin/bash
# TAV-X Universal Bootstrapper (V4.0 Absolute Anchor)
STANDARD_DIR="$HOME/.tav_x"
CORE_FILE="$STANDARD_DIR/core/main.sh"

if [ -f "$CORE_FILE" ]; then
    export TAVX_DIR="$STANDARD_DIR"
    
    chmod +x "$CORE_FILE"
    exec bash "$CORE_FILE"
    
else
    echo -e "\033[1;33m" # Yellow
    echo ">>> 未检测到安装文件 (Core Missing)..."
    echo ">>> 正在连接云端获取最新版本..."
    echo -e "\033[0m"
    
    if command -v curl &> /dev/null; then
        bash <(curl -s https://tav-x.future404.qzz.io)
    else
        echo -e "\033[0;31m❌ 错误: 未找到 curl 工具。\033[0m"
        exit 1
    fi
    
    if [ -f "$CORE_FILE" ]; then
        echo ""
        echo -e "\033[1;32m>>> 就绪！正在启动 TAV-X...\033[0m"
        sleep 1
        
        export TAVX_DIR="$STANDARD_DIR"
        chmod +x "$CORE_FILE"
        exec bash "$CORE_FILE"
    else
        echo -e "\033[0;31m❌ 启动失败：安装未完成，请检查网络。\033[0m"
        exit 1
    fi
fi