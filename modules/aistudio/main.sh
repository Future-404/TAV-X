#!/bin/bash
# [METADATA]
# MODULE_ID: aistudio
# MODULE_NAME: build插件
# MODULE_ENTRY: aistudio_menu
# APP_AUTHOR: starowo
# APP_PROJECT_URL: https://github.com/starowo/AIStudioBuildProxy
# [END_METADATA]

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

_aistudio_vars() {
    AI_ST_DIR=$(get_app_path "sillytavern")
    AI_REPO="https://github.com/starowo/AIStudioBuildProxy"
    AI_PLUGIN_NAME="AIStudioBuildProxy"
    AI_PATH_SERVER="$AI_ST_DIR/plugins/$AI_PLUGIN_NAME"
    AI_PATH_CLIENT="$AI_ST_DIR/public/scripts/extensions/third-party/$AI_PLUGIN_NAME"
}

aistudio_install() {
    _aistudio_vars
    if [ ! -d "$AI_ST_DIR" ]; then
        ui_print error "请先安装 SillyTavern 酒馆！"
        ui_pause; return 1
    fi
    
    ui_header "部署 AIStudio 插件"
    
    if command -v yq &>/dev/null; then
        yq -i '.enableServerPlugins = true' "$AI_ST_DIR/config.yaml" 2>/dev/null
    else
        sed -i 's/enableServerPlugins: false/enableServerPlugins: true/' "$AI_ST_DIR/config.yaml" 2>/dev/null
    fi

    prepare_network_strategy "$AI_REPO"
    
    ui_print info "正在部署服务端组件..."
    safe_rm "$AI_PATH_SERVER"
    local CMD_S="source '$TAVX_DIR/core/utils.sh'; git_clone_smart '-b server' '$AI_REPO' '$AI_PATH_SERVER'"
    if ui_stream_task "获取服务端仓库..." "$CMD_S"; then
        [ -f "$AI_PATH_SERVER/package.json" ] && npm_install_smart "$AI_PATH_SERVER"
    else
        return 1
    fi

    ui_print info "正在部署客户端组件..."
    safe_rm "$AI_PATH_CLIENT"
    mkdir -p "$(dirname "$AI_PATH_CLIENT")"
    local CMD_C="source '$TAVX_DIR/core/utils.sh'; git_clone_smart '-b client' '$AI_REPO' '$AI_PATH_CLIENT'"
    if ui_stream_task "获取客户端扩展..." "$CMD_C"; then
        ui_print success "🎉 AIStudio 插件安装完成！请重启酒馆。"
    else
        return 1
    fi
}

aistudio_uninstall() {
    _aistudio_vars
    if verify_kill_switch; then
        ui_spinner "清理文件中..." "safe_rm '$AI_PATH_SERVER'; safe_rm '$AI_PATH_CLIENT'"
        ui_print success "已卸载。"
        return 2
    fi
}

aistudio_menu() {
    while true; do
        _aistudio_vars
        ui_header "AIStudio 插件管理"
        local state="stopped"; local text="未安装"; local info=()
        if [ -d "$AI_PATH_SERVER" ] && [ -d "$AI_PATH_CLIENT" ]; then
            state="success"; text="已安装"; info+=( "位置: 酒馆插件目录" )
        fi
        ui_status_card "$state" "$text" "${info[@]}"
        
        local CHOICE=$(ui_menu "操作菜单" "📥 安装/更新插件" "🗑️  卸载插件" "ℹ️ 关于模块" "🔙 返回")
        case "$CHOICE" in
            *"安装"*) aistudio_install ;;
            *"卸载"*) aistudio_uninstall && [ $? -eq 2 ] && return ;;
            *"关于"*) show_module_about_info "${BASH_SOURCE[0]}" ;;
            *"返回"*) return ;;
        esac
        ui_pause
    done
}
