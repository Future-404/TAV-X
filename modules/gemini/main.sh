#!/bin/bash
# [METADATA]
# MODULE_ID: gemini
# MODULE_NAME: Gemini CLI (已移除)
# MODULE_ENTRY: gemini_menu
# APP_CATEGORY: 命令行工具
# APP_AUTHOR: Google
# APP_PROJECT_URL: https://github.com/google-gemini/gemini-cli
# APP_DESC: [已移除] Gemini CLI 模块已从 TAV-X 移除并下架，当前仅保留已安装文件的卸载清理功能。
# UPDATE_TYPE: none
# MODULE_DEPRECATED: true
# [END_METADATA]

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

_gemini_vars() {
    GEMINI_APP_ID="gemini"
    GEMINI_DIR=$(get_app_path "$GEMINI_APP_ID")
}

_gemini_ensure_path() {
    export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
    if [ -d "$PNPM_HOME" ]; then
        case ":$PATH:" in
            *":$PNPM_HOME:"*) ;;
            *) export PATH="$PNPM_HOME:$PATH" ;;
        esac
    fi
}

_gemini_is_installed() {
    _gemini_vars
    _gemini_ensure_path
    if command -v gemini &>/dev/null || [ -d "$GEMINI_DIR" ]; then
        return 0
    fi
    return 1
}

gemini_uninstall() {
    _gemini_vars
    _gemini_ensure_path
    ui_header "卸载 Gemini CLI (已移除)"
    echo -e "${YELLOW}提示：Gemini CLI 模块已从 TAV-X 移除并下架。${NC}"
    echo -e "卸载操作将卸载全局 @google/gemini-cli 包并清理关联目录。"
    echo ""

    if verify_kill_switch; then
        if command -v pnpm &>/dev/null; then
            ui_print info "正在通过 pnpm 卸载 @google/gemini-cli..."
            pnpm remove -g @google/gemini-cli 2>/dev/null || true
        fi
        if command -v gemini &>/dev/null && command -v npm &>/dev/null; then
            ui_print info "正在通过 npm 卸载 @google/gemini-cli..."
            npm uninstall -g @google/gemini-cli 2>/dev/null || true
        fi

        safe_rm "$GEMINI_DIR"
        ui_print success "Gemini CLI 已卸载清理完成！"
        ui_pause
        return 2
    fi
    return 1
}

gemini_menu() {
    while true; do
        _gemini_vars
        ui_header "Gemini CLI 管理 (已移除)"
        local state="stopped"; local text="未安装"; local info=()
        local is_installed=false

        if _gemini_is_installed; then
            state="warn"; text="已移除 (检测到已安装文件)"
            is_installed=true
            info+=( "状态: 该模块已从 TAV-X 移除，建议卸载清理" )
            info+=( "包名: @google/gemini-cli" )
            [ -d "$GEMINI_DIR" ] && info+=( "目录: $GEMINI_DIR" )
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
            *"卸载"*) gemini_uninstall; [ $? -eq 2 ] && return ;;
            *"关于"*) show_module_about_info "${BASH_SOURCE[0]}" ;;
            *"返回"*|"") return ;;
        esac
    done
}
