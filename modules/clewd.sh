#!/bin/bash
# TAV-X Module: ClewdR Manager

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

CLEWD_DIR="$TAVX_DIR/clewdr"
BIN_FILE="$CLEWD_DIR/clewdr"
LOG_FILE="$CLEWD_DIR/clewdr.log"
SECRETS_FILE="$CLEWD_DIR/secrets.env"

install_clewdr() {
    ui_header "安装 ClewdR"

    if ! command -v unzip &> /dev/null; then
        ui_print warn "正在安装解压工具..."
        pkg install unzip -y >/dev/null 2>&1
    fi

    mkdir -p "$CLEWD_DIR"
    cd "$CLEWD_DIR" || return

    local URL="https://github.com/Xerxes-2/clewdr/releases/latest/download/clewdr-android-aarch64.zip"

    prepare_network_strategy "$URL"

    local CMD="
        source \"$TAVX_DIR/core/utils.sh\"
        if download_file_smart '$URL' 'clewd.zip'; then
            unzip -o clewd.zip >/dev/null 2>&1
            chmod +x clewdr
            rm clewd.zip
            exit 0
        else
            exit 1
        fi
    "

    if ui_spinner "正在下载并安装 (智能加速)..." "$CMD"; then
        ui_print success "安装完成！"
    else
        ui_print error "下载失败，请检查网络。"
    fi
    ui_pause
}

start_clewdr() {
    ui_header "启动 ClewdR"
    if [ ! -f "$BIN_FILE" ]; then
        if ui_confirm "未检测到程序，是否立即安装？"; then
            install_clewdr
            [ ! -f "$BIN_FILE" ] && return
        else return; fi
    fi

    pkill -f "$BIN_FILE"
    cd "$CLEWD_DIR" || return
    if ui_spinner "正在启动后台服务..." "setsid nohup '$BIN_FILE' > '$LOG_FILE' 2>&1 & sleep 3"; then
        if pgrep -f "$BIN_FILE" > /dev/null; then
            local API_PASS=$(grep "API Password:" "$LOG_FILE" | head -n 1 | awk '{print $3}')
            local WEB_PASS=$(grep "Web Admin Password:" "$LOG_FILE" | head -n 1 | awk '{print $4}')
            echo "API_PASS=$API_PASS" > "$SECRETS_FILE"
            echo "WEB_PASS=$WEB_PASS" >> "$SECRETS_FILE"

            ui_print success "服务已启动！"
            echo ""
            
            if [ "$HAS_GUM" = true ]; then
                echo -e " $(gum style --foreground 212 "📊 管理面板 (Web)")"
                echo -e "   地址: $(gum style --foreground 39 "http://127.0.0.1:8484")"
                echo -e "   密码: $(gum style --foreground 220 "${WEB_PASS:-未知}")"
                echo ""
                echo -e " $(gum style --foreground 212 "🔌 API 接口 (SillyTavern)")"
                echo -e "   地址: $(gum style --foreground 39 "http://127.0.0.1:8484/v1")"
                echo -e "   密钥: $(gum style --foreground 220 "${API_PASS:-未知}")"
            else
                echo "📊 管理面板: http://127.0.0.1:8484"
                echo "   密码: ${WEB_PASS:-未知}"
                echo ""
                echo "🔌 API 地址: http://127.0.0.1:8484/v1"
                echo "   密钥: ${API_PASS:-未知}"
            fi
        else
            ui_print error "启动失败，请检查日志。"
        fi
    else
        ui_print error "启动超时。"
    fi
    ui_pause
}

stop_clewdr() {
    if pgrep -f "$BIN_FILE" > /dev/null; then
        pkill -f "$BIN_FILE"
        ui_print success "服务已停止。"
    else
        ui_print warn "服务未运行。"
    fi
    sleep 1
}

show_secrets() {
    if [ -f "$SECRETS_FILE" ]; then
        source "$SECRETS_FILE"
        ui_header "连接信息"
        
        if [ "$HAS_GUM" = true ]; then
            echo -e " $(gum style --foreground 212 "📊 Web 管理端")"
            echo -e "   🔗 $(gum style --foreground 39 "http://127.0.0.1:8484")"
            echo -e "   🔑 $(gum style --foreground 220 "${WEB_PASS}")"
            echo ""
            echo -e " $(gum style --foreground 212 "🔌 API 接口")"
            echo -e "   🔗 $(gum style --foreground 39 "http://127.0.0.1:8484/v1")"
            echo -e "   🔑 $(gum style --foreground 220 "${API_PASS}")"
        else
            echo "Web密码: ${WEB_PASS}"
            echo "API密钥: ${API_PASS}"
        fi
    else
        ui_print error "暂无缓存，请先启动服务。"
    fi
    ui_pause
}

clewd_menu() {
    while true; do
        ui_header "ClewdR AI 反代管理"

        if pgrep -f "$BIN_FILE" >/dev/null; then
            STATUS="${GREEN}● 运行中${NC}"
        else
            STATUS="${RED}● 已停止${NC}"
        fi
        echo -e "状态: $STATUS"
        echo ""

        CHOICE=$(ui_menu "请选择操作" \
            "🚀 启动/重启服务" \
            "🔑 查看密码信息" \
            "📜 查看实时日志" \
            "🛑 停止后台服务" \
            "📥 强制更新重装" \
            "🔙 返回主菜单"
        )

        case "$CHOICE" in
            *"启动"*) start_clewdr ;;
            *"密码"*) show_secrets ;;
            *"日志"*) safe_log_monitor "$LOG_FILE" ;;
            *"停止"*) stop_clewdr ;;
            *"更新"*) install_clewdr ;;
            *"返回"*) return ;;
        esac
    done
}