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
    if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
        if [ "$OS_TYPE" == "TERMUX" ]; then
            asset_pattern="android-aarch64"
        else
            asset_pattern="linux-aarch64"
        fi
    elif [[ "$arch" == "x86_64" || "$arch" == "amd64" ]]; then
        asset_pattern="linux-x86_64"
    fi
    
    ui_print info "正在获取 ClewdR 版本信息 ($asset_pattern)..."
    prepare_network_strategy
    auto_load_proxy_env
    
    local release_info=""
    # 方案 1: Python 原生发起请求 (自动支持当前环境代理与全局超长超时)
    release_info=$(python3 - "Xerxes-2/clewdr" "$asset_pattern" << 'PY_EOF' 2>/dev/null
import sys, urllib.request, json, os

repo = sys.argv[1]
pattern = sys.argv[2]
api_url = f"https://api.github.com/repos/{repo}/releases/latest"

proxy = os.environ.get("https_proxy") or os.environ.get("http_proxy") or os.environ.get("ALL_PROXY")
opener = urllib.request.build_opener(urllib.request.ProxyHandler({'http': proxy, 'https': proxy})) if proxy else urllib.request.build_opener()
req = urllib.request.Request(api_url, headers={"User-Agent": "TAV-X/ClewdR"})
try:
    with opener.open(req, timeout=10) as resp:
        data = json.loads(resp.read().decode())
        tag = data.get("tag_name", "").strip()
        for a in data.get("assets", []):
            name = a.get("name", "")
            if pattern in name and name.endswith(".zip"):
                print(f"{tag}|{a.get('browser_download_url', '')}")
                sys.exit(0)
except Exception:
    pass
sys.exit(1)
PY_EOF
)

    # 方案 2: 若 Python 请求受阻，尝试 curl 获取并由 Python 健壮解析
    if [ -z "$release_info" ]; then
        local raw_json
        raw_json=$(curl -s -m 8 "https://api.github.com/repos/Xerxes-2/clewdr/releases/latest" 2>/dev/null)
        if [ -n "$raw_json" ] && [[ "$raw_json" != *"rate limit"* ]]; then
            release_info=$(python3 - "$raw_json" "$asset_pattern" << 'PY_EOF' 2>/dev/null
import sys, json

try:
    data = json.loads(sys.argv[1])
    pattern = sys.argv[2]
    tag = data.get("tag_name", "").strip()
    for a in data.get("assets", []):
        name = a.get("name", "")
        if pattern in name and name.endswith(".zip"):
            print(f"{tag}|{a.get('browser_download_url', '')}")
            sys.exit(0)
except Exception:
    pass
sys.exit(1)
PY_EOF
)
        fi
    fi

    local download_url=""
    local tag=""
    if [ -n "$release_info" ]; then
        tag="${release_info%%|*}"
        download_url="${release_info##*|}"
    fi

    # 兜底至已知官方最新稳定版本 (v0.13.8)
    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        tag="v0.13.8"
        download_url="https://github.com/Xerxes-2/clewdr/releases/download/${tag}/clewdr-${asset_pattern}.zip"
        ui_print warn "通过 API 发现失败，切换至已知稳定版本 (${tag})..."
    else
        ui_print success "发现最新版本: $tag"
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
        
        echo "$tag" > "$CL_DIR/.version"
        safe_rm "$tmp_file"
        ui_print success "ClewdR ($tag) 安装完成。"
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

        local app_ver="未安装"
        if [ -f "$CL_DIR/.version" ]; then
            app_ver=$(cat "$CL_DIR/.version" 2>/dev/null | tr -d '\r\n')
        elif [ -f "$CL_DIR/clewdr" ]; then
            app_ver="已就绪"
        fi

        if [ "$OS_TYPE" == "TERMUX" ]; then
            if sv status clewd 2>/dev/null | grep -q "^run:"; then
                state="running"; text="运行中"
            fi
        elif check_process_smart "$CL_PID" "clewdr|node.*clewd\.js"; then
            state="running"; text="运行中"
        fi

        info+=( "版本: $app_ver" )

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