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

aistudio2api_show_tutorial() {
    ui_header "如何获取 AI Studio 账号凭据"

    local md_content="
# 📚 Google AI Studio 凭据获取指南

AIStudio2API 需要 Google AI Studio 的账号凭据以发起免 Key 调用。
凭据是通用的，可以在电脑上提取后推送至手机，也可直接在单台手机上完成。

---

## 💻 方案一：电脑 Chrome 远程配对 (推荐有电脑的用户)

如果您身边有电脑，推荐使用官方内建的“远程配对”：

1. 在本管理菜单启动服务后，选择「🌐 打开 Web 控制台」；
2. 在浏览器打开控制台的“账户”页，点击右上角「远程添加」，复制配对命令；
3. 在电脑终端中直接运行该命令，电脑里 Chrome 登录的账号就会自动无线推送到手机！

---

## 📱 方案二：安卓手机单机获取 (纯手机首选)

如果您身边没有电脑，只需在手机上使用支持扩展的浏览器即可搞定：

### 1. 准备手机浏览器
在手机上安装支持扩展的 Chromium 浏览器，推荐：
* **Kiwi Browser（猕猴桃浏览器）** (推荐，纯净轻量)
* **狐猴浏览器 (Lemur Browser)**

### 2. 安装 Cookie 导出插件
打开浏览器，进入扩展商店搜索并安装 **Cookie-Editor** 插件。

### 3. 提取凭据并导出
1. 在该浏览器中登录 [aistudio.google.com](https://aistudio.google.com)；
2. 登录成功后，点击浏览器右上角菜单 ➔ 点击 **Cookie-Editor** 图标；
3. 点击底部的 **Export** ➔ 选择 **Export as JSON**；
   *(此时凭据已复制到剪贴板，部分浏览器可能同时提示下载为 .json 文件)*。

---

## 📥 导入到本系统

拿到凭据后，返回本管理菜单，选择 **「📥 导入账号凭据」**：

* **方式 A【直接粘贴】(最便捷)**：选择「直接粘贴 JSON 内容」，长按屏幕粘贴，系统会自动识别并一秒导入！
* **方式 B【文件导入】**：若保存为 `.json` 文件，系统会**自动扫描 Download 目录**，直接按回车即可导入！
* 系统已内置**智能转码器**与**防呆校验**，自动清洗 Cookie 字段并核实 Google 登录态。

---

> 💡 **安卓存储权限说明 (针对文件导入)**：
> Termux 首次读取手机下载目录时系统会弹出存储授权弹窗，请点击【允许】；若曾拒绝授权，可在手机【系统设置 ➔ 应用管理 ➔ Termux ➔ 权限】中开启存储访问权限。
"

    if [ "$HAS_GUM" = true ]; then
        echo "$md_content" | gum format
    else
        echo -e "${YELLOW}AI Studio 凭据获取指南${NC}"
        echo -e "【电脑端】启动服务 -> Web控制台点击'远程添加' -> 电脑端运行配对命令"
        echo -e "【手机端】Kiwi 浏览器登录 aistudio.google.com -> Cookie-Editor 导出 -> 直接粘贴或文件导入"
        echo -e "【权限提示】若使用文件导入请确保已授予 Termux 手机存储权限 (termux-setup-storage)"
    fi
    ui_pause
}

_aistudio2api_process_and_import() {
    local input_data="$1"
    local is_file="$2"
    local target_file=""

    if [ "$is_file" = "true" ]; then
        if [ ! -f "$input_data" ]; then
            ui_print error "未找到凭据文件: $input_data"
            return 1
        fi
        target_file="$input_data"
    else
        target_file="$TMP_DIR/aistudio_raw_auth_$$.json"
        printf "%s\n" "$input_data" > "$target_file"
    fi

    ui_print info "正在分析并转码凭据格式..."
    local converted_file="$TMP_DIR/aistudio_auth_converted_$$.json"

    python3 - "$target_file" "$converted_file" << 'PY_EOF'
import json, sys, re

src_path = sys.argv[1]
dst_path = sys.argv[2]

try:
    with open(src_path, "r", encoding="utf-8") as f:
        raw_text = f.read().strip()
except Exception as e:
    sys.stderr.write(f"读取凭据数据失败: {e}\n")
    sys.exit(2)

cookies = []
origins = []
parsed_ok = False

# 1. 优先尝试解析为 JSON (Cookie-Editor 数组 或 Playwright 字典)
if (raw_text.startswith("{") and raw_text.endswith("}")) or (raw_text.startswith("[") and raw_text.endswith("]")):
    try:
        raw_json = json.loads(raw_text)
        if isinstance(raw_json, dict) and "cookies" in raw_json:
            cookies = raw_json.get("cookies", [])
            origins = raw_json.get("origins", [])
            parsed_ok = True
        elif isinstance(raw_json, list):
            for c in raw_json:
                if not isinstance(c, dict):
                    continue
                s_raw = str(c.get("sameSite") or "").strip().lower()
                if s_raw == "lax":
                    s_site = "Lax"
                elif s_raw == "strict":
                    s_site = "Strict"
                else:
                    s_site = "None"

                exp = c.get("expirationDate") or c.get("expires")
                try:
                    expires = float(exp) if exp is not None else -1.0
                except (ValueError, TypeError):
                    expires = -1.0

                cookies.append({
                    "name": c.get("name", ""),
                    "value": c.get("value", ""),
                    "domain": c.get("domain", ".google.com"),
                    "path": c.get("path", "/"),
                    "expires": expires,
                    "httpOnly": bool(c.get("httpOnly", False)),
                    "secure": bool(c.get("secure", True)),
                    "sameSite": s_site
                })
            parsed_ok = True
    except Exception:
        parsed_ok = False

# 2. 若非 JSON 或 JSON 解析失败，尝试自适应解析为 Cookie Header 纯文本 (name=value; name2=value2...)
if not parsed_ok:
    header_text = raw_text
    if header_text.lower().startswith("cookie:"):
        header_text = header_text[7:].strip()

    tokens = re.split(r'[;\n\r]+', header_text)
    for token in tokens:
        token = token.strip()
        if not token or "=" not in token:
            continue
        name, value = token.split("=", 1)
        name = name.strip()
        value = value.strip()
        if not name or not value:
            continue

        is_sec = True if (name.startswith("__Secure-") or "sapisid" in name.lower()) else False
        is_httponly = True if name in ["SID", "HSID", "SSID", "__Secure-1PSID", "__Secure-3PSID"] else False
        cookies.append({
            "name": name,
            "value": value,
            "domain": ".google.com",
            "path": "/",
            "expires": -1.0,
            "httpOnly": is_httponly,
            "secure": is_sec,
            "sameSite": "None" if is_sec else "Lax"
        })
    if cookies:
        parsed_ok = True

if not cookies:
    sys.stderr.write("未解析到任何有效 Cookie 条目。支持 JSON 格式以及 'key=value;' 纯文本格式\n")
    sys.exit(3)

# 校验 Google 登录凭据核心标识
google_keys = {"SAPISID", "__Secure-1PAPISID", "__Secure-3PAPISID", "SID", "SSID", "HSID"}
found = [c["name"] for c in cookies if c.get("name") in google_keys]
if not found:
    sys.stderr.write("⚠️ 未在 Cookie 中检测到 Google 登录态标识 (SAPISID/SID 等)。请确认您是在 aistudio.google.com 登录完成后导出的！\n")
    sys.exit(4)

out = {"cookies": cookies, "origins": origins}
with open(dst_path, "w", encoding="utf-8") as f:
    json.dump(out, f, indent=2, ensure_ascii=False)

print(f"有效凭据解析成功 (共 {len(cookies)} 个 Cookie，已确认登录标识: {', '.join(set(found))})")
PY_EOF

    local py_res=$?
    [ "$is_file" != "true" ] && rm -f "$target_file" 2>/dev/null

    if [ $py_res -ne 0 ]; then
        ui_print error "凭据解析或格式校验未通过，请检查内容是否正确。"
        rm -f "$converted_file" 2>/dev/null
        return 1
    fi

    ui_print success "凭据自适应转码校验通过！"
    ui_print info "正在通过 aistudio2api 导入并签署状态凭据..."
    cd "$AS_DIR" || return 1
    if "$AS_BIN" setup --storage-state "$converted_file"; then
        ui_print success "🎉 账号凭据导入并验证成功！"
        if is_app_running "aistudio2api"; then
            ui_print info "正在重启服务以使新账号生效..."
            aistudio2api_restart
        fi
    else
        ui_print error "凭据导入签署失败，请确认导出的 Cookie 包含 Google AI Studio 完整登录态。"
    fi
    rm -f "$converted_file" 2>/dev/null
    return 0
}

aistudio2api_import_from_paste() {
    ui_header "📋 粘贴 Cookie 凭据导入"

    # 如果安装了 termux-api，尝试自动检测剪贴板
    local clip_content=""
    if command -v termux-clipboard-get >/dev/null 2>&1; then
        clip_content=$(termux-clipboard-get 2>/dev/null)
        if [[ "$clip_content" =~ ^[[:space:]]*(\[|\{) ]] || [[ "$clip_content" =~ (SAPISID|__Secure-1PAPISID|SID)= ]]; then
            ui_print info "💡 检测到系统剪贴板中含有 Cookie 凭据数据！"
            if ui_confirm "是否直接使用剪贴板中的内容导入？"; then
                _aistudio2api_process_and_import "$clip_content" false
                ui_pause; return
            fi
        fi
    fi

    echo -e "说明："
    echo -e "  • 支持 Kiwi / 狐猴浏览器中 \033[1;33mCookie-Editor\033[0m 导出的任意格式："
    echo -e "    - \033[1;36mExport as JSON\033[0m (JSON 数组)"
    echo -e "    - \033[1;36mExport as Header String\033[0m (如 name=value; name2=value...)"
    echo -e "    - 从抓包工具或 DevTools 复制的 \033[1;36mCookie 文本\033[0m"
    echo -e "  • 在下方输入框内\033[1;36m长按屏幕空白处\033[0m选择【粘贴】"
    echo -e "  • 粘贴完成后，点击手机键盘上方工具栏的 \033[1;32m[CTRL]\033[0m 键，再按字母 \033[1;32m[D]\033[0m 提交"
    echo -e "  • 若要取消输入，按 \033[1;31m[ESC]\033[0m 退出\n"

    local raw_paste=""
    if [ "$HAS_GUM" = true ]; then
        raw_paste=$("$GUM_BIN" write \
            --header="📋 凭据输入框 (长按粘贴后按 Ctrl+D 提交，按 Esc 取消)：" \
            --placeholder="在此处长按粘贴 Cookie 内容 (支持 JSON 或 key=value; 纯文本)..." \
            --width=0 \
            --height=10 \
            --show-line-numbers \
            --cursor.mode="blink")
        local ret=$?
        if [ $ret -ne 0 ] || [ -z "$raw_paste" ]; then
            ui_print warn "已取消操作或未输入有效内容。"
            ui_pause; return
        fi
    else
        local paste_script="$TMP_DIR/read_paste_$$.py"
        cat << 'EOF_PY' > "$paste_script"
import sys, json, os, select

sys.stderr.write("  \033[1;36m➜\033[0m 请长按屏幕选择【粘贴】Cookie JSON 内容：\n")
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
            combined = "".join(lines).strip()
            if (combined.startswith("[") and combined.endswith("]")) or (combined.startswith("{") and combined.endswith("}")):
                try:
                    json.loads(combined)
                    r, _, _ = select.select([tty], [], [], 0.3)
                    if not r:
                        break
                except Exception:
                    pass
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
            ui_pause; return
        fi
    fi

    _aistudio2api_process_and_import "$raw_paste" false
    ui_pause
}

aistudio2api_import_from_file() {
    ui_header "📁 从文件导入 Google AI Studio 凭据"

    # 确保存储权限
    ensure_storage_permission

    # 自动探测手机 Download 目录下最新的 JSON 凭据文件
    local default_file=""
    local candidates=()
    for search_dir in "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/storage/downloads" "$HOME/downloads" "$TMP_DIR"; do
        if [ -d "$search_dir" ]; then
            while IFS= read -r f; do
                [ -n "$f" ] && candidates+=("$f")
            done < <(find "$search_dir" -maxdepth 2 -type f -name "*.json" 2>/dev/null | xargs ls -t 2>/dev/null | head -n 3)
        fi
        [ ${#candidates[@]} -gt 0 ] && break
    done

    if [ ${#candidates[@]} -gt 0 ]; then
        default_file="${candidates[0]}"
        ui_print info "💡 自动检测到最近生成的凭据文件："
        echo -e "   \033[1;36m$default_file\033[0m\n"
    fi

    echo -e "说明："
    echo -e "  • 支持 Kiwi 浏览器中 \033[1;33mCookie-Editor\033[0m 插件导出的 JSON 文件"
    echo -e "  • 支持标准的 \033[1;33mPlaywright / StorageState\033[0m JSON 凭据文件"
    echo -e "  • 系统将自动识别并自适应转换格式，免去手动改写\n"

    local json_file
    json_file=$(ui_input "请输入凭据文件路径 (直接回车使用检测到的文件)" "$default_file" false)
    if [ -z "$json_file" ]; then
        ui_print warn "已取消操作。"
        ui_pause; return
    fi

    if [ ! -f "$json_file" ]; then
        ui_print error "未找到文件: $json_file"
        ui_pause; return 1
    fi

    _aistudio2api_process_and_import "$json_file" true
    ui_pause
}

aistudio2api_import_auth() {
    _aistudio2api_vars
    ui_header "📥 导入 Google AI Studio 账号凭据"

    if [ ! -x "$AS_BIN" ]; then
        ui_print error "程序未安装，请先执行安装。"
        ui_pause; return 1
    fi

    local choice
    choice=$(ui_menu "请选择凭据导入方式" \
        "📋 直接粘贴 JSON 内容 (打开多行输入框直接粘贴)" \
        "📁 从文件导入 (自动扫描手机 Download 目录 .json)" \
        "🌐 在 Web 控制台上传 (调用手机浏览器操作)" \
        "🔙 返回上一级")

    case "$choice" in
        *"直接粘贴"*)
            aistudio2api_import_from_paste
            ;;
        *"从文件导入"*)
            aistudio2api_import_from_file
            ;;
        *"Web 控制台"*)
            aistudio2api_open_webui
            ;;
        *)
            return 0
            ;;
    esac
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
            "📥 导入账号凭据" \
            "📚 获取凭据教程" \
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
            *"获取凭据教程"*|*"教程"*)
                aistudio2api_show_tutorial
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
