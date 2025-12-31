#!/bin/bash
# TAV-X Core: Security & System Config

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

NETWORK_CONFIG="$TAVX_DIR/config/network.conf"
MEMORY_CONFIG="$TAVX_DIR/config/memory.conf"

configure_server_settings() {
    [ ! -f "$INSTALL_DIR/config.yaml" ] && { ui_print error "配置文件不存在，请先安装酒馆。"; ui_pause; return; }

    local CONFIG_MAP=(
        "SEPARATOR|--- 基础连接设置 ---"
        "listen|允许外部网络连接 (0.0.0.0)"
        "whitelistMode|白名单模式 (限制IP访问)"
        "basicAuthMode|强制密码登录 (BasicAuth)"
        "enableUserAccounts|多用户账号系统"
        "enableDiscreetLogin|谨慎登录模式 (隐藏用户名)"
        
        "SEPARATOR|--- 网络与安全进阶 ---"
        "disableCsrfProtection|禁用 CSRF 保护 (解决跨域报错)"
        "enableCorsProxy|启用 CORS 代理 (允许外部前端)"
        "protocol.ipv6|启用 IPv6 协议支持"
        "ssl.enabled|启用 SSL/HTTPS"
        "hostWhitelist.enabled|Host 头白名单检查"

        "SEPARATOR|--- 性能与更新优化 ---"
        "performance.lazyLoadCharacters|懒加载角色卡 (极大提升启动速度)"
        "performance.useDiskCache|启用硬盘缓存 (DiskCache)"
        "extensions.enabled|加载扩展插件"
        "extensions.autoUpdate|自动更新扩展 (建议关闭)"
        "enableServerPlugins|加载服务端插件"
        "enableServerPluginsAutoUpdate|自动更新服务端插件"

        "SEPARATOR|--- 危险区域 ---"
        "RESET_CONFIG|⚠️ 恢复默认配置 (删除当前文件)"
    )

    while true; do
        ui_header "核心参数配置"
        echo -e "${CYAN}点击条目即可切换状态${NC}"
        echo "----------------------------------------"

        local MENU_OPTS=()
        local KEY_LIST=()
        
        for item in "${CONFIG_MAP[@]}"; do
            local key="${item%%|*}"
            local label="${item#*|}"
            if [ "$key" == "SEPARATOR" ]; then
                MENU_OPTS+=("📂 $label")
                KEY_LIST+=("SEPARATOR")
                continue
            fi
            if [ "$key" == "RESET_CONFIG" ]; then
                MENU_OPTS+=("💥 $label")
                KEY_LIST+=("RESET_CONFIG")
                continue
            fi
            
            local val=$(config_get "$key")
            local icon="🔴"
            local stat="[关闭]"
            
            if [ "$val" == "true" ]; then
                icon="🟢"
                stat="[开启]"
            fi
            
            if [[ "$key" == "whitelistMode" || "$key" == "performance.useDiskCache" ]]; then
                if [ "$val" == "true" ]; then icon="🟡"; fi
            fi
            
            if [[ "$key" == *"autoUpdate"* || "$key" == *"AutoUpdate"* ]]; then
                 if [ "$val" == "true" ]; then icon="🟡"; fi
            fi

            MENU_OPTS+=("$icon $label $stat")
            KEY_LIST+=("$key")
        done
        
        MENU_OPTS+=("🔙 返回上级")

        local CHOICE_IDX
        if [ "$HAS_GUM" = true ]; then
            local SELECTED_TEXT=$(gum choose "${MENU_OPTS[@]}" --header "" --cursor.foreground 212)
            for i in "${!MENU_OPTS[@]}"; do
                if [[ "${MENU_OPTS[$i]}" == "$SELECTED_TEXT" ]]; then CHOICE_IDX=$i; break; fi
            done
        else
            local i=1
            for opt in "${MENU_OPTS[@]}"; do echo "$i. $opt"; ((i++)); done
            read -p "请输入序号: " input_idx
            if [[ "$input_idx" =~ ^[0-9]+$ ]]; then
                CHOICE_IDX=$((input_idx - 1))
            fi
        fi

        if [[ "${MENU_OPTS[$CHOICE_IDX]}" == *"返回"* ]]; then
            return
        fi

        if [ -n "$CHOICE_IDX" ] && [ "$CHOICE_IDX" -ge 0 ] && [ "$CHOICE_IDX" -lt "${#KEY_LIST[@]}" ]; then
            local target_key="${KEY_LIST[$CHOICE_IDX]}"
            if [ "$target_key" == "SEPARATOR" ]; then continue; fi
            if [ "$target_key" == "RESET_CONFIG" ]; then
                echo ""
                echo -e "${RED}警告：此操作将彻底删除当前的 config.yaml 文件！${NC}"
                echo -e "所有自定义设置都将丢失，酒馆下次启动时会生成全新的默认配置。"
                echo ""
                if ui_confirm "确定要执行恢复出厂设置吗？"; then
                    rm -f "$INSTALL_DIR/config.yaml"
                    ui_print success "配置文件已删除。"
                    echo -e "${YELLOW}请前往 [🚀 启动服务] -> [本地启动] 以生成新配置。${NC}"
                    ui_pause
                    return
                fi
                continue
            fi

            local current_val=$(config_get "$target_key")
            local new_val="true"
            
            if [ "$current_val" == "true" ]; then new_val="false"; fi
            
            if config_set "$target_key" "$new_val"; then
                sleep 0.1
            fi
        fi
    done
}

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
        ui_pause; return
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

change_pip_source() {
    ui_header "PIP 源配置 (Python)"
    local current=$(pip config get global.index-url 2>/dev/null)
    [ -z "$current" ] && current="官方源 (默认)"
    echo -e "当前源: ${CYAN}$current${NC}"
    echo ""

    local OPTIONS=(
        "清华源|https://pypi.tuna.tsinghua.edu.cn/simple"
        "阿里源|https://mirrors.aliyun.com/pypi/simple/"
        "腾讯源|https://mirrors.cloud.tencent.com/pypi/simple"
        "官方源|https://pypi.org/simple"
    )

    local MENU_OPTS=()
    local URLS=()
    for item in "${OPTIONS[@]}"; do
        MENU_OPTS+=("${item%%|*}")
        URLS+=("${item#*|}")
    done
    MENU_OPTS+=("🔙 返回")

    local CHOICE=$(ui_menu "选择镜像源" "${MENU_OPTS[@]}")
    
    if [[ "$CHOICE" == *"返回"* ]]; then return; fi

    local TARGET_URL=""
    for i in "${!MENU_OPTS[@]}"; do
        if [[ "${MENU_OPTS[$i]}" == "$CHOICE" ]]; then TARGET_URL="${URLS[$i]}"; break; fi
    done

    if [ -n "$TARGET_URL" ]; then
        if pip config set global.index-url "$TARGET_URL"; then
            ui_print success "PIP 源已设置为: $CHOICE"
        else
            ui_print error "设置失败，请检查 pip 是否安装。"
        fi
    fi
    ui_pause
}

change_npm_source() {
    ui_header "NPM 源配置 (Node.js)"
    local current=$(npm config get registry 2>/dev/null)
    echo -e "当前源: ${CYAN}$current${NC}"
    echo ""

    local OPTIONS=(
        "淘宝源 (npmmirror)|https://registry.npmmirror.com/"
        "腾讯源|https://mirrors.cloud.tencent.com/npm/"
        "官方源|https://registry.npmjs.org/"
    )

    local MENU_OPTS=()
    local URLS=()
    for item in "${OPTIONS[@]}"; do
        MENU_OPTS+=("${item%%|*}")
        URLS+=("${item#*|}")
    done
    MENU_OPTS+=("🔙 返回")

    local CHOICE=$(ui_menu "选择镜像源" "${MENU_OPTS[@]}")
    
    if [[ "$CHOICE" == *"返回"* ]]; then return; fi

    local TARGET_URL=""
    for i in "${!MENU_OPTS[@]}"; do
        if [[ "${MENU_OPTS[$i]}" == "$CHOICE" ]]; then TARGET_URL="${URLS[$i]}"; break; fi
    done

    if [ -n "$TARGET_URL" ]; then
        if npm config set registry "$TARGET_URL"; then
            ui_print success "NPM 源已设置为: $CHOICE"
        else
            ui_print error "设置失败，请检查 npm 是否安装。"
        fi
    fi
    ui_pause
}

change_system_source() {
    ui_header "系统软件源配置"
    
    if [ "$OS_TYPE" == "TERMUX" ]; then
        if command -v termux-change-repo &> /dev/null; then
            ui_print info "正在启动 Termux 官方换源工具..."
            sleep 1
            termux-change-repo
        else
            ui_print error "未找到 termux-change-repo 工具。"
        fi
    else
        echo -e "${YELLOW}Linux 一键换源 (推荐使用 LinuxMirrors)${NC}"
        echo -e "此脚本由 LinuxMirrors 开源项目 provide，支持 Debian/Ubuntu/CentOS 等主流系统。"
        echo -e "它可以自动检测系统版本并替换为最快的国内源。"
        echo ""
        
        if ui_confirm "是否运行一键换源脚本？"; then
            if command -v curl &> /dev/null; then
                bash <(curl -sSL https://linuxmirrors.cn/main.sh)
            else
                ui_print error "未找到 curl，请先安装: sudo apt install curl"
            fi
        fi
    fi
    ui_pause
}

clean_git_remotes() {
    ui_header "Git 仓库源清洗"
    echo -e "${YELLOW}此功能将把所有组件的更新源重置为 GitHub 官方地址。${NC}"
    echo -e "用途：修复因镜像站失效导致的 'git pull' 报错。"
    echo -e "影响范围：脚本自身、SillyTavern 本体、所有已安装插件。"
    echo ""
    
    if ! ui_confirm "确认执行清洗吗？"; then return; fi
    
    echo ""
    ui_print info "正在扫描并修复..."
    
    local count=0
    
    if reset_to_official_remote "$TAVX_DIR" "Future-404/TAV-X.git"; then
        echo -e "  - TAV-X: ${GREEN}OK${NC}"
        ((count++))
    fi
    
    if reset_to_official_remote "$INSTALL_DIR" "SillyTavern/SillyTavern.git"; then
        echo -e "  - SillyTavern: ${GREEN}OK${NC}"
        ((count++))
    fi
    
    local plugin_dirs=("$INSTALL_DIR/plugins" "$INSTALL_DIR/public/scripts/extensions/third-party")
    
    for p_root in "${plugin_dirs[@]}"; do
        if [ -d "$p_root" ]; then
            for d in "$p_root"/*;
 do
                if [ -d "$d/.git" ]; then
                    (
                        cd "$d" || exit
                        local curr_url=$(git remote get-url origin 2>/dev/null)
                        if [[ "$curr_url" == *"https://github.com/"* ]] || [[ "$curr_url" == *"http://github.com/"* ]]; then
                            local clean_path=${curr_url#*github.com/}
                            local new_url="https://github.com/${clean_path}"
                            
                            if [ "$curr_url" != "$new_url" ]; then
                                git remote set-url origin "$new_url"
                                echo -e "  - $(basename "$d"): ${GREEN}Fixed${NC}"
                                ((count++))
                            fi
                        fi
                    )
                fi
            done
        fi
    done
    
    echo ""
    ui_print success "修复完成！共处理 $count 个仓库。"
    echo -e "${YELLOW}提示：今后更新时，脚本会自动使用动态镜像加速。${NC}"
    ui_pause
}

configure_download_network() {
    while true; do
        ui_header "网络与软件源配置"
        local curr_mode="自动 (智能自愈)"
        if [ -f "$NETWORK_CONFIG" ]; then
            local c=$(cat "$NETWORK_CONFIG"); curr_mode="${c#*|}"
            [ ${#curr_mode} -gt 30 ] && curr_mode="${curr_mode:0:28}..."
        fi
        echo -e "下载代理策略: ${CYAN}$curr_mode${NC}"
        echo "----------------------------------------"

        CHOICE=$(ui_menu "请选择操作" \
            "🔧 配置自定义代理" \
            "🔄 重置为自动模式" \
            "♻️  修复 Git 仓库源" \
            "🐍 更换 PIP 源" \
            "📦 更换 NPM 源" \
            "🐧 更换系统源" \
            "🔙 返回" 
        )

        case "$CHOICE" in
            *"自定义"*) 
                local url=$(ui_input "输入代理 (如 http://127.0.0.1:7890)" "" "false")
                if [[ "$url" =~ ^(http|https|socks5|socks5h)://.* ]]; then 
                    echo "PROXY|$url" > "$NETWORK_CONFIG"
                    ui_print success "已保存自定义代理。"
                else 
                    ui_print error "格式错误，请包含协议头 (如 socks5://)"
                fi
                ui_pause ;; 
            *"重置"*) 
                if [ -f "$NETWORK_CONFIG" ]; then
                    rm -f "$NETWORK_CONFIG"
                    ui_print success "配置文件已清除。"
                fi
                unset SELECTED_MIRROR
                ui_print success "网络策略已重置为自动模式。"
                ui_pause ;; 
            
            *"修复 Git"*) clean_git_remotes ;; 
            
            *"PIP"*) change_pip_source ;; 
            *"NPM"*) change_npm_source ;; 
            *"系统源"*) change_system_source ;; 
            *"返回"*) return ;; 
        esac
    done
}

change_port() {
    ui_header "修改端口"
    
    CURR=$(config_get port)
    
    if [[ -z "$CURR" ]] || [[ "$CURR" == "-1" ]]; then
        ui_print error "配置文件异常：无法获取有效端口号 ($CURR)。"
        ui_print warn "请检查 config.yaml 格式是否正确。"
        ui_pause
        return
    fi
    
    local new=$(ui_input "输入新端口 (1024-65535)" "$CURR" "false")
    
    if [[ "$new" =~ ^[0-9]+$ ]] && [ "$new" -ge 1024 ] && [ "$new" -le 65535 ]; then
        config_set port "$new"
        ui_print success "端口已改为 $new"
    else 
        ui_print error "无效端口"
    fi
    ui_pause
}

reset_password() {
    ui_header "重置密码"
    [ ! -d "$INSTALL_DIR" ] && { ui_print error "未安装酒馆"; ui_pause; return; }
    
    cd "$INSTALL_DIR" || return
    config_set enableUserAccounts true
    
    [ ! -f "recover.js" ] && { ui_print error "recover.js 丢失"; ui_pause; return; }
    echo -e "${YELLOW}用户列表:${NC}"; ls -F data/ | grep "/" | grep -v "^_" | sed 's/\///g' | sed 's/^/  - /'
    local u=$(ui_input "用户名" "default-user" "false"); local p=$(ui_input "新密码" "" "false")
    [ -z "$p" ] && ui_print warn "密码为空" || { echo ""; node recover.js "$u" "$p"; echo ""; ui_print success "已重置"; }
    ui_pause
}

configure_api_proxy() {
    while true; do
        ui_header "API 代理配置"
        local is_enabled=$(config_get requestProxy.enabled)
        local current_url=$(config_get requestProxy.url)
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
                        config_set requestProxy.enabled true 
                        config_set requestProxy.url "$v" 
                        ui_print success "同步成功: $v"
                    else 
                        ui_print warn "系统非代理模式"
                    fi
                else 
                    local dyn=$(get_active_proxy)
                    if [ -n "$dyn" ]; then
                        config_set requestProxy.enabled true 
                        config_set requestProxy.url "$dyn" 
                        ui_print success "自动探测并应用: $dyn"
                    else
                        ui_print warn "未检测到本地代理"
                    fi
                fi 
                ui_pause ;; 
            *"手动"*) 
                i=$(ui_input "代理地址" "" "false")
                if [[ "$i" =~ ^http.* ]]; then 
                    config_set requestProxy.enabled true 
                    config_set requestProxy.url "$i" 
                    ui_print success "已保存并开启"
                else 
                    ui_print error "格式错误"
                fi 
                ui_pause ;; 
            *"关闭"*) 
                config_set requestProxy.enabled false 
                ui_print success "已关闭代理连接";
                ui_pause ;; 
            *"返回"*) return ;; 
        esac
    done
}

configure_cf_token() {
    ui_header "Cloudflare Tunnel Token"
    local token_file="$TAVX_DIR/config/cf_token"
    
    local current_stat="${YELLOW}未配置 (使用临时隧道)${NC}"
    if [ -f "$token_file" ] && [ -s "$token_file" ]; then
        local t=$(cat "$token_file")
        current_stat="${GREEN}已配置${NC} (${t:0:6}......)"
    fi

    echo -e "当前状态: $current_stat"
    echo "----------------------------------------"
    echo -e "说明: 使用 Token 可绑定自定义域名，连接更稳定。"
    echo -e "请在 Cloudflare Zero Trust 后台获取 Tunnel Token。"
    echo ""

    CHOICE=$(ui_menu "请选择操作" "✏️ 输入/更新 Token" "🗑️ 清除 Token (恢复默认)" "🔙 返回")

    case "$CHOICE" in
        *"输入"*) 
            local input=$(ui_input "请粘贴 Token" "" "false")
            if [ -n "$input" ]; then
                echo "$input" > "$token_file"
                ui_print success "Token 已保存！"
            fi
            ui_pause ;; 
        *"清除"*) 
            rm -f "$token_file"
            ui_print success "Token 已清除，已恢复为临时隧道模式。"
            ui_pause ;; 
        *"返回"*) return ;; 
    esac
}

security_menu() {
    while true; do
        ui_header "系统设置"
        CHOICE=$(ui_menu "请选择功能" \
            "⚙️  核心参数配置" \
            "🧠 配置运行内存" \
            "📥 下载网络配置" \
            "🌐 配置API代理" \
            "☁️  配置Cloudflare Token" \
            "🔐 重置登录密码" \
            "🔌 修改服务端口" \
            "🧨 卸载与重置" \
            "🔙 返回主菜单"
        )
        case "$CHOICE" in
            *"核心参数"*) configure_server_settings ;; 
            *"内存"*) configure_memory ;; 
            *"下载"*) configure_download_network ;; 
            *"API"*) configure_api_proxy ;; 
            *"Cloudflare"*) configure_cf_token ;; 
            *"密码"*) reset_password ;; 
            *"端口"*) change_port ;; 
            *"卸载"*) uninstall_menu ;; 
            *"返回"*) return ;; 
        esac
    done
}