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
    if command -v stop_all_services_routine &>/dev/null;
then
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
    local current
    current=$(npm config get registry 2>/dev/null)
    echo -e "当前源: ${CYAN}$current${NC}"; echo ""
    local OPTS=("淘宝源 (npmmirror)|https://registry.npmmirror.com/" "腾讯源|https://mirrors.cloud.tencent.com/npm/" "官方源|https://registry.npmjs.org/")
    local MENU_OPTS=(); local URLS=()
    for item in "${OPTS[@]}"; do MENU_OPTS+=("${item%%|*}"); URLS+=("${item#*|}"); done; MENU_OPTS+=("🔙 返回")
    local CHOICE
    CHOICE=$(ui_menu "选择镜像源" "${MENU_OPTS[@]}")
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
        if ui_confirm "运行一键换源脚本？"; then 
            if command -v curl &> /dev/null;
then
                 bash <(curl -sSL https://linuxmirrors.cn/main.sh)
            else
                 ui_print error "缺 curl"
            fi
        fi
    fi; ui_pause
}

clean_git_remotes() {
    ui_header "Git 仓库源清洗"
    if ! ui_confirm "重置所有组件更新源为 GitHub 官方地址？"; then return; fi
    ui_print info "正在修复..."
    
    local st_path
    st_path=$(get_app_path "sillytavern")
    reset_to_official_remote "$TAVX_DIR" "Future-404/TAV-X.git" && echo -e "  - TAV-X: OK"
    [ -d "$st_path" ] && reset_to_official_remote "$st_path" "SillyTavern/SillyTavern.git" && echo -e "  - SillyTavern: OK"
    
    ui_print success "修复完成。"; ui_pause
}

configure_download_network() {
    while true; do
        ui_header "网络与软件源配置"
        local curr_mode="自动"
        if [ -f "$NETWORK_CONFIG" ]; then
            local c
            c=$(cat "$NETWORK_CONFIG")
            curr_mode="${c#*|}"
        fi
        echo -e "当前策略: ${CYAN}$curr_mode${NC}"; echo "----------------------------------------"
        local OPTS=("🔧 自定义下载代理" "🔄 重置网络设置" "♻️  修复 Git 仓库源" "🐍 更换 PIP 源" "📦 更换 NPM 源" "🐧 更换系统源" "🔙 返回")
        local CHOICE
        CHOICE=$(ui_menu "选择操作" "${OPTS[@]}")
        case "$CHOICE" in
            *"自定义"*) 
                local url
                url=$(ui_input "输入代理 (如 http://127.0.0.1:7890)" "" "false")
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

clean_system_garbage() {
    ui_header "系统垃圾清理"
    echo -e "准备清理以下内容："
    echo -e "  1. 系统临时文件 ($TMP_DIR/tavx_*)"
    echo -e "  2. 模块运行产生的旧日志 (logs/*.log)"
    echo ""
    
    if ! ui_confirm "确认立即清理？"; then return; fi
    
    ui_spinner "正在清理..." "
        source \"$TAVX_DIR/core/utils.sh\"
        # 1. 清理传统日志 (Legacy & Linux)
        safe_rm \"$LOGS_DIR\"/*.log
        
        # 2. 清理服务归档日志 (Termux 专属)
        if [ \"$OS_TYPE\" == \"TERMUX\" ]; then
            # 使用 safe_rm 处理，虽然在 $PREFIX 下，但 safe_rm 允许删除子文件
            safe_rm \"$PREFIX/var/service\"/*/log/@* 2>/dev/null
        fi
        
        # 3. 清理临时文件
        safe_rm \"$TMP_DIR\"/tavx_* \"$TMP_DIR\"/*.log \"$TMP_DIR\"/gcli_wheels 2>/dev/null
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
    
    local md_content="
### 🌟 开发者心声

作为个人开发者，我想知道：
* **「是否真的有人在用？」** —— 这直接决定我是否继续维护它。
* **「大家在什么系统上用它？」** —— 这帮助我决定优先优化的方向。

---

### 🛡️ 数据隐私承诺

为此，我仅收集 **最基础** 的数据：
* ✅ 应用版本号
* ✅ 操作系统类型 (Android/Linux)

> **❌ 绝不收集：** 任何身份信息、位置、本地文件等个人隐私。
> 所有数据均已进行 **完全匿名与脱敏处理**。

你可以随时在源码中审查此逻辑：
[https://github.com/Future-404/TAV-X](https://github.com/Future-404/TAV-X)

---

**你的每一次使用，都是对我最大的鼓励。这份数据是我持续维护项目的关键动力。**

> ⚠️ **关闭后将导致...**
> 我将无法获知你的使用情况，这可能会让我误判项目已无人需要，从而影响后续更新。
"

    if [ "$HAS_GUM" = true ]; then
        echo "$md_content" | gum format
    else
        # Fallback for text mode
        echo -e "${YELLOW}作为个人开发者，我想知道：${NC}"
        echo -e " • ${CYAN}「是否真的有人在用？」${NC}"
        echo -e " • ${CYAN}「大家在什么系统上用它？」${NC}"
        echo ""
        echo -e "为此，我仅收集${GREEN}最基础${NC}的数据："
        echo -e " ${GREEN}✓${NC} 版本号与系统类型"
        echo -e " ${RED}✗ 绝不收集隐私信息${NC}"
        echo ""
        echo -e "你的支持是我更新的动力。"
        echo "----------------------------------"
    fi
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

manage_autorun_services() {
    [ "$OS_TYPE" != "TERMUX" ] && { ui_print error "此功能仅支持 Termux 环境。"; ui_pause; return; }
    
    while true; do
        ui_header "开机自启管理"
        echo -e "${YELLOW}说明：${NC}被标记为 [X] 的服务将在打开 Termux 时自动启动。"
        echo "----------------------------------------"
        
        local sv_base="$PREFIX/var/service"
        local sv_list=()
        local sv_paths=()
        
        if [ -d "$sv_base" ]; then
            for s in "$sv_base"/*; do
                [ ! -d "$s" ] && continue
                if [ -f "$s/.tavx_managed" ]; then
                    local sname
                    sname=$(basename "$s")
                    local state="[X]"
                    if [ -f "$s/down" ]; then state="[ ]"; fi
                    
                    sv_list+=("$state $sname")
                    sv_paths+=("$s")
                fi
            done
        fi
        
        if [ ${#sv_list[@]} -eq 0 ]; then
            ui_print warn "暂无受管服务。"
            ui_pause; return
        fi
        
        sv_list+=("🔙 返回")
        
        local CHOICE
        CHOICE=$(ui_menu "点击切换状态" "${sv_list[@]}")
        if [[ "$CHOICE" == *"返回"* ]]; then return; fi
        
        local selected_name
        selected_name=$(echo "$CHOICE" | awk '{print $NF}')
        local idx=-1
        
        for i in "${!sv_paths[@]}"; do
            if [[ "$(basename "${sv_paths[$i]}")" == "$selected_name" ]]; then
                idx=$i; break
            fi
        done
        
        if [ "$idx" -ge 0 ]; then
            local s_path="${sv_paths[$idx]}"
            if [ -f "$s_path/down" ]; then
                rm -f "$s_path/down"
                ui_print success "已启用自启: $selected_name"
            else
                touch "$s_path/down"
                ui_print warn "已禁用自启: $selected_name"
            fi
            sleep 0.5
        fi
    done
}

change_ui_mode() {
    ui_header "界面模式切换"
    echo -e "当前模式: $([ "$HAS_GUM" = true ] && echo "图形化" || echo "纯文本")"
    echo ""
    echo -e "${YELLOW}说明：${NC}"
    echo -e "  图形化模式：更美观，支持方向键选择，但在部分终端可能乱码。"
    echo -e "  纯文本模式：兼容性最好，使用数字键选择。"
    echo ""

    local CHOICE
    CHOICE=$(ui_menu "请选择模式" "🎨 图形化模式" "📝 纯文本模式" "🔙 返回")
    
    local NEW_MODE=""
    case "$CHOICE" in
        *"图形化"*) NEW_MODE="gum" ;; 
        *"纯文本"*) NEW_MODE="text" ;; 
        *"返回"*) return ;; 
    esac
    
    if [ -n "$NEW_MODE" ]; then
        local CONFIG_ENV="$TAVX_DIR/config/settings.env"
        if [ "$NEW_MODE" == "gum" ] && ! command -v gum &>/dev/null;
then
            ui_print error "未检测到 gum 组件，无法启用图形化模式。"
            return
        fi
        if [ ! -f "$CONFIG_ENV" ]; then touch "$CONFIG_ENV"; fi
        if grep -q "^UI_MODE=" "$CONFIG_ENV"; then
            sed -i "s/^UI_MODE=.*/UI_MODE=$NEW_MODE/" "$CONFIG_ENV"
        else
            echo "UI_MODE=$NEW_MODE" >> "$CONFIG_ENV"
        fi
        
        ui_print success "设置已保存！重启脚本后生效。"
        ui_pause
    fi
}

show_lan_info() {
    while true; do
        ui_header "局域网信息"
        
        local ip
        ip=$(get_local_ip)
        
        echo -e "${YELLOW}您的设备 IP 地址:${NC}"
        echo -e "  ${GREEN}${ip}${NC}"
        echo ""
        echo -e "${CYAN}💡 提示:${NC}"
        echo -e "  要让其他设备访问，请确保您的应用已配置为监听 ${YELLOW}0.0.0.0${NC}。"
        echo -e "  如果是 SillyTavern，默认通常已开启。"
        echo -e "  局域网访问地址格式通常为: http://$ip:端口号"
        echo "----------------------------------------"
        
        local OPTS=("🔄 刷新 IP" "🔙 返回")
        local CHOICE
        CHOICE=$(ui_menu "操作" "${OPTS[@]}")
        
        if [[ "$CHOICE" == *"返回"* ]]; then return; fi
    done
}

system_settings_menu() {
    while true; do
        ui_header "系统设置"
        local OPTS=(
            "🏠 查看局域网信息"
            "📥 下载源与代理配置"
            "🚀 开机自启管理"
            "🎨 界面模式切换"
            "🐍 Python环境管理"
            "🐧 Debian 容器管理"
            "📱 ADB智能助手"
            "📊 匿名统计开关"
            "🧹 系统垃圾清理"
            "💥 一键彻底毁灭 (危险)"
            "🔙 返回主菜单"
        )
        local CHOICE
        CHOICE=$(ui_menu "请选择功能" "${OPTS[@]}")
        case "$CHOICE" in
            *"局域网"*) show_lan_info ;; 
            *"下载源"*) configure_download_network ;; 
            *"自启"*) manage_autorun_services ;; 
            *"界面"*) change_ui_mode ;; 
            *"Python"*) 
                source "$TAVX_DIR/core/python_utils.sh"
                python_environment_manager_ui ;; 
            *"Debian"*)
                proot_settings_menu ;;
            *"ADB"*) 
                source "$TAVX_DIR/core/adb_utils.sh"
                adb_manager_ui ;; 
            *"统计"*) configure_analytics ;; 
            *"清理"*) clean_system_garbage ;; 
            *"彻底毁灭"*) full_wipe ;; 
            *"返回"*) return ;; 
        esac
    done
}
