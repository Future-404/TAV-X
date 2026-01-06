#!/bin/bash

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"
source "$TAVX_DIR/core/install.sh"

CF_LOG="$INSTALL_DIR/cf_tunnel.log"
SERVER_LOG="$INSTALL_DIR/server.log"
NETWORK_CONFIG="$TAVX_DIR/config/network.conf"
MEMORY_CONFIG="$TAVX_DIR/config/memory.conf"

get_active_port() {
    local port=8000
    local cfg_port=$(config_get port)
    if [[ "$cfg_port" =~ ^[0-9]+$ ]]; then
        port="$cfg_port"
    fi
    echo "$port"
}

get_memory_args() {
    if [ -f "$MEMORY_CONFIG" ]; then
        local mem=$(cat "$MEMORY_CONFIG")
        if [[ "$mem" =~ ^[0-9]+$ ]] && [ "$mem" -gt 0 ]; then
            echo "--max-old-space-size=$mem"
        fi
    fi
}

get_smart_proxy_url() {
    if [ -f "$NETWORK_CONFIG" ]; then
        local c=$(cat "$NETWORK_CONFIG"); local t=${c%%|*}; local v=${c#*|};
        v=$(echo "$v"|tr -d '\n\r')
        if [ "$t" == "PROXY" ]; then
            echo "$v"
        fi
    fi
}

print_login_tips() {
    echo ""
    echo -e "${YELLOW}💡 提示: 若状态未刷新或无法登录，请检查:${NC}"
    echo -e "${YELLOW}   1. [系统设置] -> [核心参数配置]${NC}"
    echo -e "${YELLOW}   2. 并尝试在设置中为 default-user 设置一个密码${NC}"
}

apply_recommended_settings() {
    ui_print info "正在应用推荐配置..."
    
    local BATCH_JSON='{
        "listen": true,
        "whitelistMode": false,
        "basicAuthMode": false,
        "ssl.enabled": false,
        "hostWhitelist.enabled": false,
        "enableUserAccounts": true,
        "enableDiscreetLogin": true,
        "extensions.enabled": true,
        "enableServerPlugins": true,
        "performance.useDiskCache": false,
        "performance.lazyLoadCharacters": true
    }'
    
    if config_set_batch "$BATCH_JSON"; then
        ui_print success "推荐配置已应用！"
    else
        ui_print error "配置应用失败，请检查日志。"
    fi
    sleep 1
}

check_install_integrity() {
    if [ ! -d "$INSTALL_DIR" ] || [ ! -f "$INSTALL_DIR/server.js" ]; then
        ui_print error "未检测到酒馆核心文件。"
        if ui_confirm "是否立即运行安装修复？"; then 
            install_sillytavern
            return 0
        else return 1; fi
    fi
    return 0
}

stop_services() {
    local PORT=$(get_active_port)
    
    kill_process_safe "$ST_PID_FILE" "node.*server.js"
    kill_process_safe "$CF_PID_FILE" "cloudflared"

    if command -v termux-wake-unlock &>/dev/null; then termux-wake-unlock; fi
    
    local wait_count=0
    while pgrep -f "node server.js" > /dev/null; do
        if [ "$wait_count" -eq 0 ]; then ui_print info "正在停止旧进程..."; fi
        sleep 0.5
        ((wait_count++))
        if [ "$wait_count" -ge 10 ]; then 
            ui_print warn "进程响应超时，执行强制清理..."
            pkill -9 -f "node server.js"
        fi
        if [ "$wait_count" -ge 20 ]; then break; fi
    done
    sleep 1
}

start_node_server() {
    local MEM_ARGS=$(get_memory_args)
    cd "$INSTALL_DIR" || return 1
    if command -v termux-wake-lock &>/dev/null; then termux-wake-lock; fi
    rm -f "$SERVER_LOG"
    local START_CMD="nohup node $MEM_ARGS server.js > '$SERVER_LOG' 2>&1 & echo \$! > '$ST_PID_FILE'"
    
    if ui_spinner "正在启动酒馆服务..." "eval \"$START_CMD\""; then
        sleep 1
        local pid=$(cat "$ST_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
             disown "$pid" 2>/dev/null 
             return 0
        fi
    fi
    return 1
}

detect_protocol_logic() {
    local proxy=$1
    if [ -n "$proxy" ]; then echo "http2"; return; fi
    local t1="www.cloudflare.com"; local count=0
    if ping -c 1 -W 1 "$t1" >/dev/null 2>&1; then count=1; fi
    local udp_ok=0; timeout 1 nc -u -z -w 1 quic.cloudflare.com 7844 2>/dev/null && udp_ok=1
    if [ "$udp_ok" -eq 1 ]; then echo "quic"; else echo "http2"; fi
}

wait_for_link_logic() {
    local max=15; local count=0
    while [ $count -le $max ]; do
        if [ -f "$CF_LOG" ]; then
            local link=$(grep -o "https://[-a-zA-Z0-9]*\.trycloudflare\.com" "$CF_LOG" | grep -v "api.trycloudflare.com" | tail -n 1)
            if [ -n "$link" ]; then echo "$link"; return 0; fi
        fi
        sleep 1
        ((count++))
    done
    return 1
}

start_fixed_tunnel() {
    local PORT=$1; local PROXY_URL=$2; local CF_TOKEN=$3
    local CF_CMD="tunnel run --token $CF_TOKEN"
    
    if [ -n "$PROXY_URL" ]; then
        ui_print info "代理已注入: $PROXY_URL"
        setsid env TUNNEL_HTTP_PROXY="$PROXY_URL" nohup cloudflared $CF_CMD --protocol http2 > "$CF_LOG" 2>&1 &
    else
        setsid nohup cloudflared $CF_CMD > "$CF_LOG" 2>&1 &
    fi
    echo $! > "$CF_PID_FILE"
    
    ui_print success "服务已启动！"
    echo ""
    echo -e "${GREEN}请访问您在 Cloudflare 后台绑定的域名。${NC}"
    echo -e "${GRAY}(固定隧道无需获取临时链接)${NC}"
    print_login_tips
}

start_temp_tunnel() {
    local PORT=$1; local PROXY_URL=$2
    local PROTOCOL="http2"
    if [ -n "$PROXY_URL" ]; then
        ui_print info "检测到代理，强制使用 HTTP2..."
    else
        PROTOCOL=$(detect_protocol_logic "")
    fi
    
    local CF_ARGS=(tunnel --protocol "$PROTOCOL" --url "http://127.0.0.1:$PORT" --no-autoupdate)
    
    if [ -n "$PROXY_URL" ]; then
        ui_print info "隧道已接入代理网关: $PROXY_URL"
        setsid env TUNNEL_HTTP_PROXY="$PROXY_URL" nohup cloudflared "${CF_ARGS[@]}" > "$CF_LOG" 2>&1 &
    else
        setsid nohup cloudflared "${CF_ARGS[@]}" > "$CF_LOG" 2>&1 &
    fi
    echo $! > "$CF_PID_FILE"
    
    rm -f "$TAVX_DIR/.temp_link"
    local wait_cmd="source \"$TAVX_DIR/core/launcher.sh\"; link=\\\$(wait_for_link_logic\"); if [ -n \"\\$link\" ]; then echo \"\\$link\" > \"$TAVX_DIR/.temp_link\"; exit 0; else exit 1; fi"
    
    if ui_spinner "建立隧道 ($PROTOCOL)..." "$wait_cmd"; then
        local LINK=$(cat "$TAVX_DIR/.temp_link")
        ui_print success "链接创建成功！"
        echo ""
        echo -e "${YELLOW}👉 $LINK${NC}"
        echo ""
        echo -e "${CYAN}(长按复制)${NC}"
        print_login_tips
    else 
        ui_print error "链接获取超时。"
        ui_print warn "提示: 若一直超时，请尝试开启/关闭 VPN 后重试。"
    fi
}

start_menu() {
    check_install_integrity || return
    local PORT=$(get_active_port)

    while true; do
        _auto_heal_network_config
        local PROXY_URL=$(get_smart_proxy_url)
        local MEM_ARGS=$(get_memory_args)
        
        local status_txt=""
        
        local state_type="stopped"
        local status_text="已停止"

        if check_process_smart "$CF_PID_FILE" "cloudflared.*tunnel"; then
            if grep -q "protocol=quic" "$CF_LOG" 2>/dev/null; then P="QUIC"; else P="HTTP2"; fi
            state_type="running"
            status_text="穿透运行中 ($P)"
        elif check_process_smart "$ST_PID_FILE" "node.*server.js"; then
            state_type="running"
            status_text="本地运行中"
        fi
        
        local info_list=()
        [ -n "$PROXY_URL" ] && info_list+=( "前置代理: 已启用" )
        if [ -n "$MEM_ARGS" ]; then 
            local mem_val=$(echo $MEM_ARGS | cut -d'=' -f2)
            info_list+=( "内存限制: ${mem_val}MB" )
        fi

        ui_header "启动中心 (Port: $PORT)"
        ui_status_card "$state_type" "$status_text" "${info_list[@]}"

        CHOICE=$(ui_menu "请选择操作" "🏠 启动本地模式" "🌍 启动远程穿透" "🔍 获取远程链接" "⚡ 一键应用推荐配置" "📜 监控运行日志" "🛑 停止所有服务" "🔙 返回主菜单")

        case "$CHOICE" in
            *"本地模式"*) 
                stop_services
                start_node_server
                local PORT=$(get_active_port)
                local TARGET_URL="http://127.0.0.1:$PORT"
                
                ui_print success "本地服务已启动！"
                echo -e "地址: ${CYAN}$TARGET_URL${NC}"
                
                print_login_tips
                
                local BROWSER_CONF="$TAVX_DIR/config/browser.conf"
                local browser_mode="ST"
                
                if [ -f "$BROWSER_CONF" ]; then
                    browser_mode=$(cat "$BROWSER_CONF")
                fi
                
                if [ "$browser_mode" == "SCRIPT" ]; then
                    ui_print info "正在通过脚本唤起浏览器..."
                    open_browser "$TARGET_URL"
                elif [ "$browser_mode" == "NONE" ]; then
                    ui_print info "自动跳转已禁用，请手动复制地址访问。"
                else
                    : 
                fi
                
                ui_pause ;;
                
            *"远程穿透"*) 
                stop_services
                start_node_server
                rm -f "$CF_LOG"
                local PORT=$(get_active_port); local PROXY_URL=$(get_smart_proxy_url)
                local TOKEN_FILE="$TAVX_DIR/config/cf_token"
                local CF_TOKEN=""; [ -f "$TOKEN_FILE" ] && [ -s "$TOKEN_FILE" ] && CF_TOKEN=$(cat "$TOKEN_FILE")
                if [ -n "$CF_TOKEN" ]; then
                    ui_print info "检测到 Token，启动固定隧道..."
                    start_fixed_tunnel "$PORT" "$PROXY_URL" "$CF_TOKEN"
                else
                    start_temp_tunnel "$PORT" "$PROXY_URL"
                fi
                ui_pause ;;
            
            *"推荐配置"*) apply_recommended_settings ;; 
            
            *"远程链接"*) 
                local TOKEN_FILE="$TAVX_DIR/config/cf_token"
                if [ -f "$TOKEN_FILE" ] && [ -s "$TOKEN_FILE" ]; then
                    ui_print info "当前为固定隧道模式"
                    echo -e "${GREEN}请访问您在 Cloudflare 后台绑定的域名。${NC}"
                else
                    local LINK=$(wait_for_link_logic)
                    if [ -n "$LINK" ]; then 
                        ui_print success "当前链接:"
                        echo -e "\n${YELLOW}$LINK${NC}\n"
                        echo -e "${CYAN}(长按复制)${NC}"
                    else 
                        ui_print warn "无法获取链接 (服务未启动或网络超时)"
                    fi
                fi
                ui_pause ;; 
                
            *"日志"*) 
                SUB=$(ui_menu "选择日志" "📜 酒馆日志" "🚇 隧道日志" "🔙 返回")
                case "$SUB" in *"酒馆"*) safe_log_monitor "$SERVER_LOG" ;; *"隧道"*) safe_log_monitor "$CF_LOG" ;; esac ;; 
                
            *"停止"*) stop_services; ui_pause ;; 
            *"返回"*) return ;;
        esac
    done
}
