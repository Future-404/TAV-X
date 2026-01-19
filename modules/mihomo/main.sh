#!/bin/bash
# [METADATA]
# MODULE_ID: mihomo
# MODULE_NAME: Mihomo 代理核心
# MODULE_ENTRY: mihomo_menu
# APP_CATEGORY: 网络与代理
# APP_AUTHOR: MetaCubeX
# APP_PROJECT_URL: https://github.com/MetaCubeX/mihomo
# APP_DESC: Mihomo (原 Clash.Meta) 是一个基于 Go 语言开发的轻量级代理核心，兼容 Clash 配置格式。它支持多种代理协议和高级规则匹配，是目前性能最强、功能最丰富的 Clash 内核分支。
# [END_METADATA]

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

_mihomo_vars() {
    MIHOMO_APP_ID="mihomo"
    MIHOMO_DIR=$(get_app_path "$MIHOMO_APP_ID")
    MIHOMO_BIN="$MIHOMO_DIR/mihomo"
    MIHOMO_CONF="$MIHOMO_DIR/config.yaml"
    MIHOMO_LOG="$LOGS_DIR/mihomo.log"
    MIHOMO_PID="$RUN_DIR/mihomo.pid"
    MIHOMO_SUBS="$CONFIG_DIR/mihomo_subs.list"
    MIHOMO_SECRET_CONF="$CONFIG_DIR/mihomo_secret.conf"
    MIHOMO_PATCH="$CONFIG_DIR/mihomo_patch.yaml"
    MIHOMO_VER="v1.19.18"
}

mihomo_install() {
    _mihomo_vars
    ui_header "安装/更新 Mihomo Core"
    mkdir -p "$MIHOMO_DIR"
    
    local arch=$(uname -m)
    local dl_arch="amd64"
    [[ "$arch" == "aarch64" || "$arch" == "arm64" ]] && dl_arch="arm64"

    local filename="mihomo-linux-${dl_arch}-${MIHOMO_VER}.gz"
    local url="https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_VER}/${filename}"
    local tmp_gz="$TMP_DIR/$filename"
    
    local CMD="source '$TAVX_DIR/core/utils.sh'; download_file_smart '$url' '$tmp_gz' 'true' && gzip -d -f '$tmp_gz' && mv '${tmp_gz%.gz}' '$MIHOMO_BIN' && chmod +x '$MIHOMO_BIN'"

    if ! ui_stream_task "正在部署核心二进制..." "$CMD"; then
        ui_print error "下载失败。"
        return 1
    fi

    local ui_dir="$MIHOMO_DIR/ui"
    if [ ! -d "$ui_dir" ]; then
        ui_print info "正在部署本地 WebUI..."
        sys_install_pkg "unzip"
        local ui_url="https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip"
        local tmp_ui="$TMP_DIR/ui.zip"
        local UI_CMD="source '$TAVX_DIR/core/utils.sh'; download_file_smart '$ui_url' '$tmp_ui' 'true' && unzip -o '$tmp_ui' -d '$MIHOMO_DIR' && safe_rm '$tmp_ui'"
        
        if ui_stream_task "下载面板资源..." "$UI_CMD"; then
            local extracted_dir=$(find "$MIHOMO_DIR" -maxdepth 1 -type d -name "metacubexd-*" | head -n 1)
            [ -n "$extracted_dir" ] && mv "$extracted_dir" "$ui_dir"
            ui_print success "WebUI 已就绪。"
        fi
    fi
}

mihomo_start() {
    _mihomo_vars
    [ ! -f "$MIHOMO_BIN" ] && { mihomo_install || return 1; }
    
    if [ ! -s "$MIHOMO_SUBS" ]; then
        ui_print warn "尚未添加任何订阅。"
        return 1
    fi
    
    local secret=""
    [ -f "$MIHOMO_SECRET_CONF" ] && secret=$(cat "$MIHOMO_SECRET_CONF")
    
    mkdir -p "$MIHOMO_DIR/proxy_providers"
    cat > "$MIHOMO_CONF" <<EOF
port: 17890
socks-port: 17891
allow-lan: true
mode: rule
log-level: warning
external-controller: 0.0.0.0:19090
external-ui: ui
secret: "$secret"
EOF

    echo "proxy-providers:" >> "$MIHOMO_CONF"
    local provider_names=()
    local i=1
    while IFS= read -r url; do
        [[ -z "$url" || "$url" =~ ^# ]] && continue
        local name="Sub$i"
        provider_names+=("$name")
        cat >> "$MIHOMO_CONF" <<EOF
  $name:
    type: http
    url: "$url"
    path: ./proxy_providers/sub_$i.yaml
    interval: 3600
    proxy: DIRECT
    override:
      additional-http-headers:
        User-Agent: "ClashMeta"
    health-check:
      enable: true
      interval: 600
      url: http://www.gstatic.com/generate_204
EOF
        ((i++))
    done < "$MIHOMO_SUBS"

    local use_list=$(printf ", %s" "${provider_names[@]}")
    use_list=${use_list:2}
    
    cat >> "$MIHOMO_CONF" <<EOF
proxy-groups:
  - name: "🚀 节点选择"
    type: select
    use: [$use_list]
    proxies: [DIRECT]
rules:
  - MATCH,🚀 节点选择
EOF

    if [ -f "$MIHOMO_PATCH" ] && command -v yq &>/dev/null; then
        ui_print info "检测到自定义配置补丁，正在合并..."
        yq -i '. *= load("'$MIHOMO_PATCH'")' "$MIHOMO_CONF"
        
        if [ $? -eq 0 ]; then
            ui_print success "补丁应用成功。"
        else
            ui_print error "补丁应用失败，请检查 YAML 语法。"
        fi
    fi

    mihomo_stop
    
    ui_print info "正在启动 Mihomo 核心服务..."
    
    if [ "$OS_TYPE" == "TERMUX" ]; then
        tavx_service_register "mihomo" "./mihomo -d ." "$MIHOMO_DIR"
        tavx_service_control "up" "mihomo"
        ui_print success "服务启动命令已发送。"
    else
        cd "$MIHOMO_DIR" || return 1
        echo "--- Mihomo Start $(date) --- " > "$MIHOMO_LOG"
        local START_CMD="setsid ./mihomo -d . >> '$MIHOMO_LOG' 2>&1 & echo \$!"
        local new_pid=$(eval "$START_CMD")
        
        if [ -n "$new_pid" ]; then
            echo "$new_pid" > "$MIHOMO_PID"
            renice -n -5 -p "$new_pid" >/dev/null 2>&1
            
            sleep 2
            if check_process_smart "$MIHOMO_PID" "mihomo"; then
                ui_print success "核心服务启动成功！"
                echo -e "  - 控制面板: http://127.0.0.1:19090/ui"
                echo -e "  - 代理端口: 17890 (HTTP) / 17891 (SOCKS5)"
            else
                ui_print error "服务未能正常启动。"
                echo -e "${YELLOW}最后 10 行日志：${NC}"
                tail -n 10 "$MIHOMO_LOG"
            fi
        else
            ui_print error "系统进程创建失败。"
        fi
    fi
}

mihomo_stop() {
    _mihomo_vars
    if [ "$OS_TYPE" == "TERMUX" ]; then
        tavx_service_control "down" "mihomo"
    else
        kill_process_safe "$MIHOMO_PID" "mihomo" >/dev/null 2>&1
        pkill -9 -f "mihomo" >/dev/null 2>&1
        rm -f "$MIHOMO_PID"
    fi
}

mihomo_uninstall() {
    _mihomo_vars
    if verify_kill_switch; then
        mihomo_stop
        ui_spinner "清理文件中..." "safe_rm '$MIHOMO_DIR' '$MIHOMO_SUBS' '$MIHOMO_SECRET_CONF' '$MIHOMO_PID' '$MIHOMO_LOG' '$MIHOMO_PATCH'"
        ui_print success "卸载完成。"
        return 2
    fi
}

mihomo_menu() {
    while true; do
        _mihomo_vars
        ui_header "Mihomo 代理管理"
        local state="stopped"; local text="已停止"; local info=()
        local log_path="$MIHOMO_LOG"
        [ "$OS_TYPE" == "TERMUX" ] && log_path="$PREFIX/var/service/mihomo/log/current"

        if [ "$OS_TYPE" == "TERMUX" ]; then
            if sv status mihomo 2>/dev/null | grep -q "^run:"; then
                state="running"; text="运行中"
            fi
        elif check_process_smart "$MIHOMO_PID" "mihomo"; then
            state="running"; text="运行中"
        fi

        if [ "$state" == "running" ]; then
            info+=( "面板: http://127.0.0.1:19090/ui" "代理: 127.0.0.1:17890" )
        fi
        
        ui_status_card "$state" "$text" "${info[@]}"
        
        local CHOICE=$(ui_menu "操作菜单" "🚀 启动服务" "🛑 停止服务" "🔗 设置订阅" "🔧 高级配置" "🔑 设置密钥" "📊 打开面板" "📜 查看日志" "⚙️  更新核心" "🗑️  卸载模块" "ℹ️ 关于模块" "🔙 返回")
        case "$CHOICE" in
            *"启动"*) mihomo_start; ui_pause ;; 
            *"停止"*) mihomo_stop; ui_print success "已停止"; ui_pause ;; 
            *"订阅"*) 
                while true; do
                    ui_header "订阅管理"
                    local count=0; [ -f "$MIHOMO_SUBS" ] && count=$(grep -c "^http" "$MIHOMO_SUBS")
                    echo -e "当前已添加 ${CYAN}$count${NC} 个订阅地址"
                    echo "----------------------------------------"
                    local sub_opt=$(ui_menu "订阅操作" "➕ 添加新订阅" "📜 查看已添加" "🗑️  清空所有" "🔙 返回")
                    case "$sub_opt" in
                        *"➕"*)
                            local url=$(ui_input_validated "请输入订阅链接" "" "url")
                            [ -n "$url" ] && { echo "$url" >> "$MIHOMO_SUBS"; ui_print success "添加成功"; }
                            ;;
                        *"📜"*)
                            if [ -s "$MIHOMO_SUBS" ]; then
                                ui_header "已添加的订阅"
                                cat "$MIHOMO_SUBS" | sed 's/^/  🔗 /'
                            else
                                ui_print warn "目前没有任何订阅地址。"
                            fi
                            ui_pause
                            ;;
                        *"🗑️"*)
                            if ui_confirm "确定要删除所有订阅吗？"; then
                                safe_rm "$MIHOMO_SUBS"
                                ui_print success "已清空。"
                            fi
                            ;;
                        *) break ;;
                    esac
                done ;;
            *"高级"*)
                if [ ! -f "$MIHOMO_PATCH" ]; then
                    ui_print info "正在生成示例补丁文件..."
                    cat > "$MIHOMO_PATCH" <<EOF
# 此文件内容将在启动时合并到 config.yaml 中 
# 你可以在此覆盖默认设置，或添加自定义规则

# [示例] 开启 TUN 模式
# tun:
#   enable: true
#   stack: gvisor
#   auto-route: true
#   auto-detect-interface: true

# [示例] 自定义 DNS
# dns:
#   enable: true
#   ipv6: false
#   listen: 0.0.0.0:1053
#   nameserver:
#     - 223.5.5.5
#     - 119.29.29.29

# [示例] 自定义规则 (覆盖默认规则)
# rules:
#   - DOMAIN-SUFFIX,google.com,🚀 节点选择
#   - MATCH,🚀 节点选择
EOF
                fi
                "${EDITOR:-nano}" "$MIHOMO_PATCH"
                ui_print info "修改已保存，重启服务后生效。"
                ui_pause ;;
            *"密钥"*) 
                local cur=""; [ -f "$MIHOMO_SECRET_CONF" ] && cur=$(cat "$MIHOMO_SECRET_CONF")
                local sec=$(ui_input "面板密钥" "$cur" "false")
                echo "$sec" > "$MIHOMO_SECRET_CONF"; ui_print success "已保存"; ui_pause ;; 
            *"面板"*) open_browser "http://127.0.0.1:19090/ui" ;; 
            *"日志"*) safe_log_monitor "$log_path" ;; 
            *"更新"*) mihomo_install ;; 
            *"卸载"*) mihomo_uninstall && [ $? -eq 2 ] && return ;; 
            *"关于"*) show_module_about_info "${BASH_SOURCE[0]}" ;;
            *"返回"*) return ;; 
        esac
    done
}
