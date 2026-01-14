#!/bin/bash
# TAV-X Core: Environment Context & Global Config
[ -n "$_TAVX_ENV_LOADED" ] && return
_TAVX_ENV_LOADED=true

if [ -n "$TERMUX_VERSION" ]; then
    export OS_TYPE="TERMUX"
    export SUDO_CMD=""
    export TMP_DIR="/data/data/com.termux/files/usr/tmp"
    [ ! -d "$TMP_DIR" ] && export TMP_DIR="$PREFIX/tmp"
else
    export OS_TYPE="LINUX"
    if [ "$EUID" -eq 0 ]; then
        export SUDO_CMD=""
    elif command -v sudo &> /dev/null; then
        export SUDO_CMD="sudo"
    else
        export SUDO_CMD=""
    fi
    export TMP_DIR="${TMPDIR:-/tmp}"
fi

mkdir -p "$TMP_DIR"

# 标准化运行目录：优先使用传入变量，其次尝试检测当前脚本位置，最后默认为 ~/.tav_x
if [ -z "$TAVX_DIR" ]; then
    CURRENT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # 假设 env.sh 位于 core/ 目录，上一级即为项目根目录
    POSSIBLE_ROOT="$(dirname "$CURRENT_SCRIPT_DIR")"
    if [ -f "$POSSIBLE_ROOT/core/main.sh" ]; then
        export TAVX_DIR="$POSSIBLE_ROOT"
    else
        export TAVX_DIR="$HOME/.tav_x"
    fi
fi

export TAVX_ROOT="$TAVX_DIR"
export CONFIG_DIR="$TAVX_DIR/config"
export LOGS_DIR="$TAVX_DIR/logs"
export RUN_DIR="$TAVX_DIR/run"
export APPS_DIR="$HOME/tav_apps"
export TAVX_BIN="$TAVX_DIR/bin"

mkdir -p "$CONFIG_DIR" "$LOGS_DIR" "$RUN_DIR" "$APPS_DIR" "$TAVX_BIN"

[[ ":$PATH:" != *":$TAVX_BIN:"* ]] && export PATH="$TAVX_BIN:$PATH"

export CURRENT_VERSION="3.0.8"
export NETWORK_CONFIG="$CONFIG_DIR/network.conf"

export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[1;34m'
export CYAN='\033[1;36m'
export NC='\033[0m'

export GLOBAL_PROXY_PORTS=(
    "7890:http" "7891:http" "1080:http" "1081:http" 
    "10809:http" "10808:http" "17890:http" "17891:socks5" 
    "20171:http" "20170:http" "9090:http" "8080:http" "2080:http"
)

export GLOBAL_MIRRORS=(
    "https://ghproxy.net/" "https://mirror.ghproxy.com/" "https://ghproxy.cc/" 
    "https://gh.likk.cc/" "https://hub.gitmirror.com/" "https://hk.gh-proxy.com/" 
    "https://ui.ghproxy.cc/" "https://gh-proxy.com/" 
    "https://gh.jasonzeng.dev/" "https://gh.idayer.com/" "https://edgeone.gh-proxy.com/" 
    "https://ghproxy.site/" "https://www.gitwarp.com/" "https://cors.isteed.cc/" "https://ghproxy.vip/"    
)

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[DONE]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

export -f info
export -f success
export -f warn
export -f error
