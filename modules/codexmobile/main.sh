#!/bin/bash
# [METADATA]
# MODULE_ID: codexmobile
# MODULE_NAME: Codex Mobile (Web UI)
# MODULE_ENTRY: codexmobile_menu
# APP_CATEGORY: AIBOX
# APP_AUTHOR: friuns2
# APP_PROJECT_URL: https://github.com/friuns2/codex-mobile
# APP_DESC: 专为移动端 (Termux) 与 Linux/Windows 设计的 Codex 远程 Web UI 界面，提供极简网页控制面板与内置终端。
# [END_METADATA]

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

_codexmobile_vars() {
    CM_APP_ID="codexmobile"
    CM_DIR=$(get_app_path "$CM_APP_ID")
    CM_LOG="$LOGS_DIR/codexmobile.log"
    CM_PID="$RUN_DIR/codexmobile.pid"
    CM_ENV_CONF="$CONFIG_DIR/codexmobile.env"
    mkdir -p "$CM_DIR"
}

_codexmobile_load_env() {
    _codexmobile_vars
    CM_PORT="18923"
    CM_BIND_HOST="0.0.0.0"
    CM_ENABLE_TUNNEL="false"
    CM_SKIP_LOGIN="true"

    if [ -f "$CM_ENV_CONF" ]; then
        # shellcheck disable=SC1090
        source "$CM_ENV_CONF"
    fi
}

_codexmobile_save_env() {
    _codexmobile_vars
    cat <<EOF > "$CM_ENV_CONF"
# Codex Mobile Configuration
CM_PORT="$CM_PORT"
CM_BIND_HOST="$CM_BIND_HOST"
CM_ENABLE_TUNNEL="$CM_ENABLE_TUNNEL"
CM_SKIP_LOGIN="$CM_SKIP_LOGIN"
EOF
}

codexmobile_install() {
    _codexmobile_vars
    ui_header "安装 Codex Mobile (Web UI)"

    local GIT_REPO="https://github.com/friuns2/codex-mobile.git"

    if ! command -v git &> /dev/null; then
        ui_print warn "未检测到 git，正在安装..."
        sys_install_pkg "git" || return 1
    fi

    prepare_network_strategy
    
    local do_install=true

    if [ -d "$CM_DIR" ] && [ -d "$CM_DIR/.git" ]; then
        if ui_confirm "检测到已安装 Codex Mobile，是否更新源码？\n[No] 将清除并重新克隆安装"; then
            cd "$CM_DIR" || return 1
            local remote_url
            remote_url=$(get_dynamic_repo_url "$GIT_REPO")
            if ui_stream_task "正在更新源码..." "git pull --autostash '$remote_url'"; then
                ui_print success "源码更新成功。"
                do_install=false
            else
                ui_print error "更新失败，将重新安装。"
                safe_rm "$CM_DIR"
            fi
        else
            safe_rm "$CM_DIR"
        fi
    elif [ -d "$CM_DIR" ]; then
        ui_print warn "发现残留目录，正在清理重装..."
        safe_rm "$CM_DIR"
    fi

    if [ "$do_install" = true ]; then
        if git_clone_smart "" "$GIT_REPO" "$CM_DIR"; then
            ui_print success "仓库拉取完成。"
        else
            ui_print error "Git 克隆失败，请检查网络设置。"
            ui_pause; return 1
        fi
    fi

    ui_print info "检查 Node.js 环境 (推荐 >= 18)..."
    cd "$CM_DIR" || return 1
    
    local node_ok=false
    if command -v node &> /dev/null; then
        local node_ver
        node_ver=$(node -v | cut -d. -f1 | tr -d 'v')
        if [ -n "$node_ver" ] && [ "$node_ver" -ge 18 ]; then
            node_ok=true
        else
            ui_print warn "检测到 Node.js 版本 ($node_ver) 较低。"
        fi
    fi

    if [ "$node_ok" = false ]; then
        ui_print info "正在自动升级/安装 Node.js..."
        sys_install_pkg "nodejs" "npm"
        if ! command -v node &> /dev/null; then
            ui_print error "Node.js 安装失败，请手动安装 Node.js 18+ 后重试。"
            ui_pause; return 1
        fi
    fi

    if [ "$OS_TYPE" == "TERMUX" ]; then
        if ! command -v clang &> /dev/null || ! command -v make &> /dev/null; then
            ui_print info "Termux 环境: 补充 C/C++ 依赖工具 (node-pty 原生编译所需)..."
            sys_install_pkg "clang" "make" "python"
        fi
    elif command -v apt-get &> /dev/null; then
        if ! dpkg -s build-essential &> /dev/null; then
            ui_print info "Linux 环境: 补充 build-essential 工具..."
            sys_install_pkg "build-essential"
        fi
    fi

    ui_print info "检查构建包管理器 (pnpm)..."
    if ! command -v pnpm &> /dev/null; then
        ui_print info "正在自动安装 pnpm..."
        npm install -g pnpm 2>/dev/null || true
    fi

    ui_print info "开始安装依赖并构建应用..."
    local BUILD_CMD
    if command -v pnpm &> /dev/null; then
        BUILD_CMD="pnpm install && pnpm run build:frontend && pnpm run build:cli"
    else
        BUILD_CMD="npm install && npm run build:frontend && npm run build:cli"
    fi

    if ui_stream_task "正在构建 Codex Mobile..." "$BUILD_CMD"; then
        ui_print success "依赖安装与前端构建完成！"
    else
        ui_print error "构建失败，请检查网络或依赖环境。"
        ui_pause; return 1
    fi

    if [ ! -f "$CM_ENV_CONF" ]; then
        _codexmobile_save_env
        ui_print success "已生成默认配置文件 ($CM_ENV_CONF)"
    fi

    ui_print success "Codex Mobile 安装成功！"
}

codexmobile_start() {
    _codexmobile_vars
    _codexmobile_load_env

    if [ ! -f "$CM_DIR/package.json" ] || [ ! -f "$CM_DIR/dist-cli/index.js" ]; then
        if ui_confirm "未检测到已构建的 Codex Mobile，是否立即安装？"; then
            codexmobile_install || return 1
        else
            return 1
        fi
    fi

    ui_header "启动 Codex Mobile"
    auto_load_proxy_env

    cd "$CM_DIR" || return 1

    local ARGS=("--port" "$CM_PORT" "--host" "$CM_BIND_HOST")
    if [ "$CM_ENABLE_TUNNEL" != "true" ]; then
        ARGS+=("--no-tunnel")
    fi
    if [ "$CM_SKIP_LOGIN" == "true" ]; then
        ARGS+=("--no-login")
    fi

    local RUN_CMD="node dist-cli/index.js ${ARGS[*]}"

    if [ "$OS_TYPE" == "TERMUX" ]; then
        if command -v termux-wake-lock &> /dev/null; then
            termux-wake-lock 2>/dev/null
        fi

        tavx_service_register "codexmobile" "$RUN_CMD" "$CM_DIR"
        tavx_service_control "up" "codexmobile"
        ui_print success "Termux 后台服务启动命令已发出。"
    else
        codexmobile_stop
        echo "--- Codex Mobile Start $(date) ---" > "$CM_LOG"
        local START_CMD="setsid nohup $RUN_CMD >> '$CM_LOG' 2>&1 & echo \$! > '$CM_PID'"

        if ui_spinner "正在启动 Codex Mobile..." "eval \"$START_CMD\""; then
            sleep 2
            if check_process_smart "$CM_PID" "dist-cli/index.js|codexapp|codexmobile"; then
                ui_print success "Codex Mobile 服务已成功驻留！"
            else
                ui_print error "启动失败，进程未正常驻留，请查看日志。"
                ui_pause; return 1
            fi
        fi
    fi
}

codexmobile_stop() {
    _codexmobile_vars
    if [ "$OS_TYPE" == "TERMUX" ]; then
        tavx_service_control "down" "codexmobile"
        if command -v termux-wake-unlock &> /dev/null; then
            termux-wake-unlock 2>/dev/null
        fi
    else
        kill_process_safe "$CM_PID" "dist-cli/index.js|codexapp|codexmobile"
        pkill -f "dist-cli/index.js" 2>/dev/null
    fi
}

codexmobile_uninstall() {
    _codexmobile_vars
    ui_header "卸载 Codex Mobile"
    if ! verify_kill_switch; then return; fi

    codexmobile_stop
    tavx_service_remove "codexmobile"

    if ui_spinner "正在清理数据文件..." "safe_rm '$CM_DIR' '$CM_PID' '$CM_ENV_CONF'"; then
        ui_print success "Codex Mobile 卸载完成。"
        return 2
    fi
}

codexmobile_config_menu() {
    _codexmobile_load_env

    while true; do
        ui_header "⚙️ Codex Mobile 参数配置"
        echo -e "当前端口 : ${GREEN}${CM_PORT}${NC}"
        echo -e "绑定地址 : ${GREEN}${CM_BIND_HOST}${NC}"
        echo -e "Cloudflare 隧道 : ${GREEN}${CM_ENABLE_TUNNEL}${NC}"
        echo -e "免登录模式 (--no-login): ${GREEN}${CM_SKIP_LOGIN}${NC}"
        echo ""

        local CHOICE
        CHOICE=$(ui_menu "选择要修改的设置" \
            "1. 修改服务端口 [当前: $CM_PORT]" \
            "2. 修改监听网卡 [当前: $CM_BIND_HOST]" \
            "3. 切换 Cloudflare 隧道模式 [当前: $CM_ENABLE_TUNNEL]" \
            "4. 切换免登录模式 (--no-login) [当前: $CM_SKIP_LOGIN]" \
            "💾 保存并返回")

        case "$CHOICE" in
            *"1."*)
                local input_port
                input_port=$(ui_input "输入新的服务端口 (1-65535)" "$CM_PORT")
                if [[ "$input_port" =~ ^[0-9]+$ ]] && [ "$input_port" -ge 1 ] && [ "$input_port" -le 65535 ]; then
                    CM_PORT="$input_port"
                    ui_print success "端口设置为: $CM_PORT"
                else
                    ui_print error "无效的端口号！"
                    ui_pause
                fi
                ;;
            *"2."*)
                local input_host
                input_host=$(ui_input "输入监听地址 (如 0.0.0.0 或 127.0.0.1)" "$CM_BIND_HOST")
                if [ -n "$input_host" ]; then
                    CM_BIND_HOST="$input_host"
                    ui_print success "绑定地址设置为: $CM_BIND_HOST"
                fi
                ;;
            *"3."*)
                if [ "$CM_ENABLE_TUNNEL" == "true" ]; then
                    CM_ENABLE_TUNNEL="false"
                else
                    CM_ENABLE_TUNNEL="true"
                fi
                ui_print success "Cloudflare 隧道已设置为: $CM_ENABLE_TUNNEL"
                ;;
            *"4."*)
                if [ "$CM_SKIP_LOGIN" == "true" ]; then
                    CM_SKIP_LOGIN="false"
                else
                    CM_SKIP_LOGIN="true"
                fi
                ui_print success "免登录模式已设置为: $CM_SKIP_LOGIN"
                ;;
            *"保存"*)
                _codexmobile_save_env
                ui_print success "配置保存成功！如果服务正在运行，请重启后生效。"
                ui_pause; return 0
                ;;
            *)
                return 0
                ;;
        esac
    done
}

codexmobile_menu() {
    while true; do
        _codexmobile_vars
        _codexmobile_load_env

        ui_header "📱 Codex Mobile (Web UI) 管理"

        local state="stopped"; local text="已停止"; local info=()
        local log_path="$CM_LOG"
        [ "$OS_TYPE" == "TERMUX" ] && log_path="$PREFIX/var/service/codexmobile/log/current"

        if [ "$OS_TYPE" == "TERMUX" ]; then
            if sv status codexmobile 2>/dev/null | grep -q "^run:"; then
                state="running"; text="运行中"
            fi
        elif check_process_smart "$CM_PID" "dist-cli/index.js|codexapp|codexmobile"; then
            state="running"; text="运行中"
        fi

        if [ "$state" == "running" ]; then
            local local_ip
            local_ip=$(get_local_ip 2>/dev/null || echo "127.0.0.1")
            info+=( "本地访问: http://127.0.0.1:$CM_PORT" )
            info+=( "局域网: http://$local_ip:$CM_PORT" )
            info+=( "免登录: $CM_SKIP_LOGIN | 隧道: $CM_ENABLE_TUNNEL" )
        else
            info+=( "提示: 服务未启动" )
            info+=( "当前预设端口: $CM_PORT" )
        fi

        ui_status_card "$state" "$text" "${info[@]}"

        local CHOICE
        CHOICE=$(ui_menu "请选择操作" \
            "🚀 启动服务" \
            "🛑 停止服务" \
            "🔄 重启服务" \
            "⚙️ 参数配置" \
            "📜 查看日志" \
            "⚡ (Termux) 保持CPU唤醒锁" \
            "📥 重装/更新源码" \
            "🗑️  卸载模块" \
            "🧭 关于模块" \
            "🔙 返回")

        case "$CHOICE" in
            *"启动"*)
                codexmobile_start; ui_pause ;;
            *"停止"*)
                codexmobile_stop; ui_print success "已发出停止指令"; ui_pause ;;
            *"重启"*)
                codexmobile_stop; sleep 1; codexmobile_start; ui_pause ;;
            *"参数配置"*)
                codexmobile_config_menu ;;
            *"日志"*)
                ui_watch_log "codexmobile" ;;
            *"唤醒锁"*)
                if [ "$OS_TYPE" == "TERMUX" ]; then
                    if command -v termux-wake-lock &>/dev/null; then
                        termux-wake-lock
                        ui_print success "已应用 Termux WakeLock 锁定 (防止Android杀死进程)"
                    else
                        ui_print error "未找到 termux-wake-lock 工具，请检查 termux-api 安装。"
                    fi
                else
                    ui_print info "当前操作系统为 Linux，$OS_TYPE 环境无需配置 Termux 唤醒锁。"
                fi
                ui_pause ;;
            *"重装"*)
                codexmobile_install ;;
            *"卸载"*)
                codexmobile_uninstall && [ $? -eq 2 ] && return ;;
            *"关于"*)
                show_module_about_info "${BASH_SOURCE[0]}" ;;
            *"返回"*)
                return ;;
        esac
    done
}
