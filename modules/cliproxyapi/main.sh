#!/bin/bash
# [METADATA]
# MODULE_ID: cliproxyapi
# MODULE_NAME: CLIProxyAPI 代理
# MODULE_ENTRY: cliproxyapi_menu
# APP_CATEGORY: AI模型接口
# APP_AUTHOR: router-for-me
# APP_PROJECT_URL: https://github.com/router-for-me/CLIProxyAPI
# APP_DESC: CLIProxyAPI 是一个由 Go 编写的高性能代理工具，支持远程管理和 WebUI 后台，非常适合在手机端作为代理中转使用。
# [END_METADATA]

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

_cp_vars() {
    CP_APP_ID="cliproxyapi"
    CP_DIR=$(get_app_path "$CP_APP_ID")
    CP_BIN="$CP_DIR/cli-proxy-api"
    CP_CONFIG="$CP_DIR/config.yaml"
    CP_LOG="$CP_DIR/proxy.log"
    CP_SVC_NAME="cliproxyapi"
}

cliproxyapi_install() {
    _cp_vars
    ui_header "CLIProxyAPI 安装向导"
    
    if [ -d "$CP_DIR" ]; then
        ui_print warn "检测到已存在目录: $CP_DIR"
        if ! ui_confirm "确认重新安装吗？(将清空现有数据)"; then return; fi
        safe_rm "$CP_DIR"
    fi
    
    # 1. 检查并安装 Golang
    if ! command -v go &>/dev/null; then
        ui_print info "正在准备 Go 语言环境..."
        if ! sys_install_pkg "golang"; then
            ui_print error "Go 环境安装失败，请检查网络。"
            return 1
        fi
    fi

    # 2. 获取源码
    prepare_network_strategy
    local CLONE_CMD="source "$TAVX_DIR/core/utils.sh"; git_clone_smart '' 'router-for-me/CLIProxyAPI' '$CP_DIR'"
    if ! ui_stream_task "正在拉取源码..." "$CLONE_CMD"; then
        ui_print error "源码下载失败。"
        return 1
    fi

    # 3. 编译二进制文件
    cd "$CP_DIR" || return 1
    ui_print info "正在编译二进制文件 (这可能需要一点时间)..."
    if ! ui_stream_task "正在编译..." "go build -o cli-proxy-api ./cmd/server"; then
        ui_print error "编译失败，请检查错误输出。"
        return 1
    fi
    chmod +x "$CP_BIN"

    # 4. 配置初始化
    if [ -f "config.example.yaml" ]; then
        cp config.example.yaml config.yaml
        ui_print info "正在自动优化配置文件..."
        
        # 使用 yq 进行标准修改
        yq -i '.remote-management.allow-remote = true' config.yaml
        yq -i '.remote-management.secret-key = "admin123"' config.yaml
        yq -i '.remote-management.disable-control-panel = false' config.yaml
        
        ui_print success "配置文件已初始化 (默认管理密钥: admin123)"
    fi

    ui_print success "安装成功！"
}

cliproxyapi_start() {
    _cp_vars
    [ ! -x "$CP_BIN" ] && { ui_print error "程序未安装或不可执行"; return 1; }

    if is_app_running "$CP_APP_ID"; then
        ui_print warn "服务已在运行中"
        return 0
    fi

    if [ "$OS_TYPE" == "TERMUX" ]; then
        tavx_service_register "$CP_SVC_NAME" "./cli-proxy-api" "$CP_DIR"
        tavx_service_control "up" "$CP_SVC_NAME"
        ui_print success "服务启动命令已发送。"
    else
        cd "$CP_DIR" || return 1
        rm -f "$RUN_DIR/${CP_APP_ID}.pid"
        setsid nohup ./cli-proxy-api > "$CP_LOG" 2>&1 &
        local new_pid=$!
        sleep 0.5
        if kill -0 "$new_pid" 2>/dev/null; then
            echo "$new_pid" > "$RUN_DIR/${CP_APP_ID}.pid"
            ui_print success "已在后台启动 (PID: $new_pid)。"
        else
            ui_print error "启动失败，请查看日志: $CP_LOG"
            return 1
        fi
    fi
}

cliproxyapi_stop() {
    _cp_vars
    if [ "$OS_TYPE" == "TERMUX" ]; then
        tavx_service_control "down" "$CP_SVC_NAME"
    else
        kill_process_safe "$RUN_DIR/${CP_APP_ID}.pid" "cli-proxy-api"
    fi
}

cliproxyapi_uninstall() {
    _cp_vars
    ui_header "卸载 CLIProxyAPI"
    [ ! -d "$CP_DIR" ] && { ui_print error "未安装。"; return; }
    
    if ! verify_kill_switch; then return; fi
    
    cliproxyapi_stop
    tavx_service_remove "$CP_SVC_NAME"
    
    if ui_spinner "正在清理数据..." "safe_rm '$CP_DIR' '$RUN_DIR/${CP_APP_ID}.pid'"; then
        ui_print success "卸载完成。"
        return 2
    fi
}

cliproxyapi_menu() {
    _cp_vars
    if [ ! -d "$CP_DIR" ]; then
        ui_header "CLIProxyAPI"
        ui_print warn "应用尚未安装。"
        if ui_confirm "立即安装？"; then cliproxyapi_install; else return; fi
    fi
    
    while true; do
        _cp_vars
        local state="stopped"; local text="已停止"; local info=()
        
        if is_app_running "$CP_APP_ID"; then
            state="running"
            text="运行中"
        fi
        
        # 尝试从配置中获取端口
        local port="未知"
        if [ -f "$CP_CONFIG" ]; then
            port=$(grep "^port:" "$CP_CONFIG" | head -n 1 | awk '{print $2}' | tr -d '"')
            [ -z "$port" ] && port="8317 (默认)"
        fi
        info+=( "监听端口: $port" )
        
        ui_header "CLIProxyAPI 管理面板"
        ui_status_card "$state" "$text" "${info[@]}"
        
        local CHOICE
        CHOICE=$(ui_menu "操作菜单" "🚀 启动服务" "🛑 停止服务" "⚙️  可视化配置" "📝 手动编辑" "📜 查看日志" "🗑️  卸载模块" "🧭 关于模块" "🔙 返回")
        case "$CHOICE" in
            *"启动"*) cliproxyapi_start; ui_pause ;; 
            *"停止"*) cliproxyapi_stop; ui_print success "服务已停止"; ui_pause ;; 
            *"可视化配置"*) 
                node "$TAVX_DIR/modules/cliproxyapi/config.js"
                if is_app_running "$CP_APP_ID"; then
                    if ui_confirm "配置已修改，是否重启服务以生效？"; then
                        cliproxyapi_stop; sleep 1; cliproxyapi_start
                    fi
                fi
                ;;
            *"手动编辑"*)
                if command -v nano &>/dev/null; then nano "$CP_CONFIG"; else vi "$CP_CONFIG"; fi
                if is_app_running "$CP_APP_ID"; then
                    if ui_confirm "配置已修改，是否重启服务以生效？"; then
                        cliproxyapi_stop; sleep 1; cliproxyapi_start
                    fi
                fi
                ;;
            *"日志"*) ui_watch_log "$CP_SVC_NAME" ;; 
            *"卸载"*) cliproxyapi_uninstall && [ $? -eq 2 ] && return ;; 
            *"关于"*) show_module_about_info "${BASH_SOURCE[0]}" ;; 
            *"返回"*) return ;; 
        esac
    done
}
