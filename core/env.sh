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
export TAVX_DIR="${TAVX_DIR:-$HOME/.tav_x}"
export TAVX_LOG_FILE="$TAVX_DIR/tavx_runtime.log"
export TAVX_ROOT="$TAVX_DIR"
export INSTALL_DIR="$HOME/SillyTavern"
export CONFIG_FILE="$INSTALL_DIR/config.yaml"
export CONFIG_DIR="$TAVX_DIR/config"
mkdir -p "$CONFIG_DIR"

export TAVX_TRACKED_LOGS=(
    "$TAVX_LOG_FILE"
    "${TAVX_LOG_FILE}.old"
    "$TAVX_DIR/.update_available"
    "$TAVX_DIR/.temp_link"
    "$INSTALL_DIR/server.log"
    "$INSTALL_DIR/cf_tunnel.log"
    "$TAVX_DIR/clewdr/clewdr.log"
    "$TAVX_DIR/gemini_proxy/service.log"
    "$TAVX_DIR/gemini_proxy/tunnel.log"
    "$TAVX_DIR/adb_log.txt"
    "$TAVX_DIR/autoglm_install.log"
    "$TMP_DIR/tavx_git_error.log"
    "$TMP_DIR/tavx_curl_error.log"
)

MAX_LOG_SIZE=$((5 * 1024 * 1024))
if [ -f "$TAVX_LOG_FILE" ]; then
    FILE_SIZE=$(stat -c%s "$TAVX_LOG_FILE" 2>/dev/null || echo 0)
    if [ "$FILE_SIZE" -gt "$MAX_LOG_SIZE" ]; then
        mv "$TAVX_LOG_FILE" "${TAVX_LOG_FILE}.old"
    fi
fi

if [ ! -f "$TAVX_LOG_FILE" ]; then
    touch "$TAVX_LOG_FILE"
fi
echo "--- Session Started: $(date '+%Y-%m-%d %H:%M:%S') ---" >> "$TAVX_LOG_FILE"
export NETWORK_CONFIG="$CONFIG_DIR/network.conf"
export ST_PID_FILE="$TAVX_DIR/.st.pid"
export CF_PID_FILE="$TAVX_DIR/.cf.pid"
export CLEWD_PID_FILE="$TAVX_DIR/.clewd.pid"
export GEMINI_PID_FILE="$TAVX_DIR/.gemini.pid"
export AUDIO_PID_FILE="$TAVX_DIR/.audio_heartbeat.pid"

export CURRENT_VERSION="v2.6.5"
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[1;34m'
export CYAN='\033[1;36m'
export NC='\033[0m'

# 1. 常用代理端口池
export GLOBAL_PROXY_PORTS=(
    "17890:http"
    "17891:http"
    "7890:http"
    "7891:http"
    "10809:http"
    "10808:http"
    "20171:http"
    "20170:http"
    "9090:http"
    "8080:http"
    "1080:http"
    "2080:http"
)

# 2. GitHub 镜像源池
export GLOBAL_MIRRORS=(
    "https://ghproxy.net/"
    "https://mirror.ghproxy.com/"
    "https://ghproxy.cc/"
    "https://gh.likk.cc/"
    "https://hub.gitmirror.com/"
    "https://hk.gh-proxy.com/"
    "https://ui.ghproxy.cc/"
    "https://gh.ddlc.top/"
    "https://gh-proxy.com/"
    "https://gh.jasonzeng.dev/"
    "https://gh.idayer.com/"
    "https://edgeone.gh-proxy.com/"
    "https://ghproxy.site/"
    "https://www.gitwarp.com/"
    "https://cors.isteed.cc/"
    "https://ghproxy.vip/"    
)

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[DONE]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }