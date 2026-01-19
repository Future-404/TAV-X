#!/bin/bash
# [METADATA]
# MODULE_ID: koishi
# MODULE_NAME: Koishi 机器人
# MODULE_ENTRY: koishi_menu
# APP_CATEGORY: AIBOX
# APP_AUTHOR: KoishiJS
# APP_PROJECT_URL: https://koishi.chat/
# APP_DESC: Koishi 是一个跨平台、极具扩展性的聊天机器人框架。支持多平台适配（OneBot, Telegram, Discord等）和丰富的插件生态。
# [END_METADATA]

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

_koishi_vars() {
    KOISHI_ID="koishi"
    KOISHI_DIR=$(get_app_path "$KOISHI_ID")
    KOISHI_PID="$RUN_DIR/koishi.pid"
    KOISHI_LOG="$KOISHI_DIR/koishi.log"
    KOISHI_CONFIG="$KOISHI_DIR/koishi.yml"
}

_koishi_check_env() {
    if ! command -v node &>/dev/null; then
        ui_print error "需要 Node.js 环境。请先安装 Node.js。"
        return 1
    fi
    return 0
}

koishi_install() {
    _koishi_vars
    ui_header "部署 Koishi 机器人"
    
    _koishi_check_env || return
    
    if [ -d "$KOISHI_DIR" ] && [ -f "$KOISHI_DIR/package.json" ]; then
        ui_print warn "Koishi 似乎已经安装在: $KOISHI_DIR"
        if ! ui_confirm "要重新安装吗？(将覆盖原有配置)"; then return; fi
        safe_rm "$KOISHI_DIR"
    fi

    mkdir -p "$KOISHI_DIR"
    cd "$KOISHI_DIR" || return

    ui_print info "应用网络加速策略..."
    prepare_network_strategy "NPM"

    ui_print info "正在通过官方脚手架初始化..."
    if ui_stream_task "正在安装 Koishi 核心框架..." "echo 'n' | npx --yes create-koishi . && npm install"; then
        ui_print success "安装完成！"
    else
        ui_print error "安装失败，请检查网络。"
        return 1
    fi
    ui_pause
}

koishi_start() {
    _koishi_vars
    if [ ! -d "$KOISHI_DIR" ]; then
        ui_print error "Koishi 未安装。"
        return 1
    fi

    local port=$(grep "port:" "$KOISHI_CONFIG" | awk '{print $2}' | tr -d '\r')
    [ -z "$port" ] && port="5140"

    if [ "$OS_TYPE" == "TERMUX" ]; then
        tavx_service_register "koishi" "npx koishi start" "$KOISHI_DIR"
        tavx_service_control "up" "koishi"
        ui_print success "Koishi 启动指令已发送。"
        ui_print info "Web 控制台地址: http://127.0.0.1:$port"
        
        sleep 2
        if command -v termux-open-url &>/dev/null; then
             termux-open-url "http://127.0.0.1:$port"
        fi
    else
        cd "$KOISHI_DIR" || return 1
        koishi_stop >/dev/null 2>&1
        rm -f "$KOISHI_LOG"
        
        local START_CMD="setsid nohup npx koishi start > '$KOISHI_LOG' 2>&1 & echo \$! > '$KOISHI_PID'"
        ui_spinner "正在启动 Koishi..." "eval \"$START_CMD\""
        
        sleep 2
        if check_process_smart "$KOISHI_PID" "koishi"; then
             ui_print success "Koishi 已在后台运行。"
             ui_print info "Web 控制台地址: http://127.0.0.1:$port"
             if command -v xdg-open &>/dev/null; then
                 xdg-open "http://127.0.0.1:$port" >/dev/null 2>&1
             fi
        else
             ui_print error "启动失败，请检查日志。"
        fi
    fi
}

koishi_stop() {
    _koishi_vars
    if [ "$OS_TYPE" == "TERMUX" ]; then
        tavx_service_control "down" "koishi"
    else
        kill_process_safe "$KOISHI_PID" "koishi"
    fi
}

koishi_uninstall() {
    _koishi_vars
    ui_header "卸载 Koishi"
    if ! verify_kill_switch; then return; fi
    
    koishi_stop
    
    if ui_spinner "正在删除文件..." "safe_rm '$KOISHI_DIR'"; then
        ui_print success "已卸载。"
        return 2
    fi
}

koishi_menu() {
    _koishi_vars
    if [ ! -d "$KOISHI_DIR" ]; then
        ui_header "Koishi 机器人"
        ui_print warn "应用尚未安装。"
        if ui_confirm "立即安装？"; then koishi_install; else return; fi
    fi

    while true; do
        _koishi_vars
        local state="stopped"; local text="已停止"
        
        if [ "$OS_TYPE" == "TERMUX" ]; then
            if sv status koishi 2>/dev/null | grep -q "^run:"; then
                state="running"; text="运行中"
            fi
        elif check_process_smart "$KOISHI_PID" "koishi"; then
             state="running"; text="运行中"
        fi
        
        local port=$(grep "port:" "$KOISHI_CONFIG" | awk '{print $2}' | tr -d '\r')
        [ -z "$port" ] && port="5140"
        
        ui_header "Koishi 管理面板"
        ui_status_card "$state" "$text" "端口: $port" "WebUI: http://127.0.0.1:$port"
        
        local CHOICE=$(ui_menu "操作菜单" "🚀 启动服务" "🛑 停止服务" "🔧 重置密码
        " "📜 查看日志" "🗑️  卸载模块" "🧭 关于模块" "🔙 返回")
        
        case "$CHOICE" in
            *"启动"*) koishi_start; ui_pause ;; 
            *"停止"*) koishi_stop; ui_print success "已停止"; ui_pause ;; 
            *"重置密码"*) 
                 ui_print info "请在启动状态下访问 Web 控制台进行配置。"
                 ui_print info "Koishi v4+ 默认为无密码模式，首次访问可创建管理员。"
                 ui_pause ;; 
            *"日志"*) 
                local log_path="$KOISHI_LOG"
                [ "$OS_TYPE" == "TERMUX" ] && log_path="$PREFIX/var/service/koishi/log/current"
                safe_log_monitor "$log_path"
                ;; 
            *"卸载"*) koishi_uninstall && [ $? -eq 2 ] && return ;; 
            *"关于"*) show_module_about_info "${BASH_SOURCE[0]}" ;; 
            *"返回"*) return ;; 
        esac
    done
}
