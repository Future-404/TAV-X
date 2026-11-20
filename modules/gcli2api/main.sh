#!/bin/bash
# [METADATA]
# MODULE_ID: gcli2api
# MODULE_NAME: GCLI2API (已移除)
# MODULE_ENTRY: gcli2api_menu
# APP_CATEGORY: AI模型接口
# APP_AUTHOR: su-kaka
# APP_PROJECT_URL: https://github.com/su-kaka/gcli2api
# APP_DESC: [已移除] GCLI2API 模块已从 TAV-X 移除并下架，当前仅保留已安装文件的卸载清理功能。
# UPDATE_TYPE: none
# MODULE_DEPRECATED: true
# [END_METADATA]

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

_gcli2api_vars() {
    GCLI_APP_ID="gcli2api"
    GCLI_DIR=$(get_app_path "$GCLI_APP_ID")
    GCLI_LOG="$LOGS_DIR/gcli2api.log"
    GCLI_PID="$RUN_DIR/gcli2api.pid"
    GCLI_CONF="$CONFIG_DIR/gcli2api.conf"
}

_gcli2api_is_running() {
    _gcli2api_vars
    if [ "$OS_TYPE" == "TERMUX" ] && sv status gcli2api 2>/dev/null | grep -q "^run:"; then
        return 0
    fi
    if check_process_smart "$GCLI_PID" "python.*web.py"; then
        return 0
    fi
    return 1
}

_gcli2api_is_installed() {
    _gcli2api_vars
    if [ -d "$GCLI_DIR" ] || [ -f "$GCLI_CONF" ] || [ -f "$GCLI_PID" ] || [ -f "$GCLI_LOG" ]; then
        return 0
    fi
    if [ "$OS_TYPE" == "TERMUX" ] && [ -d "$PREFIX/var/service/gcli2api" ]; then
        return 0
    fi
    return 1
}

gcli2api_stop() {
    _gcli2api_vars
    if [ "$OS_TYPE" == "TERMUX" ]; then
        [ -d "$PREFIX/var/service/gcli2api" ] && tavx_service_control "down" "gcli2api"
        [ -f "$GCLI_PID" ] && kill_process_safe "$GCLI_PID" "python.*web.py"
    else
        kill_process_safe "$GCLI_PID" "python.*web.py"
    fi
}

gcli2api_uninstall() {
    _gcli2api_vars
    ui_header "卸载 GCLI2API (已移除)"
    echo -e "${YELLOW}提示：GCLI2API 模块已从 TAV-X 移除并下架。${NC}"
    echo -e "卸载操作将停止服务并清理程序目录、配置、日志及 PID 文件。"
    echo ""

    if verify_kill_switch; then
        gcli2api_stop
        tavx_service_remove "gcli2api"
        safe_rm "$GCLI_DIR" "$GCLI_LOG" "$GCLI_CONF" "$GCLI_PID" "$TMP_DIR/gcli_wheels"
        ui_print success "GCLI2API 已卸载清理完成！"
        ui_pause
        return 2
    fi
    return 1
}

gcli2api_menu() {
    while true; do
        _gcli2api_vars
        ui_header "GCLI2API 管理 (已移除)"
        local state="stopped"; local text="未安装"; local info=()
        local is_installed=false

        if _gcli2api_is_installed; then
            state="warn"
            is_installed=true
            if _gcli2api_is_running; then
                text="已移除 (服务运行中，建议卸载)"
            else
                text="已移除 (检测到已安装文件)"
            fi
            info+=( "状态: 该模块已从 TAV-X 移除，建议卸载清理" )
            [ -d "$GCLI_DIR" ] && info+=( "目录: $GCLI_DIR" )
        else
            info+=( "状态: 该模块已从 TAV-X 移除下架，不再支持安装" )
        fi
        ui_status_card "$state" "$text" "${info[@]}"

        local MENU_OPTS=()
        if [ "$is_installed" = true ]; then
            MENU_OPTS+=("🗑️  彻底卸载模块")
        fi
        MENU_OPTS+=("🧭 关于模块" "🔙 返回")

        local CHOICE
        CHOICE=$(ui_menu "操作菜单" "${MENU_OPTS[@]}")
        case "$CHOICE" in
            *"卸载"*) gcli2api_uninstall; [ $? -eq 2 ] && return ;;
            *"关于"*) show_module_about_info "${BASH_SOURCE[0]}" ;;
            *"返回"*|"") return ;;
        esac
    done
}
