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
    
    local VER="0.17.0"
    local URL="https://github.com/charmbracelet/gum/releases/download/v${VER}/gum_${VER}_Linux_${G_ARCH}.tar.gz"
    
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

check_python_installed() {
    if command -v python3 &>/dev/null && command -v pip3 &>/dev/null;
 then
        return 0
    fi
    return 1
}

install_python_system() {
    ui_header "Python 环境安装"
    ui_print info "检测到当前模块需要 Python 运行时..."
    
    if check_python_installed; then
        ui_print success "Python 环境已就绪。"
        sleep 1
        return 0
    fi

    echo -e "${YELLOW}即将安装 Python 及其基础组件...${NC}"
    echo "----------------------------------------"
    
    local install_cmd=""
    if [ "$OS_TYPE" == "TERMUX" ]; then
        install_cmd="pkg install -y python"
    else
        if command -v apt-get &>/dev/null;
 then
            install_cmd="$SUDO_CMD apt-get update && $SUDO_CMD apt-get install -y python3 python3-pip python3-venv"
        else
            ui_print error "暂不支持非 Apt 系 Linux 的自动安装。"
            ui_print info "请手动安装: python3, pip, venv"
            ui_pause; return 1
        fi
    fi
    
    if ui_spinner "正在安装 Python..." "$install_cmd"; then
        if check_python_installed; then
            ui_print success "Python 安装成功！"
            pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple >/dev/null 2>&1
            return 0
        fi
    fi
    
    ui_print error "Python 安装失败，请检查网络或软件源。"
    ui_pause
    return 1
}

check_node_version() {
    if ! command -v node &> /dev/null; then return 1; fi
    
    local ver=$(node -v | tr -d 'v' | cut -d '.' -f 1)
    
    if [ -z "$ver" ] || [ "$ver" -lt 20 ]; then
        return 1
    fi
    return 0
}

setup_nodesource() {
    ui_print info "正在配置 NodeSource 源..."
    $SUDO_CMD apt-get update
    $SUDO_CMD apt-get install -y curl gnupg ca-certificates
    
    if curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO_CMD bash -; then
        ui_print success "源配置完成，正在安装 Node.js..."
        $SUDO_CMD apt-get install -y nodejs
        return $?
    else
        ui_print error "源配置失败，请检查网络。"
        return 1
    fi
}

check_dependencies() {
    if [ "$DEPS_CHECKED" == "true" ]; then return 0; fi

    local MISSING_PKGS=""
    
    local HAS_NODE=false; check_node_version && HAS_NODE=true
    local HAS_GIT=false; command -v git &> /dev/null && HAS_GIT=true
    local HAS_CF=false; command -v cloudflared &> /dev/null && HAS_CF=true
    local HAS_GUM=false; command -v gum &> /dev/null && HAS_GUM=true
    local HAS_TAR=false; command -v tar &> /dev/null && HAS_TAR=true

    if $HAS_NODE && $HAS_GIT && $HAS_CF && $HAS_GUM && $HAS_TAR;
 then
        export DEPS_CHECKED="true"
        return 0
    fi

    ui_header "环境初始化"
    echo -e "${BLUE}[INFO]${NC} 正在检查全套组件 ($OS_TYPE)..."

    if ! $HAS_NODE; then 
        echo -e "${YELLOW}[WARN]${NC} Node.js 未找到或版本过低 (<v20)"
        if [ "$OS_TYPE" == "TERMUX" ]; then 
            MISSING_PKGS="$MISSING_PKGS nodejs"
        else 
            echo -e "${YELLOW}检测到 Linux 环境，是否自动配置 NodeSource 源以安装最新 Node.js?${NC}"
            if ui_confirm "这需要 root 权限 (sudo) 且会修改系统源列表。"; then
                setup_nodesource
                if check_node_version; then HAS_NODE=true; else MISSING_PKGS="$MISSING_PKGS nodejs"; fi
            else
                 echo -e "${RED}[ERROR]${NC} 跳过 Node.js 配置。SillyTavern 可能无法启动。"
                 MISSING_PKGS="$MISSING_PKGS nodejs npm"
            fi
        fi
    fi

    if ! $HAS_GIT; then 
        echo -e "${YELLOW}[WARN]${NC} 未找到 Git"
        MISSING_PKGS="$MISSING_PKGS git"
    fi
    
    if ! $HAS_TAR; then MISSING_PKGS="$MISSING_PKGS tar"; fi

    if [ "$OS_TYPE" == "TERMUX" ]; then
        if ! $HAS_GUM; then MISSING_PKGS="$MISSING_PKGS gum"; fi
        if ! $HAS_CF; then MISSING_PKGS="$MISSING_PKGS cloudflared"; fi
    fi

    if [ -n "$MISSING_PKGS" ]; then
        echo -e "${BLUE}[INFO]${NC} 正在安装系统依赖: $MISSING_PKGS"
        if [ "$OS_TYPE" == "TERMUX" ]; then
            pkg update -y && pkg install $MISSING_PKGS -y
        else
            $SUDO_CMD apt-get update -y
            $SUDO_CMD apt-get install $MISSING_PKGS -y
        fi
    fi
    
    if [ "$OS_TYPE" == "LINUX" ]; then
        if ! command -v gum &>/dev/null; then install_gum_linux; fi
        if ! command -v cloudflared &>/dev/null; then install_cloudflared_linux; fi
    fi
    
    if command -v node &> /dev/null && \
       command -v git &> /dev/null && \
       command -v cloudflared &> /dev/null && \
       command -v gum &> /dev/null;
 then
        
        echo -e "${GREEN}[DONE]${NC} 环境全量修复完成！"
        export DEPS_CHECKED="true"
        read -n 1 -s -r -p "按任意键继续..."
    else
        echo -e "${RED}[ERROR]${NC} 环境修复不完整！"
        echo -e "${YELLOW}请尝试手动运行安装命令或检查网络。${NC}"
        read -n 1 -s -r -p "按任意键继续..."
    fi
}