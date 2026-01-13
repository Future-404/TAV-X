#!/bin/bash
# [METADATA]
# MODULE_ID: gcli2api
# MODULE_NAME: GCLI 转 API
# MODULE_ENTRY: gcli2api_menu
# [END_METADATA]

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"
source "$TAVX_DIR/core/python_utils.sh"

_gcli2api_vars() {
    GCLI_APP_ID="gcli2api"
    GCLI_DIR=$(get_app_path "$GCLI_APP_ID")
    GCLI_VENV="$GCLI_DIR/venv"
    GCLI_LOG="$LOGS_DIR/gcli2api.log"
    GCLI_PID="$RUN_DIR/gcli2api.pid"
    GCLI_CONF="$CONFIG_DIR/gcli2api.conf"
    GCLI_REPO="https://github.com/su-kaka/gcli2api"
}

_gcli2api_load_config() {
    _gcli2api_vars
    GCLI_PORT="7861"
    GCLI_PWD="pwd"
    GCLI_HOST="0.0.0.0"
    [ -f "$GCLI_CONF" ] && source "$GCLI_CONF"
}

gcli2api_install() {
    _gcli2api_vars
    ui_header "安装 GCLI2API"
    
    mkdir -p "$GCLI_DIR"
    
    prepare_network_strategy
    
    if [ ! -d "$GCLI_DIR/.git" ]; then
        if ! ui_stream_task "从 GitHub 克隆仓库..." "source \"\$TAVX_DIR/core/utils.sh\"; git_clone_smart '-b master' '$GCLI_REPO' '$GCLI_DIR'"; then
            ui_print error "克隆失败。"
            return 1
        fi
    else
        ui_print info "正在同步最新代码..."
        (cd "$GCLI_DIR" && git pull)
    fi
    
    if ! ui_spinner "创建虚拟环境..." "source \"\$TAVX_DIR/core/python_utils.sh\"; create_venv_smart '$GCLI_VENV'"; then
        ui_print error "虚拟环境创建失败。"
        return 1
    fi

    # [加速逻辑] Termux Python 3.12 专属预编译包
    if [ "$OS_TYPE" == "TERMUX" ] && check_python_version_match "3.12"; then
        ui_print info "正在获取 Termux 预编译加速包..."
        mkdir -p "$TMP_DIR/gcli_wheels"
        local wheel_base="https://github.com/Future-404/termux-python-wheels/raw/main/wheels"
        
        # 必须使用 linux_aarch64 后缀以兼容 pip
        local p_whl="pydantic_core-2.41.5-cp312-cp312-linux_aarch64.whl"
        local m_whl="pymongo-4.16.0-cp312-cp312-linux_aarch64.whl"
        
        # 在子shell中激活环境并安装 wheel
        (
            source "$GCLI_VENV/bin/activate"
            
            ui_stream_task "下载 pydantic-core..." "curl -L -f -s -o '$TMP_DIR/gcli_wheels/$p_whl' '$wheel_base/$p_whl'" && \
            pip install "$TMP_DIR/gcli_wheels/$p_whl"
            
            ui_stream_task "下载 pymongo..." "curl -L -f -s -o '$TMP_DIR/gcli_wheels/$m_whl' '$wheel_base/$m_whl'" && \
            pip install "$TMP_DIR/gcli_wheels/$m_whl"
        )
    fi
    
    local INSTALL_CMD="source \"\$TAVX_DIR/core/python_utils.sh\"; install_requirements_smart '$GCLI_VENV' '$GCLI_DIR/requirements.txt' 'standard'"
    if ! ui_stream_task "正在安装 Pip 依赖 (可能较慢)..." "$INSTALL_CMD"; then
        ui_print error "依赖安装失败。"
        return 1
    fi
    
    ui_print success "GCLI2API 部署完成。"
}

gcli2api_start() {
    _gcli2api_load_config
    [ ! -d "$GCLI_DIR" ] && { gcli2api_install || return 1; }
    
    if [ ! -f "$GCLI_DIR/web.py" ]; then
        ui_print error "程序核心文件丢失 (web.py)，请尝试 [更新重装]。"
        ui_pause; return 1
    fi

    gcli2api_stop
    pkill -9 -f "python.*web.py" 2>/dev/null
    local CMD="(cd '$GCLI_DIR' && source '$GCLI_VENV/bin/activate' && export PORT='$GCLI_PORT' PASSWORD='$GCLI_PWD' HOST='$GCLI_HOST' && setsid nohup python web.py >> '$GCLI_LOG' 2>&1 </dev/null & echo \$! > '$GCLI_PID')"
    
    ui_print info "正在启动服务..."
    eval "$CMD"
    sleep 2
    
    local real_pid=$(pgrep -f "python.*web.py" | grep -v "grep" | head -n 1)
    
    if [ -n "$real_pid" ]; then
        echo "$real_pid" > "$GCLI_PID"
        ui_print success "启动成功！"
    else
        ui_print error "启动失败，请查看日志。"
        tail -n 5 "$GCLI_LOG"
    fi
}

gcli2api_stop() {
    _gcli2api_vars
    kill_process_safe "$GCLI_PID" "python.*web.py"
}

gcli2api_uninstall() {
    _gcli2api_vars
    if verify_kill_switch; then
        gcli2api_stop
        safe_rm "$GCLI_DIR" "$GCLI_LOG" "$GCLI_CONF" "$GCLI_PID"
        ui_print success "已卸载。"
        return 2
    fi
}

gcli2api_menu() {
    while true; do
        _gcli2api_load_config
        ui_header "🌐 GCLI 转 API"
        local state="stopped"; local text="未运行"; local info=()
        if check_process_smart "$GCLI_PID" "python.*web.py"; then
            state="running"; text="运行中"
            info+=( "地址: http://127.0.0.1:$GCLI_PORT" "密码: $GCLI_PWD" )
        fi
        ui_status_card "$state" "$text" "${info[@]}"
        
        local CHOICE=$(ui_menu "操作菜单" "🚀 启动/重启" "🛑 停止服务" "⚙️  修改配置" "📜 查看日志" "⬆️  更新重装" "🗑️  卸载模块" "🔙 返回")
        case "$CHOICE" in
            *"启动"*) gcli2api_start; ui_pause ;; 
            *"停止"*) gcli2api_stop; ui_print success "已停止"; ui_pause ;; 
            *"配置"*) 
                GCLI_PORT=$(ui_input_validated "新端口" "$GCLI_PORT" "numeric")
                GCLI_PWD=$(ui_input "新密码" "$GCLI_PWD" "false")
                
                write_env_safe "$GCLI_CONF" "GCLI_PORT" "$GCLI_PORT"
                write_env_safe "$GCLI_CONF" "GCLI_PWD" "$GCLI_PWD"
                write_env_safe "$GCLI_CONF" "GCLI_HOST" "$GCLI_HOST"
                
                ui_print success "配置已保存"; ui_pause ;; 
            *"日志"*) safe_log_monitor "$GCLI_LOG" ;; 
            *"更新"*) gcli2api_install ;; 
            *"卸载"*) gcli2api_uninstall && [ $? -eq 2 ] && return ;; 
            *"返回"*) return ;; 
        esac
    done
}