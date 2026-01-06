#!/bin/bash
# [METADATA]
# MODULE_NAME: 🌐 GCLI 转 API
# MODULE_ENTRY: gcli2api_menu
# [END_METADATA]

source "$TAVX_DIR/core/utils.sh"
source "$TAVX_DIR/core/deps.sh"

GCLI_DIR="$TAVX_DIR/gcli2api"
GCLI_VENV="$GCLI_DIR/venv"
GCLI_CONFIG="$TAVX_DIR/config/gcli2api.conf"
GCLI_PID="$TAVX_DIR/run/gcli2api.pid"
GCLI_LOG="$TAVX_DIR/logs/gcli2api.log"

load_gcli_config() {
    export GCLI_PORT="7861"
    export GCLI_PWD="pwd"
    export GCLI_HOST="0.0.0.0"

    if [ -f "$GCLI_CONFIG" ]; then
        source "$GCLI_CONFIG"
    fi
}

install_gcli() {
    ui_header "安装 GCLI2API"
    
    if [ -d "$GCLI_DIR" ]; then
        if ui_confirm "检测到旧目录，是否删除重装？"; then
            rm -rf "$GCLI_DIR"
        else
            ui_print info "正在尝试更新代码..."
            cd "$GCLI_DIR" && git pull
            ui_print success "代码更新完成。"
        fi
    fi

    if [ ! -d "$GCLI_DIR" ]; then
        ui_print info "正在从 GitHub 克隆仓库..."
        if git clone https://github.com/su-kaka/gcli2api "$GCLI_DIR"; then
            ui_print success "克隆成功。"
        else
            ui_print error "克隆失败，请检查网络。"
            ui_pause; return
        fi
    fi

    ui_print info "正在准备 Python 环境..."
    if ! command -v python3 &>/dev/null; then
        ui_print error "未找到 python3，请先到 [Python 环境管理] 安装。"
        ui_pause; return
    fi

    if [ ! -d "$GCLI_VENV" ]; then
        python3 -m venv "$GCLI_VENV"
        ui_print success "虚拟环境创建完成。"
    fi

    ui_print info "正在安装依赖 (这可能需要几分钟)..."
    source "$GCLI_VENV/bin/activate"
    
    if command -v uv &>/dev/null; then
        uv pip install -r "$GCLI_DIR/requirements.txt"
    else
        pip install --upgrade pip
        pip install -r "$GCLI_DIR/requirements.txt"
    fi
    
    if [ $? -eq 0 ]; then
        ui_print success "依赖安装完成！"
    else
        ui_print error "依赖安装失败。"
    fi
    ui_pause
}

start_gcli() {
    load_gcli_config
    
    if [ ! -d "$GCLI_DIR" ]; then
        ui_print error "请先安装模块。"
        ui_pause; return
    fi

    if check_process_smart "$GCLI_PID"; then
        ui_print warn "服务已经在运行中。"
        ui_pause; return
    fi

    ui_print info "正在启动服务..."
    
    source "$GCLI_VENV/bin/activate"
    cd "$GCLI_DIR" || return

    export PORT="$GCLI_PORT"
    export PASSWORD="$GCLI_PWD"
    export HOST="$GCLI_HOST"
    nohup python web.py > "$GCLI_LOG" 2>&1 &
    local new_pid=$!
    echo "$new_pid" > "$GCLI_PID"
    
    sleep 2
    if check_process_smart "$GCLI_PID"; then
        ui_print success "启动成功！(PID: $new_pid)"
        echo -e "访问地址: http://127.0.0.1:$GCLI_PORT"
    else
        ui_print error "启动失败，请检查日志。"
        cat "$GCLI_LOG" | tail -n 10
    fi
    ui_pause
}

stop_gcli() {
    kill_process_safe "$GCLI_PID" "python.*web.py"
    sleep 1
    
    if ! check_process_smart "$GCLI_PID"; then
        ui_print success "服务已停止。"
    else
        ui_print error "停止失败，进程可能仍卡死。"
        rm -f "$GCLI_PID"
    fi
    ui_pause
}

configure_gcli() {
    load_gcli_config
    
    while true; do
        ui_header "GCLI 配置管理"
        echo -e "当前端口: ${CYAN}$GCLI_PORT${NC}"
        echo -e "当前密码: ${CYAN}$GCLI_PWD${NC}"
        echo "----------------------------------------"
        
        local CHOICE=$(ui_menu "请选择修改项" \
            "🔌 修改端口" \
            "🔑 修改密码" \
            "💾 保存并返回" \
        )
        
        if [ -z "$CHOICE" ]; then
            ui_print error "菜单异常退出。"
            ui_pause; return
        fi
        
        case "$CHOICE" in
            *"端口"*) GCLI_PORT=$(ui_input "请输入新端口" "$GCLI_PORT" "false") ;;
            *"密码"*) GCLI_PWD=$(ui_input "请输入新密码" "$GCLI_PWD" "false") ;;
            *"保存"*)
                echo "GCLI_PORT=$GCLI_PORT" > "$GCLI_CONFIG"
                echo "GCLI_PWD=$GCLI_PWD" >> "$GCLI_CONFIG"
                echo "GCLI_HOST=$GCLI_HOST" >> "$GCLI_CONFIG"
                ui_print success "配置已保存 (重启服务生效)。"
                ui_pause; return ;;
        esac
    done
}

gcli2api_menu() {
    while true; do
        load_gcli_config
        ui_header "🌐 GCLI 转 API 服务"
        
        local state_type="stopped"
        local status_text="未运行"
        local info_list=()

        if check_process_smart "$GCLI_PID"; then
            state_type="running"
            status_text="运行中"
            info_list+=( "端口: $GCLI_PORT" "密码: $GCLI_PWD" "PID : $(cat "$GCLI_PID")" )
        else
            if [ -d "$GCLI_DIR" ]; then
                state_type="stopped"
                status_text="已停止"
                info_list+=( "已安装: $GCLI_DIR" )
            else
                state_type="info"
                status_text="未安装"
            fi
        fi
        
        ui_status_card "$state_type" "$status_text" "${info_list[@]}"

        local MENU_OPTS=()
        if [ "$state_type" == "running" ]; then
            MENU_OPTS+=( "🛑 停止服务" "🔄 重启服务" "📜 查看日志" )
        else
            if [ -d "$GCLI_DIR" ]; then
                MENU_OPTS+=( "🚀 启动服务" "⬆️  更新代码" "📜 查看日志" "🗑️  卸载模块" )
            else
                MENU_OPTS+=( "⬇️  安装模块" )
            fi
        fi
        MENU_OPTS+=( "⚙️  修改配置" "🔙 返回主菜单" )

        local CHOICE=$(ui_menu "请选择操作" "${MENU_OPTS[@]}")
        
        case "$CHOICE" in
            *"安装"*) install_gcli ;; 
            *"启动"*) start_gcli ;; 
            *"停止"*) stop_gcli ;; 
            *"重启"*) stop_gcli; start_gcli ;; 
            *"更新"*) cd "$GCLI_DIR" && git pull && ui_print success "更新完成" && ui_pause ;; 
            *"配置"*) configure_gcli ;; 
            *"日志"*) safe_log_monitor "$GCLI_LOG" ;; 
            *"卸载"*) 
                if ui_confirm "确定要卸载 GCLI2API 吗？"; then
                    stop_gcli
                    rm -rf "$GCLI_DIR" "$GCLI_CONFIG" "$GCLI_LOG"
                    ui_print success "已卸载。"
                    ui_pause
                fi ;; 
            *"返回"*) return ;; 
        esac
    done
}
