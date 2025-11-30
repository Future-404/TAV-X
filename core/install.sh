#!/bin/bash
# TAV-X Core: Installer (V2.1 Smart Proxy & Mirror)

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

install_sillytavern() {
    ui_header "SillyTavern 安装向导"

    if [ -d "$INSTALL_DIR" ]; then
        ui_print warn "检测到旧版本目录: $INSTALL_DIR"
        echo -e "${RED}继续安装将清空旧目录！${NC}"
        if ! ui_confirm "确认覆盖安装吗？"; then return; fi
        rm -rf "$INSTALL_DIR"
    fi

    local PROXY_ENV=""
    if [ ! -f "$NETWORK_CONFIG" ]; then
        ui_print info "正在扫描本地代理环境..."
        local detected=$(get_dynamic_proxy)
        
        if [ -n "$detected" ]; then
            ui_print success "自动发现代理: $detected"
            PROXY_ENV="$detected"
            echo "PROXY|$detected" > "$NETWORK_CONFIG"
            export TAVX_TEMP_PROXY="true"
        else
            ui_print info "未发现本地代理，启用智能镜像策略。"
        fi
    else
        local net_conf=$(cat "$NETWORK_CONFIG")
        if [[ "$net_conf" == PROXY* ]]; then
            local p=${net_conf#*|}
            PROXY_ENV=$(echo "$p" | tr -d '\n\r')
        fi
    fi

    if ui_spinner "正在拉取酒馆源码 (Release)..." "git_clone_smart '-b release' 'SillyTavern/SillyTavern' '$INSTALL_DIR'"; then
        ui_print success "源码下载完成！"
    else
        ui_print error "源码下载失败，请检查网络连接。"
        [ "$TAVX_TEMP_PROXY" == "true" ] && rm -f "$NETWORK_CONFIG"
        ui_pause; return 1
    fi

    cd "$INSTALL_DIR" || return
    local NPM_CMD="npm install --no-audit --no-fund --quiet --production"
    
    if [ -n "$PROXY_ENV" ]; then
        ui_print info "NPM 正在使用代理加速..."
        NPM_CMD="export https_proxy='$PROXY_ENV'; export http_proxy='$PROXY_ENV'; $NPM_CMD"
    else
        ui_print info "无代理环境，临时切换 NPM 镜像源..."
        npm config set registry https://registry.npmmirror.com
        export TAVX_TEMP_REGISTRY="true"
    fi

    if ui_spinner "正在安装依赖库 (请耐心等待)..." "$NPM_CMD"; then
        ui_print success "依赖安装完成！"
        
        [ "$TAVX_TEMP_PROXY" == "true" ] && rm -f "$NETWORK_CONFIG"
        if [ "$TAVX_TEMP_REGISTRY" == "true" ]; then
            npm config delete registry # 恢复官方源，避免影响用户其他项目
            ui_print info "已恢复 NPM 默认源。"
        fi
        
        chmod +x start.sh 2>/dev/null
        ui_print success "🎉 SillyTavern 安装成功！"
        echo -e "您现在可以使用主菜单的 [🚀 启动服务] 来运行了。"
    else
        ui_print error "依赖安装失败。"
        [ "$TAVX_TEMP_PROXY" == "true" ] && rm -f "$NETWORK_CONFIG"
        [ "$TAVX_TEMP_REGISTRY" == "true" ] && npm config delete registry
    fi
    ui_pause
}