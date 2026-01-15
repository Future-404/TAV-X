#!/bin/bash
# TAV-X Core: Dependency Manager
[ -n "$_TAVX_DEPS_LOADED" ] && return
_TAVX_DEPS_LOADED=true

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

install_gum_linux() {
    echo -e "${YELLOW}>>> 正在安装 Gum ...${NC}"
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

    local DL_CMD="curl -L -o $TMP_DIR/gum.tar.gz '$URL'"
    if ui_stream_task "正在下载 Gum ..." "$DL_CMD"; then
        cd "$TMP_DIR"
        tar -xzf gum.tar.gz
        local BIN_DIR="/usr/local/bin"
        if [ ! -w "$BIN_DIR" ] && [ -z "$SUDO_CMD" ]; then
             BIN_DIR="$HOME/.local/bin"
             mkdir -p "$BIN_DIR"
        fi
        
        $SUDO_CMD mv gum "$BIN_DIR/gum"
        $SUDO_CMD chmod +x "$BIN_DIR/gum"
        safe_rm gum.tar.gz LICENSE README.md 2>/dev/null
        
        [[ "$BIN_DIR" == *".local"* ]] && [[ ":$PATH:" != *":$BIN_DIR:"* ]] && export PATH="$BIN_DIR:$PATH"
        
        if command -v gum &>/dev/null; then 
            ui_print success "Gum 安装成功"
            return 0
        fi
    fi
    ui_print error "Gum 安装失败，请手动下载。"
    return 1
}
export -f install_gum_linux

install_yq() {
    if command -v yq &>/dev/null; then return 0; fi
    ui_print info "正在获取 yq ..."
    
    if [ "$OS_TYPE" == "TERMUX" ]; then
        if sys_install_pkg "yq"; then
            ui_print success "yq 安装成功"
            return 0
        fi
        ui_print warn "pkg 安装失败，切换至手动下载模式..."
    fi

    local ARCH=$(uname -m)
    local YQ_ARCH="amd64"
    [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && YQ_ARCH="arm64"
    
    local BIN_DIR="/usr/local/bin"
    [ "$OS_TYPE" == "TERMUX" ] && BIN_DIR="$PREFIX/bin"
    if [ ! -w "$BIN_DIR" ] && [ -z "$SUDO_CMD" ]; then 
        BIN_DIR="$TAVX_BIN"
        mkdir -p "$BIN_DIR"
    fi

    local VER="v4.44.3"
    local URL="https://github.com/mikefarah/yq/releases/download/${VER}/yq_linux_${YQ_ARCH}"
    local DL_CMD="source \"$TAVX_DIR/core/utils.sh\"; download_file_smart '$URL' '$BIN_DIR/yq'"
    
    if ui_stream_task "下载 yq 组件..." "$DL_CMD"; then
        chmod +x "$BIN_DIR/yq"
        if command -v "$BIN_DIR/yq" &>/dev/null; then
            ui_print success "yq 安装成功"
            return 0
        fi
    fi
    ui_print error "yq 安装失败，部分配置功能将不可用。"
    return 1
}
export -f install_yq

install_cloudflared_linux() {
    ui_print info "正在获取 Cloudflared ($OS_TYPE)..."
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
     
    local DL_CMD="curl -L -o $TMP_DIR/cloudflared '$URL'"
    if ui_stream_task "正在下载 Cloudflared..." "$DL_CMD"; then
         local BIN_DIR="/usr/local/bin"
         [ ! -w "$BIN_DIR" ] && [ -z "$SUDO_CMD" ] && BIN_DIR="$HOME/.local/bin"
         mkdir -p "$BIN_DIR"
         
         $SUDO_CMD mv "$TMP_DIR/cloudflared" "$BIN_DIR/cloudflared"
         $SUDO_CMD chmod +x "$BIN_DIR/cloudflared"
         
         [[ "$BIN_DIR" == *".local"* ]] && [[ ":$PATH:" != *":$BIN_DIR:"* ]] && export PATH="$BIN_DIR:$PATH"
         return 0
    fi
    return 1
}
export -f install_cloudflared_linux

check_python_installed() {
    if command -v python3 &>/dev/null && command -v pip3 &>/dev/null; then
        return 0
    fi
    return 1
}
export -f check_python_installed

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
    
    local pkgs="python"
    [ "$OS_TYPE" == "LINUX" ] && pkgs="python3 python3-pip python3-venv"
    
    if sys_install_pkg "$pkgs"; then
        if check_python_installed; then
            ui_print success "Python 安装成功！"
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
    sys_install_pkg "curl gnupg ca-certificates" || return 1
    
    local SETUP_CMD="curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO_CMD bash -"
        if ui_stream_task "注入 NodeSource 源..." "$SETUP_CMD"; then
            if sys_install_pkg "nodejs"; then
                ui_print success "Node.js 安装完成。"
                return 0
            fi
        fi
        ui_print error "Node.js 安装失败，请检查网络。"
        return 1
    }
    export -f setup_nodesource
    
    install_motd_hook() {
        [ "$OS_TYPE" != "TERMUX" ] && return
        
        local hook_file="$PREFIX/etc/profile.d/tavx_status.sh"
        [ -f "$hook_file" ] && return
        
        ui_print info "正在配置终端启动提示..."
        cat > "$hook_file" <<'EOF'
#!/bin/sh
# TAV-X Auto-status check
if [ -d "$PREFIX/var/service" ] && command -v sv >/dev/null; then
    _tx_srvs=""
    for s in "$PREFIX/var/service"/*; do
        if [ -f "$s/.tavx_managed" ] && sv status "$(basename "$s")" 2>/dev/null | grep -q "^run:"; then
            _tx_srvs="$_tx_srvs $(basename "$s")"
        fi
    done
    [ -n "$_tx_srvs" ] && echo -e "\033[1;36m✨ TAV-X 后台服务运行中:$_tx_srvs\033[0m"
fi
EOF
        chmod +x "$hook_file"
    }
    export -f install_motd_hook

    check_dependencies() {
        if [ "$DEPS_CHECKED" == "true" ]; then 
            [ "$OS_TYPE" == "TERMUX" ] && install_motd_hook
            return 0 
        fi
    
        local MISSING_PKGS=""
        local ALL_FOUND=true
        local NEEDS_UI=false

        for dep in "${CORE_DEPENDENCIES[@]}"; do
            local cmd="${dep%%|*}"
            if [ "$cmd" == "node" ]; then
                if ! check_node_version; then NEEDS_UI=true; break; fi
            elif ! command -v "$cmd" &> /dev/null; then
                NEEDS_UI=true; break
            fi
        done

        if [ "$NEEDS_UI" == "true" ]; then
            ui_header "环境初始化"
            echo -e "${BLUE}[INFO]${NC} 正在检查全套核心组件 ($OS_TYPE)..."
        fi

        for dep in "${CORE_DEPENDENCIES[@]}"; do
            local cmd="${dep%%|*}"
            local pkg_termux=$(echo "$dep" | cut -d'|' -f2)
            local pkg_linux=$(echo "$dep" | cut -d'|' -f3)
            
            if [ "$cmd" == "node" ]; then
                if ! check_node_version; then
                    if [ "$OS_TYPE" == "TERMUX" ]; then MISSING_PKGS="$MISSING_PKGS $pkg_termux"
                    else
                        [ "$NEEDS_UI" == "false" ] && ui_header "环境初始化"
                        echo -e "${YELLOW}Node.js 版本过低或未安装，正在配置 NodeSource...${NC}"
                        setup_nodesource || ALL_FOUND=false
                    fi
                fi
                continue
            fi

            if ! command -v "$cmd" &> /dev/null; then
                if [ "$OS_TYPE" == "LINUX" ]; then
                    if [ "$cmd" == "gum" ]; then install_gum_linux || ALL_FOUND=false; continue; fi
                    if [ "$cmd" == "yq" ]; then install_yq || ALL_FOUND=false; continue; fi
                fi

                echo -e "${YELLOW}[WARN]${NC} 未找到依赖: $cmd"
                [ "$OS_TYPE" == "TERMUX" ] && MISSING_PKGS="$MISSING_PKGS $pkg_termux" || MISSING_PKGS="$MISSING_PKGS $pkg_linux"
            fi
        done
    
        if [ -n "$MISSING_PKGS" ]; then
            ui_print info "正在修复缺失依赖: $MISSING_PKGS"
            if ! sys_install_pkg "$MISSING_PKGS"; then
                ALL_FOUND=false
            fi
        fi
        
        [ "$OS_TYPE" == "TERMUX" ] && install_motd_hook

        if [ "$ALL_FOUND" == "true" ]; then
            export DEPS_CHECKED="true"
            if [ "$NEEDS_UI" == "true" ]; then
                ui_print success "环境全量修复完成！"
                ui_pause
            fi
            return 0
        else
            ui_print error "环境修复不完整，请检查报错信息。"
            ui_pause
            return 1
        fi
    }
    export -f check_dependencies
    