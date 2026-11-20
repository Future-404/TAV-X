#!/bin/bash
# [METADATA]
# MODULE_ID: geminiweb2api
# MODULE_NAME: Gemini-Web2API (Go版)
# MODULE_ENTRY: geminiweb2api_menu
# APP_CATEGORY: AI模型接口
# APP_AUTHOR: Mag1cFall
# APP_PROJECT_URL: https://github.com/Mag1cFall/Gemini-Web2API
# APP_DESC: 基于 Go 的 Google Gemini Web 代理服务，兼容 OpenAI、Claude 与 Gemini 协议，支持多账号负载均衡、访客会话、官网工具与 WebUI 管理。
# UPDATE_TYPE: github_release
# UPDATE_REPO: Mag1cFall/Gemini-Web2API
# [END_METADATA]

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"
source "$TAVX_DIR/core/net_utils.sh"

_gw_vars() {
    GW_APP_ID="geminiweb2api"
    GW_DIR=$(get_app_path "$GW_APP_ID")
    GW_BIN="$GW_DIR/gemini-web2api"
    GW_ENV="$GW_DIR/.env"
    GW_LOG="$LOGS_DIR/geminiweb2api.log"
    GW_PID="$RUN_DIR/geminiweb2api.pid"
    GW_AUTH_DIR="$GW_DIR/auth"
    GW_REPO="Mag1cFall/Gemini-Web2API"
}

_gw_env_get() {
    _gw_vars
    local key="$1"
    local default="${2:-}"

    if [ ! -f "$GW_ENV" ]; then
        echo "$default"
        return
    fi

    local line val="" found=false
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        if [[ "$line" == "${key}="* ]]; then
            val="${line#*=}"
            found=true
        fi
    done < "$GW_ENV"

    if [ "$found" = false ]; then
        echo "$default"
        return
    fi

    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    if [[ "$val" == \"*\" ]] && [ ${#val} -ge 2 ]; then
        val="${val:1:${#val}-2}"
    elif [[ "$val" == \'*\' ]] && [ ${#val} -ge 2 ]; then
        val="${val:1:${#val}-2}"
    fi

    if [ -z "$val" ]; then
        echo "$default"
    else
        echo "$val"
    fi
}

_gw_env_set() {
    _gw_vars
    local key="$1"
    local val="$2"

    mkdir -p "$GW_DIR"
    local tmp_file="$TMP_DIR/gw_env_$$.tmp"
    local updated=false
    : > "$tmp_file"

    if [ -f "$GW_ENV" ]; then
        local line
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line%$'\r'}"
            if [[ "$line" == "${key}="* ]]; then
                if [ "$updated" = false ]; then
                    printf '%s=%s\n' "$key" "$val" >> "$tmp_file"
                    updated=true
                fi
            else
                printf '%s\n' "$line" >> "$tmp_file"
            fi
        done < "$GW_ENV"
    fi

    if [ "$updated" = false ]; then
        printf '%s=%s\n' "$key" "$val" >> "$tmp_file"
    fi

    mv -f "$tmp_file" "$GW_ENV"
}

_gw_get_port() {
    local addr
    addr=$(_gw_env_get "LISTEN_ADDR" "0.0.0.0:8007")
    local port="8007"
    if [[ "$addr" == *":"* ]]; then
        port="${addr##*:}"
    fi
    echo "${port:-8007}"
}

_gw_get_auth_count() {
    _gw_vars
    local count=0
    if [ -d "$GW_AUTH_DIR" ]; then
        shopt -s nullglob
        local files=("$GW_AUTH_DIR"/*/storage-state.json "$GW_AUTH_DIR/storage-state.json")
        shopt -u nullglob
        local f
        for f in "${files[@]}"; do
            [ -f "$f" ] && count=$((count + 1))
        done
    fi
    echo "$count"
}

geminiweb2api_get_version() {
    _gw_vars
    if [ -x "$GW_BIN" ]; then
        local out ver
        out=$("$GW_BIN" version 2>/dev/null | head -n 1)
        ver=$(echo "$out" | grep -oE 'v?[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)
        [ -n "$ver" ] && echo "$ver" && return 0
    fi
    return 1
}

_gw_init_env() {
    _gw_vars
    mkdir -p "$GW_DIR" "$GW_AUTH_DIR"

    if [ ! -f "$GW_ENV" ]; then
        ui_print info "正在初始化默认运行配置 (.env)..."
        local detected_proxy=""
        if command -v get_active_proxy &>/dev/null; then
            detected_proxy=$(get_active_proxy 2>/dev/null)
        fi
        cat << EOF > "$GW_ENV"
# 认证状态文件、目录或逗号分隔的多个路径 (空目录即启用访客模式)
GEMINI_AUTH_STATES=auth

# 服务监听地址
LISTEN_ADDR=0.0.0.0:8007

# 本地 API 认证密钥 (留空即无鉴权，多个 key 用逗号分隔)
PROXY_API_KEY=

# 代理池 (多个代理用逗号分隔，支持 HTTP/HTTPS/SOCKS4/SOCKS5；留空跟随系统代理)
PROXY=${detected_proxy}

# 是否写入 Gemini 官网历史记录
GEMINI_SAVE_HISTORY=false

# 多轮对话续接上一轮所在的官网会话 (实验性)
GEMINI_CONTINUE_SESSION=false

# 非流式请求等待期间每 10 秒发送保活换行
NONSTREAM_KEEPALIVE=true

# 流式请求收齐后按流式输出
FAKE_STREAM=false

# 无会话请求调度策略: round-robin | fill-first
ROUTING_STRATEGY=round-robin
PER_ACCOUNT_CONCURRENCY=1
ACCOUNT_COOLDOWN=2m
SESSION_TTL=30m
INIT_TIMEOUT=20s

# 日志配置
LOG_LEVEL=info
LOG_FORMAT=text
REQUEST_BODY_LOG=false
LOG_FILE=true
LOG_MAX_TOTAL_MB=200

# 管理控制台登录 (关闭时管理端仅接受本机访问)
ADMIN_AUTH_ENABLED=false
ADMIN_USERNAME=admin
ADMIN_PASSWORD=
EOF
        if [ -n "$detected_proxy" ]; then
            ui_print info "💡 自动检测到本地代理并关联: $detected_proxy"
        fi
        ui_print success "配置文件 (.env) 初始化完成！"
    fi
}

_gw_parse_release_json() {
    local raw_json="$1"
    local asset_arch="$2"

    printf '%s' "$raw_json" | python3 -c '
import sys, json

arch = sys.argv[1]
try:
    data = json.load(sys.stdin)
    tag = (data.get("tag_name") or "").strip()
    for a in data.get("assets", []):
        name = a.get("name", "")
        if (
            name.startswith("gemini-web2api-")
            and "desktop" not in name.lower()
            and arch in name
            and name.endswith(".tar.gz")
        ):
            url = a.get("browser_download_url", "")
            if tag and url:
                print(f"{tag}|{url}")
                sys.exit(0)
except Exception:
    pass
sys.exit(1)
' "$asset_arch" 2>/dev/null
}

_gw_resolve_release_asset() {
    local repo="$1"
    local asset_arch="$2"
    local raw_json=""

    # 方案 1: Python 请求（自动支持当前代理，失败回退直连）
    raw_json=$(python3 - "$repo" << 'PY_EOF' 2>/dev/null
import sys, urllib.request, os

repo = sys.argv[1]
api_url = f"https://api.github.com/repos/{repo}/releases/latest"
proxy = os.environ.get("https_proxy") or os.environ.get("http_proxy") or os.environ.get("ALL_PROXY")

def fetch(url, p=None):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({'http': p, 'https': p})) if p else urllib.request.build_opener()
    req = urllib.request.Request(url, headers={"User-Agent": "TAV-X/Gemini-Web2API"})
    with opener.open(req, timeout=10) as resp:
        return resp.read().decode("utf-8", errors="replace")

data = ""
if proxy:
    try:
        data = fetch(api_url, proxy)
    except Exception:
        data = ""
if not data:
    try:
        data = fetch(api_url, None)
    except Exception:
        data = ""

if data:
    sys.stdout.write(data)
    sys.exit(0)
sys.exit(1)
PY_EOF
)

    local parsed=""
    if [ -n "$raw_json" ] && [[ "$raw_json" != *"rate limit"* ]]; then
        parsed=$(_gw_parse_release_json "$raw_json" "$asset_arch")
    fi

    # 方案 2: curl 兜底请求
    if [ -z "$parsed" ]; then
        raw_json=$(curl -s -m 8 "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null)
        [ -z "$raw_json" ] && raw_json=$(curl --noproxy "*" -s -m 8 "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null)
        if [ -n "$raw_json" ] && [[ "$raw_json" != *"rate limit"* ]]; then
            parsed=$(_gw_parse_release_json "$raw_json" "$asset_arch")
        fi
    fi

    if [ -n "$parsed" ]; then
        echo "$parsed"
        return 0
    fi
    return 1
}

_gw_deploy_release() {
    _gw_vars

    local arch
    arch=$(uname -m)
    local asset_arch=""
    case "$arch" in
        aarch64|arm64) asset_arch="linux-arm64" ;;
        x86_64|amd64)  asset_arch="linux-amd64" ;;
        *)
            ui_print error "暂不支持当前的系统架构: $arch"
            return 1
            ;;
    esac

    ui_print info "检测到系统架构: $arch (匹配 CLI 资产: $asset_arch，已自动排除桌面版)"
    prepare_network_strategy
    auto_load_proxy_env

    ui_print info "正在获取 Gemini-Web2API 最新发布版本..."
    local release_info=""
    release_info=$(_gw_resolve_release_asset "$GW_REPO" "$asset_arch")

    local tag="" download_url=""
    if [ -n "$release_info" ]; then
        tag="${release_info%%|*}"
        download_url="${release_info##*|}"
    fi

    if [ -z "$download_url" ] || [ "$download_url" == "null" ]; then
        tag="v0.2.0"
        download_url="https://github.com/${GW_REPO}/releases/download/${tag}/gemini-web2api-${tag}-${asset_arch}.tar.gz"
        ui_print warn "通过 API 发现失败，切换至已知最新稳定版本 (${tag})..."
    else
        ui_print success "发现最新版本: $tag"
    fi

    local tmp_archive="$TMP_DIR/geminiweb2api_${tag}_${asset_arch}.tar.gz"
    local tmp_extract="$TMP_DIR/geminiweb2api_extract_$$"
    safe_rm "$tmp_archive" "$tmp_extract"
    mkdir -p "$tmp_extract"

    local dl_cmd="source \"$TAVX_DIR/core/net_utils.sh\"; download_file_smart '$download_url' '$tmp_archive' 'true'"
    if ! ui_stream_task "下载 Gemini-Web2API 预编译包..." "$dl_cmd"; then
        ui_print error "下载失败，请检查网络设置或代理。"
        safe_rm "$tmp_archive" "$tmp_extract"
        return 1
    fi

    ui_print info "正在解压并部署二进制文件..."
    if ! tar -xzf "$tmp_archive" -C "$tmp_extract"; then
        ui_print error "解压归档文件失败。"
        safe_rm "$tmp_archive" "$tmp_extract"
        return 1
    fi

    local extracted_bin
    extracted_bin=$(find "$tmp_extract" -type f -name "gemini-web2api" | head -n 1)
    if [ -z "$extracted_bin" ] || [ ! -f "$extracted_bin" ]; then
        ui_print error "归档包中未找到 gemini-web2api 可执行文件。"
        safe_rm "$tmp_archive" "$tmp_extract"
        return 1
    fi

    mkdir -p "$GW_DIR" "$GW_AUTH_DIR"
    rm -f "$GW_BIN" 2>/dev/null
    cp -f "$extracted_bin" "$GW_BIN"
    chmod +x "$GW_BIN"
    echo "$tag" > "$GW_DIR/.version"
    safe_rm "$tmp_archive" "$tmp_extract"

    _gw_init_env

    if "$GW_BIN" version &>/dev/null; then
        ui_print success "程序环境测试通过！"
    else
        ui_print warn "二进制版本自检返回异常，但已成功部署至 $GW_BIN"
    fi

    return 0
}

geminiweb2api_install() {
    _gw_vars
    ui_header "安装 Gemini-Web2API (Go版)"

    if is_app_running "geminiweb2api"; then
        ui_print info "检测到服务正在运行，正在停止以替换程序文件..."
        geminiweb2api_stop
    fi

    if _gw_deploy_release; then
        ui_print success "Gemini-Web2API 安装成功！"
        ui_pause
        return 0
    fi

    ui_pause
    return 1
}

geminiweb2api_update() {
    _gw_vars
    if _gw_deploy_release; then
        return 0
    fi
    return 1
}

geminiweb2api_start() {
    _gw_vars
    if [ ! -x "$GW_BIN" ]; then
        if ui_confirm "未检测到已安装的 Gemini-Web2API，是否立即安装？"; then
            geminiweb2api_install || return 1
        else
            return 1
        fi
    fi

    ui_header "启动 Gemini-Web2API"
    _gw_init_env
    auto_load_proxy_env

    local cur_p
    cur_p=$(_gw_env_get "PROXY" "")
    if [ -z "$cur_p" ] && command -v get_active_proxy &>/dev/null; then
        local found_p
        found_p=$(get_active_proxy 2>/dev/null)
        if [ -n "$found_p" ]; then
            _gw_env_set "PROXY" "$found_p"
            ui_print info "💡 检测到本地代理，已自动配置: $found_p"
        fi
    fi

    cd "$GW_DIR" || return 1

    local port
    port=$(_gw_get_port)
    local RUN_CMD="'$GW_BIN' --open-ui=false"

    if [ "$OS_TYPE" == "TERMUX" ]; then
        if command -v termux-wake-lock &>/dev/null; then
            termux-wake-lock 2>/dev/null
        fi

        tavx_service_register "geminiweb2api" "$RUN_CMD" "$GW_DIR"
        tavx_service_control "up" "geminiweb2api"
        sleep 1.5
        if is_app_running "geminiweb2api"; then
            ui_print success "Termux 后台服务已成功运行！"
        else
            ui_print warn "服务启动指令已发出，正在后台启动..."
        fi
    else
        geminiweb2api_stop
        echo "--- Gemini-Web2API Start $(date) ---" > "$GW_LOG"
        local START_CMD="cd '$GW_DIR' && setsid nohup '$GW_BIN' --open-ui=false >> '$GW_LOG' 2>&1 </dev/null & echo \$! > '$GW_PID'"
        if ui_spinner "正在启动 Gemini-Web2API..." "eval \"$START_CMD\""; then
            sleep 1.5
            if check_process_smart "$GW_PID" "gemini-web2api"; then
                ui_print success "服务启动成功！"
            else
                ui_print error "进程未正常驻留，请检查日志: $GW_LOG"
                return 1
            fi
        fi
    fi

    local local_ip
    local_ip=$(get_local_ip)
    local accounts
    accounts=$(_gw_get_auth_count)

    ui_print success "Gemini-Web2API 服务正在运行中！"
    echo -e "  🌐 本机控制台: \033[1;36mhttp://127.0.0.1:${port}\033[0m"
    echo -e "  📡 局域网 API: \033[1;36mhttp://${local_ip}:${port}/v1\033[0m"
    if [ "$accounts" -eq 0 ]; then
        echo -e "  💡 账号状态  : \033[1;33m未导入账号，已自动启用访客会话模式 (支持基础免费模型)\033[0m"
    else
        echo -e "  👤 已加载账号: \033[1;32m${accounts} 个\033[0m"
    fi
    return 0
}

geminiweb2api_stop() {
    _gw_vars
    ui_print info "正在停止 Gemini-Web2API..."

    if [ "$OS_TYPE" == "TERMUX" ] && command -v sv &>/dev/null; then
        [ -d "$PREFIX/var/service/geminiweb2api" ] && tavx_service_control "down" "geminiweb2api"
    fi

    if [ -f "$GW_PID" ]; then
        kill_process_safe "$GW_PID" "gemini-web2api"
    fi
    pkill -f "$GW_BIN" 2>/dev/null || true
    sleep 0.5
    ui_print success "已停止。"
}

geminiweb2api_restart() {
    geminiweb2api_stop
    sleep 1
    geminiweb2api_start
}

geminiweb2api_uninstall() {
    _gw_vars
    ui_header "卸载 Gemini-Web2API"
    echo -e "${YELLOW}注意：卸载将删除程序二进制、.env 配置、已导入账号及 SQLite 账本数据。${NC}"
    echo ""

    if verify_kill_switch; then
        geminiweb2api_stop
        if [ "$OS_TYPE" == "TERMUX" ]; then
            tavx_service_remove "geminiweb2api"
        fi
        safe_rm "$GW_DIR" "$GW_LOG" "$GW_PID"
        ui_print success "Gemini-Web2API 已彻底卸载。"
        ui_pause
        return 2
    fi
    return 1
}

geminiweb2api_open_webui() {
    _gw_vars
    local port
    port=$(_gw_get_port)
    local url="http://127.0.0.1:${port}"

    if ! is_app_running "geminiweb2api"; then
        ui_print warn "服务尚未启动，正在先为您启动服务..."
        geminiweb2api_start || { ui_pause; return 1; }
    fi

    ui_print info "正在打开 Web 控制台: $url"
    if command -v termux-open-url &>/dev/null; then
        termux-open-url "$url"
    elif command -v xdg-open &>/dev/null && { [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; }; then
        xdg-open "$url" >/dev/null 2>&1
    else
        open_browser "$url"
    fi
    ui_pause
}

_gw_normalize_cookie_file() {
    local src_file="$1"
    local dst_file="$2"

    python3 - "$src_file" "$dst_file" << 'PY_EOF'
import json, re, sys

src_path, dst_path = sys.argv[1], sys.argv[2]

try:
    with open(src_path, "r", encoding="utf-8", errors="replace") as f:
        raw = f.read()
except Exception as e:
    sys.stderr.write(f"读取 Cookie 内容失败: {e}\n")
    sys.exit(2)

text = raw.lstrip("\ufeff").strip()
if not text:
    sys.stderr.write("Cookie 内容为空。\n")
    sys.exit(3)

required = {"SAPISID", "__Secure-1PSID"}

if text.startswith("{") or text.startswith("["):
    try:
        data = json.loads(text)
    except Exception as e:
        sys.stderr.write(f"Cookie JSON 解析失败: {e}\n")
        sys.exit(4)

    if isinstance(data, dict):
        items = data.get("cookies", [])
    elif isinstance(data, list):
        items = data
    else:
        items = []

    if not isinstance(items, list) or not items:
        sys.stderr.write("JSON 中未包含有效的 cookies 数组。\n")
        sys.exit(4)

    names = {
        c.get("name", "").strip()
        for c in items
        if isinstance(c, dict) and c.get("name") and c.get("value")
    }
    missing = [k for k in ("SAPISID", "__Secure-1PSID") if k not in names]
    if missing:
        sys.stderr.write(
            f"⚠️ Cookie 缺少核心字段 ({', '.join(missing)})。请确认已在 gemini.google.com 登录后导出。\n"
        )
        sys.exit(5)

    with open(dst_path, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"已验证 JSON 格式 Cookie (共 {len(items)} 条)")
    sys.exit(0)

if "\t" in text:
    names = set()
    valid_lines = 0
    for line in text.replace("\r\n", "\n").split("\n"):
        s = line.strip()
        if not s:
            continue
        if s.startswith("#HttpOnly_"):
            s = s[len("#HttpOnly_"):]
        elif s.startswith("#"):
            continue
        fields = s.split("\t")
        if len(fields) == 7 and fields[5].strip() and fields[6].strip():
            names.add(fields[5].strip())
            valid_lines += 1

    if valid_lines == 0:
        sys.stderr.write("Netscape cookies.txt 未包含有效 Cookie 行。\n")
        sys.exit(4)

    missing = [k for k in ("SAPISID", "__Secure-1PSID") if k not in names]
    if missing:
        sys.stderr.write(
            f"⚠️ cookies.txt 缺少核心字段 ({', '.join(missing)})。请确认已在 gemini.google.com 登录后导出。\n"
        )
        sys.exit(5)

    with open(dst_path, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"已验证 Netscape 格式 Cookie (共 {valid_lines} 条)")
    sys.exit(0)

header = text
if header.lower().startswith("cookie:"):
    header = header[7:].strip()

pairs = []
seen = set()
for token in re.split(r'[;\r\n]+', header):
    token = token.strip()
    if not token or "=" not in token:
        continue
    name, value = token.split("=", 1)
    name = name.strip()
    value = value.strip()
    if not name or not value:
        continue
    if name in seen:
        continue
    seen.add(name)
    pairs.append((name, value))

if not pairs:
    sys.stderr.write("未解析到任何有效的 key=value Cookie 项。\n")
    sys.exit(4)

names = {n for n, _ in pairs}
missing = [k for k in ("SAPISID", "__Secure-1PSID") if k not in names]
if missing:
    sys.stderr.write(
        f"⚠️ Cookie Header 缺少核心字段 ({', '.join(missing)})。请确认已在 gemini.google.com 登录后导出。\n"
    )
    sys.exit(5)

normalized_header = "; ".join(f"{n}={v}" for n, v in pairs)
with open(dst_path, "w", encoding="utf-8") as f:
    f.write(normalized_header)
print(f"已规范化为单行 Cookie Header (共 {len(pairs)} 项)")
PY_EOF
}

_gw_process_and_import() {
    _gw_vars
    local input_data="$1"
    local is_file="$2"

    if [ ! -x "$GW_BIN" ]; then
        ui_print error "程序未安装，请先执行安装。"
        return 1
    fi

    local src_file=""
    if [ "$is_file" = "true" ]; then
        if [ ! -f "$input_data" ]; then
            ui_print error "未找到凭据文件: $input_data"
            return 1
        fi
        src_file="$input_data"
    else
        src_file="$TMP_DIR/gw_raw_cookie_$$.txt"
        printf "%s\n" "$input_data" > "$src_file"
    fi

    local normalized_file="$TMP_DIR/gw_norm_cookie_$$.txt"
    ui_print info "正在校验与规范化 Cookie 数据..."
    if ! _gw_normalize_cookie_file "$src_file" "$normalized_file"; then
        [ "$is_file" != "true" ] && rm -f "$src_file" 2>/dev/null
        rm -f "$normalized_file" 2>/dev/null
        return 1
    fi
    [ "$is_file" != "true" ] && rm -f "$src_file" 2>/dev/null

    local next_idx
    next_idx=$(( $(_gw_get_auth_count) + 1 ))
    local default_id="account${next_idx}"

    local account_id
    account_id=$(ui_input "请输入账号标识 ID (仅限字母/数字/_/-，如 main 或 acc1)" "$default_id" false)
    if [ -z "$account_id" ]; then
        ui_print warn "已取消操作。"
        rm -f "$normalized_file" 2>/dev/null
        return 1
    fi
    if [[ ! "$account_id" =~ ^[a-zA-Z0-9._-]+$ ]] || [[ ! "$account_id" =~ [a-zA-Z0-9] ]] || [[ "$account_id" == *".."* ]]; then
        ui_print error "账号 ID 格式无效，必须包含英文字母或数字，且仅可使用字母/数字/./_/-。"
        rm -f "$normalized_file" 2>/dev/null
        return 1
    fi

    local auth_user
    auth_user=$(ui_input "多账号序号 --authuser (gemini.google.com/u/N/app 中的 N，默认 0)" "0" false)
    auth_user="${auth_user:-0}"
    if [[ ! "$auth_user" =~ ^[0-9]+$ ]]; then
        ui_print error "authuser 必须为非负整数 (例如 0、1、2)。"
        rm -f "$normalized_file" 2>/dev/null
        return 1
    fi

    _gw_init_env
    auto_load_proxy_env

    local was_running=false
    if is_app_running "geminiweb2api"; then
        was_running=true
        ui_print info "检测到服务正在运行，临时停止以解除 auth 目录锁..."
        geminiweb2api_stop
    fi

    if [ "$OS_TYPE" == "TERMUX" ]; then
        export SSL_CERT_FILE="$PREFIX/etc/tls/cert.pem"
        export SSL_CERT_DIR="$PREFIX/etc/tls"
    fi

    ui_print info "正在执行 gemini-web2api setup 验证并写入账号 [$account_id]..."
    local import_ok=false
    if (cd "$GW_DIR" && "$GW_BIN" setup --cookie-file "$normalized_file" --id "$account_id" --authuser "$auth_user"); then
        import_ok=true
        ui_print success "🎉 账号 [$account_id] 导入并验证成功！"
    else
        ui_print error "账号导入失败，请检查 Cookie 有效性及网络/代理连通性。"
    fi

    rm -f "$normalized_file" 2>/dev/null

    if [ "$was_running" = true ]; then
        ui_print info "正在恢复后台服务..."
        geminiweb2api_start
    fi

    [ "$import_ok" = true ] && return 0 || return 1
}

geminiweb2api_import_from_paste() {
    ui_header "📋 粘贴 Cookie 凭据导入"

    local clip_content=""
    if command -v termux-clipboard-get >/dev/null 2>&1; then
        clip_content=$(termux-clipboard-get 2>/dev/null)
        if [[ "$clip_content" =~ ^[[:space:]]*(\[|\{) ]] || [[ "$clip_content" == *"SAPISID"* && "$clip_content" == *"__Secure-1PSID"* ]]; then
            ui_print info "💡 检测到系统剪贴板中含有 Gemini Cookie 数据！"
            if ui_confirm "是否直接使用剪贴板中的内容导入？"; then
                _gw_process_and_import "$clip_content" false
                ui_pause
                return
            fi
        fi
    fi

    echo -e "说明："
    echo -e "  • 支持 \033[1;33mCookie Tool\033[0m / \033[1;33mCookie-Editor\033[0m 导出的任意格式："
    echo -e "    - Cookie 纯文本字符串 (key=value; ...，支持自动折叠多行)"
    echo -e "    - JSON 数组或 Playwright StorageState"
    echo -e "    - Netscape cookies.txt 格式"
    echo -e "  • 在下方输入框内\033[1;36m长按屏幕空白处\033[0m选择【粘贴】"
    echo -e "  • 粘贴完成后按 \033[1;32mCtrl+D\033[0m 提交，按 \033[1;31mEsc\033[0m 取消\n"

    local raw_paste=""
    if [ "$HAS_GUM" = true ]; then
        raw_paste=$("$GUM_BIN" write \
            --header="📋 Cookie 凭据输入框 (粘贴后按 Ctrl+D 提交，按 Esc 取消)：" \
            --placeholder="在此处粘贴 Cookie 文本、JSON 或 cookies.txt 内容..." \
            --width=0 \
            --height=10 \
            --show-line-numbers \
            --cursor.mode="blink")
        local ret=$?
        if [ $ret -ne 0 ] || [ -z "$raw_paste" ]; then
            ui_print warn "已取消操作或未输入有效内容。"
            ui_pause
            return
        fi
    else
        local paste_script="$TMP_DIR/gw_read_paste_$$.py"
        cat << 'EOF_PY' > "$paste_script"
import sys

sys.stderr.write("  \033[1;36m➜\033[0m 请粘贴 Cookie 内容：\n")
sys.stderr.write("    (粘贴完成后，请在新起一行输入 END 并按回车结束，输入 q 取消)\n\n")

try:
    with open("/dev/tty", "r") as tty:
        lines = []
        while True:
            line = tty.readline()
            if not line:
                break
            s = line.strip()
            if s in ["END", "exit", "q"]:
                if s != "END" and not lines:
                    sys.exit(1)
                break
            lines.append(line)
        raw = "".join(lines).strip()
        if raw:
            sys.stdout.write(raw)
        else:
            sys.exit(1)
except Exception:
    sys.exit(1)
EOF_PY
        raw_paste=$(python3 "$paste_script")
        local ret=$?
        rm -f "$paste_script" 2>/dev/null
        if [ $ret -ne 0 ] || [ -z "$raw_paste" ]; then
            ui_print warn "已取消操作或未输入有效内容。"
            ui_pause
            return
        fi
    fi

    _gw_process_and_import "$raw_paste" false
    ui_pause
}

geminiweb2api_import_from_file() {
    ui_header "📁 从文件导入 Gemini Cookie 凭据"

    ensure_storage_permission

    local default_file=""
    local candidates=()
    local search_dir
    for search_dir in "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/storage/downloads" "$HOME/downloads" "$TMP_DIR"; do
        if [ -d "$search_dir" ]; then
            while IFS= read -r f; do
                [ -n "$f" ] && candidates+=("$f")
            done < <(find "$search_dir" -maxdepth 2 -type f \( -name "*.json" -o -name "*.txt" \) 2>/dev/null | xargs -r ls -t 2>/dev/null | head -n 3)
        fi
        [ ${#candidates[@]} -gt 0 ] && break
    done

    if [ ${#candidates[@]} -gt 0 ]; then
        default_file="${candidates[0]}"
        ui_print info "💡 自动检测到最近的文件："
        echo -e "   \033[1;36m$default_file\033[0m\n"
    fi

    echo -e "说明："
    echo -e "  • 支持 \033[1;33mCookie Tool / Cookie-Editor\033[0m 导出的 .json 文件"
    echo -e "  • 支持 \033[1;33mNetscape cookies.txt\033[0m 或保存了 Cookie Header 的 .txt 文件\n"

    local cookie_file
    cookie_file=$(ui_input "请输入凭据文件路径 (直接回车使用检测到的文件)" "$default_file" false)
    if [ -z "$cookie_file" ]; then
        ui_print warn "已取消操作。"
        ui_pause
        return
    fi

    if [ ! -f "$cookie_file" ]; then
        ui_print error "未找到文件: $cookie_file"
        ui_pause
        return 1
    fi

    _gw_process_and_import "$cookie_file" true
    ui_pause
}

geminiweb2api_import_auth() {
    _gw_vars
    if [ ! -x "$GW_BIN" ]; then
        ui_print error "程序未安装，请先执行安装。"
        ui_pause
        return 1
    fi

    local choice
    choice=$(ui_menu "请选择账号凭据导入方式" \
        "📋 直接粘贴 Cookie 内容 (支持 Cookie Tool 文本 / JSON / Netscape)" \
        "📁 从文件导入 (自动扫描手机 Download 目录 .json / .txt)" \
        "🌐 在 Web 控制台热导入 (免停服，支持多账号识别与电脑远程配对)" \
        "🔙 返回上一级")

    case "$choice" in
        *"直接粘贴"*)
            geminiweb2api_import_from_paste
            ;;
        *"从文件导入"*)
            geminiweb2api_import_from_file
            ;;
        *"Web 控制台"*)
            geminiweb2api_open_webui
            ;;
        *)
            return 0
            ;;
    esac
}

geminiweb2api_show_tutorial() {
    ui_header "如何获取 Gemini Web 账号凭据"

    local md_content="
# 📚 Google Gemini Web 凭据获取指南

Gemini-Web2API 不导入账号也可直接使用**访客会话模式**体验免费基础模型；
导入个人 Google 账号后可解锁完整模型目录、图片/视频生成、Deep Research、Canvas 与多账号负载均衡。

---

## 💻 方案一：电脑 Chrome 远程配对 (推荐，支持自动续签)

1. 在本菜单启动服务后，打开 **「🌐 打开 Web 控制台」**；
2. 进入管理端的 **「导入账号」** 页面，生成配对令牌并复制远程配对命令；
3. 在已登录 Chrome 的电脑上执行命令，即可把账号无线推送到手机并自动保持会话续签。

---

## 📱 方案二：手机单机导出 Cookie 导入

1. 在手机安装支持扩展的浏览器（推荐 **Kiwi Browser** 或 **狐猴浏览器**）；
2. 安装 **Cookie Tool**（推荐，一键复制）或 **Cookie-Editor** 扩展；
3. 登录 [gemini.google.com](https://gemini.google.com) 后，点击扩展复制当前站点全部 Cookie；
4. 返回本菜单选择 **「📥 导入账号凭据」**，粘贴或选择导出的文件即可。

> 💡 **多账号提醒**：若同一浏览器登录了多个 Google 账号，查看地址栏 \`gemini.google.com/u/N/app\` 中的数字 \`N\`，在导入时填入对应 \`authuser\` 序号（默认 \`0\`）。
"

    if [ "$HAS_GUM" = true ]; then
        echo "$md_content" | gum format
    else
        echo -e "${YELLOW}Gemini Web 凭据获取指南${NC}"
        echo -e "【访客模式】不导入账号也可直接启动服务，使用基础免费模型"
        echo -e "【电脑远程】启动服务 -> Web控制台「导入账号」生成配对令牌 -> 电脑执行命令推送（支持自动续签）"
        echo -e "【手机导出】Kiwi/狐猴浏览器登录 gemini.google.com -> Cookie Tool 复制 -> 本菜单「导入账号凭据」"
    fi
    ui_pause
}

geminiweb2api_config_menu() {
    _gw_vars
    _gw_init_env

    while true; do
        ui_header "⚙️ Gemini-Web2API 参数配置"
        local port cur_key cur_proxy cur_hist cur_strat cur_admin_auth
        port=$(_gw_get_port)
        cur_key=$(_gw_env_get "PROXY_API_KEY" "")
        cur_proxy=$(_gw_env_get "PROXY" "")
        cur_hist=$(_gw_env_get "GEMINI_SAVE_HISTORY" "false")
        cur_strat=$(_gw_env_get "ROUTING_STRATEGY" "round-robin")
        cur_admin_auth=$(_gw_env_get "ADMIN_AUTH_ENABLED" "false")

        echo -e "当前配置概要："
        echo -e "  • 监听端口     : \033[1;36m${port}\033[0m"
        echo -e "  • API 密钥     : \033[1;33m${cur_key:-<无鉴权 (公开)>}\033[0m"
        echo -e "  • 上游代理池   : \033[1;35m${cur_proxy:-<跟随系统/直连>}\033[0m"
        echo -e "  • 保存官网历史 : \033[1;32m${cur_hist}\033[0m"
        echo -e "  • 调度策略     : \033[1;34m${cur_strat}\033[0m"
        echo -e "  • 管理远程登录 : \033[1;36m${cur_admin_auth}\033[0m\n"

        local CHOICE
        CHOICE=$(ui_menu "请选择要修改的项" \
            "🔌 修改监听端口" \
            "🔑 设置 / 修改 API 认证密钥" \
            "🌐 配置上游代理 / 代理池" \
            "📜 切换保存官网历史 (GEMINI_SAVE_HISTORY)" \
            "⚖️  切换账号调度策略 (round-robin / fill-first)" \
            "🔐 配置管理端远程登录 (ADMIN_AUTH)" \
            "📝 手动编辑完整 .env 文件" \
            "🔙 返回上一级")

        case "$CHOICE" in
            *"监听端口"*)
                local new_port
                new_port=$(ui_input "请输入新的服务端口 (1024-65535)" "$port" false)
                if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -ge 1024 ] && [ "$new_port" -le 65535 ]; then
                    _gw_env_set "LISTEN_ADDR" "0.0.0.0:${new_port}"
                    ui_print success "端口已修改为: $new_port (重启服务后生效)"
                else
                    ui_print error "端口输入无效。"
                fi
                ui_pause
                ;;
            *"API 认证密钥"*)
                local new_key
                new_key=$(ui_input "请输入 API 密钥 (多个逗号分隔，留空关闭鉴权)" "$cur_key" false)
                _gw_env_set "PROXY_API_KEY" "$new_key"
                ui_print success "API 密钥已更新 (重启服务后生效)"
                ui_pause
                ;;
            *"代理"*)
                local new_p
                new_p=$(ui_input "请输入代理或代理池 (逗号分隔，如 http://127.0.0.1:7890，留空清除)" "$cur_proxy" false)
                _gw_env_set "PROXY" "$new_p"
                ui_print success "代理设置已更新 (重启服务后生效)"
                ui_pause
                ;;
            *"官网历史"*)
                local next_hist="true"
                [ "$cur_hist" == "true" ] && next_hist="false"
                _gw_env_set "GEMINI_SAVE_HISTORY" "$next_hist"
                ui_print success "GEMINI_SAVE_HISTORY 已切换为: $next_hist (重启服务后生效)"
                ui_pause
                ;;
            *"调度策略"*)
                local sel_strat
                sel_strat=$(ui_menu "请选择多账号调度策略" \
                    "🔄 round-robin (轮询分配，均衡消耗额度)" \
                    "📌 fill-first (优先使用排在前面的空闲账号)")
                if [[ "$sel_strat" == *"round-robin"* ]]; then
                    _gw_env_set "ROUTING_STRATEGY" "round-robin"
                    ui_print success "调度策略已设为 round-robin (重启服务后生效)"
                elif [[ "$sel_strat" == *"fill-first"* ]]; then
                    _gw_env_set "ROUTING_STRATEGY" "fill-first"
                    ui_print success "调度策略已设为 fill-first (重启服务后生效)"
                fi
                ui_pause
                ;;
            *"远程登录"*)
                local sel_auth
                sel_auth=$(ui_menu "管理控制台访问控制" \
                    "🔒 开启登录验证 (允许局域网/远程访问管理端，需密码)" \
                    "🏠 关闭登录验证 (免密登录，仅限本机 127.0.0.1 访问)")
                if [[ "$sel_auth" == *"开启"* ]]; then
                    local cur_user new_user new_pass
                    cur_user=$(_gw_env_get "ADMIN_USERNAME" "admin")
                    new_user=$(ui_input "管理员用户名" "${cur_user:-admin}" false)
                    new_pass=$(ui_input "管理员密码 (不能为空)" "" true)
                    if [ -z "$new_pass" ]; then
                        ui_print error "密码不能为空，已取消开启管理端登录。"
                    else
                        _gw_env_set "ADMIN_USERNAME" "${new_user:-admin}"
                        _gw_env_set "ADMIN_PASSWORD" "$new_pass"
                        _gw_env_set "ADMIN_AUTH_ENABLED" "true"
                        ui_print success "已开启管理端登录验证 (重启服务后生效)"
                    fi
                elif [[ "$sel_auth" == *"关闭"* ]]; then
                    _gw_env_set "ADMIN_AUTH_ENABLED" "false"
                    ui_print success "已关闭管理端登录验证 (仅限本机访问，重启服务后生效)"
                fi
                ui_pause
                ;;
            *"手动编辑"*)
                if command -v nano &>/dev/null; then
                    nano "$GW_ENV"
                else
                    vi "$GW_ENV"
                fi
                ;;
            *"返回"*|"")
                return
                ;;
        esac
    done
}

geminiweb2api_menu() {
    _gw_vars

    while true; do
        local state="stopped"
        local state_text="已停止"
        local info=()

        if is_app_running "geminiweb2api"; then
            state="running"
            state_text="运行中"
        fi

        local port local_ip accounts cur_proxy app_ver="未安装"
        port=$(_gw_get_port)
        local_ip=$(get_local_ip)
        accounts=$(_gw_get_auth_count)
        cur_proxy=$(_gw_env_get "PROXY" "")

        if [ -f "$GW_DIR/.version" ]; then
            app_ver=$(cat "$GW_DIR/.version" 2>/dev/null | tr -d '\r\n')
        elif [ -x "$GW_BIN" ]; then
            app_ver=$(geminiweb2api_get_version 2>/dev/null || echo "已就绪")
        fi

        info+=("版本: ${app_ver}")
        info+=("端口: $port")
        info+=("控制台: http://127.0.0.1:$port")
        info+=("局域网: http://${local_ip}:$port/v1")
        if [ "$accounts" -eq 0 ]; then
            info+=("已导入账号: 0 个 (访客模式可用)")
        else
            info+=("已导入账号: ${accounts} 个")
        fi
        info+=("出口代理: ${cur_proxy:-跟随系统/直连}")
        info+=("提示: 网页端在线更新可能因进程占用失败，推荐在此处更新")

        ui_header "Gemini-Web2API (Go版) 管理面板"
        ui_status_card "$state" "$state_text" "${info[@]}"

        local CHOICE
        CHOICE=$(ui_menu "操作菜单" \
            "🚀 启动服务" \
            "🛑 停止服务" \
            "🔄 重启服务" \
            "🌐 打开 Web 控制台" \
            "📥 导入账号凭据" \
            "📚 获取凭据教程" \
            "⚙️  参数配置" \
            "📜 查看实时日志" \
            "🔄 检查与更新版本" \
            "⬇️  重新部署/修复安装" \
            "🗑️  卸载模块" \
            "🧭 关于模块" \
            "🔙 返回主菜单")

        case "$CHOICE" in
            *"启动服务"*)
                geminiweb2api_start
                ui_pause
                ;;
            *"停止服务"*)
                geminiweb2api_stop
                ui_print success "服务已停止。"
                ui_pause
                ;;
            *"重启服务"*)
                geminiweb2api_restart
                ui_pause
                ;;
            *"打开 Web"*|*"控制台"*)
                geminiweb2api_open_webui
                ;;
            *"导入账号"*)
                geminiweb2api_import_auth
                ;;
            *"获取凭据教程"*|*"教程"*)
                geminiweb2api_show_tutorial
                ;;
            *"参数配置"*)
                geminiweb2api_config_menu
                ;;
            *"实时日志"*)
                ui_watch_log "geminiweb2api"
                ;;
            *"检查与更新版本"*)
                if command -v module_perform_update &>/dev/null; then
                    module_perform_update "geminiweb2api"
                else
                    geminiweb2api_update
                    ui_pause
                fi
                ;;
            *"重新部署"*|*"重新安装"*)
                geminiweb2api_install
                ;;
            *"卸载模块"*)
                geminiweb2api_uninstall
                [ $? -eq 2 ] && return
                ;;
            *"关于模块"*)
                show_module_about_info "${BASH_SOURCE[0]}"
                ;;
            *"返回"*|"")
                return
                ;;
        esac
    done
}
