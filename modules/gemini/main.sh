#!/bin/bash
# [METADATA]
# MODULE_ID: gemini
# MODULE_NAME: Gemini 智能代理
# MODULE_ENTRY: gemini_menu
# [END_METADATA]

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"
source "$TAVX_DIR/core/python_utils.sh"

_gemini_vars() {
    GE_APP_ID="gemini"
    GE_DIR=$(get_app_path "$GE_APP_ID")
    GE_VENV="$GE_DIR/venv"
    GE_LOG="$LOGS_DIR/gemini.log"
    GE_PID="$RUN_DIR/gemini.pid"
    GE_ENV_CONF="$CONFIG_DIR/gemini.env"
    GE_CREDS="$GE_DIR/oauth_creds.json"
    GE_REPO="https://github.com/gzzhongqi/geminicli2api"
    mkdir -p "$GE_DIR"
}

_gemini_check_google() {
    ui_print info "检测 Google 连通性..."
    local proxy=$(get_active_proxy)
    local cmd="curl -I -s --max-time 5 https://www.google.com"
    [ -n "$proxy" ] && cmd="$cmd --proxy $proxy"
    
    if $cmd >/dev/null 2>&1; then return 0; fi
    ui_print error "无法连接 Google！Gemini 服务必须通过代理工作。"
    return 1
}

gemini_install() {
    _gemini_vars
    ui_header "部署 Gemini 代理"
    
    # 提前准备网络策略
    prepare_network_strategy

    if [ ! -d "$GE_DIR/.git" ]; then
        if ! git_clone_smart "" "$GE_REPO" "$GE_DIR"; then
            ui_print error "源码下载失败。"
            return 1
        fi
    else
        ui_print info "同步最新代码..."
        (cd "$GE_DIR" && git pull)
    fi
    
    if ui_stream_task "创建虚拟环境..." "source \"\$TAVX_DIR/core/python_utils.sh\"; create_venv_smart '$GE_VENV'"; then
        ui_print info "正在安装项目依赖..."
        local INSTALL_CMD="source \"\$TAVX_DIR/core/python_utils.sh\"; install_requirements_smart '$GE_VENV' '$GE_DIR/requirements.txt' 'standard'"
        
        if ! ui_stream_task "安装 Python 依赖..." "$INSTALL_CMD"; then
            ui_print error "依赖安装失败。"
            return 1
        fi
    else
        ui_print error "虚拟环境创建失败。"
        return 1
    fi
    
    if [ ! -f "$GE_ENV_CONF" ]; then
        echo -e "HOST=0.0.0.0\nPORT=8888\nGEMINI_AUTH_PASSWORD=password" > "$GE_ENV_CONF"
    fi
    ui_print success "安装完成。"
}

gemini_start() {
    _gemini_vars
    [ ! -d "$GE_DIR" ] && { gemini_install || return 1; }
    _gemini_check_google || return 1
    
    gemini_stop
    local port=$(grep "^PORT=" "$GE_ENV_CONF" | cut -d= -f2); [ -z "$port" ] && port=8888
    ln -sf "$GE_ENV_CONF" "$GE_DIR/.env"
    
    if [ ! -f "$GE_CREDS" ]; then
        ui_print error "未找到凭据。请先授权。"
        ui_pause; return 1
    fi
    
    local proxy=$(get_active_proxy)
    local p_env=""
    [ -n "$proxy" ] && p_env="http_proxy='$proxy' https_proxy='$proxy' all_proxy='$proxy'"
    
    local CMD="cd '$GE_DIR' && source '$GE_VENV/bin/activate' && env $p_env nohup python run.py > '$GE_LOG' 2>&1 & echo \$! > '$GE_PID'"
    
    if ui_spinner "启动进程..." "eval \"$CMD\"" ; then
        sleep 2
        if check_process_smart "$GE_PID" "python.*run.py"; then
            ui_print success "服务已启动。"
        else
            ui_print error "启动失败，请检查日志。"
            tail -n 5 "$GE_LOG"
        fi
    fi
}

gemini_stop() {
    _gemini_vars
    kill_process_safe "$GE_PID" "python.*run.py"
}

gemini_uninstall() {
    _gemini_vars
    if verify_kill_switch; then
        gemini_stop
        ui_spinner "清理文件中..." "safe_rm '$GE_DIR' '$GE_ENV_CONF' '$GE_PID' '$GE_LOG'"
        ui_print success "已卸载。"
        return 2
    fi
}

authenticate_google() {
    _gemini_vars
    [ ! -d "$GE_DIR" ] && { gemini_install || return 1; }
    _gemini_check_google || return 1
    
    if [ -f "$GE_CREDS" ]; then
        if ! ui_confirm "已存在凭据，是否重新认证？"; then return; fi
        safe_rm "$GE_CREDS"
    fi
    
    gemini_stop
    local proxy=$(get_active_proxy); local p_env=""
    [ -n "$proxy" ] && p_env="http_proxy='$proxy' https_proxy='$proxy'"
    
    local AUTH_LOG="$TMP_DIR/gemini_auth.log"
    local CMD="source '$GE_VENV/bin/activate' && env -u GEMINI_CREDENTIALS GEMINI_AUTH_PASSWORD='init' PYTHONUNBUFFERED=1 $p_env python -u run.py > '$AUTH_LOG' 2>&1 & echo \$! > '$GE_PID'"
    eval "$CMD"
    
    ui_print info "等待认证链接..."
    local url=""
    for i in {1..15}; do
        if grep -q "https://accounts.google.com" "$AUTH_LOG"; then
            url=$(grep -o "https://accounts.google.com[^ ]*" "$AUTH_LOG" | head -n 1 | tr -d '\r\n')
            break
        fi
        sleep 1
    done
    
    if [ -n "$url" ]; then
        open_browser "$url"
        ui_print success "浏览器已打开，登录后请回来启动服务。"
    else
        ui_print error "获取链接超时。"
    fi
    ui_pause
}

gemini_menu() {
    while true; do
        _gemini_vars
        ui_header "♊ Gemini 智能代理"
        local state="stopped"; local text="未运行"; local info=()
        if check_process_smart "$GE_PID" "python.*run.py"; then
            state="running"; text="运行中"
            local port=$(grep "^PORT=" "$GE_ENV_CONF" 2>/dev/null | cut -d= -f2)
            info+=( "地址: http://127.0.0.1:${port:-8888}/v1" )
        fi
        [ -f "$GE_CREDS" ] && info+=( "授权: ✅" ) || info+=( "授权: ❌" )
        
        ui_status_card "$state" "$text" "${info[@]}"
        local CHOICE=$(ui_menu "操作菜单" "🚀 启动/重启" "🔑 Google认证" "⚙️  修改配置" "🛑 停止服务" "📜 查看日志" "⬆️  更新代码" "🗑️  卸载模块" "🔙 返回")
        case "$CHOICE" in
            *"启动"*) gemini_start; ui_pause ;;
            *"认证"*) authenticate_google ;;
            *"配置"*) 
                local p=$(grep "^PORT=" "$GE_ENV_CONF" | cut -d= -f2)
                local new_p=$(ui_input "新端口" "${p:-8888}" "false")
                if [ -n "$new_p" ]; then
                    write_env_safe "$GE_ENV_CONF" "PORT" "$new_p"
                    ui_print success "已保存"
                fi
                ui_pause ;;
            *"停止"*) gemini_stop; ui_print success "已停止"; ui_pause ;;
            *"日志"*) safe_log_monitor "$GE_LOG" ;;
            *"更新"*) gemini_install ;;
            *"卸载"*) gemini_uninstall && [ $? -eq 2 ] && return ;;
            *"返回"*) return ;;
        esac
    done
}
