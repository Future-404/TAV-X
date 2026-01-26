#!/bin/bash
# [METADATA]
# MODULE_ID: antigravity
# MODULE_NAME: Antigravity2API
# MODULE_ENTRY: antigravity_menu
# APP_CATEGORY: AI模型接口
# APP_AUTHOR: liuw1535
# APP_PROJECT_URL: https://github.com/liuw1535/antigravity2api-nodejs
# APP_DESC: 将 Google Antigravity API 转换为 OpenAI 兼容格式的代理服务，支持流式响应、工具调用和多账号管理。
# [END_METADATA]

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

_antigravity_vars() {
    AG_APP_ID="antigravity"
    AG_DIR=$(get_app_path "$AG_APP_ID")
    AG_LOG="$LOGS_DIR/antigravity.log"
    AG_PID="$RUN_DIR/antigravity.pid"
    AG_CONF="$AG_DIR/config.json"
    mkdir -p "$AG_DIR"
}

antigravity_install() {
    _antigravity_vars
    ui_header "安装 Antigravity2API"

    local GIT_REPO="https://github.com/liuw1535/antigravity2api-nodejs.git"

    if ! command -v git &> /dev/null; then
        ui_print warn "未检测到 git，正在安装..."
        sys_install_pkg "git" || return 1
    fi

    prepare_network_strategy
    
    local do_install=true

    if [ -d "$AG_DIR" ] && [ -d "$AG_DIR/.git" ]; then
        if ui_confirm "检测到旧版本，是否仅更新源码？\n选择 [No] 将删除重装"; then
            cd "$AG_DIR" || return 1
            local remote_url
            remote_url=$(get_dynamic_repo_url "$GIT_REPO")
            if ui_stream_task "正在更新源码..." "git pull --autostash '$remote_url'"; then
                ui_print success "源码已更新。"
                do_install=false
            else
                ui_print error "更新失败，将尝试重新安装。"
                safe_rm "$AG_DIR"
            fi
        else
            safe_rm "$AG_DIR"
        fi
    elif [ -d "$AG_DIR" ]; then
        ui_print warn "目录存在但不是 Git 仓库，正在备份并重装..."
        mv "$AG_DIR" "${AG_DIR}_bak_$(date +%s)"
    fi
    
    if [ "$do_install" = true ]; then
        if git_clone_smart "" "$GIT_REPO" "$AG_DIR"; then
            ui_print success "仓库部署完成。"
        else
            ui_print error "克隆失败，请检查网络连接。"
            ui_pause; return 1
        fi
    fi

    ui_print info "正在检查依赖环境..."
    cd "$AG_DIR" || return 1
    local node_valid=false
    if command -v node &> /dev/null; then
        local ver
        ver=$(node -v | cut -d. -f1 | tr -d 'v')
        if [ -n "$ver" ] && [ "$ver" -ge 18 ]; then
            node_valid=true
        else
            ui_print warn "检测到 Node.js 版本 ($ver) 可能过低 (推荐 >= 18)。"
        fi
    fi

    if [ "$node_valid" = false ]; then
        ui_print warn "正在尝试安装/更新 Node.js..."
        sys_install_pkg "nodejs" "npm"
        
        if command -v node &> /dev/null; then
             local ver
             ver=$(node -v | cut -d. -f1 | tr -d 'v')
             if [ -n "$ver" ] && [ "$ver" -ge 18 ]; then
                 ui_print success "Node.js 版本符合要求 ($ver)。"
             else
                 ui_print warn "警告: 当前 Node.js 版本 ($ver) 仍低于 18，应用可能无法运行。"
                 ui_print warn "请手动升级 Node.js，或使用 'n' / 'nvm' 管理版本。"
                 ui_pause
             fi
        else
             ui_print error "Node.js 安装失败。请手动安装 Node.js (>=18)。"
             return 1
        fi
    fi

    if [ "$OS_TYPE" != "TERMUX" ] && command -v apt-get &> /dev/null; then
        if ! dpkg -s build-essential &> /dev/null; then
            ui_print info "正在检查编译工具..."
            sys_install_pkg "build-essential"
        fi
    fi
    
    if npm_install_smart "$AG_DIR"; then
            ui_print success "依赖安装完成。"
            
            if [ ! -f "$AG_CONF" ] && [ -f "$AG_DIR/config.json.example" ]; then
                cp "$AG_DIR/config.json.example" "$AG_CONF"
                ui_print info "已生成默认配置文件。"
            fi
            
            ui_print success "安装完成。"
    else
            ui_print error "依赖安装失败。"
            ui_pause; return 1
    fi
}

antigravity_start() {
    _antigravity_vars
    if [ ! -f "$AG_DIR/package.json" ]; then
        if ui_confirm "未检测到程序，是否立即安装？"; then antigravity_install || return 1; else return 1; fi
    fi
    
    ui_header "启动 Antigravity2API"
    
    auto_load_proxy_env

    cd "$AG_DIR" || return 1
    
    local RUN_CMD="npm start"

    if [ "$OS_TYPE" == "TERMUX" ]; then
        tavx_service_register "antigravity" "$RUN_CMD" "$AG_DIR"
        tavx_service_control "up" "antigravity"
        ui_print success "服务启动命令已发送。"
    else
        antigravity_stop
        echo "--- Antigravity Start $(date) --- " > "$AG_LOG"
        local START_CMD="setsid nohup $RUN_CMD >> '$AG_LOG' 2>&1 & echo \$! > '$AG_PID'"
        
        if ui_spinner "正在启动后台服务..." "eval \"$START_CMD\" "; then
            sleep 2
            if check_process_smart "$AG_PID" "node.*src/server/index.js|antigravity"; then
                ui_print success "服务已启动！"
            else
                ui_print error "启动失败，进程未驻留。"
                ui_pause; return 1
            fi
        fi
    fi
}

antigravity_stop() {
    _antigravity_vars
    if [ "$OS_TYPE" == "TERMUX" ]; then
        tavx_service_control "down" "antigravity"
    else
        kill_process_safe "$AG_PID" "node.*src/server/index.js|antigravity"
        pkill -f "node src/server/index.js" 2>/dev/null
    fi
}

antigravity_uninstall() {
    _antigravity_vars
    ui_header "卸载 Antigravity2API"
    if ! verify_kill_switch; then return; fi
    
    antigravity_stop
    if ui_spinner "正在清除..." "safe_rm '$AG_DIR' '$AG_PID'"; then
        ui_print success "模块数据已卸载。"
        return 2 
    fi
}

antigravity_login() {
    _antigravity_vars
    if [ ! -d "$AG_DIR" ]; then
        ui_print error "请先安装模块。"
        ui_pause; return 1
    fi
    
    ui_header "Antigravity OAuth 授权"
    
    auto_load_proxy_env
    
    cd "$AG_DIR" || return 1
    
    local AUTH_LOG="$TMP_DIR/ag_auth.log"
    : > "$AUTH_LOG"
    
    (
        local loop=0
        while [ "$loop" -lt 120 ]; do
            if grep -q "https://accounts.google.com" "$AUTH_LOG"; then
                local url
                url=$(grep -o "https://accounts.google.com[^ ]*" "$AUTH_LOG" | head -n 1 | tr -d '\r\n')
                if [ -n "$url" ]; then
                    open_browser "$url"
                    break
                fi
            fi
            sleep 1
            ((loop++))
        done
    ) &
    
    ui_print info "即将启动授权脚本..."
    echo -e "${YELLOW}>>> 浏览器应该会自动打开。如果失败，请手动复制下方的链接:${NC}"
    echo ""
    node scripts/oauth-server.js | tee "$AUTH_LOG"
    
    rm -f "$AUTH_LOG"
    echo ""
    ui_pause
}

antigravity_menu() {
    while true; do
        _antigravity_vars
        ui_header "Antigravity2API 管理"
        
        local state="stopped"; local text="已停止"; local info=()
        local log_path="$AG_LOG"
        [ "$OS_TYPE" == "TERMUX" ] && log_path="$PREFIX/var/service/antigravity/log/current"

        if [ "$OS_TYPE" == "TERMUX" ]; then
            if sv status antigravity 2>/dev/null | grep -q "^run:"; then
                state="running"; text="运行中"
            fi
        elif check_process_smart "$AG_PID" "node.*src/server/index.js|antigravity"; then
            state="running"; text="运行中"
        fi

        if [ "$state" == "running" ]; then
            local port="8045"
            if [ -f "$AG_CONF" ]; then
                local conf_port
                conf_port=$(grep -o '"port": *[0-9]*' "$AG_CONF" | head -1 | awk -F: '{print $2}' | tr -d ' ,')
                [ -n "$conf_port" ] && port="$conf_port"
            fi
            
            info+=( "地址: http://127.0.0.1:$port" )
            
             local admin_pass="查看配置"
             if [ -f "$log_path" ]; then
                local pass_grep
                pass_grep=$(grep "ADMIN_PASSWORD=" "$log_path" | tail -n 1 | cut -d= -f2)
                [ -n "$pass_grep" ] && admin_pass="$pass_grep"
             fi
             info+=( "密码: $admin_pass" )
        else
            info+=( "提示: 请先启动服务" )
        fi
        
        ui_status_card "$state" "$text" "${info[@]}"
        local CHOICE
        CHOICE=$(ui_menu "请选择操作" "🚀 启动服务" "🔑 获取授权" "📜 查看日志" "🛑 停止服务" "📥 重装/更新" "🗑️  卸载模块" "⚙️  编辑配置" "🧭 关于模块" "🔙 返回")
        case "$CHOICE" in
            *"启动"*) antigravity_start; ui_pause ;; 
            *"获取授权"*) antigravity_login ;;
            *"日志"*) safe_log_monitor "$log_path" ;; 
            *"停止"*) antigravity_stop; ui_print success "已停止"; ui_pause ;; 
            *"重装"*) antigravity_install ;; 
            *"卸载"*) antigravity_uninstall && [ $? -eq 2 ] && return ;;
            *"配置"*) 
                node "$TAVX_DIR/modules/antigravity/config.js"
                ;; 
            *"关于"*) show_module_about_info "${BASH_SOURCE[0]}" ;;
            *"返回"*) return ;; 
        esac
    done
}
