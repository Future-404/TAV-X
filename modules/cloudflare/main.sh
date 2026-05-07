#!/bin/bash
# [METADATA]
# MODULE_ID: cloudflare
# MODULE_NAME: Cloudflare 隧道
# MODULE_ENTRY: cf_menu
# APP_CATEGORY: 网络与代理
# APP_AUTHOR: cloudflare
# APP_PROJECT_URL: https://github.com/cloudflare/cloudflared
# APP_DESC: Cloudflare Tunnel(cloudflared)允许您通过Cloudflare的边缘网络安全地将本地服务暴露到公网，无需配置防火墙规则或公网IP。支持自动管理DNS记录、HTTPS证书以及高性能的全球加速。
# [END_METADATA]

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"
# shellcheck disable=SC1091
[ -f "$TAVX_DIR/modules/cloudflare/api_utils.sh" ] && source "$TAVX_DIR/modules/cloudflare/api_utils.sh"

_cf_vars() {
    CF_APP_ID="cloudflare"
    CF_DIR=$(get_app_path "$CF_APP_ID")
    if [ "$OS_TYPE" == "TERMUX" ]; then
        CF_BIN="cloudflared"
    else
        CF_BIN="$CF_DIR/cloudflared"
    fi
    
    CF_USER_DATA="$HOME/.cloudflared"
    CF_LOG_DIR="$LOGS_DIR/cf_tunnels"
    CF_RUN_DIR="$RUN_DIR"
    CF_API_TOKEN_FILE="$CONFIG_DIR/cf_api_token"
    
    mkdir -p "$CF_DIR" "$CF_USER_DATA" "$CF_LOG_DIR" "$CF_RUN_DIR"
}

cloudflare_install() {
    _cf_vars
    
    if [ "$OS_TYPE" == "TERMUX" ]; then
        if command -v cloudflared &>/dev/null; then 
            ui_print info "检测到 Cloudflared 已安装。"
            mkdir -p "$CF_DIR"
            touch "$CF_DIR/.installed"
            return 0
        fi
        ui_header "安装 Cloudflared (Termux)"
        if sys_install_pkg "cloudflared"; then
            ui_print success "安装完成。"
            mkdir -p "$CF_DIR"
            touch "$CF_DIR/.installed"
            return 0
        else
            ui_print error "安装失败。"
            return 1
        fi
    else
        if [ -f "$CF_BIN" ]; then return 0; fi
        ui_header "安装 Cloudflared (Linux)"
        local arch
        arch=$(uname -m)
        local dl="amd64"
        [[ "$arch" == "aarch64" || "$arch" == "arm64" ]] && dl="arm64"
        [[ "$arch" == "arm" || "$arch" == "armv7l" ]] && dl="arm"
        
        local url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$dl"
        local cmd
        cmd="source \"$TAVX_DIR/core/utils.sh\"; download_file_smart '$url' '$CF_BIN'"
        if ui_stream_task "正在下载核心组件..." "$cmd"; then
            chmod +x "$CF_BIN"
            ui_print success "安装完成。"
            return 0
        else
            ui_print error "下载失败。"
            return 1
        fi
    fi
}

cf_import_cert() {
    _cf_vars
    ui_header "手动导入凭证"
    echo -e "请选择已下载的 ${CYAN}cert.pem${NC} 文件。"
    echo "----------------------------------------"
    
    local selected_file=""
    if [ "$HAS_GUM" = true ]; then
        selected_file=$("$GUM_BIN" file --cursor.foreground="$C_PINK" "$HOME")
    else
        selected_file=$(ui_input "请输入文件绝对路径" "" "false")
    fi
    
    [ -z "$selected_file" ] && return 1
    [ ! -f "$selected_file" ] && { ui_print error "文件不存在: $selected_file"; ui_pause; return 1; }
    
    if ! grep -q "PRIVATE KEY" "$selected_file"; then
        ui_print error "无效的证书文件（未检测到私钥标识）。"
        ui_pause; return 1
    fi
    
    ui_spinner "正在导入凭证..." "cp '$selected_file' '$CF_USER_DATA/cert.pem'"
    ui_print success "导入成功！"
    return 0
}

cf_login() {
    _cf_vars
    if [ "$OS_TYPE" == "TERMUX" ]; then
        command -v cloudflared &>/dev/null || cloudflare_install || return 1
    else
        [ -f "$CF_BIN" ] || cloudflare_install || return 1
    fi
    
    ui_header "Cloudflare 登录授权"
    echo -e "${YELLOW}重要提示:${NC}"
    echo -e "1. 请确认浏览器已登录: ${CYAN}dash.cloudflare.com${NC}"
    echo -e "2. 如果自动回调失败，浏览器会下载 ${CYAN}cert.pem${NC} 文件。"
    echo -e "3. 脚本会自动扫描下载目录，无需手动移动。"
    echo ""
    
    local ACTION
    ACTION=$(ui_menu "请选择授权方式" "🚀 启动浏览器授权 (推荐)" "📂 手动导入 cert.pem" "🔙 返回")
    case "$ACTION" in
        *"手动"*) cf_import_cert; return $? ;;
        *"返回"*) return 0 ;;
    esac
    
    if [ -f "$CF_USER_DATA/cert.pem" ]; then
        ui_print warn "检测到已存在登录凭证。切换账号后，旧账号下的所有隧道将无法使用！"
        if ! ui_confirm "确认切换账号？(旧凭证将被删除且不可恢复)"; then return 0; fi
        rm -f "$CF_USER_DATA/cert.pem"
    fi
    
    ui_print info "正在启动授权进程..."
    local login_log="$TMP_DIR/cf_login.log"
    rm -f "$login_log"
    
    "$CF_BIN" tunnel login > "$login_log" 2>&1 & 
    local login_pid=$!
    
    ui_print info "等待获取授权链接..."
    local url_found=false
    while true; do
        if [ -f "$CF_USER_DATA/cert.pem" ]; then
            ui_print success "检测到证书已自动生成！"
            break
        fi
        
        if ! kill -0 "$login_pid" 2>/dev/null; then
            ui_print warn "授权进程已结束 (可能是回调失败并转为文件下载)。"
            break
        fi
        
        if [ "$url_found" = false ] && grep -q "https://" "$login_log"; then
            local login_url
            login_url=$(grep -oE "https://[a-zA-Z0-9./?=_-]+" "$login_log" | head -n 1)
            if [ -n "$login_url" ]; then
                ui_print success "找到授权链接，正在打开浏览器..."
                open_browser "$login_url"
                url_found=true
                ui_print info "请在浏览器完成授权，成功后脚本会自动扫描..."
            fi
        fi
        sleep 2
    done
    
    kill "$login_pid" 2>/dev/null
    wait "$login_pid" 2>/dev/null
    
    if [ ! -f "$CF_USER_DATA/cert.pem" ]; then
        ui_print info "正在自动扫描下载目录..."
        if [ "$OS_TYPE" == "TERMUX" ] && [ ! -d "$HOME/storage/downloads" ]; then
            ui_print warn "需要存储权限才能扫描下载目录，正在申请..."
            termux-setup-storage
            sleep 3
        fi
        local scan_paths=(
            "$HOME/storage/downloads/cert*.pem"
            "$HOME/downloads/cert*.pem"
            "/sdcard/Download/cert*.pem"
        )
        
        local latest_file=""
        for pattern in "${scan_paths[@]}"; do
            local dir
            dir=$(dirname "$pattern")
            local name
            name=$(basename "$pattern")
            [ ! -d "$dir" ] && continue
            local found
            found=$(find "$dir" -maxdepth 1 -name "$name" 2>/dev/null | xargs ls -t 2>/dev/null | head -n 1)
            if [ -n "$found" ] && { [ -z "$latest_file" ] || [ "$found" -nt "$latest_file" ]; }; then
                latest_file="$found"
            fi
        done
        
        if [ -n "$latest_file" ]; then
            ui_print info "发现最新凭证: $(basename "$latest_file")"
            mv "$latest_file" "$CF_USER_DATA/cert.pem"
            ui_print success "凭证已自动迁移！"
        fi
    fi

    if [ -f "$CF_USER_DATA/cert.pem" ]; then
        ui_print success "登录成功！"
        return 0
    else
        ui_print error "自动获取失败。"
        if ui_confirm "是否手动选择已下载的 cert.pem 文件？"; then
            cf_import_cert
            return $? 
        fi
        return 1
    fi
}

cf_quick_tunnel() {
    _cf_vars
    if [ "$OS_TYPE" == "TERMUX" ]; then
        command -v cloudflared &>/dev/null || cloudflare_install || return 1
    else
        [ -f "$CF_BIN" ] || cloudflare_install || return 1
    fi
    
    ui_header "⚡ 快速暴露 (Quick Tunnel)"
    local port
    port=$(ui_input "输入本地端口" "8000" "false")
    
    local pid_file="$CF_RUN_DIR/cf_quick.pid"
    kill_process_safe "$pid_file" "cloudflared"
    
    local log_file="$CF_LOG_DIR/quick.log"
    rm -f "$log_file"
    
    setsid nohup "$CF_BIN" tunnel --url "http://127.0.0.1:$port" --no-autoupdate > "$log_file" 2>&1 &
    echo $! > "$pid_file"
    
    local url=""
    # shellcheck disable=SC2034
    for i in {1..15}; do
        sleep 1
        url=$(grep -o "https://.*\.trycloudflare.com" "$log_file" | head -n 1)
        if [ -n "$url" ]; then break; fi
        echo -n "."
    done
    echo ""
    
    if [ -n "$url" ]; then
        ui_print success "隧道已建立！"
        echo -e "🔗 公网地址: ${GREEN}$url${NC}"
        echo -e "⚠️  注意: 此域名为随机生成，进程重启后会变更。"
    else
        ui_print error "获取域名超时，请检查日志。"
        tail -n 5 "$log_file"
    fi
    ui_pause
}

cf_add_ingress() {
    local name="$1"
    local conf="$2"
    
    if ! command -v yq &>/dev/null; then
        ui_print error "此功能需要 yq 工具。"
        return 1
    fi
    
    ui_header "添加域名映射"
    local domain
    domain=$(ui_input "要绑定的域名" "" "false")
    [ -z "$domain" ] && return
    
    local service
    service=$(ui_input "本地服务地址" "http://localhost:8000" "false")
    [ -z "$service" ] && return
    
    if ui_stream_task "配置 DNS 路由..." "\"$CF_BIN\" tunnel route dns \"$name\" \"$domain\" "; then
        ui_print success "DNS 记录已添加。"
    else
        ui_print error "DNS 绑定失败 (常见原因: 域名未托管在当前账号的 Cloudflare 下，或授权时选择的域名与此域名不符)。"
        if ! ui_confirm "是否强制写入本地配置？(可能导致隧道报错)"; then return 1; fi
    fi
    
    yq -i ".ingress = [{\"hostname\": \"$domain\", \"service\": \"$service\"}] + .ingress" "$conf"
    
    ui_print success "规则已添加: $domain -> $service"
}

cf_del_ingress() {
    local name="$1"
    local conf="$2"
    
    if ! command -v yq &>/dev/null; then
        ui_print error "此功能需要 yq 工具。"
        return 1
    fi
    
    local hosts=()
    if [ "${BASH_VERSINFO:-0}" -ge 4 ]; then
        mapfile -t hosts < <(yq '.ingress[] | select(has("hostname")) | .hostname' "$conf")
    else
        # shellcheck disable=SC2207
        hosts=($(yq '.ingress[] | select(has("hostname")) | .hostname' "$conf") )
    fi
    
    if [ ${#hosts[@]} -eq 0 ]; then
        ui_print warn "当前没有配置任何域名映射。"
        ui_pause; return
    fi
    
    local target
    target=$(ui_menu "选择要移除的域名" "${hosts[@]}" "🔙 取消")
    [ "$target" == "🔙 取消" ] && return
    
    yq -i "del(.ingress[] | select(.hostname == \"$target\"))" "$conf"
    ui_print success "本地规则已移除。"
    
    if command -v cf_api_delete_dns &>/dev/null; then
        cf_api_delete_dns "$target"
    else
        echo -e "${YELLOW}提示: 请记得手动删除 Cloudflare 上的 CNAME 记录 ($target)。${NC}"
    fi
}

cf_edit_ingress() {
    local name="$1"
    local conf="$2"
    
    if ! command -v yq &>/dev/null; then
        ui_print error "此功能需要 yq 工具。"
        return 1
    fi
    
    local hosts=()
    if [ "${BASH_VERSINFO:-0}" -ge 4 ]; then
        mapfile -t hosts < <(yq '.ingress[] | select(has("hostname")) | .hostname' "$conf")
    else
        # shellcheck disable=SC2207
        hosts=($(yq '.ingress[] | select(has("hostname")) | .hostname' "$conf") )
    fi
    
    if [ ${#hosts[@]} -eq 0 ]; then
        ui_print warn "当前没有可修改的映射规则。"
        return
    fi
    
    local target
    target=$(ui_menu "选择要修改的域名" "${hosts[@]}" "🔙 取消")
    [ "$target" == "🔙 取消" ] && return
    local old_svc
    old_svc=$(yq ".ingress[] | select(.hostname == \"$target\") | .service" "$conf")
    
    ui_header "修改映射: $target"
    local new_svc
    new_svc=$(ui_input "新本地服务地址" "$old_svc" "false")
    
    if [ -n "$new_svc" ] && [ "$new_svc" != "$old_svc" ]; then
        yq -i "(.ingress[] | select(.hostname == \"$target\")).service = \"$new_svc\"" "$conf"
        ui_print success "规则已更新。"
        return 0
    else
        ui_print info "未变更。"
        return 1
    fi
}

cf_create_named_tunnel() {
    _cf_vars
    if [ "$OS_TYPE" == "TERMUX" ]; then
        command -v cloudflared &>/dev/null || cloudflare_install || return 1
    else
        [ -f "$CF_BIN" ] || cloudflare_install || return 1
    fi
    
    if [ ! -f "$CF_USER_DATA/cert.pem" ]; then
        ui_print error "未登录！请先执行 [🔐 Tunnel 登录授权]。"
        ui_pause; return 1
    fi
    
    ui_header "创建固定隧道"
    local name
    name=$(ui_input_validated "给隧道起个名字 (如 my-web)" "" "alphanumeric")
    [ -z "$name" ] && return
    
    if ui_stream_task "注册隧道: $name" "\"$CF_BIN\" tunnel create \"$name\" "; then
        ui_print success "隧道 ID 已生成。"
    else
        ui_print error "创建失败。"; ui_pause; return 1
    fi
    
    local json_file
    json_file=$(find "$CF_USER_DATA" -maxdepth 1 -name "*.json" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)
    local uuid
    uuid=$(basename "$json_file" .json)
    local conf_file="$CF_DIR/${name}.yml"
    
    cat > "$conf_file" <<EOF
tunnel: $uuid
credentials-file: $json_file

ingress:
  - service: http_status:404
EOF
    ui_print success "基础配置文件已生成。"
    
    if command -v yq &>/dev/null; then
        echo ""
        if ui_confirm "是否立即添加一个域名映射？"; then
            cf_add_ingress "$name" "$conf_file"
        else
            ui_print info "您稍后可以在管理菜单中添加映射。"
        fi
    else
        ui_print warn "未检测到 yq，跳过高级配置向导。"
        ui_print info "请手动编辑 $conf_file 添加 ingress 规则。"
    fi
    
    if ui_confirm "是否立即启动？"; then
        _start_named_tunnel "$name" "$conf_file"
    fi
}

_start_named_tunnel() {
    local name="$1"
    local conf="$2"
    _cf_vars
    
    local pid_file="$CF_RUN_DIR/cf_${name}.pid"
    local log_file="$CF_LOG_DIR/${name}.log"
    local svc_name="cf_tunnel_${name}"
    
    ui_print info "正在启动: $name ..."

    if [ "$OS_TYPE" == "TERMUX" ]; then
        tavx_service_register "$svc_name" "\"$CF_BIN\" tunnel --config \"$conf\" run \"$name\"" "$CF_DIR"
        tavx_service_control "up" "$svc_name"
        ui_print success "服务启动命令已发送。"
    else
        kill_process_safe "$pid_file" "cloudflared"
        setsid nohup "$CF_BIN" tunnel --config "$conf" run "$name" > "$log_file" 2>&1 &
        echo $! > "$pid_file"
        
        sleep 2
        if check_process_smart "$pid_file" "cloudflared"; then
            ui_print success "运行中！"
        else
            ui_print error "启动失败，查看日志: $log_file"
            tail -n 5 "$log_file"
        fi
    fi
    ui_pause
}

cf_manage_tunnels() {
    while true; do
        _cf_vars
        ui_header "管理固定隧道"
        
        local opts=()
        local files=()
        for f in "$CF_DIR"/*.yml; do
            [ ! -f "$f" ] && continue
            local t_name
            t_name=$(basename "$f" .yml)
            local pid_f="$CF_RUN_DIR/cf_${t_name}.pid"
            local svc_name="cf_tunnel_${t_name}"
            local status="🔴"
            
            if [ "$OS_TYPE" == "TERMUX" ]; then
                if sv status "$svc_name" 2>/dev/null | grep -q "^run:"; then status="🟢"; fi
            elif check_process_smart "$pid_f" "cloudflared"; then 
                status="🟢"
            fi
            
            local desc=""
            if command -v yq &>/dev/null; then
                local host
                host=$(yq '.ingress[0].hostname' "$f" 2>/dev/null)
                if [ -n "$host" ] && [ "$host" != "null" ]; then
                    desc=" ($host)"
                fi
            fi
            
            opts+=("$status $t_name$desc")
            files+=("$f")
        done
        
        if [ ${#opts[@]} -eq 0 ]; then
            ui_print warn "暂无已配置的隧道。"
            if ui_confirm "去创建一个？"; then cf_create_named_tunnel; continue; else return; fi
        fi
        
        opts+=("➕ 创建新隧道" "🔙 返回")
        
        local C
        C=$(ui_menu "选择隧道" "${opts[@]}")
        case "$C" in
            *"创建"*) cf_create_named_tunnel ;; 
            *"返回"*) return ;; 
            *)
                local sel_name
                sel_name=$(echo "$C" | awk '{print $2}')
                _tunnel_action_menu "$sel_name"
                ;; 
        esac
    done
}

_tunnel_action_menu() {
    local name="$1"
    local conf="$CF_DIR/${name}.yml"
    local pid_f="$CF_RUN_DIR/cf_${name}.pid"
    local svc_name="cf_tunnel_${name}"
    
    while true; do
        ui_header "操作: $name"
        local state="🔴 停止"
        local log_path="$CF_LOG_DIR/${name}.log"
        [ "$OS_TYPE" == "TERMUX" ] && log_path="$PREFIX/var/service/$svc_name/log/current"

        if [ "$OS_TYPE" == "TERMUX" ]; then
            if sv status "$svc_name" 2>/dev/null | grep -q "^run:"; then state="🟢 运行中"; fi
        elif check_process_smart "$pid_f" "cloudflared"; then 
            state="🟢 运行中"
        fi
        echo -e "状态: $state"
        
        if command -v yq &>/dev/null; then
             local hosts=()
             if [ "${BASH_VERSINFO:-0}" -ge 4 ]; then
                 mapfile -t hosts < <(yq '.ingress[] | select(has("hostname")) | .hostname' "$conf")
             else
                 # shellcheck disable=SC2207
                 hosts=($(yq '.ingress[] | select(has("hostname")) | .hostname' "$conf") )
             fi
             echo -e "映射数: ${#hosts[@]}"
             for h in "${hosts[@]}"; do
                 echo -e "  - ${CYAN}$h${NC}"
             done
        else
             echo -e "配置: $conf"
        fi
        
        local menu_opts=("🚀 启动服务" "🛑 停止")
        
        if command -v yq &>/dev/null; then
             menu_opts+=("➕ 添加域名映射" "🔧 修改映射配置" "➖ 删除域名映射")
        fi
        
        menu_opts+=("📝 编辑配置" "📜 查看日志" "🗑️  删除隧道" "🔙 返回")
        
        local ACT
        ACT=$(ui_menu "动作" "${menu_opts[@]}")
        case "$ACT" in
            *"启动"*) _start_named_tunnel "$name" "$conf" ;; 
            *"停止"*) 
                if [ "$OS_TYPE" == "TERMUX" ]; then
                    tavx_service_control "down" "$svc_name"
                else
                    kill_process_safe "$pid_f" "cloudflared"
                fi
                ui_print success "已停止"; ui_pause ;; 
            *"添加"*) 
                cf_add_ingress "$name" "$conf"
                if [[ "$state" == *"运行中"* ]]; then
                    ui_print info "配置已变更，正在重启隧道..."
                    _start_named_tunnel "$name" "$conf"
                fi ;; 
            *"修改映射"*) 
                if cf_edit_ingress "$name" "$conf"; then
                    if [[ "$state" == *"运行中"* ]]; then
                        ui_print info "配置已变更，正在重启隧道..."
                        _start_named_tunnel "$name" "$conf"
                    fi
                fi ;; 
            *"删除域名"*) 
                cf_del_ingress "$name" "$conf" 
                if [[ "$state" == *"运行中"* ]]; then
                    ui_print info "配置已变更，正在重启隧道..."
                    _start_named_tunnel "$name" "$conf"
                fi ;; 
            *"编辑"*) 
                if command -v nano &>/dev/null; then nano "$conf"; else vi "$conf"; fi ;; 
            *"日志"*) ui_watch_log "$svc_name" ;; 
            *"删除隧道"*) 
                if verify_kill_switch; then
                    ui_print info "正在停止本地服务..."
                    if [ "$OS_TYPE" == "TERMUX" ]; then
                        tavx_service_control "down" "$svc_name"
                        # [标准] 移除服务注册
                        tavx_service_remove "$svc_name"
                    else
                        kill_process_safe "$pid_f" "cloudflared"
                    fi

                    if command -v yq &>/dev/null; then
                        local uuid
                        uuid=$(yq '.tunnel' "$conf" 2>/dev/null)
                        local hosts=()
                        if [ "${BASH_VERSINFO:-0}" -ge 4 ]; then
                            mapfile -t hosts < <(yq '.ingress[] | select(has("hostname")) | .hostname' "$conf")
                        else
                            # shellcheck disable=SC2207
                            hosts=($(yq '.ingress[] | select(has("hostname")) | .hostname' "$conf") )
                        fi
                        
                        if [ -n "$uuid" ] && [ "$uuid" != "null" ]; then
                            ui_print info "正在移除云端隧道..."
                            sleep 1
                            "$CF_BIN" tunnel delete "$uuid" >/dev/null 2>&1
                            ui_print success "云端隧道已移除。"
                        fi
                        
                        for h in "${hosts[@]}"; do
                             if command -v cf_api_delete_dns &>/dev/null; then
                                cf_api_delete_dns "$h"
                             fi
                        done
                    else
                        ui_print warn "未检测到 yq，跳过云端资源智能清理。"
                    fi
                    
                    rm -f "$conf"
                    ui_print success "本地配置已移除"
                    return
                fi ;; 
            *"返回"*) return ;; 
        esac
    done
}

cf_stop_all() {
    _cf_vars
    ui_print info "正在停止所有 Cloudflare 进程..."
    
    # 停止 Termux 服务
    if [ "$OS_TYPE" == "TERMUX" ] && command -v sv &>/dev/null; then
        for s in "$PREFIX/var/service"/cf_tunnel_*; do
            [ ! -d "$s" ] && continue
            sv -w 2 force-stop "$(basename "$s")" 2>/dev/null
        done
    fi

    # 停止传统 PID 进程
    kill_process_safe "$CF_RUN_DIR/cf_quick.pid" "cloudflared"
    for f in "$CF_RUN_DIR"/cf_*.pid; do
        [ -f "$f" ] && kill_process_safe "$f" "cloudflared"
    done
    pkill -f "cloudflared"
    ui_print success "全部停止。"
    ui_pause
}

cf_menu() {
    while true; do
        _cf_vars
        ui_header "☁️ Cloudflare 隧道"
        
        local info=()
        if [ -f "$CF_USER_DATA/cert.pem" ]; then info+=("Tunnel: ✅ 已授权"); else info+=("Tunnel: ❌ 未授权"); fi
        if [ -f "$CF_API_TOKEN_FILE" ]; then info+=("API: ✅ 已配置"); else info+=("API: ❌ 未配置"); fi
        
        local running_cnt=0
        if command -v pgrep &>/dev/null; then
            running_cnt=$(pgrep -c "cloudflared" 2>/dev/null || echo "0")
        fi
        info+=("活跃进程: $running_cnt")
        
        ui_status_card "info" "概览" "${info[@]}"
        
        local C
        C=$(ui_menu "主菜单" \
            "🚀 启动/管理固定隧道" \
            "⚡ 临时快速暴露" \
            "🔐 Tunnel 登录授权 (必选)" \
            "🔑 API Token 设置" \
            "🧹 扫描并清理孤儿 DNS" \
            "🛑 停止所有服务" \
            "🗑️  卸载/重置模块" \
            "📖 使用文档" \
            "🧭 关于模块" \
            "🔙 返回"
        )
        
        [ -z "$C" ] && return
        
        case "$C" in
            *"固定"*) cf_manage_tunnels ;; 
            *"快速"*) cf_quick_tunnel ;; 
            *"Tunnel"*) cf_login; ui_pause ;; 
            *"API"*) cf_configure_api_token ;; 
            *"孤儿"*) cf_scan_orphan_dns ;; 
            *"停止"*) cf_stop_all ;; 
            *"卸载"*) 
                if verify_kill_switch; then
                    cf_stop_all
                    safe_rm "$CF_DIR" "$CF_LOG_DIR" "$CF_USER_DATA"
                    ui_print success "模块环境已重置。"
                    
                    if [ "$OS_TYPE" == "TERMUX" ] && command -v cloudflared &>/dev/null; then
                        echo ""
                        if ui_confirm "是否连同系统 Cloudflared 组件一起卸载？"; then
                            sys_remove_pkg "cloudflared"
                        fi
                    fi
                    return 2
                fi ;; 
            *"关于"*) show_module_about_info "${BASH_SOURCE[0]}" ;; 
            *"文档"*) ui_show_doc "$TAVX_DIR/modules/cloudflare/README.md" "Cloudflare 隧道使用文档" ;; 
            *"返回"*) return ;; 
        esac
    done
}
