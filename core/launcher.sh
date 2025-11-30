#!/bin/bash
# TAV-X Core: Service Launcher (V5.5 Original Logic Restored)

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

CF_LOG="$INSTALL_DIR/cf_tunnel.log"
SERVER_LOG="$INSTALL_DIR/server.log"
JS_TOOL="$TAVX_DIR/scripts/config_mgr.js"
NETWORK_CONFIG="$TAVX_DIR/config/network.conf"
MEMORY_CONFIG="$TAVX_DIR/config/memory.conf"

get_active_port() {
    local port=8000
    if [ -f "$JS_TOOL" ]; then
        local cfg_port=$(node "$JS_TOOL" get port 2>/dev/null)
        [[ "$cfg_port" =~ ^[0-9]+$ ]] && port="$cfg_port"
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

fix_ssl_config() {
    [ -f "$JS_TOOL" ] && node "$JS_TOOL" set ssl.enabled false >/dev/null 2>&1
}

is_port_open() {
    timeout 0.1 bash -c "</dev/tcp/$1/$2" 2>/dev/null && return 0 || return 1
}

get_smart_proxy_url() {
    if [ -f "$NETWORK_CONFIG" ]; then
        local c=$(cat "$NETWORK_CONFIG"); local t=${c%%|*}; local v=${c#*|}
        v=$(echo "$v"|tr -d '\n\r')
        if [ "$t" == "PROXY" ]; then
            local p=$(echo "$v"|awk -F':' '{print $NF}')
            local h="127.0.0.1"
            [[ "$v" == *"://"* ]] && h=$(echo "$v"|sed -e 's|^[^/]*//||' -e 's|:.*$||')
            if is_port_open "$h" "$p"; then echo "$v"; else return; fi
        fi
    fi
}

stop_services() {
    local PORT=$(get_active_port)
    
    pkill -f "node server.js"
    pkill -f "cloudflared"
    termux-wake-unlock 2>/dev/null
    
    local count=0
    while is_port_open "127.0.0.1" "$PORT"; do
        if [ "$count" -eq 0 ]; then
            ui_print info "正在停止旧进程..."
        fi
        
        sleep 0.5
        ((count++))
        
        if [ "$count" -ge 6 ]; then
            fuser -k -9 "$PORT/tcp" >/dev/null 2>&1
        fi
        
        if [ "$count" -ge 10 ]; then
            ui_print warn "旧进程可能未完全清理，尝试强制启动..."
            break
        fi
    done
    
    sleep 0.5
}

detect_protocol_logic() {
    local proxy=$1
    if [ -n "$proxy" ]; then echo "http2"; return; fi
    
    local t1="www.cloudflare.com"; local t2="1.0.0.1"; local sum=0; local count=0
    
    for i in {1..2}; do
        local r=$(ping -c 1 -W 1 "$t1" 2>/dev/null)
        local ms=$(echo "$r"|awk -F'/' 'END{if($5)print int($5);else print 9999}')
        if [ "$ms" -lt 9999 ]; then sum=$((sum+ms)); count=$((count+1)); fi
    done
    
    if [ "$count" -eq 0 ]; then
        local r=$(ping -c 1 -W 1 "$t2" 2>/dev/null)
        local ms=$(echo "$r"|awk -F'/' 'END{if($5)print int($5);else print 9999}')
        if [ "$ms" -lt 9999 ]; then sum=$((sum+ms)); count=$((count+1)); fi
    fi
    
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

check_install_integrity() {
    if [ ! -d "$INSTALL_DIR" ] || [ ! -f "$INSTALL_DIR/server.js" ]; then
        ui_print error "未检测到酒馆核心文件。"
        if ui_confirm "是否立即运行安装修复？"; then source "$TAVX_DIR/core/install.sh"; install_sillytavern; return 0; else return 1; fi
    fi
    return 0
}

start_menu() {
    check_install_integrity || return
    fix_ssl_config
    local PORT=$(get_active_port)

    while true; do
        local PROXY_URL=$(get_smart_proxy_url)
        local MEM_ARGS=$(get_memory_args)
        
        local status_txt=""
        if pgrep -f "cloudflared" >/dev/null; then 
            if grep -q "protocol=quic" "$CF_LOG" 2>/dev/null; then P="QUIC"; else P="HTTP2"; fi
            status_txt="${GREEN}● 穿透运行中 ($P)${NC}"
        elif pgrep -f "node server.js" >/dev/null; then 
            status_txt="${GREEN}● 本地运行中${NC}"
        else status_txt="${RED}● 已停止${NC}"; fi
        [ -n "$PROXY_URL" ] && status_txt="$status_txt ${CYAN}[代理活跃]${NC}"
        
        local MEM_SHOW=""
        if [ -n "$MEM_ARGS" ]; then MEM_SHOW=" | 🧠 $(echo $MEM_ARGS | cut -d'=' -f2)MB"; fi

        ui_header "启动中心 (Port: $PORT$MEM_SHOW)"
        echo -e "状态: $status_txt"
        echo ""

        CHOICE=$(ui_menu "请选择操作" "🏠 启动本地模式" "🌍 启动远程穿透" "🔍 获取远程链接" "📜 监控运行日志" "🛑 停止所有服务" "🔙 返回主菜单")

        case "$CHOICE" in
            *"本地模式"*) 
                stop_services
                
                cd "$INSTALL_DIR" || return
                termux-wake-lock
                rm -f "$SERVER_LOG"
                fix_ssl_config
                
                ui_spinner "正在启动酒馆服务..." "nohup node $MEM_ARGS server.js > '$SERVER_LOG' 2>&1 & sleep 2"
                ui_print success "本地启动: http://127.0.0.1:$PORT"
                ui_pause ;;
            *"远程穿透"*) 
                stop_services
                cd "$INSTALL_DIR" || return
                termux-wake-lock
                rm -f "$SERVER_LOG" "$CF_LOG"
                fix_ssl_config
                ui_spinner "正在启动酒馆..." "nohup node $MEM_ARGS server.js > '$SERVER_LOG' 2>&1 & sleep 2"
                
                PROTOCOL="http2"; ui_print info "评估网络..."
                PROTOCOL=$(detect_protocol_logic "$PROXY_URL")
                
                local CF_ARGS=(tunnel --protocol "$PROTOCOL" --url "http://127.0.0.1:$PORT" --no-autoupdate)
                if [ -n "$PROXY_URL" ]; then
                    ui_print info "注入代理: $PROXY_URL"
                    env TUNNEL_HTTP_PROXY="$PROXY_URL" cloudflared "${CF_ARGS[@]}" > "$CF_LOG" 2>&1 &
                else
                    cloudflared "${CF_ARGS[@]}" > "$CF_LOG" 2>&1 &
                fi
                # -----------------------------------
                
                rm -f "$TAVX_DIR/.temp_link"
                wait_cmd="source $TAVX_DIR/core/launcher.sh; link=\$(wait_for_link_logic); if [ -n \"\$link\" ]; then echo \"\$link\" > \"$TAVX_DIR/.temp_link\"; exit 0; else exit 1; fi"
                if ui_spinner "建立隧道 ($PROTOCOL)..." "$wait_cmd"; then
                    LINK=$(cat "$TAVX_DIR/.temp_link"); ui_print success "链接创建成功！"; echo ""; echo -e "${YELLOW}👉 $LINK${NC}"; echo ""; echo -e "${CYAN}(长按复制)${NC}"
                else ui_print error "链接获取超时。"; fi
                ui_pause ;;

            *"远程链接"*)
                LINK=$(wait_for_link_logic)
                if [ -n "$LINK" ]; then 
                    ui_print success "当前链接:"; echo -e "\n${YELLOW}$LINK${NC}\n"; echo -e "${CYAN}(长按复制)${NC}"
                else 
                    ui_print warn "无法获取链接 (服务未启动或网络超时)"
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
