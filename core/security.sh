#!/bin/bash
# TAV-X Core: Security & System Config (V6.6 Uninstall Added)

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

JS_TOOL="$TAVX_DIR/scripts/config_mgr.js"
NETWORK_CONFIG="$TAVX_DIR/config/network.conf"
MEMORY_CONFIG="$TAVX_DIR/config/memory.conf"

configure_memory() {
    ui_header "运行内存配置 (Memory Tuning)"
    
    local mem_info=$(free -m | grep "Mem:")
    local total_mem=$(echo "$mem_info" | awk '{print $2}')
    local avail_mem=$(echo "$mem_info" | awk '{print $7}')
    
    [[ -z "$total_mem" ]] && total_mem=0
    [[ -z "$avail_mem" ]] && avail_mem=0
    
    local safe_max=$((total_mem - 2048))
    if [ "$safe_max" -lt 1024 ]; then safe_max=1024; fi
    
    local curr_set="默认 (Node.js Auto)"
    if [ -f "$MEMORY_CONFIG" ]; then
        curr_set="$(cat "$MEMORY_CONFIG") MB"
    fi

    echo -e "${CYAN}当前设备内存状态:${NC}"
    echo -e "📦 总物理内存: ${GREEN}${total_mem} MB${NC}"
    echo -e "🟢 当前可用量: ${YELLOW}${avail_mem} MB${NC} (剩余)"
    echo -e "⚙️ 当前配置值: ${PURPLE}${curr_set}${NC}"
    echo "----------------------------------------"
    echo -e "${YELLOW}推荐设置:${NC}"
    echo -e "• 4096 (4GB) - 均衡选择，适合大多数情况"
    echo -e "• $safe_max (Max) - 理论极限，超过此值易被杀后台"
    echo "----------------------------------------"
    
    echo -e "请输入分配给酒馆的最大内存 (单位 MB)"
    echo -e "输入 ${RED}0${NC} 恢复默认，输入具体数字自定义。"
    
    local input_mem=$(ui_input "请输入 (例如 4096)" "" "false")
    
    if [[ ! "$input_mem" =~ ^[0-9]+$ ]]; then
        ui_print error "请输入有效的数字。"
        ui_pause
        return
    fi
    
    if [ "$input_mem" -eq 0 ]; then
        rm -f "$MEMORY_CONFIG"
        ui_print success "已恢复默认内存策略。"
    else
    
        if [ "$input_mem" -gt "$safe_max" ]; then
            ui_print warn "注意：设定值 ($input_mem) 接近或超过物理极限 ($total_mem)！"
            if ! ui_confirm "这可能导致 Termux 崩溃，确定要继续吗？"; then
                ui_pause; return
            fi
        elif [ "$input_mem" -gt "$avail_mem" ]; then
            ui_print warn "提示：设定值大于当前可用内存，系统可能会使用 Swap。"
        fi
        
        echo "$input_mem" > "$MEMORY_CONFIG"
        ui_print success "已设置最大内存: ${input_mem} MB"
    fi
    ui_pause
}

configure_download_network() {
    ui_header "下载网络配置"
    local curr_mode="自动/未配置"
    if [ -f "$NETWORK_CONFIG" ]; then
        local c=$(cat "$NETWORK_CONFIG"); curr_mode="${c#*|}"
        [ ${#curr_mode} -gt 30 ] && curr_mode="${curr_mode:0:28}..."
    fi
    echo -e "当前策略: ${CYAN}$curr_mode${NC}\n"

    CHOICE=$(ui_menu "请选择模式" "🤖 智能优选 (Smart Auto)" "🔧 自定义代理 (Custom Proxy)" "🔙 返回")

    case "$CHOICE" in
        *"智能"*)
            CMD="source $TAVX_DIR/core/utils.sh; 
                 p=\$(get_dynamic_proxy); 
                 if [ -n \"\$p\" ]; then echo \"PROXY|\$p\" > \"$NETWORK_CONFIG\"; exit 0; fi;
                 rm -f \"$NETWORK_CONFIG\"; exit 1"
            
            if ui_spinner "扫描中..." "$CMD"; then
                [ -f "$NETWORK_CONFIG" ] && ui_print success "已更新: $(cat "$NETWORK_CONFIG" | cut -d'|' -f2)" || ui_print warn "重置默认。"
            else ui_print error "探测错误或无可用代理。"; fi
            ui_pause ;;
        *"自定义"*)
            local url=$(ui_input "输入代理 (如 http://127.0.0.1:7890)" "" "false")
            [[ "$url" =~ ^(http|https|socks5)://.* ]] && { echo "PROXY|$url" > "$NETWORK_CONFIG"; ui_print success "已保存"; } || ui_print error "格式错误"
            ui_pause ;;
    esac
}

optimize_config() {
    ui_header "系统设置优化"
    echo -e "${YELLOW}即将应用 Termux 最佳配置：${NC}\n  • 多用户验证 & 隐私登录\n  • 关闭磁盘缓存\n  • 开启懒加载 (性能优化)\n"
    if ui_confirm "确认执行优化？"; then
        ui_spinner "修改中..." "
            node '$JS_TOOL' set enableUserAccounts true
            node '$JS_TOOL' set enableDiscreetLogin true
            node '$JS_TOOL' set useDiskCache false
            node '$JS_TOOL' set lazyLoadCharacters true
            node '$JS_TOOL' set performance.lazyLoadCharacters true"
        ui_print success "优化完成！插件状态已保留。"
    else ui_print info "已取消。"; fi
    ui_pause
}

change_port() {
    ui_header "修改端口"
    CURR=$(node "$JS_TOOL" get port 2>/dev/null)
    local new=$(ui_input "输入新端口 (1024-65535)" "${CURR:-8000}" "false")
    if [[ "$new" =~ ^[0-9]+$ ]] && [ "$new" -ge 1024 ] && [ "$new" -le 65535 ]; then
        node "$JS_TOOL" set port "$new"; ui_print success "端口已改为 $new"
    else ui_print error "无效端口"; fi
    ui_pause
}

reset_password() {
    ui_header "重置密码"
    [ ! -d "$INSTALL_DIR" ] && { ui_print error "未安装酒馆"; ui_pause; return; }
    cd "$INSTALL_DIR" || return; node "$JS_TOOL" set enableUserAccounts true
    [ ! -f "recover.js" ] && { ui_print error "recover.js 丢失"; ui_pause; return; }
    echo -e "${YELLOW}用户列表:${NC}"; ls -F data/ | grep "/" | grep -v "^_" | sed 's/\///g' | sed 's/^/  - /'
    local u=$(ui_input "用户名" "default-user" "false"); local p=$(ui_input "新密码" "" "false")
    [ -z "$p" ] && ui_print warn "密码为空" || { echo ""; node recover.js "$u" "$p"; echo ""; ui_print success "已重置"; }
    ui_pause
}

configure_api_proxy() {
    while true; do
        ui_header "API 代理配置"
        local is_enabled=$(node "$JS_TOOL" get requestProxy.enabled 2>/dev/null)
        local current_url=$(node "$JS_TOOL" get requestProxy.url 2>/dev/null)
        [ -z "$current_url" ] && current_url="未设置"

        echo -e "当前配置状态："
        if [ "$is_enabled" == "true" ]; then
            echo -e "  🟢 状态: ${GREEN}已开启 (Enabled)${NC}"
            echo -e "  🔗 地址: ${CYAN}$current_url${NC}"
        else
            echo -e "  🔴 状态: ${RED}已关闭 (Disabled)${NC}"
            echo -e "  🔗 地址: ${CYAN}$current_url${NC} (未生效)"
        fi
        echo "----------------------------------------"

        CHOICE=$(ui_menu "请选择操作" "🔄 同步系统代理" "✏️ 手动输入" "🚫 关闭代理" "🔙 返回")
        
        case "$CHOICE" in
            *"同步"*)
                if [ -f "$NETWORK_CONFIG" ]; then
                    c=$(cat "$NETWORK_CONFIG")
                    if [[ "$c" == PROXY* ]]; then 
                        v=${c#*|}; v=$(echo "$v"|tr -d '\n\r'); 
                        node "$JS_TOOL" set requestProxy.enabled true; 
                        node "$JS_TOOL" set requestProxy.url "$v"; 
                        ui_print success "同步成功: $v"
                    else 
                        ui_print warn "系统非代理模式"
                    fi
                else 
                    local dyn=$(get_dynamic_proxy)
                    if [ -n "$dyn" ]; then
                        node "$JS_TOOL" set requestProxy.enabled true; 
                        node "$JS_TOOL" set requestProxy.url "$dyn"; 
                        ui_print success "自动探测并应用: $dyn"
                    else
                        ui_print warn "未检测到本地代理"
                    fi
                fi 
                ui_pause ;;
            *"手动"*)
                i=$(ui_input "代理地址" "" "false")
                if [[ "$i" =~ ^http.* ]]; then 
                    node "$JS_TOOL" set requestProxy.enabled true; 
                    node "$JS_TOOL" set requestProxy.url "$i"; 
                    ui_print success "已保存并开启"
                else 
                    ui_print error "格式错误"
                fi 
                ui_pause ;;
            *"关闭"*) 
                node "$JS_TOOL" set requestProxy.enabled false; 
                ui_print success "已关闭代理连接";
                ui_pause ;;
            *"返回"*) return ;;
        esac
    done
}

security_menu() {
    while true; do
        ui_header "系统设置"
        CHOICE=$(ui_menu "请选择功能" \
            "🚀 一键系统优化" \
            "🧠 配置运行内存" \
            "📥 下载网络配置" \
            "🌐 配置API代理" \
            "🔐 重置登录密码" \
            "🔌 修改服务端口" \
            "🧨 卸载与重置" \
            "🔙 返回主菜单"
        )
        case "$CHOICE" in
            *"优化"*) optimize_config ;;
            *"内存"*) configure_memory ;; 
            *"下载"*) configure_download_network ;;
            *"API"*) configure_api_proxy ;;
            *"密码"*) reset_password ;;
            *"端口"*) change_port ;;
            *"卸载"*) uninstall_menu ;;
            *"返回"*) return ;;
        esac
    done
}
