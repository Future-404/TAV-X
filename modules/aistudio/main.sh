#!/bin/bash
# [METADATA]
# MODULE_ID: aistudio
# MODULE_NAME: build插件 (已停更)
# MODULE_ENTRY: aistudio_menu
# APP_CATEGORY: AI模型接口
# APP_AUTHOR: starowo
# APP_PROJECT_URL: https://github.com/starowo/AIStudioBuildProxy
# APP_DESC: [已停更] AIStudioBuildProxy 插件已停止维护并下架，当前仅保留已安装文件的卸载清理功能。推荐使用 AIStudio2API。
# UPDATE_TYPE: none
# MODULE_DEPRECATED: true
# [END_METADATA]

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

_aistudio_vars() {
    AI_ST_DIR=$(get_app_path "sillytavern")
    AI_PLUGIN_NAME="AIStudioBuildProxy"
    AI_PATH_SERVER="$AI_ST_DIR/plugins/$AI_PLUGIN_NAME"
    AI_PATH_CLIENT="$AI_ST_DIR/public/scripts/extensions/third-party/$AI_PLUGIN_NAME"
}

_aistudio_is_installed() {
    _aistudio_vars
    if [ -d "$AI_PATH_SERVER" ] || [ -d "$AI_PATH_CLIENT" ]; then
        return 0
    fi
    return 1
}

aistudio_uninstall() {
    _aistudio_vars
    ui_header "卸载 build插件 (已停更)"
    echo -e "${YELLOW}提示：该插件已被原作者弃用并停更。${NC}"
    echo -e "卸载操作将安全清理酒馆插件目录下的所有相关文件。"
    echo ""
    
    if verify_kill_switch; then
        ui_spinner "正在清理服务端与客户端文件..." "safe_rm '$AI_PATH_SERVER'; safe_rm '$AI_PATH_CLIENT'"
        ui_print success "build插件已成功卸载！"
        if is_app_running "sillytavern"; then
            echo ""
            if ui_confirm "检测到 SillyTavern 酒馆正在运行，是否立即重启酒馆以完成插件卸载？"; then
                if command -v sillytavern_restart &>/dev/null; then
                    sillytavern_restart
                fi
            else
                ui_print info "提示：请稍后自行重启酒馆以生效。"
            fi
        fi
        return 2
    fi
}

aistudio_menu() {
    while true; do
        _aistudio_vars
        ui_header "build插件管理 (已停更)"
        local state="stopped"; local text="未安装"; local info=()
        local is_installed=false

        if _aistudio_is_installed; then
            state="warn"; text="已停更 (残留文件已检测到)"
            is_installed=true
            info+=( "状态: 项目已停止维护，建议卸载" )
            info+=( "位置: 酒馆插件目录" )
            info+=( "替代推荐: AIStudio2API" )
        else
            info+=( "状态: 该插件已停更下架，已不再支持安装" )
            info+=( "替代推荐: AIStudio2API (Go版)" )
        fi
        ui_status_card "$state" "$text" "${info[@]}"

        local MENU_OPTS=()
        if [ "$is_installed" = true ]; then
            MENU_OPTS+=("🗑️  彻底卸载插件")
        fi
        MENU_OPTS+=("🧭 关于模块" "🔙 返回主菜单")

        local CHOICE
        CHOICE=$(ui_menu "操作菜单" "${MENU_OPTS[@]}")
        case "$CHOICE" in
            *"卸载"*) aistudio_uninstall && [ $? -eq 2 ] && return ;;
            *"关于"*) show_module_about_info "${BASH_SOURCE[0]}" ;;
            *"返回"*) return ;;
        esac
        ui_pause
    done
}
