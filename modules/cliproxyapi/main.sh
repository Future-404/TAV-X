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
source "$TAVX_DIR/core/net_utils.sh"

_cp_vars() {
    CP_APP_ID="cliproxyapi"
    CP_DIR=$(get_app_path "$CP_APP_ID")
    CP_BIN="$CP_DIR/cli-proxy-api"
    CP_CONFIG="$CP_DIR/config.yaml"
    CP_LOG="$CP_DIR/proxy.log"
    CP_SVC_NAME="cliproxyapi"
    CP_REPO="router-for-me/CLIProxyAPI"
    mkdir -p "$CP_DIR"
}

_cp_get_port() {
    _cp_vars
    local port="8317"
    if [ -f "$CP_CONFIG" ]; then
        local parsed
        parsed=$(python3 - "$CP_CONFIG" << 'PY_EOF' 2>/dev/null
import sys, re

try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        lines = f.readlines()
    in_server = False
    for line in lines:
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        if indent == 0:
            in_server = s.startswith("server:")
            m_root = re.match(r'^port:\s*["\']?(\d+)["\']?', s)
            if m_root:
                print(m_root.group(1))
                sys.exit(0)
        elif in_server:
            m_srv = re.match(r'^port:\s*["\']?(\d+)["\']?', s)
            if m_srv:
                print(m_srv.group(1))
                sys.exit(0)
except Exception:
    pass
PY_EOF
)
        [ -n "$parsed" ] && port="$parsed"
    fi
    echo "$port"
}

_cp_init_or_migrate_config() {
    _cp_vars
    local is_new=false
    if [ ! -f "$CP_CONFIG" ] && [ -f "$CP_DIR/config.example.yaml" ]; then
        cp "$CP_DIR/config.example.yaml" "$CP_CONFIG"
        is_new=true
    fi
    [ ! -f "$CP_CONFIG" ] && return 0

    local detected_proxy=""
    if command -v get_active_proxy &>/dev/null; then
        detected_proxy=$(get_active_proxy 2>/dev/null)
    fi

    python3 - "$CP_CONFIG" "$is_new" "$detected_proxy" << 'PY_EOF' 2>/dev/null
import sys, re

cfg_path = sys.argv[1]
is_new = sys.argv[2] == "true"
proxy = sys.argv[3].strip() if len(sys.argv) > 3 else ""

with open(cfg_path, "r", encoding="utf-8") as f:
    content = f.read()

# 检查是否存在旧版写入的 remote-management 块，若存在则提取旧值并移除该废弃块
legacy_secret = ""
legacy_remote = None
m_legacy = re.search(r'(?m)^remote-management:\s*\n((?:[ \t]+.*\n?)*)', content)
if m_legacy:
    block = m_legacy.group(1)
    m_sec = re.search(r'secret-key:\s*["\']?([^"\'\n#]+)["\']?', block)
    if m_sec:
        legacy_secret = m_sec.group(1).strip()
    m_rem = re.search(r'allow-remote:\s*(true|false)', block)
    if m_rem:
        legacy_remote = m_rem.group(1).strip()
    content = content[:m_legacy.start()] + content[m_legacy.end():]

lines = content.splitlines()
in_sec = ""
changed = bool(m_legacy)

for i, line in enumerate(lines):
    s = line.strip()
    if not s or s.startswith("#"):
        continue
    indent = len(line) - len(line.lstrip())
    if indent == 0 and s.endswith(":"):
        in_sec = s[:-1].strip()
        continue

    if in_sec == "management":
        if re.match(r'^\s*allow-remote:\s*false\b', line) and (is_new or legacy_remote == "true"):
            lines[i] = re.sub(r'(allow-remote:\s*)false', r'\1true', line)
            changed = True
        elif re.match(r'^\s*secret-key:\s*""', line) and (is_new or legacy_secret):
            sec_val = legacy_secret if legacy_secret else "admin123"
            lines[i] = re.sub(r'(secret-key:\s*)""', f'\\1"{sec_val}"', line)
            changed = True
    elif in_sec == "requests" and is_new and proxy:
        if re.match(r'^\s*proxy-url:\s*""', line):
            lines[i] = re.sub(r'(proxy-url:\s*)""', f'\\1"{proxy}"', line)
            changed = True

if changed:
    with open(cfg_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
PY_EOF

    if [ "$is_new" = true ]; then
        ui_print success "配置文件 (v8) 已初始化 (默认开启远程访问，管理密钥: admin123)"
    fi
}

cliproxyapi_install() {
    _cp_vars
    ui_header "安装 / 更新 CLIProxyAPI"

    local arch
    arch=$(uname -m)
    local asset_arch="linux_amd64"
    case "$arch" in
        aarch64|arm64) asset_arch="linux_aarch64" ;;
        x86_64|amd64)  asset_arch="linux_amd64" ;;
        *)
            ui_print error "暂不支持当前的系统架构: $arch"
            ui_pause; return 1
            ;;
    esac

    ui_print info "检测到系统架构: $arch (匹配静态预编译包: ${asset_arch}_no-plugin)"
    prepare_network_strategy
    auto_load_proxy_env

    ui_print info "正在获取 CLIProxyAPI 最新发布版本..."
    local release_info=""
    # 方案 1: Python 原生发起请求
    release_info=$(python3 - "$CP_REPO" "${asset_arch}_no-plugin.tar.gz" << 'PY_EOF' 2>/dev/null
import sys, urllib.request, json, os

repo = sys.argv[1]
target_suffix = sys.argv[2]
api_url = f"https://api.github.com/repos/{repo}/releases/latest"

proxy = os.environ.get("https_proxy") or os.environ.get("http_proxy") or os.environ.get("ALL_PROXY")
opener = urllib.request.build_opener(urllib.request.ProxyHandler({'http': proxy, 'https': proxy})) if proxy else urllib.request.build_opener()
req = urllib.request.Request(api_url, headers={"User-Agent": "TAV-X/CLIProxyAPI"})
try:
    with opener.open(req, timeout=10) as resp:
        data = json.loads(resp.read().decode())
        tag = data.get("tag_name", "").strip()
        for a in data.get("assets", []):
            name = a.get("name", "")
            if name.endswith(target_suffix):
                print(f"{tag}|{a.get('browser_download_url', '')}")
                sys.exit(0)
except Exception:
    pass
sys.exit(1)
PY_EOF
)

    # 方案 2: 若 Python 请求受阻，尝试 curl 获取并解析
    if [ -z "$release_info" ]; then
        local raw_json
        raw_json=$(curl -s -m 8 "https://api.github.com/repos/${CP_REPO}/releases/latest" 2>/dev/null)
        if [ -n "$raw_json" ] && [[ "$raw_json" != *"rate limit"* ]]; then
            release_info=$(python3 - "$raw_json" "${asset_arch}_no-plugin.tar.gz" << 'PY_EOF' 2>/dev/null
import sys, json

try:
    data = json.loads(sys.argv[1])
    target_suffix = sys.argv[2]
    tag = data.get("tag_name", "").strip()
    for a in data.get("assets", []):
        name = a.get("name", "")
        if name.endswith(target_suffix):
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

    # 兜底至已知官方最新稳定版本 (v8.0.64)
    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        tag="v8.0.64"
        local ver_num="${tag#v}"
        download_url="https://github.com/${CP_REPO}/releases/download/${tag}/CLIProxyAPI_${ver_num}_${asset_arch}_no-plugin.tar.gz"
        ui_print warn "通过 API 发现失败，切换至已知最新稳定版本 (${tag})..."
    else
        ui_print success "发现最新版本: $tag"
    fi

    local tmp_archive="$TMP_DIR/cliproxyapi_${tag}_${asset_arch}.tar.gz"
    local DL_CMD="source \"$TAVX_DIR/core/net_utils.sh\"; download_file_smart '$download_url' '$tmp_archive' 'true'"

    if ! ui_stream_task "下载 CLIProxyAPI 预编译包..." "$DL_CMD"; then
        ui_print error "下载失败，请检查网络设置或代理。"
        ui_pause; return 1
    fi

    ui_print info "正在解压并部署二进制文件 (保留现有配置与凭据)..."
    local tmp_extract="$TMP_DIR/cliproxyapi_extract_$$"
    mkdir -p "$tmp_extract"
    if ! tar -xzf "$tmp_archive" -C "$tmp_extract"; then
        ui_print error "解压归档文件失败。"
        rm -rf "$tmp_extract" "$tmp_archive"
        ui_pause; return 1
    fi

    local extracted_bin
    extracted_bin=$(find "$tmp_extract" -type f -name "cli-proxy-api" | head -n 1)
    if [ -z "$extracted_bin" ] || [ ! -f "$extracted_bin" ]; then
        ui_print error "归档包中未找到 cli-proxy-api 可执行文件。"
        rm -rf "$tmp_extract" "$tmp_archive"
        ui_pause; return 1
    fi

    cp "$extracted_bin" "$CP_BIN"
    chmod +x "$CP_BIN"

    local extracted_cfg
    extracted_cfg=$(find "$tmp_extract" -type f -name "config.example.yaml" | head -n 1)
    [ -n "$extracted_cfg" ] && cp "$extracted_cfg" "$CP_DIR/config.example.yaml"

    echo "$tag" > "$CP_DIR/.version"
    rm -rf "$tmp_extract" "$tmp_archive"

    # 初始化或自愈迁移配置
    _cp_init_or_migrate_config

    ui_print success "CLIProxyAPI ($tag) 安装成功！"
}

cliproxyapi_start() {
    _cp_vars
    [ ! -x "$CP_BIN" ] && { ui_print error "程序未安装或不可执行"; return 1; }

    _cp_init_or_migrate_config

    if is_app_running "$CP_APP_ID"; then
        ui_print warn "服务已在运行中"
        return 0
    fi

    # 启动前强制清理残留
    cliproxyapi_stop

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
        # 暴力清理 Termux 下可能的卡死进程
        pkill -9 -f "cli-proxy-api" >/dev/null 2>&1
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
    if [ ! -x "$CP_BIN" ]; then
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

        local app_ver="未安装"
        if [ -f "$CP_DIR/.version" ]; then
            app_ver=$(cat "$CP_DIR/.version" 2>/dev/null | tr -d '\r\n')
        elif [ -x "$CP_BIN" ]; then
            app_ver="已就绪"
        fi
        
        local port
        port=$(_cp_get_port)
        info+=( "版本: $app_ver" )
        info+=( "监听端口: $port" )
        info+=( "管理面板: http://127.0.0.1:$port" )
        
        ui_header "CLIProxyAPI 管理面板"
        ui_status_card "$state" "$text" "${info[@]}"
        
        local CHOICE
        CHOICE=$(ui_menu "操作菜单" "🚀 启动服务" "🛑 停止服务" "⚙️  可视化配置" "📝 手动编辑" "📜 查看日志" "📥 更新/重新安装" "🗑️  卸载模块" "🧭 关于模块" "🔙 返回")
        case "$CHOICE" in
            *"启动"*) cliproxyapi_start; ui_pause ;; 
            *"停止"*) cliproxyapi_stop; ui_print success "服务已停止"; ui_pause ;; 
            *"可视化配置"*) 
                _cp_init_or_migrate_config
                node "$TAVX_DIR/modules/cliproxyapi/config.js"
                if is_app_running "$CP_APP_ID"; then
                    if ui_confirm "配置已修改，是否重启服务以生效？"; then
                        cliproxyapi_stop; sleep 1; cliproxyapi_start
                    fi
                fi
                ;;
            *"手动编辑"*)
                _cp_init_or_migrate_config
                if command -v nano &>/dev/null; then nano "$CP_CONFIG"; else vi "$CP_CONFIG"; fi
                if is_app_running "$CP_APP_ID"; then
                    if ui_confirm "配置已修改，是否重启服务以生效？"; then
                        cliproxyapi_stop; sleep 1; cliproxyapi_start
                    fi
                fi
                ;;
            *"日志"*) ui_watch_log "$CP_SVC_NAME" ;; 
            *"更新"*|*"安装"*) cliproxyapi_install; ui_pause ;;
            *"卸载"*) cliproxyapi_uninstall && [ $? -eq 2 ] && return ;; 
            *"关于"*) show_module_about_info "${BASH_SOURCE[0]}" ;; 
            *"返回"*) return ;; 
        esac
    done
}
