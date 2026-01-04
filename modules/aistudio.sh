#!/bin/bash
# [METADATA]
# MODULE_NAME: 🏗️  AIStudio 代理
# MODULE_ENTRY: aistudio_menu
# [END_METADATA]
source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

REPO_URL="https://github.com/starowo/AIStudioBuildProxy"
PLUGIN_NAME="AIStudioBuildProxy"
SERVER_BRANCH="server"
CLIENT_BRANCH="client"

PATH_SERVER="$INSTALL_DIR/plugins/$PLUGIN_NAME"
PATH_CLIENT="$INSTALL_DIR/public/scripts/extensions/third-party/$PLUGIN_NAME"

check_st_installed() {
    if [ ! -d "$INSTALL_DIR" ]; then
        ui_print error "未检测到 SillyTavern 安装目录。"
        ui_print info "请先在主菜单安装酒馆。"
        return 1
    fi
    return 0
}

enable_server_plugins_conf() {
    ui_print info "正在检查配置..."
    if config_set "enableServerPlugins" "true"; then
        ui_print success "已开启服务端插件支持"
    else
        ui_print warn "配置修改失败，请稍后手动检查 config.yaml"
    fi
}

install_aistudio() {
    check_st_installed || { ui_pause; return; }
    ui_header "部署 AIStudioBuildProxy"
    enable_server_plugins_conf
    prepare_network_strategy "$REPO_URL"
    ui_print info "正在处理服务端组件..."
    safe_rm "$PATH_SERVER"
    local CMD_SERVER="source \"$TAVX_DIR/core/utils.sh\"; git_clone_smart '-b $SERVER_BRANCH' '$REPO_URL' '$PATH_SERVER'"
    
    if ui_spinner "下载服务端代码..." "$CMD_SERVER"; then
        ui_print success "服务端代码就绪。"
        
        if [ -f "$PATH_SERVER/package.json" ]; then
            ui_print info "正在安装依赖 (npm install)..."
            if npm_install_smart "$PATH_SERVER"; then
                ui_print success "依赖安装完成。"
            else
                ui_print error "依赖安装失败。"
                ui_pause; return
            fi
        fi
    else
        ui_print error "服务端下载失败。"
        ui_pause; return
    fi

    echo ""

    ui_print info "正在处理客户端组件..."
    safe_rm "$PATH_CLIENT"
    mkdir -p "$(dirname "$PATH_CLIENT")"
    
    local CMD_CLIENT="source \"$TAVX_DIR/core/utils.sh\"; git_clone_smart '-b $CLIENT_BRANCH' '$REPO_URL' '$PATH_CLIENT'"
    
    if ui_spinner "下载客户端扩展..." "$CMD_CLIENT"; then
        ui_print success "客户端扩展就绪。"
        echo ""
        ui_print success "🎉 AIStudioBuildProxy 安装全部完成！"
        echo -e "${YELLOW}请重启 SillyTavern 以加载新插件。${NC}"
        echo -e "服务端口: HTTP 8889 / WS 9998"
    else
        ui_print error "客户端下载失败。"
    fi
    ui_pause
}

uninstall_aistudio() {
    ui_header "卸载 AIStudio 插件"
    
    if [ ! -d "$PATH_SERVER" ] && [ ! -d "$PATH_CLIENT" ]; then
        ui_print warn "未检测到 AIStudio 插件。"
        ui_pause; return
    fi
    
    if ! verify_kill_switch; then return; fi
    
    ui_spinner "正在清理文件..." "
        source \"$TAVX_DIR/core/utils.sh\"
        safe_rm '$PATH_SERVER'
        safe_rm '$PATH_CLIENT'
    "
    ui_print success "已卸载。重启酒馆后生效。"
    return 2
}

check_status() {
    local s_status="${RED}未安装${NC}"
    local c_status="${RED}未安装${NC}"
    
    if [ -d "$PATH_SERVER" ]; then s_status="${GREEN}已安装${NC}"; fi
    if [ -d "$PATH_CLIENT" ]; then c_status="${GREEN}已安装${NC}"; fi
    
    echo -e "服务端: $s_status | 客户端: $c_status"
    echo "----------------------------------------"
}

aistudio_menu() {
    while true; do
        ui_header "AIStudio 代理服务"
        check_status

        CHOICE=$(ui_menu "请选择操作" \
            "📥 安装/更新插件" \
            "🗑️  卸载插件" \
            "🔙 返回上级"
        )

        case "$CHOICE" in
            *"安装"*) install_aistudio ;;
            *"卸载"*) uninstall_aistudio; [ $? -eq 2 ] && return ;;
            *"返回"*) return ;;
        esac
    done
}