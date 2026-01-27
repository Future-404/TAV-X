#!/bin/bash
# [METADATA]
# MODULE_ID: clewd
# MODULE_NAME: ClewdR 管理
# MODULE_ENTRY: clewd_menu
# APP_CATEGORY: AI模型接口
# APP_AUTHOR: Xerxes-2
# APP_PROJECT_URL: https://github.com/Xerxes-2/clewdr
# APP_DESC: ClewdR是一个用于Claude（Claude.ai、Claude Code的Rust代理程序。它能保持较低的资源占用，提供OpenAI风格的API接口，并附带一个小型React管理界面，用于管理Cookie和设置。
# [END_METADATA]

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

_clewd_vars() {
    CL_APP_ID="clewd"
    CL_DIR=$(get_app_path "$CL_APP_ID")
    CL_LOG="$LOGS_DIR/clewd.log"
    CL_PID="$RUN_DIR/clewd.pid"
    # shellcheck disable=SC2034
    CL_CONF="$CL_DIR/config.js"
    # shellcheck disable=SC2034
    CL_SECRETS="$CONFIG_DIR/clewd_secrets.conf"
    mkdir -p "$CL_DIR"
}

clewd_install() {
    _clewd_vars
    ui_header "安装 Clewd (Rust版)" 
    
    local arch
    arch=$(uname -m)
    local asset_pattern="linux-x86_64"
    [[ "$arch" == "aarch64" || "$arch" == "arm64" ]] && asset_pattern="android-aarch64"
    
    ui_print info "正在获取版本信息 ($asset_pattern)..."
    auto_load_proxy_env
    
    local api_url="https://api.github.com/repos/Xerxes-2/clewdr/releases/latest"
    local json
    json=$(curl -s -m 10 "$api_url")
    
    if [ -z "$json" ] || [[ "$json" == *"rate limit"* ]]; then
        ui_print error "GitHub API 请求失败 (可能触发频率限制)。"
        ui_pause; return 1
    fi

    local download_url
    download_url=$(echo "$json" | yq -p json '.assets[] | select(.name | contains("'$asset_pattern'")) | .browser_download_url' 2>/dev/null | head -n 1)
    
    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        ui_print error "无法从 API 解析下载地址。架构: $asset_pattern"
        ui_pause; return 1
    fi
    
    local tmp_file="$TMP_DIR/clewdr_dist.zip"
    local DL_CMD="source \"$TAVX_DIR/core/utils.sh\"; download_file_smart '\''$download_url\'' '$tmp_file' 'false'"
    
    if ui_stream_task "正在下载发行包..." "$DL_CMD"; then
        ui_print info "正在解压..."
        unzip -q -o "$tmp_file" -d "$CL_DIR"
        chmod +x "$CL_DIR"/* 2>/dev/null
        
        if [ ! -f "$CL_DIR/clewdr" ]; then
            local bin_path
            bin_path=$(find "$CL_DIR" -name "clewdr" -type f | head -n 1)
            [ -n "$bin_path" ] && mv "$bin_path" "$CL_DIR/clewdr"
        fi
        
        safe_rm "$tmp_file"
        ui_print success "安装完成。"
    else
        ui_print error "安装失败。"
        ui_pause; return 1
    fi
}

clewd_start() {
    _clewd_vars
    if [ ! -f "$CL_DIR/clewdr" ] && [ ! -f "$CL_DIR/clewd.js" ]; then
        if ui_confirm "未检测到程序，是否立即安装？"; then clewd_install || return 1; else return 1; fi
    fi
    
    ui_header "启动 Clewd"
    cd "$CL_DIR" || return 1
    
    local RUN_CMD=""
    if [ -f "clewdr" ]; then RUN_CMD="./clewdr"
    elif [ -f "clewd.js" ]; then RUN_CMD="node clewd.js"
    fi

    if [ "$OS_TYPE" == "TERMUX" ]; then
        tavx_service_register "clewd" "$RUN_CMD" "$CL_DIR"
        tavx_service_control "up" "clewd"
        ui_print success "服务启动命令已发送。"
    else
        clewd_stop
        echo "--- Clewd Start $(date) --- " > "$CL_LOG"
        local START_CMD="setsid nohup $RUN_CMD >> '$CL_LOG' 2>&1 & echo \$! > '$CL_PID'"
        
        if ui_spinner "正在启动后台服务..." "eval \"$START_CMD\" "; then
            sleep 2
            if check_process_smart "$CL_PID" "clewdr|node.*clewd\.js"; then
                ui_print success "服务已启动！"
            else
                ui_print error "启动失败，进程未驻留。"
                ui_pause; return 1
            fi
        fi
    fi
}

clewd_stop() {
    _clewd_vars
    if [ "$OS_TYPE" == "TERMUX" ]; then
        tavx_service_control "down" "clewd"
    else
        kill_process_safe "$CL_PID" "clewdr|node.*clewd\.js"
        pkill -f "clewdr" 2>/dev/null
        pkill -f "node clewd.js" 2>/dev/null
    fi
}

clewd_uninstall() {
    _clewd_vars
    ui_header "卸载 Clewd"
    if ! verify_kill_switch; then return; fi
    
    clewd_stop
    tavx_service_remove "clewd"
    
    if ui_spinner "正在清除..." "safe_rm '$CL_DIR' '$CL_PID'"; then
        ui_print success "模块数据已卸载。"
        return 2 
    fi
}

clewd_menu() {
    while true; do
        _clewd_vars
        ui_header "Clewd AI 反代管理"
        
        local state="stopped"; local text="已停止"; local info=()
        local log_path="$CL_LOG"
        [ "$OS_TYPE" == "TERMUX" ] && log_path="$PREFIX/var/service/clewd/log/current"

        if [ "$OS_TYPE" == "TERMUX" ]; then
            if sv status clewd 2>/dev/null | grep -q "^run:"; then
                state="running"; text="运行中"
            fi
        elif check_process_smart "$CL_PID" "clewdr|node.*clewd\.js"; then
            state="running"; text="运行中"
        fi

        if [ "$state" == "running" ]; then
            local pass="未知"
            if [ -f "$log_path" ]; then
                local API_PASS
                API_PASS=$(grep -iE "password:|Pass:" "$log_path" | head -n 1 | awk -F': ' '{print $2}' | tr -d ' ')
                [ -z "$API_PASS" ] && API_PASS=$(grep -E "API Password:|Pass:" "$log_path" | head -n 1 | awk '{print $NF}')
                [ -n "$API_PASS" ] && pass="$API_PASS"
            fi
            
            local port="8444"
            [ -f "$log_path" ] && grep -q "8484" "$log_path" && port="8484"
            
            info+=( "接口: http://127.0.0.1:$port/v1" "密钥: $pass" )
        else
            info+=( "提示: 请先启动服务" )
        fi
        
        ui_status_card "$state" "$text" "${info[@]}"
        local CHOICE
        CHOICE=$(ui_menu "请选择操作" "🚀 启动服务" "🔑 查看密码" "📜 查看日志" "🛑 停止服务" "📥 更新重装" "🗑️  卸载模块" "🧭 关于模块" "🔙 返回")
        case "$CHOICE" in
            *"启动"*) clewd_start; ui_pause ;; 
            *"密码"*) 
                if [ -f "$log_path" ]; then
                    ui_header "Clewd 运行密码"
                    grep -iE "password|pass" "$log_path" | head -n 10
                else
                    ui_print warn "日志文件不存在。"
                fi
                ui_pause ;; 
            *"日志"*) ui_watch_log "clewd" ;; 
            *"停止"*) clewd_stop; ui_print success "已停止"; ui_pause ;; 
            *"更新"*) clewd_install ;; 
            *"卸载"*) clewd_uninstall && [ $? -eq 2 ] && return ;; 
            *"关于"*) show_module_about_info "${BASH_SOURCE[0]}" ;;
            *"返回"*) return ;; 
        esac
    done
}