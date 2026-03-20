#!/bin/bash
# [METADATA]
# MODULE_ID: gb2api
# MODULE_NAME: GB2API
# MODULE_ENTRY: gb2api_menu
# APP_CATEGORY: AI模型接口
# APP_VERSION: 1.0.0-Stable
# APP_AUTHOR: Future 404
# APP_PROJECT_URL: https://github.com/Future-404/TAV-X
# APP_DESC: 基于 Gemini Business 逆向工程，提供完全兼容 OpenAI 标准的 API 接口，支持多账号智能调度、深度思考隔离及完美多模态渲染。
# [END_METADATA]

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"
source "$TAVX_DIR/core/python_utils.sh"

_gb2api_vars() {
    GB2A_APP_ID="gb2api"
    GB2A_DIR=$(get_app_path "$GB2A_APP_ID")
    GB2A_VENV="$GB2A_DIR/venv"
    GB2A_LOG="$LOGS_DIR/gb2api.log"
    GB2A_PID="$RUN_DIR/gb2api.pid"
    GB2A_ENV_CONF="$CONFIG_DIR/gb2api.env"
    mkdir -p "$GB2A_DIR"
}

gb2api_diagnostic() {
    _gb2api_vars
    ui_header "♊ GB2API 生产环境诊断"
    
    local errors=0
    
    echo -e "1. 核心依赖检查:"
    [ -d "$GB2A_DIR/core" ] && echo -e "   - 逆向核心 (core): ${GREEN}OK${NC}" || { echo -e "   - 逆向核心: ${RED}缺失${NC}"; ((errors++)); }
    [ -f "$GB2A_DIR/app.py" ] && echo -e "   - 服务端 (app.py): ${GREEN}OK${NC}" || { echo -e "   - 服务端: ${RED}缺失${NC}"; ((errors++)); }
    
    echo -e "\n2. 运行环境检查:"
    [ -f "$GB2A_VENV/bin/python" ] && echo -e "   - 虚拟环境 (venv): ${GREEN}OK${NC}" || { echo -e "   - 虚拟环境: ${RED}未创建${NC}"; ((errors++)); }
    
    echo -e "\n3. 网络与配置检查:"
    [ -f "$GB2A_ENV_CONF" ] && echo -e "   - 环境变量 (env): ${GREEN}OK${NC}" || { echo -e "   - 环境变量: ${YELLOW}未配置 (将使用默认)${NC}"; }
    
    local port; port=$(grep "^PORT=" "$GB2A_ENV_CONF" 2>/dev/null | cut -d= -f2); port=${port:-7860}
    if timeout 0.5 bash -c "</dev/tcp/127.0.0.1/$port" 2>/dev/null; then
        echo -e "   - 端口状态 ($port): ${GREEN}正在监听${NC}"
    else
        echo -e "   - 端口状态 ($port): ${YELLOW}未启动${NC}"
    fi

    echo -e "\n----------------------------------------"
    if [ $errors -eq 0 ]; then
        ui_print success "诊断完成：所有生产组件已就绪。"
    else
        ui_print error "诊断完成：检测到 $errors 处异常，请尝试 [更新逻辑]。"
    fi
    ui_pause
}

gb2api_install() {
    _gb2api_vars
    ui_header "部署 Gemini Business 2 API"
    
    prepare_network_strategy

    # 复制核心逻辑与脚本
    ui_print info "正在同步核心逻辑与脚本..."
    # 从模块源码目录拷贝脚本到运行目录
    cp -r "$TAVX_DIR/modules/gb2api/core" "$GB2A_DIR/"
    cp -r "$TAVX_DIR/modules/gb2api/util" "$GB2A_DIR/"
    cp "$TAVX_DIR/modules/gb2api/requirements.txt" "$GB2A_DIR/"
    cp "$TAVX_DIR/modules/gb2api/app.py" "$GB2A_DIR/"
    cp "$TAVX_DIR/modules/gb2api/import_account.py" "$GB2A_DIR/"
    cp "$TAVX_DIR/modules/gb2api/check_accounts.py" "$GB2A_DIR/"

    if ui_stream_task "创建 Python 虚拟环境..." "source \"$TAVX_DIR/core/python_utils.sh\"; create_venv_smart '$GB2A_VENV'"; then
        ui_print info "正在安装 Python 依赖..."
        local INSTALL_CMD="source \"$TAVX_DIR/core/python_utils.sh\"; install_requirements_smart '$GB2A_VENV' '$GB2A_DIR/requirements.txt' 'standard'"
        
        if ! ui_stream_task "安装依赖 (可能耗时较长)..." "$INSTALL_CMD"; then
            ui_print error "依赖安装失败。"
            return 1
        fi
    else
        ui_print error "虚拟环境创建失败。"
        return 1
    fi
    
    if [ ! -f "$GB2A_ENV_CONF" ]; then
        echo -e "HOST=0.0.0.0\nPORT=7860\nADMIN_KEY=admin123\nAPI_KEY=sk-business-key" > "$GB2A_ENV_CONF"
    fi
    ui_print success "安装完成。"
}

gb2api_start() {
    _gb2api_vars
    if [ ! -d "$GB2A_DIR" ] || [ ! -f "$GB2A_ENV_CONF" ]; then
        gb2api_install || return 1
    fi
    
    gb2api_stop
    local port
    port=$(grep "^PORT=" "$GB2A_ENV_CONF" | cut -d= -f2); [ -z "$port" ] && port=7860
    
    # 链接环境变量
    ln -sf "$GB2A_ENV_CONF" "$GB2A_DIR/.env"
    
    local proxy
    proxy=$(get_active_proxy)
    local p_env=""
    [ -n "$proxy" ] && p_env="http_proxy=$proxy https_proxy=$proxy all_proxy=$proxy"
    
    ui_print info "正在启动 Gemini Business API 服务..."

    if [ "$OS_TYPE" == "TERMUX" ]; then
        local RUN_CMD="env $p_env '$GB2A_VENV/bin/python' app.py"
        tavx_service_register "gb2api" "$RUN_CMD" "$GB2A_DIR"
        tavx_service_control "up" "gb2api"
        sleep 2
        ui_print success "服务启动命令已发送。"
    else
        cd "$GB2A_DIR" || return 1
        # 直接执行并脱离终端
        env $p_env nohup "$GB2A_VENV/bin/python" app.py > "$GB2A_LOG" 2>&1 &
        local pid=$!
        echo "$pid" > "$GB2A_PID"
        
        # 验证启动
        sleep 2
        if kill -0 "$pid" 2>/dev/null; then
            ui_print success "服务已启动，监听端口: $port (PID: $pid)"
        else
            ui_print error "服务启动失败，请检查日志: $GB2A_LOG"
            [ -f "$GB2A_LOG" ] && tail -n 10 "$GB2A_LOG"
        fi
    fi
}

gb2api_stop() {
    _gb2api_vars
    if [ "$OS_TYPE" == "TERMUX" ]; then
        tavx_service_control "down" "gb2api"
    else
        kill_process_safe "$GB2A_PID" "python.*app.py"
    fi
}

gb2api_uninstall() {
    _gb2api_vars
    if verify_kill_switch; then
        gb2api_stop
        tavx_service_remove "gb2api"
        ui_spinner "清理文件中..." "safe_rm '$GB2A_DIR' '$GB2A_ENV_CONF' '$GB2A_PID' '$GB2A_LOG'"
        ui_print success "已卸载。"
        return 2
    fi
}

gb2api_menu() {
    while true; do
        _gb2api_vars
        ui_header "♊ GB2API 管理面板"
        local state="stopped"; local text="未运行"; local info=()
        
        if [ "$OS_TYPE" == "TERMUX" ]; then
            if sv status gb2api 2>/dev/null | grep -q "^run:"; then
                state="running"; text="运行中"
            fi
        elif check_process_smart "$GB2A_PID" "python.*app.py"; then
            state="running"; text="运行中"
        fi

        if [ "$state" == "running" ]; then
            local port
            port=$(grep "^PORT=" "$GB2A_ENV_CONF" 2>/dev/null | cut -d= -f2)
            info+=( "地址: http://127.0.0.1:${port:-7860}/v1" )
        fi
        
        ui_status_card "$state" "$text" "${info[@]}"
        local CHOICE
        CHOICE=$(ui_menu "操作菜单" "🚀 启动服务" "🛑 停止服务" "🔍 账号监控" "🩺 环境诊断" "📥 导入账号" "⚙️  修改配置" "📜 查看日志" "⬇️  更新逻辑" "🗑️  卸载模块" "🧭 关于模块" "🔙 返回")
        case "$CHOICE" in
            *"启动"*) gb2api_start; ui_pause ;; 
            *"停止"*) gb2api_stop; ui_print success "已停止"; ui_pause ;; 
            *"监控"*)
                _gb2api_vars
                # 确保脚本存在
                [ ! -f "$GB2A_DIR/check_accounts.py" ] && cp "$TAVX_DIR/modules/gb2api/check_accounts.py" "$GB2A_DIR/"
                cd "$GB2A_DIR" && "$GB2A_VENV/bin/python" check_accounts.py
                ui_pause ;;
            *"诊断"*) gb2api_diagnostic ;;
            *"导入"*) 
                _gb2api_vars
                # 动态补全脚本，防止文件丢失
                [ ! -f "$GB2A_DIR/import_account.py" ] && cp "$TAVX_DIR/modules/gb2api/import_account.py" "$GB2A_DIR/"
                cd "$GB2A_DIR" && "$GB2A_VENV/bin/python" import_account.py
                ui_pause ;;
            *"配置"*) 
                # 简单编辑配置
                if [ -f "$GB2A_ENV_CONF" ]; then
                    nano "$GB2A_ENV_CONF"
                else
                    ui_print error "配置文件不存在"
                fi
                ui_pause ;; 
            *"日志"*) ui_watch_log "gb2api" ;; 
            *"更新"*) gb2api_install ;; 
            *"卸载"*) gb2api_uninstall && [ $? -eq 2 ] && return ;; 
            *"关于"*) show_module_about_info "${BASH_SOURCE[0]}" ;; 
            *"返回"*) return ;; 
        esac
    done
}
