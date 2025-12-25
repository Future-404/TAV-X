#!/bin/bash
# TAV-X Core: Dependency Manager

source "$TAVX_DIR/core/ui.sh"
[ -z "$OS_TYPE" ] && source "$TAVX_DIR/core/env.sh"

install_gum_linux() {
    echo -e "${YELLOW}>>> 正在安装 Gum (UI 组件)...${NC}"
    local ARCH=$(uname -m)
    local G_ARCH=""
    case "$ARCH" in
        x86_64) G_ARCH="x86_64" ;; 
        aarch64) G_ARCH="arm64" ;; 
        *) ui_print error "暂不支持此架构自动安装 Gum: $ARCH"; return 1 ;; 
    esac
    
    local VER="0.13.0"
    local URL="https://github.com/charmbracelet/gum/releases/download/v${VER}/gum_${VER}_Linux_${G_ARCH}.tar.gz"
    
    # Simple mirror support
    if [ -n "$SELECTED_MIRROR" ] && [[ "$SELECTED_MIRROR" != *"github.com"* ]]; then
         URL="${SELECTED_MIRROR}${URL}"
    fi

    if curl -L -o /tmp/gum.tar.gz "$URL"; then
        cd /tmp
        tar -xzf gum.tar.gz
        local BIN_DIR="/usr/local/bin"
        if [ ! -w "$BIN_DIR" ] && [ -z "$SUDO_CMD" ]; then
             BIN_DIR="$HOME/.local/bin"
             mkdir -p "$BIN_DIR"
        fi
        
        $SUDO_CMD mv gum "$BIN_DIR/gum"
        $SUDO_CMD chmod +x "$BIN_DIR/gum"
        rm gum.tar.gz LICENSE README.md 2>/dev/null
        
        # Update path for current session if local
        [[ "$BIN_DIR" == *".local"* ]] && export PATH="$BIN_DIR:$PATH"
        
        if command -v gum &>/dev/null; then 
            ui_print success "Gum 安装成功"
            return 0
        fi
    fi
    ui_print error "Gum 安装失败，请手动下载。"
    return 1
}

install_cloudflared_linux() {
    echo -e "${YELLOW}>>> 正在安装 Cloudflared...${NC}"
    local ARCH=$(uname -m)
    local C_ARCH=""
    case "$ARCH" in
        x86_64) C_ARCH="amd64" ;; 
        aarch64) C_ARCH="arm64" ;; 
        *) return 1 ;; 
    esac
    
    local URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${C_ARCH}"
    
    if [ -n "$SELECTED_MIRROR" ] && [[ "$SELECTED_MIRROR" != *"github.com"* ]]; then
         URL="${SELECTED_MIRROR}${URL}"
    fi
     
    if curl -L -o /tmp/cloudflared "$URL"; then
         local BIN_DIR="/usr/local/bin"
         [ ! -w "$BIN_DIR" ] && [ -z "$SUDO_CMD" ] && BIN_DIR="$HOME/.local/bin"
         mkdir -p "$BIN_DIR"
         
         $SUDO_CMD mv /tmp/cloudflared "$BIN_DIR/cloudflared"
         $SUDO_CMD chmod +x "$BIN_DIR/cloudflared"
         
         [[ "$BIN_DIR" == *".local"* ]] && export PATH="$BIN_DIR:$PATH"
         return 0
    fi
    return 1
}

check_dependencies() {
    if [ "$DEPS_CHECKED" == "true" ]; then return 0; fi

    local MISSING_PKGS=""
    
    # Pre-check logic
    local HAS_NODE=false; command -v node &> /dev/null && HAS_NODE=true
    local HAS_GIT=false; command -v git &> /dev/null && HAS_GIT=true
    local HAS_CF=false; command -v cloudflared &> /dev/null && HAS_CF=true
    local HAS_GUM=false; command -v gum &> /dev/null && HAS_GUM=true
    local HAS_TAR=false; command -v tar &> /dev/null && HAS_TAR=true

    if $HAS_NODE && $HAS_GIT && $HAS_CF && $HAS_GUM && $HAS_TAR; then
        export DEPS_CHECKED="true"
        return 0
    fi

    ui_header "环境初始化"
    echo -e "${BLUE}[INFO]${NC} 正在检查全套组件 ($OS_TYPE)..."

    # Identify missing system packages
    if ! $HAS_NODE; then 
        echo -e "${YELLOW}[WARN]${NC} 未找到 Node.js"
        if [ "$OS_TYPE" == "TERMUX" ]; then MISSING_PKGS="$MISSING_PKGS nodejs-lts"; else MISSING_PKGS="$MISSING_PKGS nodejs npm"; fi
    fi

    if ! $HAS_GIT; then 
        echo -e "${YELLOW}[WARN]${NC} 未找到 Git"
        MISSING_PKGS="$MISSING_PKGS git"
    fi
    
    if ! $HAS_TAR; then MISSING_PKGS="$MISSING_PKGS tar"; fi

    # Termux gets everything via pkg
    if [ "$OS_TYPE" == "TERMUX" ]; then
        if ! $HAS_GUM; then MISSING_PKGS="$MISSING_PKGS gum"; fi
        if ! $HAS_CF; then MISSING_PKGS="$MISSING_PKGS cloudflared"; fi
    fi

    # Install System Packages
    if [ -n "$MISSING_PKGS" ]; then
        echo -e "${BLUE}[INFO]${NC} 正在安装系统依赖: $MISSING_PKGS"
        if [ "$OS_TYPE" == "TERMUX" ]; then
            pkg update -y && pkg install $MISSING_PKGS -y
        else
            $SUDO_CMD apt-get update -y
            $SUDO_CMD apt-get install $MISSING_PKGS -y
        fi
    fi
    
    # Linux Binary Manual Installs
    if [ "$OS_TYPE" == "LINUX" ]; then
        if ! command -v gum &>/dev/null; then install_gum_linux; fi
        if ! command -v cloudflared &>/dev/null; then install_cloudflared_linux; fi
    fi
    
    # Final Verification
    if command -v node &> /dev/null && \
       command -v git &> /dev/null && \
       command -v cloudflared &> /dev/null && \
       command -v gum &> /dev/null; then
        
        echo -e "${GREEN}[DONE]${NC} 环境全量修复完成！"
        export DEPS_CHECKED="true"
        read -n 1 -s -r -p "按任意键继续..."
    else
        echo -e "${RED}[ERROR]${NC} 环境修复不完整！"
        echo -e "${YELLOW}请尝试手动运行安装命令或检查网络。${NC}"
        # We allow proceeding, as some features might work partialy
        read -n 1 -s -r -p "按任意键继续..."
    fi
}
