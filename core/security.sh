#!/bin/bash
# TAV-X Core: System Settings

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

NETWORK_CONFIG="$TAVX_DIR/config/network.conf"

full_wipe() {
    ui_header "一键彻底卸载"
    echo -e "${RED}危险等级：⭐⭐⭐⭐⭐${NC}"
    echo -e "此操作将执行以下所有动作："
    echo -e "  1. 卸载 SillyTavern 及所有已安装模块"
    echo -e "  2. 删除所有配置数据和本地文件"
    echo -e "  3. 清理环境变量"
    echo -e "  4. 自我删除 TAV-X 脚本"
    echo ""
    
    if ! verify_kill_switch; then return; fi
    if command -v stop_all_services_routine &>/dev/null; then
        stop_all_services_routine
    fi
    
    ui_spinner "正在执行深度清理..." "
        if [ -d \"$APPS_DIR\" ]; then
            for app in \"$APPS_DIR\"/*; do
                [ -d \"\$app\" ] && rm -rf \"\$app\"
            done
        fi
        
        [ -d \"\$HOME/SillyTavern\" ] && rm -rf \"\$HOME/SillyTavern\"
        
        sed -i '/alias st=/d' \"$HOME/.bashrc\" 2>/dev/null
        sed -i '/alias ai=/d' \"$HOME/.bashrc\" 2>/dev/null
    "
    
    ui_print success "业务数据已清除。"
    echo -e "${YELLOW}自毁程序启动... 再见！👋${NC}"
    sleep 2
    cd "$HOME" || exit
    /bin/rm -rf "$TAVX_DIR"
    exit 0
}

change_npm_source() {
    ui_header "NPM 源配置 (Node.js)"
    local current=$(npm config get registry 2>/dev/null)
    echo -e "当前源: ${CYAN}$current${NC}"; echo ""
    local OPTS=("淘宝源 (npmmirror)|https://registry.npmmirror.com/" "腾讯源|https://mirrors.cloud.tencent.com/npm/" "官方源|https://registry.npmjs.org/")
    local MENU_OPTS=(); local URLS=()
    for item in "${OPTS[@]}"; do MENU_OPTS+=("${item%%|*}"); URLS+=("${item#*|}"); done; MENU_OPTS+=("🔙 返回")
    local CHOICE=$(ui_menu "选择镜像源" "${MENU_OPTS[@]}")
    if [[ "$CHOICE" == *"返回"* ]]; then return; fi
    local TARGET_URL=""; for i in "${!MENU_OPTS[@]}"; do if [[ "${MENU_OPTS[$i]}" == "$CHOICE" ]]; then TARGET_URL="${URLS[$i]}"; break; fi; done
    if [ -n "$TARGET_URL" ]; then if npm config set registry "$TARGET_URL"; then ui_print success "NPM 源已设置为: $CHOICE"; else ui_print error "设置失败"; fi; fi; ui_pause
}

change_system_source() {
    ui_header "系统软件源配置"
    if [ "$OS_TYPE" == "TERMUX" ]; then
        if command -v termux-change-repo &> /dev/null; then ui_print info "启动 Termux 官方工具..."; sleep 1; termux-change-repo; else ui_print error "未找到 termux-change-repo"; fi
    else
        echo -e "${YELLOW}Linux 一键换源 (LinuxMirrors)${NC}"; echo ""
        if ui_confirm "运行一键换源脚本？"; then command -v curl &> /dev/null && bash <(curl -sSL https://linuxmirrors.cn/main.sh) || ui_print error "缺 curl"; fi
    fi; ui_pause
}

clean_git_remotes() {
    ui_header "Git 仓库源清洗"
    if ! ui_confirm "重置所有组件更新源为 GitHub 官方地址？"; then return; fi
    ui_print info "正在修复..."
    
    local st_path=$(get_app_path "sillytavern")
    reset_to_official_remote "$TAVX_DIR" "Future-404/TAV-X.git" && echo -e "  - TAV-X: OK"
    [ -d "$st_path" ] && reset_to_official_remote "$st_path" "SillyTavern/SillyTavern.git" && echo -e "  - SillyTavern: OK"
    
    ui_print success "修复完成。"; ui_pause
}

configure_download_network() {
    while true; do
        ui_header "网络与软件源配置"
        local curr_mode="自动"
        if [ -f "$NETWORK_CONFIG" ]; then
            local c=$(cat "$NETWORK_CONFIG")
            curr_mode="${c#*|}"
        fi
        echo -e "当前策略: ${CYAN}$curr_mode${NC}"; echo "----------------------------------------"
        local OPTS=("🔧 自定义下载代理" "🔄 重置网络设置" "♻️  修复 Git 仓库源" "🐍 更换 PIP 源" "📦 更换 NPM 源" "🐧 更换系统源" "🔙 返回")
        local CHOICE=$(ui_menu "选择操作" "${OPTS[@]}")
        case "$CHOICE" in
            *"自定义"*)
                local url=$(ui_input "输入代理 (如 http://127.0.0.1:7890)" "" "false")
                if [[ "$url" =~ ^(http|https|socks5|socks5h)://.* ]]; then
                    echo "PROXY|$url" > "$NETWORK_CONFIG"
                    ui_print success "已保存"
                else
                    ui_print error "格式错误"
                fi
                ui_pause 
                ;;
            *"重置"*) 
                rm -f "$NETWORK_CONFIG"
                unset SELECTED_MIRROR
                reset_proxy_cache
                ui_print success "网络配置已重置 (下个任务将重新扫描与测速)"
                ui_pause 
                ;;
            *"Git"*) clean_git_remotes ;;
            *"PIP"*) 
                source "$TAVX_DIR/core/python_utils.sh"
                select_pypi_mirror ;;
            *"NPM"*) change_npm_source ;;
            *"系统"*) change_system_source ;;
            *"返回"*) return ;;
        esac
    done
}

configure_cf_token() {
    ui_header "Cloudflare Tunnel Token"
    local token_file="$TAVX_DIR/config/cf_token"
    local current_stat="${YELLOW}未配置${NC}"; if [ -s "$token_file" ]; then local t=$(cat "$token_file"); current_stat="${GREEN}已配置${NC} (${t:0:6}...)"; fi
    echo -e "状态: $current_stat"; echo "----------------------------------------"
    local OPTS=("✏️ 输入/更新 Token" "🗑️ 清除 Token" "🔙 返回")
    local CHOICE=$(ui_menu "选择操作" "${OPTS[@]}")
    case "$CHOICE" in
        *"输入"*) local i=$(ui_input "请粘贴 Token" "" "false"); [ -n "$i" ] && echo "$i" > "$token_file" && ui_print success "已保存"; ui_pause ;;
        *"清除"*) rm -f "$token_file"; ui_print success "已清除"; ui_pause ;; *"返回"*) return ;;
    esac
}

clean_system_garbage() {
    ui_header "系统垃圾清理"
    echo -e "准备清理以下内容："
    echo -e "  1. 系统临时文件 ($TMP_DIR/tavx_*)"
    echo -e "  2. 模块运行产生的旧日志 (logs/*.log)"
    echo ""
    
    if ! ui_confirm "确认立即清理？"; then return; fi
    
    ui_spinner "正在清理..." "
        source \"$TAVX_DIR/core/utils.sh\"
        safe_rm \"$LOGS_DIR\"/*.log
        rm -f \"$TMP_DIR\"/tavx_* 2>/dev/null
        rm -f \"$TMP_DIR\"/*.log 2>/dev/null
    "
    
    ui_print success "清理完成！"
    ui_pause
}

configure_analytics() {
    local marker_file="$TAVX_DIR/config/no_analytics"
    local current_stat
    if [ -f "$marker_file" ]; then
        current_stat="${RED}● 已关闭${NC}"
    else
        current_stat="${GREEN}● 运行中${NC}"
    fi
    
    ui_header "匿名统计与项目支持"
    echo -e "当前状态: $current_stat"
    echo ""
    echo -e "${YELLOW}作为个人开发者，我想知道：${NC}"
    echo -e " • ${CYAN}「是否真的有人在用？」${NC} —— 这直接决定我是否继续维护它。"
    echo -e " • ${CYAN}「大家在什么系统上用它？」${NC} —— 这帮助我决定优先优化的方向。"
    echo ""
    echo -e "为此，我仅收集${GREEN}最基础${NC}的数据："
    echo -e " ${GREEN}✓${NC} 应用版本号"
    echo -e " ${GREEN}✓${NC} 操作系统类型 (Android/Linux)"
    echo -e " ${RED}✗ 绝不收集：${NC} 任何身份信息、位置、本地文件等个人隐私。"
    echo -e "所有数据均已进行${PURPLE}完全匿名与脱敏处理${NC}。"
    echo -e "你可以随时在源码中审查此逻辑：${CYAN}https://github.com/Future-404/TAV-X${NC}"
    echo ""
    echo -e "你的每一次使用，都是对我最大的鼓励。这份数据是我持续维护项目的关键动力。"
    echo -e "----------------------------------"
    echo -e "${RED}关闭后将导致...${NC}"
    echo -e "我将无法获知你的使用情况，这可能会让我误判项目已无人需要，从而影响后续更新。"
    echo ""
    
    local choice
    if [ ! -f "$marker_file" ]; then
        choice=$(ui_menu "您愿意分享匿名数据，来帮助这个项目活下去吗？" "❤️ 愿意，保持开启" "👣 暂时不贡献数据")
        if [[ "$choice" == *"暂时"* ]]; then
            touch "$marker_file"
            ui_print success "设置已保存。虽然遗憾，但尊重您的选择。"
        else
            ui_print success "太棒了！感谢您的支持，我会努力做得更好！"
        fi
    else
        choice=$(ui_menu "当前处于关闭状态，是否重新开启支持开发者？" "🚀 重新开启统计" "🔙 保持关闭并返回")
        if [[ "$choice" == *"开启"* ]]; then
            rm -f "$marker_file"
            ui_print success "已重新开启匿名统计，感谢您的信任！"
        fi
    fi
    ui_pause
}

system_settings_menu() {
    while true; do
        ui_header "系统设置"
        local OPTS=(
            "📥 下载源与代理配置"
            "🐍 Python环境管理"
            "📱 ADB智能助手"
            "☁️  CloudflareToken"
            "📊 匿名统计开关"
            "🧹 系统垃圾清理"
            "💥 一键彻底毁灭 (危险)"
            "🔙 返回主菜单"
        )
        local CHOICE=$(ui_menu "请选择功能" "${OPTS[@]}")
        case "$CHOICE" in
            *"下载源"*) configure_download_network ;;
            *"Python"*) 
                source "$TAVX_DIR/core/python_utils.sh"
                python_environment_manager_ui ;;
            *"ADB"*)
                source "$TAVX_DIR/core/adb_utils.sh"
                adb_manager_ui ;;
            *"Cloudflare"*) configure_cf_token ;;
            *"统计"*) configure_analytics ;;
            *"清理"*) clean_system_garbage ;;
            *"彻底毁灭"*) full_wipe ;;
            *"返回"*) return ;;
        esac
    done
}