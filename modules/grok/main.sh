#!/bin/bash
# [METADATA]
# MODULE_ID: grok
# MODULE_NAME: Grok2API (双模版)
# MODULE_ENTRY: grok_menu
# APP_CATEGORY: AI模型接口
# APP_AUTHOR: chenyme (Integrated by TAV-X)
# APP_PROJECT_URL: https://github.com/chenyme/grok2api
# APP_DESC: 基于 FastAPI 重构 Grok2API。支持 Termux (PRoot) 和 Linux (Native) 双模运行。
# [END_METADATA]

GROK_DIR="$APPS_DIR/grok"
GROK_CONF="$GROK_DIR/.env"
GROK_LOG="$LOGS_DIR/grok.log"
GROK_PID="$RUN_DIR/grok.pid"
GROK_MODULE_DIR="$TAVX_DIR/modules/grok"

_grok_vars() {
    [ -f "$TAVX_DIR/core/env.sh" ] && source "$TAVX_DIR/core/env.sh"
    [ -f "$TAVX_DIR/core/ui.sh" ] && source "$TAVX_DIR/core/ui.sh"
    [ -f "$TAVX_DIR/core/net_utils.sh" ] && source "$TAVX_DIR/core/net_utils.sh"
    [ -f "$TAVX_DIR/core/python_utils.sh" ] && source "$TAVX_DIR/core/python_utils.sh"
    if [ "$OS_TYPE" == "TERMUX" ]; then
        [ -f "$TAVX_DIR/core/proot_manager.sh" ] && source "$TAVX_DIR/core/proot_manager.sh"
    fi
    [ -f "$GROK_MODULE_DIR/utils.sh" ] && source "$GROK_MODULE_DIR/utils.sh"
    [ -f "$GROK_MODULE_DIR/install.sh" ] && source "$GROK_MODULE_DIR/install.sh"
}

grok_menu() {
    _grok_vars
    while true; do
        ui_header "Grok2API 面板"
        local state="stopped"; local text="已停止"; local info=()
        if [ "$OS_TYPE" == "TERMUX" ]; then
            if [ -d "$PREFIX/var/service/grok" ] && sv status grok 2>/dev/null | grep -q "^run:"; then
                state="running"; text="运行中 (PRoot)"
                info+=( "PID: $(sv status grok 2>/dev/null | awk '{print $4}' | tr -d ')')" )
            fi
        else
            if check_process_smart "$GROK_PID" "python3 main.py"; then
                state="running"; text="运行中 (Native)"; info+=( "PID: $(cat "$GROK_PID")" )
            fi
        fi
        if [ "$state" == "running" ]; then
            local port="8001"
            [ -f "$GROK_CONF" ] && port=$(grep "^PORT=" "$GROK_CONF" | cut -d'=' -f2)
            info+=( "端口: ${port:-8001}" )
        fi
        ui_status_card "$state" "$text" "${info[@]}"
        local options=("🚀 启动服务" "🛑 停止服务" "♻️  重启服务" "👀 查看日志" "⚙️  修改端口" "📚 获取 Token 教程" "📥 安装/更新" "🗑️ 卸载模块" "🔙 返回上级")
        local choice; choice=$(ui_menu "请选择操作" "${options[@]}")
        case "$choice" in
            *"启动服务"*) grok_start ;; 
            *"停止服务"*) grok_stop; ui_print success "已停止"; ui_pause ;; 
            *"重启服务"*) grok_stop; sleep 1; grok_start ;; 
            *"查看日志"*) [ "$OS_TYPE" == "TERMUX" ] && ui_watch_log "grok" || safe_log_monitor "$GROK_LOG" ;; 
            *"修改端口"*) grok_set_port ;; 
            *"教程"*) grok_show_tutorial ;;
            *"安装/更新"*) grok_install ;; 
            *"卸载模块"*) 
                if verify_kill_switch; then
                    grok_stop
                    [ "$OS_TYPE" == "TERMUX" ] && tavx_service_remove "grok"
                    safe_rm "$GROK_DIR" "$GROK_LOG" "$GROK_PID"
                    ui_print success "卸载完成。"
                    ui_pause; return
                fi ;; 
            *"返回"*) return ;; 
        esac
    done
}

grok_start() {
    _grok_vars
    [ ! -d "$GROK_DIR" ] && { grok_install || return 1; }
    
    if [ "$OS_TYPE" == "TERMUX" ]; then
        ui_header "启动服务 (Proot + PTY)"
        
        # [Hot Patch] 每次启动时同步最新的启动脚本
        # 这样通过 git pull 更新代码后，无需重装即可生效
        cp "$GROK_MODULE_DIR/boot.py" "$GROK_DIR/boot.py"
        cp "$GROK_MODULE_DIR/run.sh" "$GROK_DIR/run.sh"
        chmod +x "$GROK_DIR/run.sh"
        
        # 注册服务 (直接指向静态 Wrapper)
        tavx_service_register "grok" "./run.sh" "$GROK_DIR"
        tavx_service_control "up" "grok"
        
        # 检查健康
        ui_spinner "等待容器启动..." "sleep 5"
        if sv status grok 2>/dev/null | grep -q "^run:"; then
            ui_print success "PRoot 服务已启动 (PTY Mode)！"
        else
            ui_print error "服务启动失败，请查看日志。"
            ui_watch_log "grok"
            return
        fi
    else
        # [Linux] 原生启动逻辑
        ui_header "启动服务 (Native)"
        cd "$GROK_DIR" || return
        grok_stop >/dev/null 2>&1
        [ -f .env ] && export $(grep -v '^#' .env | xargs)
        local START_CMD="setsid nohup .venv/bin/python3 main.py > '$GROK_LOG' 2>&1 & echo \$! > '$GROK_PID'"
        ui_spinner "启动服务..." "eval \"$START_CMD\""
        sleep 2
        check_process_smart "$GROK_PID" "python3 main.py" && ui_print success "服务已启动" || { ui_print error "启动失败"; tail -n 5 "$GROK_LOG"; return; }
    fi
    
    local port="8001"
    [ -f "$GROK_CONF" ] && port=$(grep "^PORT=" "$GROK_CONF" | cut -d'=' -f2)
    ui_print info "Web 面板: http://127.0.0.1:${port:-8001}/login"
    
    if command -v termux-open-url &>/dev/null; then
         termux-open-url "http://127.0.0.1:${port:-8001}/login"
    elif command -v xdg-open &>/dev/null; then
         xdg-open "http://127.0.0.1:${port:-8001}/login" >/dev/null 2>&1
    fi
    ui_pause
}

grok_stop() {
    _grok_vars
    [ "$OS_TYPE" == "TERMUX" ] && tavx_service_control "force-stop" "grok" "-w 2" || kill_process_safe "$GROK_PID" "python3 main.py"
}
