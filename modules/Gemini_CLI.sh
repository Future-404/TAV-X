#!/bin/bash
# TAV-X Module: Gemini 2.0 Proxy (V2.4 Final: Protocol Swap & Double Fallback)

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

GEMINI_DIR="$TAVX_DIR/gemini_proxy"
ENV_FILE="$GEMINI_DIR/.env"
VENV_PYTHON="$GEMINI_DIR/venv/bin/python"
VENV_PIP="$GEMINI_DIR/venv/bin/pip"
LOG_FILE="$GEMINI_DIR/gemini.log"
REPO_PATH="gzzhongqi/geminicli2api"

# --- 🛠️ 辅助函数 ---
safe_env_write() {
    local key="$1"; local val="$2"
    [ ! -f "$ENV_FILE" ] && touch "$ENV_FILE"
    if [ -f "$VENV_PYTHON" ]; then
        "$VENV_PYTHON" -c "
import sys, os
k, v = sys.argv[1], sys.argv[2]
path = '$ENV_FILE'
lines = []
if os.path.exists(path):
    with open(path, 'r', encoding='utf-8') as f: lines = f.readlines()
found = False
with open(path, 'w', encoding='utf-8') as f:
    for line in lines:
        if line.strip().startswith(k + '='):
            f.write(f'{k}={v}\n')
            found = True
        else:
            f.write(line)
    if not found: f.write(f'{k}={v}\n')
" "$key" "$val"
    else
        if grep -q "^${key}=" "$ENV_FILE"; then
            sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
        else
            echo "${key}=${val}" >> "$ENV_FILE"
        fi
    fi
}

env_get() {
    local key=$1
    if [ -f "$ENV_FILE" ]; then
        grep "^${key}=" "$ENV_FILE" | head -n 1 | cut -d'=' -f2- | tr -d '\r\n'
    fi
}

check_is_installed() {
    if [ -d "$GEMINI_DIR" ] && [ -f "$VENV_PYTHON" ]; then return 0; else return 1; fi
}

# --- 🧠 智能网络核心 ---
# 返回经过 HTTP 协议转译的代理字符串
get_compatible_proxy() {
    _auto_heal_network_config
    local network_conf="$TAVX_DIR/config/network.conf"
    
    if [ -f "$network_conf" ]; then
        local c=$(cat "$network_conf")
        if [[ "$c" == PROXY* ]]; then
            local raw_url=${c#*|}; raw_url=$(echo "$raw_url"|tr -d '\n\r')
            
            # [策略1] 协议转译: 如果是 socks，强制改为 http 以适配 pip
            if [[ "$raw_url" == socks* ]]; then
                # 替换 socks5h:// 或 socks5:// 为 http://
                local http_url="${raw_url/socks5h/http}"
                http_url="${http_url/socks5/http}"
                echo "$http_url"
                return 0
            else
                # 本身就是 http 或其他，直接返回
                echo "$raw_url"
                return 0
            fi
        fi
    fi
    return 1
}

# --- 🚀 安装逻辑 ---
install_gemini() {
    ui_header "部署 Gemini 代理服务"
    
    # 1. 编译依赖补全
    local NEED_PKGS=""
    if ! command -v python &> /dev/null; then NEED_PKGS="$NEED_PKGS python"; fi
    if ! command -v clang &> /dev/null; then NEED_PKGS="$NEED_PKGS build-essential clang"; fi
    if command -v pkg &> /dev/null; then
        NEED_PKGS="$NEED_PKGS libjpeg-turbo libxml2 libxslt zlib binutils rust"
    fi

    if [ -n "$NEED_PKGS" ]; then
        ui_print info "正在补全编译依赖..."
        if ! pkg install $NEED_PKGS -y; then
            ui_print error "依赖安装失败。"
            ui_pause; return 1
        fi
    fi

    # 2. 源码下载
    safe_rm "$GEMINI_DIR"
    local CLONE_CMD="source \"$TAVX_DIR/core/utils.sh\"; git_clone_smart '' '$REPO_PATH' '$GEMINI_DIR'"
    if ! ui_spinner "正在下载源码..." "$CLONE_CMD"; then
        ui_print error "源码下载失败。"; ui_pause; return 1
    fi

    cd "$GEMINI_DIR" || return
    
    # 3. 虚拟环境
    ui_print info "创建虚拟环境 (venv)..."
    python -m venv venv

    # 4. 构建网络环境变量
    local PROXY_URL=$(get_compatible_proxy)
    local PROXY_ENV=""
    if [ -n "$PROXY_URL" ]; then
        PROXY_ENV="env http_proxy='$PROXY_URL' https_proxy='$PROXY_URL'"
    fi
    
    local BUILD_FLAGS="export CFLAGS='-I$PREFIX/include' LDFLAGS='-L$PREFIX/lib'"

    # 5. Pip 升级 (双重降级策略)
    local pip_success=false
    
    # 尝试 A: 代理模式 (如果配置了代理)
    if [ -n "$PROXY_ENV" ]; then
        if ui_spinner "升级 Pip (代理模式: HTTP)..." "$PROXY_ENV $VENV_PIP install --upgrade pip --no-cache-dir"; then
            pip_success=true
        else
            ui_print warn "代理连接失败，切换直连..."
        fi
    fi
    
    # 尝试 B: 直连模式 (如果 A 失败或未配置代理)
    if [ "$pip_success" = false ]; then
        if ui_spinner "升级 Pip (直连模式)..." "env -u http_proxy -u https_proxy $VENV_PIP install --upgrade pip --no-cache-dir"; then
            pip_success=true
        else
            ui_print warn "Pip 升级跳过 (非致命错误)。"
        fi
    fi

    # 6. 安装业务依赖 (双重降级策略)
    local install_success=false
    local REQ_CMD="$BUILD_FLAGS; $VENV_PIP install -r requirements.txt --no-cache-dir"
    
    # 尝试 A: 代理模式
    if [ -n "$PROXY_ENV" ]; then
        if ui_spinner "安装依赖 (代理模式: HTTP)..." "$PROXY_ENV $REQ_CMD"; then
            install_success=true
        else
            ui_print warn "代理安装失败，尝试直连重试..."
        fi
    fi
    
    # 尝试 B: 直连模式
    if [ "$install_success" = false ]; then
        if ui_spinner "安装依赖 (直连模式)..." "env -u http_proxy -u https_proxy $REQ_CMD"; then
            install_success=true
        fi
    fi

    if [ "$install_success" = true ]; then
        safe_env_write "PORT" "8888"
        safe_env_write "HOST" "127.0.0.1"
        ui_print success "部署完成！"
    else
        ui_print error "最终安装失败。"
        echo -e "${YELLOW}诊断建议:${NC}"
        echo -e "1. 代理端口不支持 HTTP 协议 (请确认 VPN 设置中开启了 Mixed Port)。"
        echo -e "2. 直连网络无法访问 PyPI (请检查网络连通性)。"
        ui_pause; return 1
    fi
    ui_pause
}

# --- 🎮 核心控制 ---
start_gemini() {
    if ! check_is_installed; then
        ui_header "组件缺失"
        if ui_confirm "Gemini 服务未安装，是否安装？"; then
            install_gemini
            check_is_installed || return
        else return; fi
    fi

    local key=$(env_get GEMINI_API_KEY)
    if [ -z "$key" ]; then
        ui_print warn "未配置 API Key！"
        configure_gemini
        key=$(env_get GEMINI_API_KEY)
        [ -z "$key" ] && return
    fi

    ui_header "启动服务"
    pkill -f "$VENV_PYTHON main.py"
    
    # 启动时同样使用“协议转译”后的代理
    local PROXY_URL=$(get_compatible_proxy)
    local PROXY_ENV=""
    local PROXY_MSG="${YELLOW}直连模式${NC}"
    
    if [ -n "$PROXY_URL" ]; then
        PROXY_ENV="env http_proxy='$PROXY_URL' https_proxy='$PROXY_URL' all_proxy='$PROXY_URL'"
        PROXY_MSG="${GREEN}代理接管 (HTTP)${NC}"
    fi

    cd "$GEMINI_DIR" || return
    
    if ui_spinner "正在启动..." "$PROXY_ENV nohup $VENV_PYTHON main.py > '$LOG_FILE' 2>&1 & sleep 3"; then
        if pgrep -f "main.py" >/dev/null; then
            local port=$(env_get PORT)
            [ -z "$port" ] && port=8888
            ui_print success "运行中: http://127.0.0.1:$port/v1"
            echo -e "网络: $PROXY_MSG"
        else
            ui_print error "启动失败，请检查日志"
        fi
    else
        ui_print error "执行超时"
    fi
    ui_pause
}

stop_gemini() {
    pkill -f "$VENV_PYTHON main.py"
    ui_print success "服务已停止"; ui_pause
}

configure_gemini() {
    if ! check_is_installed; then ui_print error "请先安装！"; ui_pause; return; fi
    while true; do
        ui_header "Gemini 配置"
        local k=$(env_get GEMINI_API_KEY)
        local p=$(env_get PORT)
        [ -z "$p" ] && p=8888
        
        echo "API Key: ${k:0:6}******"
        echo "端口: $p"
        
        CHOICE=$(ui_menu "选项" "🔑 设置 Key" "🔌 修改端口" "🔙 返回")
        case "$CHOICE" in
            *"Key"*) val=$(ui_input "输入 Key" "$k" "true"); [ -n "$val" ] && safe_env_write "GEMINI_API_KEY" "$val" ;;
            *"端口"*) val=$(ui_input "端口" "$p" "false"); [[ "$val" =~ ^[0-9]+$ ]] && safe_env_write "PORT" "$val" ;;
            *"返回"*) return ;;
        esac
    done
}

gemini_menu() {
    while true; do
        ui_header "Gemini 智能代理"
        if pgrep -f "$VENV_PYTHON main.py" >/dev/null; then S="${GREEN}● 运行中${NC}"; else S="${RED}● 已停止${NC}"; fi
        echo -e "状态: $S"
        CHOICE=$(ui_menu "菜单" "🚀 启动服务" "⚙️  配置参数" "📜 实时日志" "🛑 停止服务" "📥 重装更新" "🔙 返回")
        case "$CHOICE" in
            *"启动"*) start_gemini ;;
            *"配置"*) configure_gemini ;;
            *"日志"*) safe_log_monitor "$LOG_FILE" ;;
            *"停止"*) stop_gemini ;;
            *"重装"*) rm -rf "$GEMINI_DIR"; install_gemini ;;
            *"返回"*) return ;;
        esac
    done
}