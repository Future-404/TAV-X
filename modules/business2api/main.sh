#!/bin/bash
# [METADATA]
# MODULE_ID: business2api
# MODULE_NAME: Gemini Business 2 OpenAI API
# MODULE_ENTRY: business2api_menu
# APP_CATEGORY: AI模型接口
# APP_VERSION: Beta-Testing (In Development)
# APP_AUTHOR: TAV-X Developer
# APP_PROJECT_URL: https://github.com/Future-404/TAV-X
# APP_DESC: 基于 Gemini Business 逆向工程，提供完全兼容 OpenAI 标准的 API 接口，支持多账号负载均衡和流式输出。
# [END_METADATA]

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"
source "$TAVX_DIR/core/python_utils.sh"

_b2api_vars() {
    B2A_APP_ID="business2api"
    B2A_DIR=$(get_app_path "$B2A_APP_ID")
    B2A_VENV="$B2A_DIR/venv"
    B2A_LOG="$LOGS_DIR/business2api.log"
    B2A_PID="$RUN_DIR/business2api.pid"
    B2A_ENV_CONF="$CONFIG_DIR/business2api.env"
    mkdir -p "$B2A_DIR"
}

business2api_install() {
    _b2api_vars
    ui_header "部署 Gemini Business 2 API"
    
    prepare_network_strategy

    # 复制核心逻辑与脚本
    ui_print info "正在同步核心逻辑与脚本..."
    cp -r "$TAVX_DIR/template/core" "$B2A_DIR/"
    cp -r "$TAVX_DIR/template/util" "$B2A_DIR/"
    # 使用精简版依赖文件
    cp "$TAVX_DIR/modules/business2api/requirements_mini.txt" "$B2A_DIR/requirements.txt"
    # 从模块源码目录拷贝脚本到运行目录
    cp "$TAVX_DIR/modules/business2api/app.py" "$B2A_DIR/"
    cp "$TAVX_DIR/modules/business2api/import_account.py" "$B2A_DIR/"

    if ui_stream_task "创建 Python 虚拟环境..." "source \"$TAVX_DIR/core/python_utils.sh\"; create_venv_smart '$B2A_VENV'"; then
        ui_print info "正在安装 Python 依赖..."
        local INSTALL_CMD="source \"$TAVX_DIR/core/python_utils.sh\"; install_requirements_smart '$B2A_VENV' '$B2A_DIR/requirements.txt' 'standard'"
        
        if ! ui_stream_task "安装依赖 (可能耗时较长)..." "$INSTALL_CMD"; then
            ui_print error "依赖安装失败。"
            return 1
        fi
    else
        ui_print error "虚拟环境创建失败。"
        return 1
    fi
    
    if [ ! -f "$B2A_ENV_CONF" ]; then
        echo -e "HOST=0.0.0.0\nPORT=7860\nADMIN_KEY=admin123\nAPI_KEY=sk-business-key" > "$B2A_ENV_CONF"
    fi
    ui_print success "安装完成。"
}

business2api_start() {
    _b2api_vars
    if [ ! -d "$B2A_DIR" ] || [ ! -f "$B2A_ENV_CONF" ]; then
        business2api_install || return 1
    fi
    
    business2api_stop
    local port
    port=$(grep "^PORT=" "$B2A_ENV_CONF" | cut -d= -f2); [ -z "$port" ] && port=7860
    
    # 链接环境变量
    ln -sf "$B2A_ENV_CONF" "$B2A_DIR/.env"
    
    local proxy
    proxy=$(get_active_proxy)
    local p_env=""
    [ -n "$proxy" ] && p_env="http_proxy=$proxy https_proxy=$proxy all_proxy=$proxy"
    
    ui_print info "正在启动 Gemini Business API 服务..."

    if [ "$OS_TYPE" == "TERMUX" ]; then
        local RUN_CMD="env $p_env '$B2A_VENV/bin/python' app.py"
        tavx_service_register "business2api" "$RUN_CMD" "$B2A_DIR"
        tavx_service_control "up" "business2api"
        sleep 2
        ui_print success "服务启动命令已发送。"
    else
        cd "$B2A_DIR" || return 1
        # 直接执行并脱离终端
        env $p_env nohup "$B2A_VENV/bin/python" app.py > "$B2A_LOG" 2>&1 &
        local pid=$!
        echo "$pid" > "$B2A_PID"
        
        # 验证启动
        sleep 2
        if kill -0 "$pid" 2>/dev/null; then
            ui_print success "服务已启动，监听端口: $port (PID: $pid)"
        else
            ui_print error "服务启动失败，请检查日志: $B2A_LOG"
            [ -f "$B2A_LOG" ] && tail -n 10 "$B2A_LOG"
        fi
    fi
}

business2api_stop() {
    _b2api_vars
    if [ "$OS_TYPE" == "TERMUX" ]; then
        tavx_service_control "down" "business2api"
    else
        kill_process_safe "$B2A_PID" "python.*app.py"
    fi
}

business2api_uninstall() {
    _b2api_vars
    if verify_kill_switch; then
        business2api_stop
        tavx_service_remove "business2api"
        ui_spinner "清理文件中..." "safe_rm '$B2A_DIR' '$B2A_ENV_CONF' '$B2A_PID' '$B2A_LOG'"
        ui_print success "已卸载。"
        return 2
    fi
}

business2api_menu() {
    while true; do
        _b2api_vars
        ui_header "♊ Business2API 管理面板"
        local state="stopped"; local text="未运行"; local info=()
        
        if [ "$OS_TYPE" == "TERMUX" ]; then
            if sv status business2api 2>/dev/null | grep -q "^run:"; then
                state="running"; text="运行中"
            fi
        elif check_process_smart "$B2A_PID" "python.*app.py"; then
            state="running"; text="运行中"
        fi

        if [ "$state" == "running" ]; then
            local port
            port=$(grep "^PORT=" "$B2A_ENV_CONF" 2>/dev/null | cut -d= -f2)
            info+=( "地址: http://127.0.0.1:${port:-7860}/v1" )
        fi
        
        ui_status_card "$state" "$text" "${info[@]}"
        local CHOICE
        CHOICE=$(ui_menu "操作菜单" "🚀 启动服务" "🛑 停止服务" "📥 导入账号" "⚙️  修改配置" "📜 查看日志" "⬇️  更新逻辑" "🗑️  卸载模块" "🧭 关于模块" "🔙 返回")
        case "$CHOICE" in
            *"启动"*) business2api_start; ui_pause ;; 
            *"停止"*) business2api_stop; ui_print success "已停止"; ui_pause ;; 
            *"导入"*) 
                _b2api_vars
                # 动态补全脚本，防止文件丢失
                [ ! -f "$B2A_DIR/import_account.py" ] && cp "$TAVX_DIR/modules/business2api/import_account.py" "$B2A_DIR/"
                cd "$B2A_DIR" && "$B2A_VENV/bin/python" import_account.py
                ui_pause ;;
            *"配置"*) 
                # 简单编辑配置
                if [ -f "$B2A_ENV_CONF" ]; then
                    nano "$B2A_ENV_CONF"
                else
                    ui_print error "配置文件不存在"
                fi
                ui_pause ;; 
            *"日志"*) ui_watch_log "business2api" ;; 
            *"更新"*) business2api_install ;; 
            *"卸载"*) business2api_uninstall && [ $? -eq 2 ] && return ;; 
            *"关于"*) show_module_about_info "${BASH_SOURCE[0]}" ;; 
            *"返回"*) return ;; 
        esac
    done
}
