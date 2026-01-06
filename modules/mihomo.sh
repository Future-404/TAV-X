#!/bin/bash
# [METADATA]
# MODULE_NAME: ☁️  Mihomo 代理核心
# MODULE_ENTRY: mihomo_menu
# MODULE_UNINSTALL: uninstall_mihomo
# [END_METADATA]

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

MIHOMO_DIR="$TAVX_DIR/mihomo"
BINARY="$MIHOMO_DIR/mihomo"
CONFIG_FILE="$MIHOMO_DIR/config.yaml"
PROVIDER_DIR="$MIHOMO_DIR/proxy_providers"
UI_DIR="$MIHOMO_DIR/ui"
LOG_FILE="$MIHOMO_DIR/mihomo.log"
PID_FILE="$TAVX_DIR/run/mihomo.pid"
ENV_FILE="$TAVX_DIR/config/mihomo.conf"
SECRET_FILE="$TAVX_DIR/config/mihomo_secret.conf"
MIHOMO_VER="v1.19.18"

generate_config() {
    local sub_url="$1"
    local secret="${2:-}"
    mkdir -p "$PROVIDER_DIR"
    cat > "$CONFIG_FILE" <<EOF
port: 17890
socks-port: 17891
allow-lan: true
mode: rule
log-level: info
ipv6: true
external-controller: 0.0.0.0:19090
external-ui: ui
secret: "$secret"

proxy-providers:
  UserProvider:
    type: http
    url: "$sub_url"
    path: ./proxy_providers/subscription.yaml
    interval: 3600
    health-check:
      enable: true
      interval: 600
      url: http://www.gstatic.com/generate_204

proxy-groups:
  - name: "🚀 节点选择"
    type: select
    use:
      - UserProvider
    proxies:
      - DIRECT

rules:
  - MATCH,🚀 节点选择
EOF
}

install_mihomo_core() {
    ui_header "安装 Mihomo Core ($MIHOMO_VER)"
    mkdir -p "$MIHOMO_DIR"
    
    local arch=$(uname -m)
    local dl_arch=""
    case "$arch" in
        aarch64|arm64) dl_arch="arm64" ;;
        x86_64|amd64)  dl_arch="amd64" ;;
        *) ui_print error "不支持的架构: $arch"; ui_pause; return 1 ;;
    esac

    local filename="mihomo-linux-${dl_arch}-${MIHOMO_VER}.gz"
    local url="https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_VER}/${filename}"
    
    prepare_network_strategy
    if [ -n "$SELECTED_MIRROR" ] && [[ "$SELECTED_MIRROR" != *"github.com"* ]]; then
        url="${SELECTED_MIRROR}${url}"
    fi

    echo -e "正在下载: ${CYAN}$filename${NC}"
    if ui_spinner "下载核心二进制..." "curl -L -f -o '$BINARY.gz' '$url'"; then
        ui_spinner "解压并配置..." "gzip -d -f '$BINARY.gz' && chmod +x '$BINARY'"
        if [ ! -x "$BINARY" ]; then
             ui_print error "核心解压失败或无法执行。"
             safe_rm "$BINARY"
             return 1
        fi
        ui_print success "核心安装完成。"
    else
        ui_print error "下载失败，请检查网络设置。"
        safe_rm "$BINARY.gz"
        return 1
    fi
}

install_web_ui() {
    if [ -d "$UI_DIR" ] && [ -f "$UI_DIR/index.html" ]; then return 0; fi
    
    echo ""
    ui_print info "正在部署本地 WebUI (Metacubexd)..."
    
    if ! command -v unzip &>/dev/null; then
        if [ "$OS_TYPE" == "TERMUX" ]; then pkg install unzip -y >/dev/null; else $SUDO_CMD apt install unzip -y >/dev/null; fi
    fi

    local ui_filename="metacubexd.zip"
    local ui_url="https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip"
    if [ -z "$SELECTED_MIRROR" ]; then prepare_network_strategy; fi
    
    if [ -n "$SELECTED_MIRROR" ] && [[ "$SELECTED_MIRROR" != *"github.com"* ]]; then
        ui_url="${SELECTED_MIRROR}${ui_url}"
    fi

    safe_rm "$MIHOMO_DIR/$ui_filename"

    if ui_spinner "下载面板资源..." "curl -L -f -o '$MIHOMO_DIR/$ui_filename' '$ui_url'"; then
        if ! unzip -t "$MIHOMO_DIR/$ui_filename" &>/dev/null; then
             ui_print error "下载的文件已损坏 (校验失败)，请检查网络或更换镜像源。"
             safe_rm "$MIHOMO_DIR/$ui_filename"
             return 1
        fi

        ui_spinner "解压资源..." "
            unzip -o '$MIHOMO_DIR/$ui_filename' -d '$MIHOMO_DIR' >/dev/null
            safe_rm '$UI_DIR'
            mv '$MIHOMO_DIR/metacubexd-gh-pages' '$UI_DIR'
            safe_rm '$MIHOMO_DIR/$ui_filename'
        "
        ui_print success "WebUI 部署完成。"
    else
        ui_print warn "面板下载失败，您可能需要手动下载。"
        safe_rm "$MIHOMO_DIR/$ui_filename"
    fi
}

update_subscription() {
    ui_header "配置订阅链接"
    
    local current_url=""
    if [ -f "$ENV_FILE" ]; then
        current_url=$(cat "$ENV_FILE")
    fi
    
    echo -e "当前订阅: ${CYAN}${current_url:-未设置}${NC}"
    echo -e "${YELLOW}请输入您的订阅链接 (支持 Hysteria2/Vless 等 Base64 订阅)：${NC}"
    local sub_url=$(ui_input "URL" "$current_url" "false")
    
    if [[ ! "$sub_url" =~ ^http ]]; then
        ui_print error "无效的链接。"
        ui_pause; return
    fi
    
    echo "$sub_url" > "$ENV_FILE"
    ui_print info "正在应用新配置..."
    local secret=""
    [ -f "$SECRET_FILE" ] && secret=$(cat "$SECRET_FILE")
    generate_config "$sub_url" "$secret"
    safe_rm "$PROVIDER_DIR/subscription.yaml"
    ui_print success "配置已更新！核心将在启动时自动拉取节点。"
    ui_pause
}

configure_secret() {
    ui_header "设置面板密钥 (Secret)"
    local current_secret=""
    [ -f "$SECRET_FILE" ] && current_secret=$(cat "$SECRET_FILE")
    
    echo -e "当前状态: $([ -n "$current_secret" ] && echo -e "${GREEN}已设置${NC}" || echo -e "${YELLOW}未设置 (公开)${NC}")"
    echo -e "提示: 设置密钥后，登录 Web 面板需输入此密钥。"
    echo ""
    
    local sub=$(ui_menu "选择操作" "✏️  修改/设置密钥" "🗑️  清除密钥 (公开访问)" "🔙 返回")
    case "$sub" in
        *"修改"*)
            local inp=$(ui_input "输入新密钥" "$current_secret" "false")
            if [ -n "$inp" ]; then
                echo "$inp" > "$SECRET_FILE"
                ui_print success "密钥已保存！"
            fi
            ;;
        *"清除"*)
            rm -f "$SECRET_FILE"
            ui_print success "密钥已清除。"
            ;;
    esac
}

start_mihomo() {
    if [ ! -f "$BINARY" ]; then ui_print error "未安装核心"; return; fi
    if [ ! -f "$ENV_FILE" ]; then
        ui_print warn "未设置订阅链接。"
        if ui_confirm "现在去设置吗？"; then update_subscription; fi
        if [ ! -f "$ENV_FILE" ]; then return; fi
    fi
    local url=$(cat "$ENV_FILE")
    local secret=""
    [ -f "$SECRET_FILE" ] && secret=$(cat "$SECRET_FILE")
    generate_config "$url" "$secret"
    
    if check_process_smart "$PID_FILE" "mihomo"; then
        ui_print info "服务已经在运行中。"
        ui_pause; return
    fi
    
    if is_port_open 19090; then ui_print warn "端口 19090 被占用，WebUI 可能无法启动。"; fi
    
    chmod +x "$BINARY"
    
    # 确保日志目录存在
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"  # 预先创建日志文件

    export MIHOMO_DIR
    export BINARY
    export LOG_FILE
    export PID_FILE

    local TMP_START_SCRIPT="$MIHOMO_DIR/start_tmp.sh"
    cat << 'EOF' > "$TMP_START_SCRIPT"
#!/bin/bash
set -x
cd "$MIHOMO_DIR" || exit 1
echo ">>> Starting Mihomo..."
nohup "$BINARY" -d . > "$LOG_FILE" 2>&1 &
PID=$!
echo $PID > "$PID_FILE"
echo ">>> Process started with PID: $PID"
sleep 1
if ps -p $PID > /dev/null; then
    echo ">>> Process is running."
    exit 0
else
    echo ">>> Process died immediately."
    cat "$LOG_FILE"
    exit 1
fi
EOF
    chmod +x "$TMP_START_SCRIPT"

    if ui_spinner "正在启动 Mihomo ($MIHOMO_VER)..." "bash '$TMP_START_SCRIPT'"; then
        rm -f "$TMP_START_SCRIPT"
        ui_print success "服务已启动！"
        echo -e "WebUI 面板地址: ${CYAN}http://127.0.0.1:19090/ui${NC}"
        echo -e "提示: 初次启动需要几秒钟同步节点，请在 WebUI 中查看。"
        echo -e "HTTP 代理端口: ${YELLOW}17890${NC}"
    else
        rm -f "$TMP_START_SCRIPT"
        ui_print error "启动失败，请检查日志。"
        echo -e "${YELLOW}--- 日志预览 ($LOG_FILE) ---${NC}"
        if [ -f "$LOG_FILE" ]; then
            tail -n 10 "$LOG_FILE"
        else
            echo "日志文件不存在！"
        fi
    fi
    ui_pause
}

stop_mihomo() {
    kill_process_safe "$PID_FILE" "mihomo"
    ui_print success "服务已停止。"
    ui_pause
}

uninstall_mihomo() {
    ui_header "卸载 Mihomo 模块"
    if ! verify_kill_switch; then return; fi
    stop_mihomo >/dev/null 2>&1
    if ui_spinner "正在清除文件..." "safe_rm '$MIHOMO_DIR'; safe_rm '$ENV_FILE'"; then
        ui_print success "Mihomo 模块已卸载。"
        return 2 
    else
        ui_print error "删除失败。"
        ui_pause
    fi
}

mihomo_menu() {
    if [ ! -f "$BINARY" ]; then
        if ui_confirm "检测到 Mihomo 未安装，是否立即安装？"; then
            install_mihomo_core; install_web_ui; ui_pause
        else return; fi
    fi

    while true; do
        ui_header "Mihomo 代理核心 ($MIHOMO_VER)"
        
        local state_type="stopped"
        local status_text="已停止"
        local info_list=()
        
        if check_process_smart "$PID_FILE" "mihomo"; then 
            state_type="running"
            status_text="运行中"
            info_list+=( "WebUI: http://127.0.0.1:19090/ui" )
            info_list+=( "HTTP : 127.0.0.1:17890" )
            info_list+=( "SOCKS: 127.0.0.1:17891" )
        else
            info_list+=( "提示 : 请先启动服务" )
        fi
        
        ui_status_card "$state_type" "$status_text" "${info_list[@]}"
        
        CHOICE=$(ui_menu "请选择操作" \
            "🚀 启动/重启服务" \
            "🛑 停止服务" \
            "✏️  设置订阅链接" \
            "🔑 设置面板密钥" \
            "📊 打开 WebUI 面板" \
            "📜 查看运行日志" \
            "🗑️  卸载此模块" \
            "🔙 返回" 
        )
        
        case "$CHOICE" in
            *"启动"*) start_mihomo ;;
            *"停止"*) stop_mihomo ;;
            *"设置订阅"*) update_subscription ;;
            *"设置面板密钥"*) configure_secret ;;
            *"WebUI"*) open_browser "http://127.0.0.1:19090/ui"; ui_pause ;;
            *"日志"*) safe_log_monitor "$LOG_FILE" ;;
            *"卸载"*) uninstall_mihomo; [ $? -eq 2 ] && return ;;
            *"返回"*) return ;;
        esac
    done
}
 