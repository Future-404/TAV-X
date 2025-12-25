#!/bin/bash
# [METADATA]
# MODULE_NAME: 🦀 ClewdR 管理
# MODULE_ENTRY: clewd_menu
# [END_METADATA]
source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

CLEWD_DIR="$TAVX_DIR/clewdr"
BIN_FILE="$CLEWD_DIR/clewdr"
LOG_FILE="$CLEWD_DIR/clewdr.log"
SECRETS_FILE="$CLEWD_DIR/secrets.env"

# 源码模式配置
SRC_REPO="https://github.com/teralomaniac/clewd"
SRC_ENTRY="clewd.js"

install_clewdr() {
    ui_header "安装 Clewd (ClewdR)"

    if ! command -v unzip &> /dev/null; then
        ui_print warn "正在安装解压工具..."
        if [ "$OS_TYPE" == "TERMUX" ]; then
            pkg install unzip -y >/dev/null 2>&1
        else
            $SUDO_CMD apt-get install -y unzip
        fi
    fi

    mkdir -p "$CLEWD_DIR"
    cd "$CLEWD_DIR" || return

    # --- Termux: 使用预编译的高效二进制 ---
    if [ "$OS_TYPE" == "TERMUX" ]; then
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

        if ui_spinner "正在下载 ClewdR (Android)..." "$CMD"; then
            ui_print success "安装完成！"
        else
            ui_print error "下载失败，请检查网络。"
        fi
        
    else
        # --- Linux: 使用官方源码部署 (兼容性最好) ---
        ui_print info "Linux 环境检测: 切换为源码部署模式..."
        safe_rm "$CLEWD_DIR" # 清理旧目录以免冲突
        
        prepare_network_strategy "$SRC_REPO"
        
        local CLONE_CMD="source \"$TAVX_DIR/core/utils.sh\"; git_clone_smart '' '$SRC_REPO' '$CLEWD_DIR'"
        if ui_spinner "正在拉取 Clewd 源码..." "$CLONE_CMD"; then
            ui_print info "正在安装依赖..."
            if npm_install_smart "$CLEWD_DIR"; then
                 ui_print success "安装完成！"
            else
                 ui_print error "依赖安装失败。"
            fi
        else
            ui_print error "源码下载失败。"
        fi
    fi
    ui_pause
}

start_clewdr() {
    ui_header "启动 Clewd"
    
    # 检测运行模式
    local RUN_CMD=""
    if [ -f "$CLEWD_DIR/$SRC_ENTRY" ]; then
        # 源码模式
        RUN_CMD="node $SRC_ENTRY"
        cd "$CLEWD_DIR"
    elif [ -f "$BIN_FILE" ]; then
        # 二进制模式
        RUN_CMD="./clewdr"
        cd "$CLEWD_DIR"
    else
        if ui_confirm "未检测到程序，是否立即安装？"; then
            install_clewdr
            # 递归重试
            start_clewdr
            return
        else return; fi
    fi

    pkill -f "clewdr"
    pkill -f "node clewd.js"
    
    if ui_spinner "正在启动后台服务..." "setsid nohup $RUN_CMD > '$LOG_FILE' 2>&1 & sleep 3; pgrep -f '$RUN_CMD' | head -n 1 > '$CLEWD_PID_FILE'"; then
        # 检查进程是否存在
        if [ -f "$CLEWD_PID_FILE" ] && kill -0 $(cat "$CLEWD_PID_FILE") 2>/dev/null; then
            # 提取密码逻辑 (兼容两种日志格式)
            local API_PASS=$(grep -E "API Password:|Pass:" "$LOG_FILE" | head -n 1 | awk '{print $NF}')
            # Clewd 原版通常没有 Web Admin，或者格式不同，这里做个兼容尝试
            local WEB_PASS="无需/未知"
            
            echo "API_PASS=$API_PASS" > "$SECRETS_FILE"

            ui_print success "服务已启动！"
            echo ""
            
            echo -e "${CYAN}🔌 API 接口 (SillyTavern):${NC}"
            echo -e "   地址: http://127.0.0.1:8444/v1"
            echo -e "   密钥: ${YELLOW}${API_PASS:-请查看日志}${NC}"
            echo ""
            echo -e "${GRAY}注: 默认端口为 8444 (原版) 或 8484 (修改版)，请以日志为准。${NC}"
        else
            ui_print error "启动失败，请检查日志。"
            echo -e "${YELLOW}--- 日志预览 ---${NC}"
            tail -n 5 "$LOG_FILE"
        fi
    else
        ui_print error "启动超时。"
    fi
    ui_pause
}

stop_clewdr() {
    if [ -f "$CLEWD_PID_FILE" ]; then
        local pid=$(cat "$CLEWD_PID_FILE")
        [ -n "$pid" ] && kill -9 "$pid" >/dev/null 2>&1
        rm -f "$CLEWD_PID_FILE"
        ui_print success "服务已停止。"
        return
    fi

    if pgrep -f "clewdr" >/dev/null || pgrep -f "node clewd.js" >/dev/null; then
        pkill -f "clewdr"
        pkill -f "node clewd.js"
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
        echo "API密钥: ${API_PASS}"
        echo "日志路径: $LOG_FILE"
    else
        ui_print error "暂无缓存，请先启动服务。"
    fi
    ui_pause
}

clewd_menu() {
    while true; do
        ui_header "Clewd AI 反代管理"

        if [ -f "$CLEWD_PID_FILE" ] && kill -0 $(cat "$CLEWD_PID_FILE") 2>/dev/null; then
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
