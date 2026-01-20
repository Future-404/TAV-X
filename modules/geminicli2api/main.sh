#!/bin/bash
# [METADATA]
# MODULE_ID: geminicli2api
# MODULE_NAME: Geminicli2api
# MODULE_ENTRY: geminicli2api_menu
# APP_CATEGORY: AI模型接口
# APP_AUTHOR: gzzhongqi
# APP_PROJECT_URL: https://github.com/gzzhongqi/geminicli2api
# APP_DESC: 基于 FastAPI 的代理转换服务，能够将GeminiCLI封装为兼容OpenAI和原生Gemini的API接口。让您通过熟悉的协议标准，无缝调用Google提供的免费Gemini模型配额。
# [END_METADATA]

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"
source "$TAVX_DIR/core/python_utils.sh"

_geminicli2api_vars() {
    GE_APP_ID="geminicli2api"
    GE_DIR=$(get_app_path "$GE_APP_ID")
    GE_VENV="$GE_DIR/venv"
    GE_LOG="$LOGS_DIR/geminicli2api.log"
    GE_PID="$RUN_DIR/geminicli2api.pid"
    GE_ENV_CONF="$CONFIG_DIR/geminicli2api.env"
    GE_CREDS="$GE_DIR/oauth_creds.json"
    GE_REPO="https://github.com/gzzhongqi/geminicli2api"
    mkdir -p "$GE_DIR"
}

_geminicli2api_check_google() {
    ui_print info "检测 Google 连通性..."
    local proxy
    proxy=$(get_active_proxy)
    local cmd="curl -I -s --max-time 5 https://www.google.com"
    [ -n "$proxy" ] && cmd="$cmd --proxy $proxy"
    
    if $cmd >/dev/null 2>&1; then return 0; fi
    ui_print error "无法连接 Google！Gemini 服务必须通过代理工作。"
    return 1
}

geminicli2api_install() {
    _geminicli2api_vars
    ui_header "部署 Gemini 智能代理"
    
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

geminicli2api_start() {
    _geminicli2api_vars
    if [ ! -d "$GE_DIR" ] || [ ! -f "$GE_ENV_CONF" ]; then
        geminicli2api_install || return 1
    fi
    _geminicli2api_check_google || return 1
    
    geminicli2api_stop
    local port
    port=$(grep "^PORT=" "$GE_ENV_CONF" | cut -d= -f2); [ -z "$port" ] && port=8888
    ln -sf "$GE_ENV_CONF" "$GE_DIR/.env"
    
    if [ ! -f "$GE_CREDS" ]; then
        ui_print error "未找到凭据。请先授权。"
        ui_pause; return 1
    fi
    
    local proxy
    proxy=$(get_active_proxy)
    local p_env=""
    [ -n "$proxy" ] && p_env="http_proxy=$proxy https_proxy=$proxy all_proxy=$proxy"
    
    local RUN_CMD="env $p_env '$GE_VENV/bin/python' run.py"

    ui_print info "正在启动服务..."

    if [ "$OS_TYPE" == "TERMUX" ]; then
        tavx_service_register "geminicli2api" "$RUN_CMD" "$GE_DIR"
        sv enable geminicli2api
        tavx_service_control "up" "geminicli2api"
        sleep 2
        ui_print success "服务启动命令已发送。"
    else
        local CMD="cd '$GE_DIR' && env $p_env setsid nohup python run.py > '$GE_LOG' 2>&1 & echo \!\! > '$GE_PID'"
        if ui_spinner "启动进程..." "eval \"$CMD\"" ; then
            sleep 2
            if check_process_smart "$GE_PID" "python.*run.py"; then
                ui_print success "服务已启动。"
            else
                ui_print error "启动失败，请检查日志。"
                tail -n 5 "$GE_LOG"
            fi
        fi
    fi
}

geminicli2api_stop() {
    _geminicli2api_vars
    if [ "$OS_TYPE" == "TERMUX" ]; then
        if [ -d "$PREFIX/var/service/geminicli2api" ]; then
            tavx_service_control "down" "geminicli2api"
        fi
    else
        kill_process_safe "$GE_PID" "python.*run.py"
    fi
}

geminicli2api_uninstall() {
    _geminicli2api_vars
    if verify_kill_switch; then
        geminicli2api_stop
        ui_spinner "清理文件中..." "safe_rm '$GE_DIR' '$GE_ENV_CONF' '$GE_PID' '$GE_LOG'"
        ui_print success "已卸载。"
        return 2
    fi
}

authenticate_google() {
    _geminicli2api_vars
    if [ ! -d "$GE_DIR" ] || [ ! -f "$GE_ENV_CONF" ]; then
        geminicli2api_install || return 1
    fi
    _geminicli2api_check_google || return 1
    
    if [ -f "$GE_CREDS" ]; then
        if ! ui_confirm "已存在凭据，是否重新认证？"; then return; fi
        safe_rm "$GE_CREDS"
    fi
    
    geminicli2api_stop
    local proxy
    proxy=$(get_active_proxy)
    local p_env=""
    [ -n "$proxy" ] && p_env="http_proxy='$proxy' https_proxy='$proxy'"
    
    local AUTH_LOG="$TMP_DIR/gemini_auth.log"
    local CMD="cd '$GE_DIR' && source '$GE_VENV/bin/activate' && env -u GEMINI_CREDENTIALS GEMINI_AUTH_PASSWORD='init' PYTHONUNBUFFERED=1 $p_env python -u run.py > '$AUTH_LOG' 2>&1 & echo \!\! > '$GE_PID'"
    eval "$CMD"
    
    ui_print info "等待认证链接..."
    local url=""
    # shellcheck disable=SC2034
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

geminicli2api_menu() {
    local old_app_path="$APPS_DIR/gemini"
    local new_app_path="$APPS_DIR/geminicli2api"
    if [ -d "$old_app_path" ] && [ ! -d "$new_app_path" ]; then
        if [ -f "$old_app_path/run.py" ]; then
            ui_print info "检测到旧版 Gemini 数据，正在迁移至新目录..."
            mv "$old_app_path" "$new_app_path"
            [ -f "$CONFIG_DIR/gemini.env" ] && mv "$CONFIG_DIR/gemini.env" "$CONFIG_DIR/geminicli2api.env"
            ui_print success "迁移完成！"
            sleep 1
        fi
    fi

    while true; do
        _geminicli2api_vars
        ui_header "♊ Gemini 智能代理"
        local state="stopped"; local text="未运行"; local info=()
        local log_path="$GE_LOG"
        [ "$OS_TYPE" == "TERMUX" ] && log_path="$PREFIX/var/service/geminicli2api/log/current"

        if [ "$OS_TYPE" == "TERMUX" ]; then
            if sv status geminicli2api 2>/dev/null | grep -q "^run:"; then
                state="running"; text="运行中"
            fi
        elif check_process_smart "$GE_PID" "python.*run.py"; then
            state="running"; text="运行中"
        fi

        if [ "$state" == "running" ]; then
            local port
            port=$(grep "^PORT=" "$GE_ENV_CONF" 2>/dev/null | cut -d= -f2)
            info+=( "地址: http://127.0.0.1:${port:-8888}/v1" )
        fi
        [ -f "$GE_CREDS" ] && info+=( "授权: ✅" ) || info+=( "授权: ❌" )
        
        ui_status_card "$state" "$text" "${info[@]}"
        local CHOICE
        CHOICE=$(ui_menu "操作菜单" "🚀 启动服务" "🔑 Google认证" "⚙️  修改配置" "🛑 停止服务" "📜 查看日志" "⬆️  更新代码" "🗑️  卸载模块" "🧭 关于模块" "🔙 返回")
        case "$CHOICE" in
            *"启动"*) geminicli2api_start; ui_pause ;; 
            *"认证"*) authenticate_google ;; 
            *"配置"*) 
                local p
                p=$(grep "^PORT=" "$GE_ENV_CONF" | cut -d= -f2)
                local new_p
                new_p=$(ui_input "新端口" "${p:-8888}" "false")
                if [ -n "$new_p" ]; then
                    write_env_safe "$GE_ENV_CONF" "PORT" "$new_p"
                    ui_print success "已保存"
                fi
                ui_pause ;; 
            *"停止"*) geminicli2api_stop; ui_print success "已停止"; ui_pause ;; 
            *"日志"*) safe_log_monitor "$log_path" ;; 
            *"更新"*) geminicli2api_install ;; 
            *"卸载"*) geminicli2api_uninstall && [ $? -eq 2 ] && return ;; 
            *"关于"*) show_module_about_info "${BASH_SOURCE[0]}" ;; 
            *"返回"*) return ;; 
        esac
    done
}