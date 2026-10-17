#!/bin/bash
# TAV-X Core: Utilities
[ -n "$_TAVX_UTILS_LOADED" ] && return
_TAVX_UTILS_LOADED=true

if [ -n "$TAVX_DIR" ]; then
    [ -f "$TAVX_DIR/core/env.sh" ] && source "$TAVX_DIR/core/env.sh"
    [ -f "$TAVX_DIR/core/ui.sh" ] && source "$TAVX_DIR/core/ui.sh"
    [ -f "$TAVX_DIR/core/net_utils.sh" ] && source "$TAVX_DIR/core/net_utils.sh"
fi

safe_rm() {
    for target in "$@"; do
        if [ -z "$target" ]; then
            echo "❌ [安全拦截] 目标路径为空，已跳过" >&2
            continue
        fi

        local abs_target
        if command -v realpath &> /dev/null; then
            abs_target=$(realpath -m "$target")
        else
            abs_target="$target"
            [[ "$abs_target" != /* ]] && abs_target="$PWD/$target"
        fi

        local BLACKLIST=(
            "/" 
            "$HOME" 
            "/usr" "/usr/*" 
            "/bin" "/bin/*" 
            "/sbin" "/sbin/*" 
            "/etc" "/etc/*" 
            "/var" 
            "/sys" "/proc" "/dev" "/run" "/boot"
            "/data/data/com.termux/files"
            "/data/data/com.termux/files/home"
            "/data/data/com.termux/files/usr"
            "$TAVX_DIR"
            "$TAVX_DIR/modules"
            "$TAVX_DIR/apps"
            "$TAVX_DIR/core"
            "$HOME/tav_apps"
            "$APPS_DIR"
        )

        local is_bad=false
        for bad_path in "${BLACKLIST[@]}"; do
            if [[ "$abs_target" == "$bad_path" ]]; then
                echo "❌ [安全拦截] 禁止删除关键系统目录: $abs_target" >&2
                is_bad=true
                break
            fi
        done
        [ "$is_bad" = true ] && continue

        if [[ "$target" == "." ]] || [[ "$target" == ".." ]] || [[ "$target" == "./" ]] || [[ "$target" == "../" ]]; then
            echo "❌ [安全拦截] 禁止删除当前/上级目录引用: $target" >&2
            continue
        fi

        if [ -n "$abs_target" ] && [[ "$PWD" == "$abs_target"* ]]; then
            cd "$HOME" 2>/dev/null || cd "/"
        fi

        if [ -e "$target" ] || [ -L "$target" ]; then
            rm -rf "$target"
        fi
    done
}
export -f safe_rm

pause() { echo ""; read -n 1 -s -r -p "按任意键继续..."; echo ""; }

open_browser() {
    local url=$1
    if [ "$OS_TYPE" == "TERMUX" ]; then
        command -v termux-open &>/dev/null && termux-open "$url"
    else
        if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
            if command -v xdg-open &>/dev/null; then 
                xdg-open "$url" >/dev/null 2>&1
                return
            elif command -v python3 &>/dev/null; then 
                python3 -m webbrowser "$url" >/dev/null 2>&1
                return
            fi
        fi
        echo ""
        echo -e "${YELLOW}>>> 请在浏览器中访问以下链接:${NC}"
        echo -e "${CYAN}$url${NC}"
        echo ""
    fi
}

send_analytics() {
    (
        [ -f "$TAVX_DIR/config/no_analytics" ] && return

        local STAT_URL
        local _p1="aHR0cHM6Ly90YXYtYXBp"
        local _p2="LmZ1dHVyZTQwNC5xenouaW8="
        
        if command -v base64 &> /dev/null; then
            STAT_URL=$(echo "${_p1}${_p2}" | base64 -d 2>/dev/null)
        else
            return
        fi

        if command -v curl &> /dev/null;
        then
            curl -s -m 5 "${STAT_URL}?ver=${CURRENT_VERSION}&type=runtime&os=${OS_TYPE}" > /dev/null 2>&1
        fi
    ) &
}

safe_log_monitor() {
    local file=$1
    if [ ! -f "$file" ]; then
        ui_print warn "日志文件尚未生成: $(basename "$file")"
        ui_pause; return
    fi

    if command -v less &>/dev/null; then
        echo -e "${YELLOW}💡 提示: 按 ${CYAN}q${YELLOW} 退出，按 ${CYAN}Ctrl+C${YELLOW} 暂停滚动，暂停后按 ${CYAN}F${YELLOW} 恢复${NC}"
        sleep 1
        less -R -S +F "$file"
    else
        ui_header "实时日志预览"
        echo -e "${YELLOW}提示: 当前系统缺少 less，仅支持 Ctrl+C 退出${NC}"
        echo "----------------------------------------"
        trap 'echo -e "\n${GREEN}>>> 已停止监控${NC}"' SIGINT
        tail -n 50 -f "$file"
        trap - SIGINT
        sleep 0.5
    fi
}
export -f safe_log_monitor

check_process_smart() {
    local pid_file="$1"
    local pattern="$2"

    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null;
        then
            return 0
        fi
        rm -f "$pid_file"
    fi

    if [ -z "$pattern" ]; then return 1; fi

    local real_pid
    real_pid=$(pgrep -f "$pattern" | grep -v "pgrep" | head -n 1)
    
    if [ -n "$real_pid" ]; then
        echo "$real_pid" > "$pid_file"
        return 0
    fi

    return 1
}
export -f check_process_smart

escape_for_sed() {
    local raw="$1"
    local safe="${raw//\\/\\\\}"
    safe="${safe//\//\\/}"
    safe="${safe//&/\&}"
    echo "$safe"
}
export -f escape_for_sed

write_env_safe() {
    local file="$1"
    local key="$2"
    local val="$3"
    
    if [ ! -f "$file" ]; then touch "$file"; fi
    
    local safe_val=$(escape_for_sed "$val")
    if grep -q "^$key=" "$file"; then
        sed -i "s/^$key=.*/$key=$safe_val/" "$file"
    else
        echo "$key=$val" >> "$file"
    fi
}
export -f write_env_safe

get_process_cmdline() {
    local pid=$1
    if [ -f "/proc/$pid/cmdline" ]; then
        tr "\0" " " < "/proc/$pid/cmdline"
    else
        echo ""
    fi
}
export -f get_process_cmdline

kill_process_safe() {
    local pid_file="$1"
    local pattern="$2"
    
    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            local cmdline
            cmdline=$(get_process_cmdline "$pid")
            if [[ "$cmdline" =~ $pattern ]]; then
                kill -9 "$pid" >/dev/null 2>&1
            fi
        fi
        rm -f "$pid_file"
    fi
    
    if [ -n "$pattern" ]; then
        pkill -9 -f "$pattern" >/dev/null 2>&1
    fi
}
export -f kill_process_safe

verify_kill_switch() {
    local TARGET_PHRASE="我已知此操作风险并且已做好备份"
    
    ui_header "⚠️ 高危操作安全确认"
    echo -e "${RED}警告：此操作不可逆！数据将永久丢失！${NC}"
    echo -e "为了确认是您本人操作，请准确输入以下文字："
    echo ""
    if [ "$HAS_GUM" = true ]; then
        "$GUM_BIN" style --border double --border-foreground 196 --padding "0 1" --foreground 220 "$TARGET_PHRASE"
    else
        echo ">>> $TARGET_PHRASE"
    fi
    echo ""
    
    local input=$(ui_input "在此输入确认语" "" "false")
    
    if [ "$input" == "$TARGET_PHRASE" ]; then
        return 0
    else
        ui_print error "验证失败！文字不匹配，操作已取消。"
        ui_pause
        return 1
    fi
}
export -f verify_kill_switch

get_modules_status_line() {
    local running_apps=()
    local run_dir="$TAVX_DIR/run"
    if [ ! -d "$run_dir" ]; then return; fi
    
    for pid_file in "$run_dir"/*.pid; do
        [ ! -f "$pid_file" ] && continue
        local name="${pid_file##*/}"
        name="${name%.pid}"
        if [[ "$name" == "cf_manager" || "$name" == "audio_heartbeat" || "$name" == "cloudflare_monitor" ]]; then 
            continue
        fi
        
        local pid
        read -r pid < "$pid_file" 2>/dev/null
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then 
            running_apps+=("$name")
        fi
    done
    
    local count=${#running_apps[@]}
    if [ "$count" -eq 0 ]; then
        echo ""
    elif [ "$count" -eq 1 ]; then
        echo -e "${GREEN}● ${NC}${running_apps[0]}"
    else
        echo -e "${GREEN}● ${NC}${running_apps[0]} 等 ${count} 个应用正在运行"
    fi
}
export -f get_modules_status_line

check_storage_permission() {
    [ -d "$HOME/storage/downloads" ] && ls "$HOME/storage/downloads" >/dev/null 2>&1 && return 0
    ls /sdcard/Download >/dev/null 2>&1 && return 0
    ls /storage/emulated/0/Download >/dev/null 2>&1 && return 0
    return 1
}
export -f check_storage_permission

ensure_storage_permission() {
    if [ "$OS_TYPE" == "TERMUX" ]; then
        if ! check_storage_permission; then
            if command -v termux-setup-storage >/dev/null 2>&1; then
                ui_print warn "访问手机存储目录需要系统授权。"
                ui_print info "正在请求系统存储权限，请在弹出的系统对话框中点击【允许】..."
                termux-setup-storage
                local wait_cnt=0
                while [ $wait_cnt -lt 5 ]; do
                    if check_storage_permission; then
                        break
                    fi
                    sleep 1
                    wait_cnt=$((wait_cnt + 1))
                done
                if check_storage_permission; then
                    ui_print success "存储权限已就绪！"
                    return 0
                else
                    ui_print warn "未能自动检测到权限。若弹窗未弹出，请前往手机【系统设置 -> 应用管理 -> Termux -> 权限】手动开启存储权限。"
                    return 1
                fi
            fi
        fi
    fi
    return 0
}
export -f ensure_storage_permission

# DNS 会话级检测与自动修复
# 逻辑：检查 flag 文件 → 跳过（已检查）/ 探测 DNS → 失败则修复 resolv.conf → 再测 → 还失败提示代理
ensure_dns_resolution() {
    local flag_file="/tmp/tavx_dns_ok"
    local resolv_conf="$PREFIX/etc/resolv.conf"

    # 会话级缓存：已经检测过就直接跳过
    [ -f "$flag_file" ] && return 0

    # 仅在 Termux 环境下执行
    [ "$OS_TYPE" != "TERMUX" ] && touch "$flag_file" && return 0

    # 轻量 DNS + 连通性探测（超时 4 秒）
    _dns_probe() {
        curl -s --connect-timeout 4 -o /dev/null -w "%{http_code}" \
            "https://www.google.com" 2>/dev/null | grep -q "[2-3][0-9][0-9]"
    }

    if _dns_probe; then
        touch "$flag_file"
        return 0
    fi

    # 探测失败 → 检查 resolv.conf 是否为空或只有 IPv6 回环
    local needs_fix=false
    if [ ! -s "$resolv_conf" ]; then
        needs_fix=true
    elif ! grep -qE "^nameserver[[:space:]]+[0-9]" "$resolv_conf" 2>/dev/null; then
        needs_fix=true
    fi

    if [ "$needs_fix" = true ]; then
        ui_print warn "🔧 检测到 Termux DNS 配置缺失，正在自动修复..."

        # 备份原文件
        cp "$resolv_conf" "${resolv_conf}.tavx.bak" 2>/dev/null

        # 智能选择 DNS：优先检查是否有本地代理在监听 53 端口
        local chosen_dns="8.8.8.8 8.8.4.4"
        if timeout 0.3 bash -c "</dev/tcp/127.0.0.1/53" 2>/dev/null; then
            chosen_dns="127.0.0.1"
            ui_print info "检测到本地 DNS 代理 (127.0.0.1:53)，优先使用。"
        fi

        {
            echo "# Auto-generated by TAV-X ensure_dns_resolution at $(date)"
            for ns in $chosen_dns; do
                echo "nameserver $ns"
            done
        } > "$resolv_conf"

        # 修复后再探测一次
        if _dns_probe; then
            ui_print success "✔ DNS 修复成功！网络已就绪。"
            touch "$flag_file"
            return 0
        else
            # 修复无效，恢复备份
            cp "${resolv_conf}.tavx.bak" "$resolv_conf" 2>/dev/null
        fi
    fi

    # DNS/resolv.conf 正常，但 Google 仍不可达 → 提示配置代理
    ui_print warn "⚠️  无法连接到 Google（DNS 可用但网络受限）"
    ui_print info "提示：若使用代理工具（Clash / Sing-Box），请确认已开启；"
    ui_print info "      并在「⚙️ 系统设置 → 下载网络配置」中配置代理端口。"
    # 不阻塞启动，仅提示，写入 flag 避免每次都弹
    touch "$flag_file"
    return 0
}
export -f ensure_dns_resolution

ensure_backup_dir() {
    local backup_path=""
    if [ "$OS_TYPE" == "TERMUX" ]; then
        if ! ensure_storage_permission; then
            ui_print error "获取存储权限失败。请授权后重试。"
            return 1
        fi
        backup_path="$HOME/storage/downloads/TAVX_Backup"
        if [ ! -d "$HOME/storage/downloads" ] && [ -d "/sdcard/Download" ]; then
            backup_path="/sdcard/Download/TAVX_Backup"
        fi
    else
        backup_path="$HOME/TAVX_Backup"
    fi
    if [ ! -d "$backup_path" ]; then
        if ! mkdir -p "$backup_path"; then ui_print error "无法创建备份目录: $backup_path"; return 1; fi
    fi
    if [ ! -w "$backup_path" ]; then ui_print error "目录不可写: $backup_path"; return 1; fi
    echo "$backup_path"
    return 0
}
export -f ensure_backup_dir

sys_install_pkg() {
    local pkgs="$*"
    [ -z "$pkgs" ] && return 0
    
    local cmd=""
    if [ "$OS_TYPE" == "TERMUX" ]; then
        cmd="env DEBIAN_FRONTEND=noninteractive pkg install -y -o Dpkg::Use-Pty=0 $pkgs"
    else
        cmd="env DEBIAN_FRONTEND=noninteractive $SUDO_CMD apt-get update -q && env DEBIAN_FRONTEND=noninteractive $SUDO_CMD apt-get install -y -q -o Dpkg::Use-Pty=0 $pkgs"
    fi
    
    if ui_stream_task "系统组件同步: $pkgs" "$cmd"; then
        return 0
    else
        ui_print error "包安装失败: $pkgs"
        return 1
    fi
}
export -f sys_install_pkg

sys_remove_pkg() {
    local pkgs="$*"
    [ -z "$pkgs" ] && return 0
    
    local cmd=""
    if [ "$OS_TYPE" == "TERMUX" ]; then
        cmd="env DEBIAN_FRONTEND=noninteractive pkg uninstall -y -o Dpkg::Use-Pty=0 $pkgs"
    else
        cmd="env DEBIAN_FRONTEND=noninteractive $SUDO_CMD apt-get remove -y -q -o Dpkg::Use-Pty=0 $pkgs"
    fi
    
    ui_stream_task "移除系统组件: $pkgs" "$cmd"
}
export -f sys_remove_pkg

get_sys_resources_info() {
    local total=0 avail=0 key val _
    if [ -r /proc/meminfo ]; then
        while read -r key val _; do
            case "$key" in
                MemTotal:) total=$val ;;
                MemAvailable:) avail=$val; break ;;
            esac
        done < /proc/meminfo
        if [ "$total" -gt 0 ]; then
            local used=$((total - avail))
            echo "$(( used * 100 / total )) %"
            return
        fi
    fi
    echo "0 %"
}
export -f get_sys_resources_info

get_app_path() {
    local id="$1"
    
    if [ "$id" == "sillytavern" ]; then
        echo "$HOME/SillyTavern"
        return
    fi

    if [ "$id" == "aistudio" ]; then
        local st_path=$(get_app_path "sillytavern")
        local ai_path="$st_path/public/scripts/extensions/third-party/AIStudioBuildProxy"
        if [ -d "$ai_path" ]; then
            echo "$ai_path"
            return
        fi
    fi
    
    local new_path="${APPS_DIR:-$HOME/tav_apps}/$id"
    echo "$new_path"
}
export -f get_app_path

is_dir_nonempty() {
    local d="$1"
    [ ! -d "$d" ] && return 1
    local f=("$d"/* "$d"/.[!.]* "$d"/..?*)
    [ -e "${f[0]}" ] && return 0
    return 1
}
export -f is_dir_nonempty

tavx_service_register() {
    local name="$1"
    local run_cmd="$2"
    local work_dir="$3"
    
    if [ "$OS_TYPE" == "TERMUX" ]; then
        local sv_dir="$PREFIX/var/service/$name"
        mkdir -p "$sv_dir/log"
        
        touch "$sv_dir/.tavx_managed"
        
        cat > "$sv_dir/run" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
exec 2>&1
cd "$work_dir" || exit 1
exec $run_cmd
EOF
        chmod +x "$sv_dir/run"
        
        cat > "$sv_dir/log/run" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
exec svlogd .
EOF
        chmod +x "$sv_dir/log/run"
        
        ui_print success "服务已注册: $name"
    else
        ui_print warn "Linux 环境暂不支持自动注册系统服务，将使用传统模式运行。"
    fi
}
export -f tavx_service_register

tavx_service_control() {
    local action="$1"
    local name="$2"
    local flags="$3"
    
    if [ "$OS_TYPE" == "TERMUX" ]; then
        local sv_dir="$PREFIX/var/service/$name"
        if [ "$action" != "status" ] && [ -d "$sv_dir" ] && [ ! -e "$sv_dir/supervise/ok" ]; then
            local wait_count=0
            while [ ! -e "$sv_dir/supervise/ok" ] && [ $wait_count -lt 6 ]; do
                sleep 0.5
                ((wait_count++))
            done
        fi

        if [ "$action" == "status" ]; then
            sv status "$name"
        else
            sv $flags "$action" "$name" 2>/dev/null || sv $flags "$action" "$name" 2>/dev/null
        fi
    else
        ui_print error "当前环境不支持 sv 服务控制。"
        return 1
    fi
}
export -f tavx_service_control

tavx_service_remove() {
    local name="$1"
    if [ "$OS_TYPE" == "TERMUX" ]; then
        if [ -d "$PREFIX/var/service/$name" ]; then
            sv down "$name" >/dev/null 2>&1
            rm -rf "$PREFIX/var/service/$name"
            ui_print success "服务已移除: $name"
        fi
    fi
}
export -f tavx_service_remove

is_app_running() {
    local id="$1"
    
    if [ "$OS_TYPE" == "TERMUX" ]; then
        if [ -d "$PREFIX/var/service/$id" ]; then
            if sv status "$id" 2>/dev/null | grep -q "^run:"; then return 0; fi
        fi
        
        if [[ "$id" == "cloudflare" || "$id" == "cliproxyapi" ]]; then
            local pattern="cloudflared"
            [ "$id" == "cliproxyapi" ] && pattern="cli-proxy-api"
            pgrep -f "$pattern" >/dev/null 2>&1 && return 0
            return 1
        fi
        
        local pid_file="$TAVX_DIR/run/${id}.pid"
        if [ -f "$pid_file" ] && [ -s "$pid_file" ]; then
            local pid
            read -r pid < "$pid_file" 2>/dev/null
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then return 0; fi
        fi
        
        return 1
    else
        local pid_file="$TAVX_DIR/run/${id}.pid"
        if [ "$id" == "cloudflare" ]; then
             pgrep -f "cloudflared" >/dev/null 2>&1 && return 0
        fi
        
        if [ -f "$pid_file" ] && [ -s "$pid_file" ]; then
            local pid
            read -r pid < "$pid_file" 2>/dev/null
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then return 0; fi
        fi
        return 1
    fi
}
export -f is_app_running

stop_all_services_routine() {
    ui_print info "正在停止所有服务..."
    
    if [ "$OS_TYPE" == "TERMUX" ] && command -v sv &>/dev/null; then
        local sv_base="$PREFIX/var/service"
        if [ -d "$sv_base" ]; then
            for s in "$sv_base"/*;
            do
                [ ! -d "$s" ] && continue
                if [ -f "$s/.tavx_managed" ]; then
                    local sname=$(basename "$s")
                    # 使用 force-stop 配合 2秒超时，防止 Proot 等顽固进程卡死
                    sv -w 2 force-stop "$sname" 2>/dev/null
                    ui_print success "已停止服务: $sname"
                fi
            done
        fi
    fi

    local run_dir="$TAVX_DIR/run"
    if [ -d "$run_dir" ]; then
        for pid_file in "$run_dir"/*.pid; do
            [ ! -f "$pid_file" ] && continue
            
            local pid
            pid=$(cat "$pid_file")
            local name
            name=$(basename "$pid_file" .pid)
            
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                kill -15 "$pid" 2>/dev/null
                sleep 0.5
                if kill -0 "$pid" 2>/dev/null; then
                    kill -9 "$pid" 2>/dev/null
                    ui_print warn "强制停止: $name ($pid)"
                else
                    ui_print success "已停止: $name"
                fi
            fi
            rm -f "$pid_file"
        done
    fi
    
    if command -v termux-wake-unlock &> /dev/null; then termux-wake-unlock >/dev/null 2>&1; fi
    rm -f "$TAVX_DIR/.temp_link"
}
export -f stop_all_services_routine

show_module_about_info() {
    local module_file="$1"
    if [ ! -f "$module_file" ]; then
        ui_print error "无法找到模块信息文件。"
        ui_pause
        return
    fi

    local name
    name=$(grep "# MODULE_NAME:" "$module_file" | head -n 1 | cut -d: -f2- | xargs)
    local author
    author=$(grep "# APP_AUTHOR:" "$module_file" | head -n 1 | cut -d: -f2- | xargs)
    local url
    url=$(grep "# APP_PROJECT_URL:" "$module_file" | head -n 1 | cut -d: -f2- | xargs)
    local desc
    desc=$(grep "# APP_DESC:" "$module_file" | head -n 1 | cut -d: -f2- | xargs)

    ui_header "关于: ${name:-未知模块}"

    if [ -z "$author" ] && [ -z "$url" ]; then
        ui_print warn "该模块未提供作者或项目信息。"
        ui_pause
        return
    fi
    
    if [ "$HAS_GUM" = true ]; then
        echo ""
        [ -n "$desc" ] && "$GUM_BIN" style --foreground 250 --padding "0 2" "• $desc" && echo ""
        local label_style="$GUM_BIN style --foreground 99 --width 10"
        local value_style="$GUM_BIN style --foreground 255"
        [ -n "$author" ] && echo -e "  $(echo "作者:" | $label_style)  $($value_style "$author")"
        [ -n "$url" ] && echo -e "  $(echo "项目:" | $label_style)  $($value_style "$url")"
        echo ""
        if [ -n "$url" ]; then
            if "$GUM_BIN" confirm "在浏览器中打开项目地址？"; then
                open_browser "$url"
            fi
        else
            ui_pause
        fi
    else
        echo ""
        [ -n "$desc" ] && echo -e "${YELLOW}描述:${NC}  $desc\n"
        [ -n "$author" ] && echo -e "${YELLOW}作者:${NC}  ${CYAN}$author${NC}"
        [ -n "$url" ] && echo -e "${YELLOW}项目:${NC}  ${BLUE}$url${NC}"
        echo ""
        if [ -n "$url" ]; then
            if ui_confirm "在浏览器中打开项目地址？"; then
                open_browser "$url"
            fi
        else
            ui_pause
        fi
    fi
}
export -f show_module_about_info
