#!/bin/bash
# [METADATA]
# MODULE_NAME: ♊ Gemini CLI代理
# MODULE_ENTRY: gemini_menu
# [END_METADATA]
source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

GEMINI_DIR="$TAVX_DIR/gemini_proxy"
VENV_DIR="$GEMINI_DIR/venv"
VENV_PYTHON="$VENV_DIR/bin/python"
VENV_PIP="$VENV_DIR/bin/pip"
REPO_URL="gzzhongqi/geminicli2api"
CREDS_FILE="$GEMINI_DIR/oauth_creds.json"
ENV_FILE="$GEMINI_DIR/.env"
LOG_FILE="$GEMINI_DIR/service.log"
TUNNEL_LOG="$GEMINI_DIR/tunnel.log"

get_proxy_address() {
    get_active_proxy
}

check_google_connectivity() {
    local timeout_sec=5
    local target_url="https://www.google.com"
    local proxy=$(get_proxy_address)
    
    ui_print info "正在检测 Google 连通性..."
    local cmd=("curl" "-I" "-s" "--max-time" "$timeout_sec")
    local proxy_msg="直连"
    
    if [ -n "$proxy" ]; then
        cmd+=("--proxy" "$proxy")
        proxy_msg="代理 ($proxy)"
    fi
    if "${cmd[@]}" "$target_url" >/dev/null 2>&1; then
        return 0
    else
        ui_print error "Google 连接失败！当前模式: $proxy_msg"
        echo -e "${YELLOW}可能原因:${NC}"
        echo -e "1. 未配置代理 (Gemini 必须使用魔法)。"
        echo -e "2. 代理节点不稳定或不支持 UDP/TCP。"
        echo -e "3. 网络超时。"
        echo ""
        if ui_confirm "是否跳转到网络设置进行配置？"; then
            configure_download_network
        fi
        return 1
    fi
}

check_auth_dependencies() {
    local missing=""
    command -v stdbuf >/dev/null || missing="$missing coreutils"
    
    if [ -n "$missing" ]; then
        ui_print info "安装认证依赖: $missing"
        if [ "$OS_TYPE" == "TERMUX" ]; then
            pkg install $missing -y
        else
            $SUDO_CMD apt-get install -y $missing
        fi
    fi
}

install_gemini() {
    ui_header "部署 Gemini 代理服务"
    
    if ! command -v python3 &>/dev/null; then
        ui_print error "系统未检测到 Python3。"
        echo -e "${YELLOW}请前往 [高级工具] -> [🐍 Python 环境管理] 进行安装。${NC}"
        ui_pause; return 1
    fi

    if [ "$OS_TYPE" == "TERMUX" ]; then
        if ! command -v rustc &>/dev/null || ! command -v clang &>/dev/null; then
            ui_print warn "Gemini 依赖可能需要编译，但缺少 Rust/Clang。"
            echo -e "${YELLOW}建议前往 [高级工具] -> [🐍 Python 环境管理] 补全编译环境。${NC}"
            if ! ui_confirm "强制继续 (可能失败)?"; then return 1; fi
        fi
    fi

    if [ -d "$GEMINI_DIR" ]; then rm -rf "$GEMINI_DIR"; fi
    prepare_network_strategy "$REPO_URL"

    local CLONE_CMD="source \"$TAVX_DIR/core/utils.sh\"; git_clone_smart '' '$REPO_URL' '$GEMINI_DIR'"
    if ! ui_spinner "正在下载源码..." "$CLONE_CMD"; then ui_print error "源码下载失败。"; ui_pause; return 1; fi

    cd "$GEMINI_DIR" || return

    ui_print info "创建 Python 虚拟环境..."
    python3 -m venv venv || { ui_print error "Venv 创建失败"; ui_pause; return 1; }

    ui_print info "正在安装依赖..."
    
    if pip_install_smart "$VENV_PIP" "--upgrade pip" && \
       pip_install_smart "$VENV_PIP" "requests[socks] PySocks" && \
       pip_install_smart "$VENV_PIP" "-r requirements.txt"; then
        echo "HOST=0.0.0.0" > "$ENV_FILE"
        echo "PORT=8888" >> "$ENV_FILE"
        echo "GEMINI_AUTH_PASSWORD=password" >> "$ENV_FILE"
        ui_print success "Gemini 服务部署成功！"
    else
        ui_print error "依赖安装失败。"
        echo -e "${YELLOW}请检查网络设置或手动切换 Pip 源。${NC}"
        echo -e "${YELLOW}高级工具 -> Python 环境管理 -> 修复系统 Python${NC}"
        ui_pause; return 1
    fi
    
    ui_pause
}

ensure_installed() {
    if [ ! -d "$GEMINI_DIR" ]; then
        ui_print warn "检测到 Gemini 模块尚未安装。"
        echo -e "${YELLOW}需要先部署服务才能继续。${NC}"
        echo ""
        if ui_confirm "是否立即开始安装？"; then
            install_gemini
            if [ ! -d "$GEMINI_DIR" ]; then return 1; fi
        else
            ui_print info "已取消操作。"; return 1
        fi
    fi
    return 0
}

authenticate_google() {
    ensure_installed || return
    check_google_connectivity || return
    check_auth_dependencies

    if [ -f "$CREDS_FILE" ]; then
        ui_print warn "检测到已存在登录凭据！"
        if ! ui_confirm "重新认证将覆盖现有文件，是否继续？"; then return; fi
        rm -f "$CREDS_FILE"
    fi

    ui_header "Google 账号授权"
    echo -e "${CYAN}流程说明:${NC}"
    echo -e "1. 脚本将在后台生成认证链接。"
    echo -e "2. 如果浏览器未自动弹出，请去 [📜 查看运行日志] 复制链接。"
    echo -e "3. 浏览器登录成功后，直接回来点击 [🚀 启动服务] 即可。"
    echo ""
    
    local proxy=$(get_proxy_address)
    local proxy_env=""
    [ -n "$proxy" ] && proxy_env="env http_proxy='$proxy' https_proxy='$proxy'"

    cd "$GEMINI_DIR" || return
    
    rm -f "$LOG_FILE"
    pkill -f "$VENV_PYTHON run.py"

    echo -e "${GREEN}>>> 正在后台启动认证进程...${NC}"
    nohup env -u GEMINI_CREDENTIALS \
        GEMINI_AUTH_PASSWORD=\"init\" \
        PYTHONUNBUFFERED=1 \
        $proxy_env \
        "$VENV_PYTHON" -u run.py > "$LOG_FILE" 2>&1 &
    
    local APP_PID=$!
    local CRASHED=0

    echo -ne "正在获取链接..."
    local url=""
    for i in {1..10}; do
        if ! kill -0 $APP_PID 2>/dev/null; then CRASHED=1; break; fi
        if grep -q "https://accounts.google.com" "$LOG_FILE"; then
            url=$(grep -o "https://accounts.google.com[^ ]*" "$LOG_FILE" | head -n 1 | tr -d '\r\n')
            break
        fi
        echo -ne "."
        sleep 1
    done
    echo ""

    if [ $CRASHED -eq 1 ]; then
        ui_print error "认证程序意外崩溃！"
        echo -e "${YELLOW}--- 错误日志 (最后10行) ---${NC}"
        tail -n 10 "$LOG_FILE"
        echo -e "${YELLOW}----------------------------${NC}"
        ui_pause; return
    fi

    if [ -n "$url" ]; then
        open_browser "$url"
        if [ "$OS_TYPE" == "TERMUX" ] || [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
            ui_print success "已唤起浏览器！请前往登录。"
        else
            ui_print success "请复制上方链接到本地浏览器进行登录。"
        fi
    else
        ui_print info "未能自动获取链接。"
        echo -e "${YELLOW}请手动前往主菜单 -> [📜 查看运行日志] 复制链接。${NC}"
    fi
    
    echo -e "------------------------------------------------"
    echo -e "✅ 操作步骤：浏览器登录成功后，直接回来点击 [🚀 启动服务]。"
    
    ui_pause
}

start_tunnel() {
    ensure_installed || return
    
    if ! check_process_smart "$GEMINI_PID_FILE" "python.*run.py"; then
        ui_print error "Gemini 服务未启动！"
        echo -e "请先点击 [🚀 启动/重启服务]。"
        ui_pause; return
    fi

    local port=$(grep "^PORT=" "$ENV_FILE" 2>/dev/null | cut -d= -f2); [ -z "$port" ] && port=8888
    local token_file="$TAVX_DIR/config/cf_token"
    local proxy=$(get_proxy_address)
    
    ui_header "Cloudflare 远程穿透"
    
    kill_process_safe "$TUNNEL_PID_FILE" "cloudflared tunnel"
    pkill -f "cloudflared tunnel"
    rm -f "$TUNNEL_LOG"

    if [ -f "$token_file" ] && [ -s "$token_file" ]; then
        local token=$(cat "$token_file")
        ui_print info "检测到固定 Token，正在启动固定隧道..."
        
        if [ -n "$proxy" ]; then
            setsid env TUNNEL_HTTP_PROXY="$proxy" nohup cloudflared tunnel run --token "$token" > "$TUNNEL_LOG" 2>&1 &
        else
            setsid nohup cloudflared tunnel run --token "$token" > "$TUNNEL_LOG" 2>&1 &
        fi
        
        sleep 3
        if pgrep -f "cloudflared" >/dev/null; then
            ui_print success "固定隧道已启动！"
            echo -e "请访问您绑定的自定义域名。"
        else
            ui_print error "启动失败，请检查 Log。"
        fi
        
    else
        ui_print info "启动临时隧道 (TryCloudflare)..."
        local cf_cmd="tunnel --url http://localhost:$port --no-autoupdate"
        
        if [ -n "$proxy" ]; then
            setsid env TUNNEL_HTTP_PROXY="$proxy" nohup cloudflared $cf_cmd --protocol http2 > "$TUNNEL_LOG" 2>&1 &
        else
            setsid nohup cloudflared $cf_cmd > "$TUNNEL_LOG" 2>&1 &
        fi
        
        echo -ne "正在获取链接..."
        local link=""
        for i in {1..15}; do
            if grep -q "trycloudflare.com" "$TUNNEL_LOG"; then
                link=$(grep -o "https://[-a-zA-Z0-9]*\.trycloudflare\.com" "$TUNNEL_LOG" | grep -v "api" | tail -n 1)
                if [ -n "$link" ]; then break; fi
            fi
            echo -ne "."
            sleep 1
        done
        echo ""
        
        if [ -n "$link" ]; then
            ui_print success "穿透成功！"
            echo -e "\n${YELLOW}👉 $link${NC}\n"
            echo -e "${CYAN}(长按复制，填入远程酒馆的 API 地址)${NC}"
        else
            ui_print error "获取链接超时。请检查网络或代理配置。"
        fi
    fi
    ui_pause
}

stop_tunnel() {
    kill_process_safe "$TUNNEL_PID_FILE" "cloudflared tunnel"
    pkill -f "cloudflared tunnel"
    ui_print success "远程隧道已关闭。"
    sleep 1
}

start_service() {
    ensure_installed || return
    check_google_connectivity || return
    
    local port=$(grep "^PORT=" "$ENV_FILE" 2>/dev/null | cut -d= -f2); [ -z "$port" ] && port=8888

    kill_process_safe "$GEMINI_PID_FILE" "run.py"
    pkill -f "$VENV_PYTHON run.py"
    pkill -f "cloudflared tunnel"
    
    if command -v fuser >/dev/null; then
        fuser -k -9 "$port/tcp" >/dev/null 2>&1
    elif command -v lsof >/dev/null; then
        local pid=$(lsof -t -i:"$port")
        if [ -n "$pid" ]; then kill -9 $pid >/dev/null 2>&1; fi
    fi
    sleep 1

    if [ ! -f "$CREDS_FILE" ]; then
        if ls "$GEMINI_DIR"/*creds*.json 1> /dev/null 2>&1; then
            mv "$GEMINI_DIR"/*creds*.json "$CREDS_FILE" 2>/dev/null
            ui_print success "检测到新凭据，已自动应用！"
        else
            ui_print error "未找到授权凭据。"
            echo -e "请先执行 [🔑 Google 账号授权] 并完成浏览器登录。"
            ui_pause; return
        fi
    fi

    local pass=$(grep "^GEMINI_AUTH_PASSWORD=" "$ENV_FILE" 2>/dev/null | cut -d= -f2); [ -z "$pass" ] && pass="password"
    write_env_safe "$ENV_FILE" "PORT" "$port"
    write_env_safe "$ENV_FILE" "GEMINI_AUTH_PASSWORD" "$pass"
    
    if ! grep -q "^GEMINI_CREDENTIALS=" "$ENV_FILE"; then
        echo -n "GEMINI_CREDENTIALS='" >> "$ENV_FILE"
        cat "$CREDS_FILE" >> "$ENV_FILE"
        echo "'" >> "$ENV_FILE"
    fi

    local proxy=$(get_proxy_address); local proxy_env=""
    [ -n "$proxy" ] && proxy_env="env http_proxy='$proxy' https_proxy='$proxy' all_proxy='$proxy'"
    
    ui_header "启动服务"
    cd "$GEMINI_DIR" || return
    local START_CMD="$proxy_env GEMINI_AUTH_PASSWORD='$pass' setsid nohup $VENV_PYTHON run.py > '$LOG_FILE' 2>&1 & echo \\$! > '$GEMINI_PID_FILE'"
    
    if ui_spinner "正在启动服务..." "eval \"$START_CMD\""; then
        sleep 1
        if check_process_smart "$GEMINI_PID_FILE" "python.*run.py"; then
            local pid=$(cat "$GEMINI_PID_FILE")
            disown "$pid" 2>/dev/null
            ui_print success "服务已启动！端口: $port"
        else
            ui_print error "启动失败，进程立刻退出了。"
            echo -e "${YELLOW}--- 错误日志 ---${NC}"
            tail -n 5 "$LOG_FILE"
            echo -e "${YELLOW}---------------${NC}"
        fi
    else 
        ui_print error "启动指令执行失败。"
    fi
    ui_pause
}

stop_service() {
    kill_process_safe "$GEMINI_PID_FILE" "run.py"
    pkill -f "$VENV_PYTHON run.py"
    pkill -f "cloudflared tunnel"
    ui_print success "服务与隧道已停止。"
    sleep 1
}

show_info() {
    local port=$(grep "^PORT=" "$ENV_FILE" 2>/dev/null | cut -d= -f2); [ -z "$port" ] && port=8888
    local pass=$(grep "^GEMINI_AUTH_PASSWORD=" "$ENV_FILE" 2>/dev/null | cut -d= -f2); [ -z "$pass" ] && pass="password"
    local proj=$(grep "^GOOGLE_CLOUD_PROJECT=" "$ENV_FILE" 2>/dev/null | cut -d= -f2); [ -z "$proj" ] && proj="未设置 (自动)"
    
    ui_header "连接信息"
    
    local tunnel_url=""
    if pgrep -f "cloudflared" >/dev/null; then
        if [ -s "$TAVX_DIR/config/cf_token" ]; then
            tunnel_url="请使用您的固定域名"
        elif [ -f "$TUNNEL_LOG" ]; then
            tunnel_url=$(grep -o "https://[-a-zA-Z0-9]*\.trycloudflare\.com" "$TUNNEL_LOG" | grep -v "api" | tail -n 1)
        fi
    fi

    echo -e "${YELLOW}请将以下信息填入酒馆或其他 AI 客户端:${NC}\n"
    
    if [ -n "$tunnel_url" ]; then
        echo -e "${GREEN}🌍 公网远程地址 (Cloudflare):${NC}"
        echo -e "   $tunnel_url/v1"
        echo ""
    fi

    echo -e "🏠 本地局域网地址:"
    echo -e "   http://127.0.0.1:$port/v1"
    echo ""
    echo -e "🔑 API 密钥 (Password):"
    echo -e "   $pass"
    echo ""
    echo -e "🆔 Google Cloud 项目ID:"
    echo -e "   $proj"
    
    ui_pause
}

configure_params() {
    if [ ! -f "$ENV_FILE" ]; then touch "$ENV_FILE"; fi
    local port=$(grep "^PORT=" "$ENV_FILE" | cut -d= -f2); [ -z "$port" ] && port=8888
    local pass=$(grep "^GEMINI_AUTH_PASSWORD=" "$ENV_FILE" | cut -d= -f2); [ -z "$pass" ] && pass="password"
    local proj=$(grep "^GOOGLE_CLOUD_PROJECT=" "$ENV_FILE" | cut -d= -f2); [ -z "$proj" ] && proj="未设置 (自动)"
    
    while true; do
        ui_header "参数配置"
        echo -e "端口: $port | 密码: $pass"
        echo -e "项目ID: $proj"
        echo ""
        
        CHOICE=$(ui_menu "选择修改项" "🆔 修改项目标识 (Project ID)" "🔌 修改端口" "🔑 修改密码" "🔙 返回")
        case "$CHOICE" in
            *"项目标识"*) 
                echo -e "${CYAN}提示: 请输入您的 Google Cloud Project ID (如: my-project-123)${NC}"
                echo -e "${YELLOW}留空则使用自动探测模式。${NC}"
                new_id=$(ui_input "输入 Project ID" "$proj" "false")
                
                if [[ "$new_id" =~ [^a-zA-Z0-9-] ]]; then
                    ui_print error "格式错误！Project ID 只能包含字母、数字和横杠。"
                    ui_pause
                    continue
                fi

                if [ -n "$new_id" ] && [ "$new_id" != "未设置 (自动)" ]; then
                    write_env_safe "$ENV_FILE" "GOOGLE_CLOUD_PROJECT" "$new_id"
                    proj=$new_id
                    ui_print success "项目 ID 已保存！"
                else
                    sed -i '/^GOOGLE_CLOUD_PROJECT=/d' "$ENV_FILE"
                    proj="未设置 (自动)"
                    ui_print info "已恢复自动探测模式。"
                fi
                ui_pause
                ;;
            *"端口"*) 
                p=$(ui_input "输入新端口" "$port" "false")
                if [[ "$p" =~ ^[0-9]+$ ]]; then 
                    write_env_safe "$ENV_FILE" "PORT" "$p"
                    port=$p; ui_print success "已保存 (重启生效)"
                fi ;;
            *"密码"*) 
                p=$(ui_input "输入新密码" "$pass" "false")
                if [ -n "$p" ]; then 
                    write_env_safe "$ENV_FILE" "GEMINI_AUTH_PASSWORD" "$p"
                    pass=$p; ui_print success "已保存 (重启生效)"
                fi ;;
            *"返回"*) return ;; 
        esac
    done
}

gemini_menu() {
    while true; do
        ui_header "Gemini 3.0 智能代理"
        local s="${RED}● 已停止${NC}"
        if check_process_smart "$GEMINI_PID_FILE" "python.*run.py"; then
            s="${GREEN}● 运行中${NC}"
        fi
        
        local cf="${RED}关${NC}"; pgrep -f "cloudflared" >/dev/null && cf="${GREEN}开${NC}"
        local a="${YELLOW}未认证${NC}"; [ -f "$CREDS_FILE" ] && a="${GREEN}已认证${NC}"
        
        echo -e "状态: $s | 隧道: $cf | 授权: $a"
        echo "----------------------------------------"

        CHOICE=$(ui_menu "请选择操作" \
            "🚀 启动/重启服务" \
            "🌍 开启/关闭远程穿透" \
            "🔑 Google 账号授权" \
            "📥 安装/重装服务" \
            "📝 查看连接信息" \
            "⚙️  配置参数" \
            "📜 查看运行日志" \
            "🛑 停止所有服务" \
            "🔙 返回上级"
        )
        case "$CHOICE" in
            *"启动"*) start_service ;; 
            *"远程穿透"*) 
                if pgrep -f "cloudflared" >/dev/null; then stop_tunnel; else start_tunnel; fi ;; 
            *"授权"*) authenticate_google ;; 
            *"安装"*) install_gemini ;; 
            *"连接信息"*) show_info ;; 
            *"配置"*) configure_params ;; 
            *"日志"*) safe_log_monitor "$LOG_FILE" ;; 
            *"停止"*) stop_service ;; 
            *"返回"*) return ;; 
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then gemini_menu; fi
