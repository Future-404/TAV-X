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
LOG_FILE="$TAVX_DIR/logs/clewd.log"
PID_FILE="$TAVX_DIR/run/clewd.pid"
SECRETS_FILE="$CLEWD_DIR/secrets.env"

SRC_REPO="https://github.com/teralomaniac/clewd"
SRC_ENTRY="clewd.js"

# 确保日志目录存在
mkdir -p "$TAVX_DIR/logs"
mkdir -p "$TAVX_DIR/run"
# ... (中间省略 install_clewdr)

start_clewdr() {
    ui_header "启动 Clewd"
    
    local RUN_CMD=""
    if [ -f "$CLEWD_DIR/$SRC_ENTRY" ]; then
        RUN_CMD="node $SRC_ENTRY"
        cd "$CLEWD_DIR"
    elif [ -f "$BIN_FILE" ]; then
        RUN_CMD="./clewdr"
        cd "$CLEWD_DIR"
    else
        if ui_confirm "未检测到程序，是否立即安装？"; then
            install_clewdr
            start_clewdr
            return
        else return; fi
    fi

    kill_process_safe "$PID_FILE" "clewd"
    pkill -f "clewdr"
    pkill -f "node clewd.js"
    
    # 强制清理旧日志
    echo "--- Clewd Start $(date) ---" > "$LOG_FILE"
    
    local START_CMD="setsid nohup $RUN_CMD >> '$LOG_FILE' 2>&1 & echo \$! > '$PID_FILE'"
    
    if ui_spinner "正在启动后台服务..." "eval \"$START_CMD\""; then
        sleep 2
        if check_process_smart "$PID_FILE" "clewdr|node.*clewd\.js"; then
            local pid=$(cat "$PID_FILE")
            disown "$pid" 2>/dev/null

            # 尝试抓取密码 (延迟稍长一点以确保日志生成)
            sleep 1
            local API_PASS=$(grep -E "API Password:|Pass:" "$LOG_FILE" | head -n 1 | awk '{print $NF}')
            echo "API_PASS=$API_PASS" > "$SECRETS_FILE"

            ui_print success "服务已启动！"
            echo ""
            
            echo -e "${CYAN}🔌 API 接口 (SillyTavern):${NC}"
            echo -e "   地址: http://127.0.0.1:8444/v1"
            echo -e "   密钥: ${YELLOW}${API_PASS:-请查看日志}${NC}"
            echo ""
        else
            ui_print error "启动失败，进程未驻留。"
            echo -e "${YELLOW}--- 日志预览 ---${NC}"
            tail -n 5 "$LOG_FILE"
        fi
    else
        ui_print error "启动命令执行失败。"
    fi
    ui_pause
}

stop_clewdr() {
    kill_process_safe "$PID_FILE" "clewd"
    
    if pgrep -f "clewdr" >/dev/null || pgrep -f "node clewd.js" >/dev/null; then
        pkill -f "clewdr"
        pkill -f "node clewd.js"
        ui_print success "服务已停止。"
    else
        ui_print warn "服务未运行。"
    fi
    sleep 1
}

uninstall_clewd() {
    ui_header "卸载 Clewd"
    if ! verify_kill_switch; then return; fi

    kill_process_safe "$PID_FILE" "clewd"

    if ui_spinner "正在清除 ClewdR..." "safe_rm '$CLEWD_DIR'; rm -f '$PID_FILE'"; then
        ui_print success "ClewdR 模块已卸载。"
        return 2 
    else
        ui_print error "删除失败。"
        ui_pause
    fi
}

clewd_menu() {
    while true; do
        ui_header "Clewd AI 反代管理"

        local state_type="stopped"
        local status_text="已停止"
        local info_list=()

        if check_process_smart "$PID_FILE" "clewdr|node.*clewd\.js"; then
            state_type="running"
            status_text="运行中"
            
            # 尝试读取密码
            local pass="未知"
            [ -f "$SECRETS_FILE" ] && source "$SECRETS_FILE" && pass="${API_PASS:-未知}"
            
            info_list+=( "API地址: http://127.0.0.1:8444/v1" )
            info_list+=( "API密钥: $pass" )
        else
            info_list+=( "提示: 请先启动服务以获取密钥" )
        fi
        
        ui_status_card "$state_type" "$status_text" "${info_list[@]}"

        CHOICE=$(ui_menu "请选择操作" \
            "🚀 启动/重启服务" \
            "🔑 查看密码信息" \
            "📜 查看实时日志" \
            "🛑 停止后台服务" \
            "📥 强制更新重装" \
            "🗑️ 卸载 Clewd 模块" \
            "🔙 返回主菜单"
        )

        case "$CHOICE" in
            *"启动"*) start_clewdr ;; 
            *"密码"*) show_secrets ;; 
            *"日志"*) safe_log_monitor "$LOG_FILE" ;; 
            *"停止"*) stop_clewdr ;; 
            *"更新"*) install_clewdr ;; 
            *"卸载"*) uninstall_clewd; [ $? -eq 2 ] && return ;;
            *"返回"*) return ;; 
        esac
    done
}
