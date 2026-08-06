#!/bin/bash
# [METADATA]
# MODULE_ID: codexmobile
# MODULE_NAME: Codex Mobile (Web UI)
# MODULE_ENTRY: codexmobile_menu
# APP_CATEGORY: AIBOX
# APP_AUTHOR: friuns2
# APP_PROJECT_URL: https://github.com/friuns2/codex-mobile
# APP_DESC: 专为移动端 (Termux) 与 Linux/Windows 设计的 Codex 远程 Web UI 界面，基于原作者预编译包，免本地构建秒速启动。
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
    CM_CLI_BIN="$CM_DIR/node_modules/codexapp/dist-cli/index.js"
    mkdir -p "$CM_DIR"
}

_codexmobile_load_env() {
    _codexmobile_vars
    if [ -f "$CM_ENV_CONF" ]; then
        # shellcheck disable=SC1090
        source "$CM_ENV_CONF"
    fi
    [ -z "$CM_PORT" ] && CM_PORT="18923"
    [ -z "$CM_BIND_HOST" ] && CM_BIND_HOST="0.0.0.0"
    [ -z "$CM_ENABLE_TUNNEL" ] && CM_ENABLE_TUNNEL="false"
    [ -z "$CM_SKIP_LOGIN" ] && CM_SKIP_LOGIN="true"
}

_codexmobile_save_env() {
    _codexmobile_load_env
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

    ui_print info "检查 Node.js 环境 (要求 >= 18)..."
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

    prepare_network_strategy

    ui_print info "正在下载并部署原作者预编译发行包 (codexapp)..."
    cd "$CM_DIR" || return 1

    # 创建基础 package.json 避免 npm 安装报错
    if [ ! -f "$CM_DIR/package.json" ]; then
        echo '{"name":"tavx-codexmobile-app","private":true}' > "$CM_DIR/package.json"
    fi

    local INSTALL_CMD="npm install codexapp@latest --no-audit --no-fund"
    if ui_stream_task "部署 Codex Mobile 预编译包..." "$INSTALL_CMD"; then
        ui_print success "Codex Mobile 发行包部署完成！"
    else
        ui_print error "下载部署失败，请检查网络设置。"
        ui_pause; return 1
    fi

    if [ ! -f "$CM_ENV_CONF" ]; then
        _codexmobile_save_env
        ui_print success "已生成默认配置文件 ($CM_ENV_CONF)"
    fi

    ui_print success "Codex Mobile 安装成功！(免本地编译)"
}

codexmobile_start() {
    _codexmobile_vars
    _codexmobile_load_env

    if [ ! -f "$CM_CLI_BIN" ]; then
        if ui_confirm "未检测到 Codex Mobile 组件，是否立即安装？"; then
            codexmobile_install || return 1
        else
            return 1
        fi
    fi

    ui_header "启动 Codex Mobile"
    auto_load_proxy_env

    cd "$CM_DIR" || return 1

    local ARGS=("--port" "$CM_PORT" "--no-open")
    if [ "$CM_ENABLE_TUNNEL" != "true" ]; then
        ARGS+=("--no-tunnel")
    fi
    if [ "$CM_SKIP_LOGIN" == "true" ]; then
        ARGS+=("--no-login")
    fi

    local RUN_CMD="node '$CM_CLI_BIN' ${ARGS[*]}"

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
        echo -e "Cloudflare 隧道 : ${GREEN}${CM_ENABLE_TUNNEL}${NC}"
        echo -e "免登录模式 (--no-login): ${GREEN}${CM_SKIP_LOGIN}${NC}"
        echo ""

        local CHOICE
        CHOICE=$(ui_menu "选择要修改的设置" \
            "1. 修改服务端口 [当前: $CM_PORT]" \
            "2. 切换 Cloudflare 隧道模式 [当前: $CM_ENABLE_TUNNEL]" \
            "3. 切换免登录模式 (--no-login) [当前: $CM_SKIP_LOGIN]" \
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
                if [ "$CM_ENABLE_TUNNEL" == "true" ]; then
                    CM_ENABLE_TUNNEL="false"
                else
                    CM_ENABLE_TUNNEL="true"
                fi
                ui_print success "Cloudflare 隧道已设置为: $CM_ENABLE_TUNNEL"
                ;;
            *"3."*)
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

codexmobile_import_account() {
    _codexmobile_vars
    ui_header "📥 导入 JSON 登录凭证"
    echo -e "${YELLOW}支持导入包含 access_token / refresh_token 的凭证 JSON。${NC}"
    echo -e "例如: 可以选择【输入文件路径】或【直接粘贴 JSON 字符串】"
    echo ""

    local import_mode
    import_mode=$(ui_menu "选择导入方式" "📁 读取 JSON 文件路径" "📋 直接粘贴 JSON 内容" "🔙 返回")

    local json_content=""
    if [[ "$import_mode" == *"文件路径"* ]]; then
        local file_path
        file_path=$(ui_input "请输入 JSON 文件完整路径 (如 /sdcard/Download/auth.json)")
        if [ ! -f "$file_path" ]; then
            ui_print error "找不到指定文件: $file_path"
            ui_pause; return 1
        fi
        json_content=$(cat "$file_path")
    elif [[ "$import_mode" == *"粘贴"* ]]; then
        json_content=$(ui_input "请粘贴 JSON 凭证内容")
    else
        return 0
    fi

    if [ -z "$json_content" ]; then
        ui_print error "JSON 内容不能为空！"
        ui_pause; return 1
    fi

    ui_print info "正在解析并导入凭证到多账号池..."

    export CM_IMPORT_JSON="$json_content"
    export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

    local node_import_script='
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

try {
    const rawJson = process.env.CM_IMPORT_JSON || "";
    let data;
    try {
        data = JSON.parse(rawJson);
    } catch(e) {
        console.error("JSON 格式错误，请检查语法。");
        process.exit(1);
    }

    const codexHome = process.env.CODEX_HOME || path.join(process.env.HOME || "", ".codex");
    if (!fs.existsSync(codexHome)) {
        fs.mkdirSync(codexHome, { recursive: true });
    }

    let authMode = data.auth_mode || "chatgpt";
    let tokens = data.tokens || {};
    if (data.access_token || data.accessToken) {
        tokens.access_token = data.access_token || data.accessToken;
    }
    if (data.refresh_token || data.refreshToken) {
        tokens.refresh_token = data.refresh_token || data.refreshToken;
    }
    if (data.id_token || data.idToken) {
        tokens.id_token = data.id_token || data.idToken;
    }
    if (data.account_id || data.accountId) {
        tokens.account_id = data.account_id || data.accountId;
    }

    if (!tokens.access_token) {
        console.error("未检测到有效的 access_token 凭证！");
        process.exit(1);
    }

    const authFileObj = {
        auth_mode: authMode,
        tokens: tokens
    };

    const mainAuthPath = path.join(codexHome, "auth.json");
    fs.writeFileSync(mainAuthPath, JSON.stringify(authFileObj, null, 2), "utf8");

    const accountId = tokens.account_id || ("user-" + crypto.createHash("sha256").update(tokens.access_token).digest("hex").slice(0, 16));
    const storageId = crypto.createHash("sha256").update(accountId).digest("hex");

    const accountDir = path.join(codexHome, "accounts", storageId);
    if (!fs.existsSync(accountDir)) {
        fs.mkdirSync(accountDir, { recursive: true });
    }
    fs.writeFileSync(path.join(accountDir, "auth.json"), JSON.stringify(authFileObj, null, 2), "utf8");

    const accountsStatePath = path.join(codexHome, "accounts.json");
    let state = { activeAccountId: accountId, activeStorageId: storageId, accounts: [] };
    if (fs.existsSync(accountsStatePath)) {
        try {
            const rawState = JSON.parse(fs.readFileSync(accountsStatePath, "utf8"));
            if (Array.isArray(rawState.accounts)) state.accounts = rawState.accounts;
        } catch(e) {}
    }

    state.activeAccountId = accountId;
    state.activeStorageId = storageId;

    const existingIdx = state.accounts.findIndex(a => a.storageId === storageId || a.accountId === accountId);
    const newEntry = {
        accountId: accountId,
        storageId: storageId,
        userId: null,
        authMode: authMode,
        email: data.email || null,
        planType: data.plan_type || data.planType || null,
        lastRefreshedAtIso: new Date().toISOString(),
        lastActivatedAtIso: new Date().toISOString(),
        quotaSnapshot: null,
        quotaUpdatedAtIso: null,
        quotaStatus: "idle",
        quotaError: null,
        unavailableReason: null
    };

    if (existingIdx >= 0) {
        state.accounts[existingIdx] = { ...state.accounts[existingIdx], ...newEntry };
    } else {
        state.accounts.unshift(newEntry);
    }

    fs.writeFileSync(accountsStatePath, JSON.stringify(state, null, 2), "utf8");

    console.log("SUCCESS: " + accountId);
} catch (err) {
    console.error(err.message || String(err));
    process.exit(1);
}
'

    local res
    res=$(node -e "$node_import_script" 2>&1)
    local ret=$?
    unset CM_IMPORT_JSON

    if [ $ret -eq 0 ]; then
        local acc_id
        acc_id=$(echo "$res" | grep "SUCCESS:" | cut -d: -f2 | xargs)
        ui_print success "JSON 凭证导入成功！账号 ID: ${acc_id:-已导入}"
        ui_print info "已同步至多账号池。如果服务正在运行，请重启后生效。"
    else
        ui_print error "凭证导入失败: $res"
    fi
    ui_pause
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
            "📥 导入 JSON 凭证 (多账号数据)" \
            "🛑 停止服务" \
            "🔄 重启服务" \
            "⚙️ 参数配置" \
            "📜 查看日志" \
            "⚡ (Termux) 保持CPU唤醒锁" \
            "📥 重装/更新至最新发布包" \
            "🗑️  卸载模块" \
            "🧭 关于模块" \
            "🔙 返回")

        case "$CHOICE" in
            *"启动"*)
                codexmobile_start; ui_pause ;;
            *"导入 JSON"*)
                codexmobile_import_account ;;
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
