#!/bin/bash
# [METADATA]
# MODULE_NAME: ☁️ Cloudflare 隧道管理 （测试）
# MODULE_ENTRY: cf_manager_menu
# [END_METADATA]

# 引用核心库
source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

# --- 变量定义 ---
CF_MODULE_LOG="$TAVX_DIR/logs/cf_manager.log"
CF_PID_FILE="$TAVX_DIR/run/cf_manager.pid"
CF_CONF_FILE="$TAVX_DIR/config/cf_settings.conf"
CF_TOKEN_FILE="$TAVX_DIR/config/cf_token"

# 确保目录存在
mkdir -p "$TAVX_DIR/logs"
mkdir -p "$TAVX_DIR/run"
mkdir -p "$TAVX_DIR/config"

# --- 基础工具函数 ---

get_conf() {
    local key=$1
    if [ -f "$CF_CONF_FILE" ]; then
        grep "^${key}=" "$CF_CONF_FILE" | cut -d'=' -f2
    fi
}

set_conf() {
    local key=$1
    local val=$2
    if [ ! -f "$CF_CONF_FILE" ]; then touch "$CF_CONF_FILE"; fi
    if grep -q "^${key}=" "$CF_CONF_FILE"; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$CF_CONF_FILE"
    else
        echo "${key}=${val}" >> "$CF_CONF_FILE"
    fi
}

check_cf_installed() {
    if command -v cloudflared &> /dev/null; then return 0; else return 1; fi
}

install_cf_tool() {
    ui_header "安装 Cloudflared"
    local ARCH=$(uname -m)
    local CF_ARCH=""
    case $ARCH in
        aarch64) CF_ARCH="arm64" ;;
        x86_64)  CF_ARCH="amd64" ;;
        arm*)    CF_ARCH="arm" ;;
        *)       CF_ARCH="amd64" ;;
    esac

    local URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}"
    echo -e "正在下载适用于 ${CF_ARCH} 的 Cloudflared..."
    
    if curl -L --progress-bar -o "$PREFIX/bin/cloudflared" "$URL"; then
        chmod +x "$PREFIX/bin/cloudflared"
        ui_print success "安装成功！"
    else
        ui_print error "下载失败，请检查网络。"
    fi
    ui_pause
}

check_and_install_proxychains() {
    if ! command -v proxychains4 &> /dev/null; then
        ui_print warn "检测到需要使用强制代理，正在安装 proxychains-ng..."
        if [ -n "$TERMUX_VERSION" ]; then
            pkg install proxychains-ng -y
        else
            sudo apt-get install proxychains -y 2>/dev/null || sudo apt-get install proxychains4 -y
        fi
        
        if ! command -v proxychains4 &> /dev/null; then
            ui_print error "Proxychains 安装失败！无法使用强制代理模式。"
            return 1
        fi
    fi
    return 0
}

# --- 核心逻辑函数 ---

stop_cf_tunnel() {
    if [ -f "$CF_PID_FILE" ]; then
        local pid=$(cat "$CF_PID_FILE")
        if [ -n "$pid" ]; then kill "$pid" >/dev/null 2>&1; fi
        rm -f "$CF_PID_FILE"
    fi
    pkill -f "cloudflared"
    rm -f "$CF_MODULE_LOG"
    ui_print success "隧道服务已停止。"
    sleep 1
}

configure_settings() {
    while true; do
        local curr_proxy=$(get_conf "CF_PROXY")
        local curr_proto=$(get_conf "CF_PROTOCOL"); [ -z "$curr_proto" ] && curr_proto="auto"
        local token_status="${YELLOW}未配置${NC}"
        [ -s "$CF_TOKEN_FILE" ] && token_status="${GREEN}已配置${NC}"
        [ -z "$curr_proxy" ] && curr_proxy="直连 (Direct)"
        
        ui_header "隧道参数配置"
        echo -e "📡 代理模式: ${CYAN}$curr_proxy${NC}"
        echo -e "🔌 传输协议: ${CYAN}$curr_proto${NC}"
        echo -e "🔑 Token   : $token_status"
        echo "----------------------------------------"
        
        local choice=$(ui_menu "选择修改项" \
            "📡 设置网络代理 (Proxy)" \
            "🔌 切换传输协议 (Protocol)" \
            "🔑 管理固定 Token" \
            "🔙 返回")
            
        case "$choice" in
            *"网络代理"*) 
                local p_sub=$(ui_menu "代理设置" "🚫 关闭代理 (直连)" "✏️ 输入代理地址" "🔙 取消")
                case "$p_sub" in
                    *"关闭"*) set_conf "CF_PROXY" ""; ui_print success "已设为直连模式。" ;; 
                    *"输入"*) 
                        local def=""
                        [ -f "$TAVX_DIR/config/network.conf" ] && def=$(cat "$TAVX_DIR/config/network.conf" | cut -d'|' -f2)
                        local inp=$(ui_input "输入代理 (如 http://127.0.0.1:7890)" "$def" "false")
                        if [ -n "$inp" ]; then set_conf "CF_PROXY" "$inp"; ui_print success "代理已保存。" ; fi
                        ;; 
                esac
                ;; 
            *"传输协议"*) 
                local proto_sub=$(ui_menu "选择协议" \
                    "🔄 自动 (Auto) - 默认推荐" \
                    "🌐 HTTP2 - 兼容性最好" \
                    "🚀 QUIC - 速度快但易被阻断" \
                    "🔙 取消")
                case "$proto_sub" in 
                    *"自动"*) set_conf "CF_PROTOCOL" "auto" ;; 
                    *"HTTP2"*) set_conf "CF_PROTOCOL" "http2" ;; 
                    *"QUIC"*) set_conf "CF_PROTOCOL" "quic" ;; 
                esac
                [ "$proto_sub" != "*取消*" ] && ui_print success "协议已切换。"
                ;; 
            *"Token"*) 
                local t_sub=$(ui_menu "Token 管理" "📝 输入/修改 Token" "🗑️ 清除 Token" "🔙 取消")
                case "$t_sub" in 
                    *"输入"*) 
                        local inp=$(ui_input "粘贴 Token (eyJh...)" "" "false")
                        if [ -n "$inp" ]; then echo "$inp" > "$CF_TOKEN_FILE"; ui_print success "Token 已保存！"; fi ;; 
                    *"清除"*) rm -f "$CF_TOKEN_FILE"; ui_print success "Token 已清除。";;
                esac
                ;; 
            *"返回"*) return ;; 
        esac
    done
}

# --- 独立启动逻辑 ---

start_fixed_tunnel() {
    local token=""
    [ -s "$CF_TOKEN_FILE" ] && token=$(cat "$CF_TOKEN_FILE")
    
    if [ -z "$token" ]; then
        ui_header "未配置 Token"
        echo -e "${YELLOW}固定隧道需要 Cloudflare Zero Trust 的 Token。${NC}"
        echo -e "请先在 Cloudflare 后台创建隧道并复制 Token。"
        echo ""
        if ui_confirm "现在输入 Token？"; then
             local inp=$(ui_input "粘贴 Token (eyJh...)" "" "false")
             if [ -n "$inp" ]; then 
                 echo "$inp" > "$CF_TOKEN_FILE"
                 token="$inp"
                 ui_print success "Token 已保存，正在启动..."
             else
                 return
             fi
        else
            return
        fi
    fi
    
    # 2. 启动逻辑
    local base_cmd="tunnel run --token $token"
    local proto=$(get_conf "CF_PROTOCOL"); [ -z "$proto" ] && proto="auto"
    if [ "$proto" != "auto" ]; then base_cmd="$base_cmd --protocol $proto"; fi
    
    _exec_cf_cmd "$base_cmd" "固定隧道"
}

start_quick_tunnel() {
    ui_header "启动临时隧道 (测试模式)"
    echo -e "${YELLOW}注意：临时隧道在某些网络环境下可能无法连接。${NC}"
    echo -e "${YELLOW}建议优先使用固定隧道。${NC}"
    echo ""
    
    local port=$(ui_input "请输入本地端口 (例如 8000)" "8000" "false")
    if [[ ! "$port" =~ ^[0-9]+$ ]]; then ui_print error "无效端口"; ui_pause; return; fi
    
    local base_cmd="tunnel --url http://127.0.0.1:$port --no-autoupdate"
    local proto=$(get_conf "CF_PROTOCOL"); [ -z "$proto" ] && proto="auto"
    
    # 临时隧道下，如果配置了代理，建议强制 http2
    local proxy=$(get_conf "CF_PROXY")
    if [ "$proto" == "auto" ] && [ -n "$proxy" ]; then 
        base_cmd="$base_cmd --protocol http2"
    elif [ "$proto" != "auto" ]; then
        base_cmd="$base_cmd --protocol $proto"
    fi
    
    _exec_cf_cmd "$base_cmd" "临时隧道"
}

# 通用执行器 (底层支撑)
_exec_cf_cmd() {
    local base_cmd="$1"
    local mode_name="$2"
    
    # 检查组件
    if ! check_cf_installed; then
        if ui_confirm "未检测到组件，是否安装？"; then install_cf_tool; else return; fi
        if ! check_cf_installed; then return; fi
    fi
    
    # 读取代理配置
    local proxy=$(get_conf "CF_PROXY")
    local cmd_wrapper=""
    
    if [ -n "$proxy" ]; then
        if check_and_install_proxychains; then
             # 生成专用配置文件 (无 DNS 代理)
            local clean_proxy=${proxy#*://}
            local p_ip=${clean_proxy%:*} 
            local p_port=${clean_proxy##*:}
            local pc_conf="$TAVX_DIR/run/cf_proxychains.conf"
            
            echo "strict_chain" > "$pc_conf"
            echo "tcp_read_time_out 15000" >> "$pc_conf"
            echo "tcp_connect_time_out 8000" >> "$pc_conf"
            echo "[ProxyList]" >> "$pc_conf"
            echo "http $p_ip $p_port" >> "$pc_conf"
            
            ui_print info "启用 Proxychains 代理 ($p_ip:$p_port)"
            cmd_wrapper="proxychains4 -f $pc_conf -q"
        else
            ui_print warn "Proxychains 准备失败，尝试直连..."
        fi
    fi
    
    # 强制 IPv4 & Debug
    base_cmd="$base_cmd --edge-ip-version 4 --loglevel debug"
    
    local final_cmd="nohup $cmd_wrapper cloudflared $base_cmd > \"$CF_MODULE_LOG\" 2>&1 & echo \\$! > \"$CF_PID_FILE\""
    
    ui_spinner "正在启动 $mode_name..." "sleep 1"
    
    # 调试日志
    echo "--- TAV-X Debug ---" > "$CF_MODULE_LOG"
    echo "Mode: $mode_name" >> "$CF_MODULE_LOG"
    echo "Proxy: $proxy" >> "$CF_MODULE_LOG"
    echo "Exec: $final_cmd" >> "$CF_MODULE_LOG"
    echo "-------------------" >> "$CF_MODULE_LOG"
    
    eval "$final_cmd"
    sleep 3
    
    if ! pgrep -f "cloudflared" >/dev/null; then
        ui_print error "启动失败，进程退出。"
        echo -e "${YELLOW}--- 日志预览 ---${NC}"
        tail -n 5 "$CF_MODULE_LOG"
        ui_pause; return
    fi
    
    if [[ "$mode_name" == *"固定"* ]]; then
        ui_print success "固定隧道已启动！"
        echo -e "${GREEN}请访问您在 Cloudflare 后台绑定的域名。${NC}"
    else
        echo -ne "正在获取链接..."
        local url=""
        for i in {1..15}; do
            if [ -f "$CF_MODULE_LOG" ]; then
                url=$(grep -o "https://[-a-zA-Z0-9]*\.trycloudflare\.com" "$CF_MODULE_LOG" | grep -v "api" | tail -n 1)
                if [ -n "$url" ]; then break; fi
            fi
            echo -ne "."
            sleep 1
        done
        echo ""
        if [ -n "$url" ]; then
            ui_print success "穿透成功！"
            echo -e "\n${YELLOW}👉 $url${NC}\n"
        else
            ui_print error "获取链接超时 (可能因网络问题)。"
        fi
    fi
    ui_pause
}

view_log() {
    if [ ! -f "$CF_MODULE_LOG" ]; then ui_print info "暂无日志。"; ui_pause; return; fi
    safe_log_monitor "$CF_MODULE_LOG"
}

# --- 主菜单 ---
cf_manager_menu() {
    while true; do
        ui_header "☁️ Cloudflare 隧道管理器"
        
        local state_type="stopped"
        local status_text="未运行"
        
        if pgrep -f "cloudflared" >/dev/null; then
            state_type="running"
            status_text="运行中"
        fi
        
        local p_conf=$(get_conf "CF_PROXY"); [ -z "$p_conf" ] && p_conf="直连"
        local proto_conf=$(get_conf "CF_PROTOCOL"); [ -z "$proto_conf" ] && proto_conf="自动"
        
        local info_list=(
            "代理模式: $p_conf"
            "传输协议: $proto_conf"
        )
        
        ui_status_card "$state_type" "$status_text" "${info_list[@]}"
        
        local choice=$(ui_menu "功能菜单" \
            "🚀 启动固定隧道 (推荐)" \
            "⚡ 启动临时隧道 (测试)" \
            "🛑 停止服务" \
            "⚙️  设置 (代理/Token)" \
            "📜 查看日志" \
            "🔙 返回上级")
            
        case "$choice" in
            *"固定隧道"*) start_fixed_tunnel ;; 
            *"临时隧道"*) start_quick_tunnel ;; 
            *"停止"*) stop_cf_tunnel; ui_pause ;; 
            *"设置"*) configure_settings ;; 
            *"查看日志"*) view_log ;; 
            *"返回"*) return ;; 
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then cf_manager_menu; fi