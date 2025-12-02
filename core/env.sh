#!/bin/bash
# TAV-X Core: Environment Context & Global Config

export TAVX_DIR="${TAVX_DIR:-$HOME/.tav_x}"
export TAVX_ROOT="$TAVX_DIR"

export INSTALL_DIR="$HOME/SillyTavern"
export CONFIG_FILE="$INSTALL_DIR/config.yaml"
export CONFIG_DIR="$TAVX_DIR/config"
mkdir -p "$CONFIG_DIR"

export NETWORK_CONFIG="$CONFIG_DIR/network.conf"

export CURRENT_VERSION="v2.2.0"
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[1;34m'
export CYAN='\033[1;36m'
export NC='\033[0m'

export GLOBAL_MIRRORS=(
    "https://ghproxy.net/"
    "https://mirror.ghproxy.com/"
    "https://ghproxy.cc/"
    "https://gh.likk.cc/"
    "https://github.akams.cn/"
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