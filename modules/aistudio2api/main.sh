#!/bin/bash
# [METADATA]
# MODULE_ID: aistudio2api
# MODULE_NAME: AIStudio2API (Go版)
# MODULE_ENTRY: aistudio2api_menu
# APP_CATEGORY: AI模型接口
# APP_AUTHOR: Mag1cFall
# APP_PROJECT_URL: https://github.com/Mag1cFall/AIStudio2API
# APP_DESC: 基于 Go 的高性能 Google AI Studio 代理服务，支持 Playground + Build 双额度通道、纯 Go 免浏览器 WAA 防护与 WebUI 管理。
# [END_METADATA]

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"
source "$TAVX_DIR/core/net_utils.sh"

_aistudio2api_vars() {
    AS_APP_ID="aistudio2api"
    AS_DIR=$(get_app_path "$AS_APP_ID")
    AS_BIN="$AS_DIR/aistudio2api"
    AS_ENV="$AS_DIR/.env"
    AS_LOG="$LOGS_DIR/aistudio2api.log"
    AS_PID="$RUN_DIR/aistudio2api.pid"
    AS_AUTH_DIR="$AS_DIR/auth"
    AS_REPO="Mag1cFall/AIStudio2API"
    mkdir -p "$AS_DIR" "$AS_AUTH_DIR"
}

_aistudio2api_get_port() {
    _aistudio2api_vars
    local port="2048"
    if [ -f "$AS_ENV" ]; then
        local addr
        addr=$(grep "^LISTEN_ADDR=" "$AS_ENV" | cut -d= -f2- | tr -d '"' | tr -d "'" | tr -d '\r' | xargs)
        if [[ "$addr" == *":"* ]]; then
            port="${addr##*:}"
        fi
    fi
    echo "${port:-2048}"
}

_aistudio2api_get_auth_count() {
    _aistudio2api_vars
    local count=0
    if [ -d "$AS_AUTH_DIR" ]; then
        shopt -s nullglob
        local files=("$AS_AUTH_DIR"/*)
        shopt -u nullglob
        count=${#files[@]}
    fi
    echo "$count"
}

_aistudio2api_init_env() {
    _aistudio2api_vars
    if [ ! -f "$AS_ENV" ]; then
        ui_print info "正在初始化默认运行配置 (.env)..."
        cat << 'EOF' > "$AS_ENV"
# 账户状态文件、目录或逗号分隔的多个路径
AISTUDIO_AUTH_STATES=auth

# 服务监听地址
LISTEN_ADDR=0.0.0.0:2048

# 本地 API 认证密钥 (留空即无鉴权，多个 key 用逗号分隔)
PROXY_API_KEY=

# 管理程序启动后自动启动生成服务
AUTO_START=true

# 保存公开 API 的 POST 请求与响应正文
REQUEST_BODY_LOG=false

# 同时把服务日志写入 runtime/logs/
LOG_FILE=true
LOG_MAX_TOTAL_MB=200

# 管理控制台登录免密 (手机/Termux 环境默认关闭)
ADMIN_AUTH_ENABLED=false
ADMIN_USERNAME=admin
ADMIN_PASSWORD=

# setup 与未指定账户使用的代理 (留空使用直连或系统代理)
PROXY=

# 超时设置
INIT_TIMEOUT=2m
REQUEST_TIMEOUT=5m

# 预热与工作线程并发
WARM_WORKER_LIMIT=5
MAX_ACTIVE_WORKERS=10
WARM_STARTUP_CONCURRENCY=5
PER_ACCOUNT_CONCURRENCY=2
ROUTING_STRATEGY=round-robin

# 生成请求使用的上游通道 (Playground 与 Build 双通道)
UPSTREAM_CHANNELS=playground,build
BUILD_NATIVE_NONSTREAM=true

# WAA 后端配置: 极关键! 设为 go 启用纯 Go 进程内算法，零浏览器依赖
WAA_BACKEND=go
TEMPORARY_CHAT=false
EOF
        ui_print success "配置文件 (.env) 初始化完成，默认已开启纯 Go WAA 后端！"
    fi
}

aistudio2api_install() {
    _aistudio2api_vars
    ui_header "安装 AIStudio2API (Go版)"

    local arch
    arch=$(uname -m)
    local asset_arch="linux-amd64"
    case "$arch" in
        aarch64|arm64) asset_arch="linux-arm64" ;;
        x86_64|amd64)  asset_arch="linux-amd64" ;;
        *)
            ui_print error "暂不支持当前的系统架构: $arch"
            ui_pause; return 1
            ;;
    esac

    ui_print info "检测到系统架构: $arch (匹配资产: $asset_arch)"
    prepare_network_strategy

    ui_print info "正在获取 AIStudio2API 最新发布版本..."
    local api_url="https://api.github.com/repos/${AS_REPO}/releases/latest"
    local json
    json=$(curl -s -m 10 "$api_url")

    local download_url=""
    local tag=""
    if [ -n "$json" ] && [[ "$json" != *"rate limit"* ]]; then
        tag=$(echo "$json" | yq -p json '.tag_name' 2>/dev/null | tr -d '"' | tr -d '\r')
        download_url=$(echo "$json" | yq -p json '.assets[] | select(.name | contains("'$asset_arch'")) | .browser_download_url' 2>/dev/null | head -n 1 | tr -d '"' | tr -d '\r')
    fi

    # Fallback to known stable version if API fails
    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        tag="v0.2.12"
        download_url="https://github.com/${AS_REPO}/releases/download/${tag}/aistudio2api-${tag}-${asset_arch}.tar.gz"
        ui_print warn "通过 API 发现失败，切换至已知稳定版本 (${tag})..."
    else
        ui_print success "发现最新版本: $tag"
    fi

    local tmp_archive="$TMP_DIR/aistudio2api_${tag}_${asset_arch}.tar.gz"
    local DL_CMD="source \"$TAVX_DIR/core/net_utils.sh\"; download_file_smart '$download_url' '$tmp_archive' 'true'"

    if ! ui_stream_task "下载 AIStudio2API 预编译包..." "$DL_CMD"; then
        ui_print error "下载失败，请检查网络设置或代理。"
        ui_pause; return 1
    fi

    ui_print info "正在解压并部署二进制文件..."
    local tmp_extract="$TMP_DIR/aistudio2api_extract_$$"
    mkdir -p "$tmp_extract"
    if ! tar -xzf "$tmp_archive" -C "$tmp_extract"; then
        ui_print error "解压归档文件失败。"
        rm -rf "$tmp_extract" "$tmp_archive"
        ui_pause; return 1
    fi

    local extracted_bin
    extracted_bin=$(find "$tmp_extract" -type f -name "aistudio2api" | head -n 1)
    if [ -z "$extracted_bin" ] || [ ! -f "$extracted_bin" ]; then
        ui_print error "归档包中未找到 aistudio2api 可执行文件。"
        rm -rf "$tmp_extract" "$tmp_archive"
        ui_pause; return 1
    fi

    cp "$extracted_bin" "$AS_BIN"
    chmod +x "$AS_BIN"
    rm -rf "$tmp_extract" "$tmp_archive"

    # 初始化配置
    _aistudio2api_init_env

    # 验证二进制可执行性
    if "$AS_BIN" -h &>/dev/null; then
        ui_print success "程序环境测试通过！"
    else
        ui_print warn "二进制调用检测返回异常，但已成功释放至 $AS_BIN"
    fi

    ui_print success "AIStudio2API 安装成功！"
    ui_pause
}

aistudio2api_start() {
    _aistudio2api_vars
    if [ ! -x "$AS_BIN" ]; then
        if ui_confirm "未检测到已安装的 AIStudio2API，是否立即安装？"; then
            aistudio2api_install || return 1
        else
            return 1
        fi
    fi

    ui_header "启动 AIStudio2API"
    _aistudio2api_init_env
    auto_load_proxy_env

    cd "$AS_DIR" || return 1

    local port
    port=$(_aistudio2api_get_port)
    local RUN_CMD="'$AS_BIN' -open-ui=false"

    if [ "$OS_TYPE" == "TERMUX" ]; then
        if command -v termux-wake-lock &>/dev/null; then
            termux-wake-lock 2>/dev/null
        fi

        tavx_service_register "aistudio2api" "$RUN_CMD" "$AS_DIR"
        tavx_service_control "up" "aistudio2api"
        sleep 1.5
        if is_app_running "aistudio2api"; then
            ui_print success "Termux 后台服务已成功运行！"
        else
            ui_print warn "服务启动指令已发出，正在后台启动..."
        fi
    else
        aistudio2api_stop
        echo "--- AIStudio2API Start $(date) ---" > "$AS_LOG"
        local START_CMD="cd '$AS_DIR' && setsid nohup $RUN_CMD >> '$AS_LOG' 2>&1 & echo \$! > '$AS_PID'"
        if ui_spinner "正在启动 AIStudio2API..." "eval \"$START_CMD\""; then
            sleep 1
            if check_process_smart "$AS_PID" "aistudio2api"; then
                ui_print success "服务启动成功！"
            else
                ui_print error "进程未正常驻留，请检查日志: $AS_LOG"
                ui_pause; return 1
            fi
        fi
    fi

    local local_ip
    local_ip=$(get_local_ip)
    ui_print success "AIStudio2API 服务正在运行中！"
    echo -e "  🌐 本地地址: \033[1;36mhttp://127.0.0.1:${port}\033[0m"
    echo -e "  📡 局域网地址: \033[1;36mhttp://${local_ip}:${port}\033[0m"
    ui_pause
}

aistudio2api_stop() {
    _aistudio2api_vars
    ui_print info "正在停止 AIStudio2API..."

    if [ "$OS_TYPE" == "TERMUX" ] && command -v sv &>/dev/null; then
        tavx_service_control "down" "aistudio2api"
    fi

    if [ -f "$AS_PID" ]; then
        kill_process_safe "$AS_PID" "aistudio2api"
    fi
    pkill -f "$AS_BIN" 2>/dev/null
    ui_print success "已停止。"
}

aistudio2api_restart() {
    aistudio2api_stop
    sleep 1
    aistudio2api_start
}

aistudio2api_uninstall() {
    _aistudio2api_vars
    ui_header "卸载 AIStudio2API"

    if ! ui_confirm "确定要完全卸载 AIStudio2API 吗？(将删除应用及所有已存账号数据)"; then
        return 1
    fi

    aistudio2api_stop
    if [ "$OS_TYPE" == "TERMUX" ]; then
        tavx_service_remove "aistudio2api"
    fi

    safe_rm "$AS_DIR"
    safe_rm "$AS_LOG"
    safe_rm "$AS_PID"
    ui_print success "AIStudio2API 已彻底卸载。"
    ui_pause
    return 2
}

aistudio2api_open_webui() {
    _aistudio2api_vars
    local port
    port=$(_aistudio2api_get_port)
    local url="http://127.0.0.1:${port}"

    if ! is_app_running "aistudio2api"; then
        ui_print warn "服务尚未启动，正在先为您启动服务..."
        aistudio2api_start || return
    fi

    ui_print info "正在打开 Web 控制台: $url"
    if command -v termux-open-url &>/dev/null; then
        termux-open-url "$url"
    elif command -v xdg-open &>/dev/null; then
        xdg-open "$url" 2>/dev/null
    else
        ui_print info "请在浏览器中手动访问: $url"
    fi
    ui_pause
}

aistudio2api_import_auth() {
    _aistudio2api_vars
    ui_header "📥 导入 Google AI Studio 账号凭据"

    if [ ! -x "$AS_BIN" ]; then
        ui_print error "程序未安装，请先执行安装。"
        ui_pause; return 1
    fi

    echo -e "说明："
    echo -e "  可导入从电脑/移动端浏览器扩展导出的 \033[1;33mStorageState / Playwright JSON\033[0m 凭据文件。"
    echo -e "  或者也可以在启动服务后，直接在 \033[1;36mWeb 控制台\033[0m 页面中点选上传。\n"

    local json_file
    json_file=$(ui_input "请输入 JSON 凭据文件的绝对路径" "" false)
    if [ -z "$json_file" ]; then
        ui_print warn "已取消操作。"
        ui_pause; return
    fi

    if [ ! -f "$json_file" ]; then
        ui_print error "未找到文件: $json_file"
        ui_pause; return 1
    fi

    ui_print info "正在通过 aistudio2api 导入并签署状态凭据..."
    cd "$AS_DIR" || return 1
    if "$AS_BIN" setup --storage-state "$json_file"; then
        ui_print success "账号凭据导入成功！"
    else
        ui_print error "凭据导入或验证失败，请确认文件格式有效。"
    fi
    ui_pause
}

aistudio2api_config_menu() {
    _aistudio2api_vars
    _aistudio2api_init_env

    while true; do
        ui_header "⚙️ AIStudio2API 参数配置"
        local port
        port=$(_aistudio2api_get_port)
        local cur_key
        cur_key=$(grep "^PROXY_API_KEY=" "$AS_ENV" | cut -d= -f2- | tr -d '"' | tr -d "'" | tr -d '\r' | xargs)
        local cur_backend
        cur_backend=$(grep "^WAA_BACKEND=" "$AS_ENV" | cut -d= -f2- | tr -d '"' | tr -d "'" | tr -d '\r' | xargs)
        local cur_proxy
        cur_proxy=$(grep "^PROXY=" "$AS_ENV" | cut -d= -f2- | tr -d '"' | tr -d "'" | tr -d '\r' | xargs)

        echo -e "当前配置概要："
        echo -e "  • 监听端口 : \033[1;36m${port}\033[0m"
        echo -e "  • API 密钥 : \033[1;33m${cur_key:-<无鉴权 (公开)>}\033[0m"
        echo -e "  • WAA 引擎 : \033[1;32m${cur_backend:-go}\033[0m (Termux 务必保持 go)"
        echo -e "  • 出口代理 : \033[1;35m${cur_proxy:-<跟随系统/直连>}\033[0m\n"

        local CHOICE
        CHOICE=$(ui_menu "请选择要修改的项" "🔌 修改监听端口" "🔑 设置 / 修改 API 认证密钥" "🛡️  切换 WAA 后端引擎" "🌐 配置上游专属代理" "📝 手动编辑完整 .env 文件" "🔙 返回上一级")

        case "$CHOICE" in
            *"监听端口"*)
                local new_port
                new_port=$(ui_input "请输入新的服务端口 (1024-65535)" "$port" false)
                if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -ge 1024 ] && [ "$new_port" -le 65535 ]; then
                    sed -i "s|^LISTEN_ADDR=.*|LISTEN_ADDR=0.0.0.0:${new_port}|g" "$AS_ENV"
                    ui_print success "端口已修改为: $new_port (重启服务后生效)"
                else
                    ui_print error "端口输入无效。"
                fi
                ui_pause
                ;;
            *"API 认证密钥"*)
                local new_key
                new_key=$(ui_input "请输入 API 密钥 (留空即关闭鉴权)" "$cur_key" false)
                sed -i "s|^PROXY_API_KEY=.*|PROXY_API_KEY=${new_key}|g" "$AS_ENV"
                ui_print success "API 密钥已更新 (重启服务后生效)"
                ui_pause
                ;;
            *"WAA 后端"*)
                local sel
                sel=$(ui_menu "请选择 WAA 引擎" "🟢 go (纯 Go 进程内运行，极低占用，手机必须推荐)" "⚪ camoufox (桌面级防检测浏览器，手机端不推荐)")
                if [[ "$sel" == *"go"* ]]; then
                    sed -i "s|^WAA_BACKEND=.*|WAA_BACKEND=go|g" "$AS_ENV"
                    ui_print success "已切换为纯 Go 引擎！"
                elif [[ "$sel" == *"camoufox"* ]]; then
                    sed -i "s|^WAA_BACKEND=.*|WAA_BACKEND=camoufox|g" "$AS_ENV"
                    ui_print warn "已切换为 Camoufox 引擎 (手机端可能因缺少 X11/GLIBC 无法工作)。"
                fi
                ui_pause
                ;;
            *"专属代理"*)
                local new_p
                new_p=$(ui_input "请输入代理地址 (如 http://127.0.0.1:7890，留空清除)" "$cur_proxy" false)
                sed -i "s|^PROXY=.*|PROXY=${new_p}|g" "$AS_ENV"
                ui_print success "代理设置已更新。"
                ui_pause
                ;;
            *"手动编辑"*)
                if command -v nano &>/dev/null; then
                    nano "$AS_ENV"
                else
                    vi "$AS_ENV"
                fi
                ;;
            *"返回"*)
                return
                ;;
        esac
    done
}

aistudio2api_menu() {
    _aistudio2api_vars

    while true; do
        local state="stopped"
        local state_text="已停止"
        local info=()

        if is_app_running "aistudio2api"; then
            state="running"
            state_text="运行中"
        fi

        local port
        port=$(_aistudio2api_get_port)
        local local_ip
        local_ip=$(get_local_ip)
        local accounts
        accounts=$(_aistudio2api_get_auth_count)
        local cur_backend="go"
        if [ -f "$AS_ENV" ]; then
            cur_backend=$(grep "^WAA_BACKEND=" "$AS_ENV" | cut -d= -f2- | tr -d '"' | tr -d "'" | tr -d '\r' | xargs)
        fi

        info+=("端口: $port")
        info+=("控制台: http://127.0.0.1:$port")
        info+=("局域网: http://${local_ip}:$port")
        info+=("WAA引擎: ${cur_backend:-go} (免浏览器)")
        info+=("已导入账号: ${accounts} 个")

        ui_header "AIStudio2API (Go版) 管理面板"
        ui_status_card "$state" "$state_text" "${info[@]}"

        local CHOICE
        CHOICE=$(ui_menu "操作菜单" \
            "🚀 启动服务" \
            "🛑 停止服务" \
            "🔄 重启服务" \
            "🌐 打开 Web 控制台" \
            "📥 导入账号凭据 (JSON 文件)" \
            "⚙️  参数配置" \
            "📜 查看实时日志" \
            "⬇️  检查/重新安装" \
            "🗑️  卸载模块" \
            "🧭 关于模块" \
            "🔙 返回主菜单")

        case "$CHOICE" in
            *"启动服务"*)
                aistudio2api_start
                ;;
            *"停止服务"*)
                aistudio2api_stop
                ui_print success "服务已停止。"
                ui_pause
                ;;
            *"重启服务"*)
                aistudio2api_restart
                ;;
            *"打开 Web"*|*"控制台"*)
                aistudio2api_open_webui
                ;;
            *"导入账号"*)
                aistudio2api_import_auth
                ;;
            *"参数配置"*)
                aistudio2api_config_menu
                ;;
            *"实时日志"*)
                ui_watch_log "aistudio2api"
                ;;
            *"检查/重新安装"*)
                aistudio2api_install
                ;;
            *"卸载模块"*)
                aistudio2api_uninstall && [ $? -eq 2 ] && return
                ;;
            *"关于模块"*)
                show_module_about_info "${BASH_SOURCE[0]}"
                ;;
            *"返回"*)
                return
                ;;
        esac
    done
}
