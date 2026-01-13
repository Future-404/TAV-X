#!/bin/bash
# TAV-X Core: Utilities
[ -n "$_TAVX_UTILS_LOADED" ] && return
_TAVX_UTILS_LOADED=true

if [ -n "$TAVX_DIR" ]; then
    [ -f "$TAVX_DIR/core/env.sh" ] && source "$TAVX_DIR/core/env.sh"
    [ -f "$TAVX_DIR/core/ui.sh" ] && source "$TAVX_DIR/core/ui.sh"
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
            if [[ "$abs_target" == $bad_path ]]; then
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
        # 检查是否禁用统计
        [ -f "$TAVX_DIR/config/no_analytics" ] && return

        local STAT_URL
        # Obfuscated endpoint to prevent automated scanning
        # Part 1: https://tav-api
        local _p1="aHR0cHM6Ly90YXYtYXBp"
        # Part 2: .future404.qzz.io
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

is_port_open() {
    if timeout 0.2 bash -c "</dev/tcp/$1/$2" 2>/dev/null; then return 0; else return 1; fi
}
export -f is_port_open

reset_proxy_cache() {
    unset _PROXY_CACHE_RESULT
}
export -f reset_proxy_cache

get_active_proxy() {
    local mode="${1:-silent}"
    
    if [ -n "$_PROXY_CACHE_RESULT" ] && [ "$mode" == "silent" ]; then
        [ "$_PROXY_CACHE_RESULT" == "NONE" ] && return 1 || { echo "$_PROXY_CACHE_RESULT"; return 0; }
    fi

    local network_conf="$TAVX_DIR/config/network.conf"
    if [ -f "$network_conf" ]; then
        local c=$(cat "$network_conf")
        if [[ "$c" == PROXY* ]]; then
            local val=${c#*|}; val=$(echo "$val"|tr -d '\n\r')
            _PROXY_CACHE_RESULT="$val"; echo "$val"; return 0
        fi
    fi

    if [ -n "$http_proxy" ]; then 
        _PROXY_CACHE_RESULT="$http_proxy"; echo "$http_proxy"; return 0
    fi

    local found_proxies=()
    for entry in "${GLOBAL_PROXY_PORTS[@]}"; do
        local port=${entry%%:*}
        local proto=${entry#*:} 
        if timeout 0.1 bash -c "</dev/tcp/127.0.0.1/$port" 2>/dev/null; then
            local p_url="http://127.0.0.1:$port"
            [[ "$proto" == "socks5" ]] && p_url="socks5://127.0.0.1:$port"
            [[ "$proto" == "socks5h" ]] && p_url="socks5h://127.0.0.1:$port"
            found_proxies+=("$p_url")
        fi
    done
    
    if [ ${#found_proxies[@]} -eq 0 ]; then
        _PROXY_CACHE_RESULT="NONE"; return 1
    fi

    if [ ${#found_proxies[@]} -eq 1 ] || [ "$mode" == "silent" ]; then
        _PROXY_CACHE_RESULT="${found_proxies[0]}"
        echo "${found_proxies[0]}"; return 0
    fi

    ui_print info "检测到多个可能的代理端口:" >&2
    local choice=$(ui_menu "请选择正确的代理地址" "${found_proxies[@]}" "🚫 都不正确 (手动输入)")
    
    if [[ "$choice" == *"手动输入"* ]]; then
        return 1
    else
        _PROXY_CACHE_RESULT="$choice"
        echo "$choice"; return 0
    fi
}

auto_load_proxy_env() {
    local proxy=$(get_active_proxy)
    if [ -n "$proxy" ]; then
        export http_proxy="$proxy"
        export https_proxy="$proxy"
        export all_proxy="$proxy"
        return 0
    else
        unset http_proxy https_proxy all_proxy
        return 1
    fi
}

check_github_speed() {
    local THRESHOLD=819200
    local TEST_URL="https://raw.githubusercontent.com/Future-404/TAV-X/main/core/env.sh"
    echo -e "${CYAN}正在测试 GitHub 直连速度 (阈值: 800KB/s)...${NC}"
    
    local speed=$(curl -s -L -m 5 -w "%{speed_download}\n" -o /dev/null "$TEST_URL" 2>/dev/null)
    speed=$(echo "$speed" | tr -d '\r\n ' | cut -d. -f1)
    [ -z "$speed" ] || [[ ! "$speed" =~ ^[0-9]+$ ]] && speed=0
    
    local speed_kb=$((speed / 1024))
    
    if [ "$speed" -ge "$THRESHOLD" ]; then
        echo -e "${GREEN}✔ 网速达标: ${speed_kb}KB/s${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ 网速不足: ${speed_kb}KB/s (低于 800KB/s)，准备切换镜像源。${NC}"
        return 1
    fi
}

prepare_network_strategy() {
    auto_load_proxy_env
    local proxy_active=$?
    if [ $proxy_active -ne 0 ]; then
        if [ -z "$SELECTED_MIRROR" ]; then
            if check_github_speed;
            then
                return 0
            else
                select_mirror_interactive
            fi
        fi
    fi
}

select_mirror_interactive() {
    if [ "$TAVX_NON_INTERACTIVE" == "true" ]; then
        echo "⚠️  检测到非交互环境，跳过镜像选择，默认使用官方源。"
        SELECTED_MIRROR="https://github.com/"
        return 0
    fi

    reset_proxy_cache
    if [ -n "$SELECTED_MIRROR" ]; then return 0; fi

    ui_header "镜像源测速与选择"
    echo -e "${YELLOW}提示: 测速结果仅代表连接延迟，不代表下载成功率。${NC}"
    echo "----------------------------------------"
    
    local tmp_dir="${TMP_DIR:-$TAVX_DIR}"
    local tmp_race_file="$tmp_dir/.mirror_race"
    rm -f "$tmp_race_file"
    
    local MIRROR_POOL=("${GLOBAL_MIRRORS[@]}")
    if [ ${#MIRROR_POOL[@]} -eq 0 ]; then
        MIRROR_POOL=(
            "https://ghproxy.net/"
            "https://mirror.ghproxy.com/"
            "https://ghproxy.cc/"
            "https://gh.likk.cc/"
            "https://hub.gitmirror.com/"
            "https://hk.gh-proxy.com/"
        )
    fi

    _run_shell_speed_test() {
        local mirrors_str="$1"
        local mirrors=($mirrors_str)
        local tmp_race_file="$2"
        
        for mirror in "${mirrors[@]}"; do
            local start=$(date +%s%N)
            local test_url="${mirror}https://github.com/Future-404/TAV-X/info/refs?service=git-upload-pack"
            echo -n -e "  Testing: ${mirror} ... \r"
            if curl -fsL -A "Mozilla/5.0" -r 0-10 -o /dev/null -m 5 "$test_url" 2>/dev/null;
            then
                local end=$(date +%s%N)
                local dur=$(( (end - start) / 1000000 ))
                echo "$dur|$mirror" >> "$tmp_race_file"
            fi
        done
        echo ""
    }
    export -f _run_shell_speed_test
    local mirrors_flat="${MIRROR_POOL[*]}"
    echo -e "${CYAN}正在并发测速中，请稍候...${NC}"
    _run_shell_speed_test "$mirrors_flat" "$tmp_race_file"
    ui_header "镜像源测速与选择"

    local MENU_OPTIONS=()
    local URL_MAP=()
    if [ -s "$tmp_race_file" ]; then
        sort -n "$tmp_race_file" -o "$tmp_race_file"
        
        while IFS='|' read -r dur url;
        do
            local mark="🟢"
            [ "$dur" -gt 1500 ] && mark="🟡"
            [ "$dur" -gt 3000 ] && mark="🔴"
            local domain=$(echo "$url" | awk -F/ '{print $3}')
            local item="${mark} ${dur}ms | ${domain}"
            MENU_OPTIONS+=("$item")
            URL_MAP+=("$url")
        done < "$tmp_race_file"
    else
        echo -e "${RED}⚠️  所有镜像源测速均超时。${NC}"
    fi

    MENU_OPTIONS+=("🌐 官方源 (直连 GitHub)")
    URL_MAP+=("https://github.com/")
    
    rm -f "$tmp_race_file"
    echo -e "${GREEN}请根据测速结果选择一个节点:${NC}"
    local CHOICE_STR=$(ui_menu "使用方向键选择，回车确认" "${MENU_OPTIONS[@]}")
    for i in "${!MENU_OPTIONS[@]}"; do
        if [[ "${MENU_OPTIONS[$i]}" == "$CHOICE_STR" ]]; then
            SELECTED_MIRROR="${URL_MAP[$i]}"
            break
        fi
    done

    if [ -z "$SELECTED_MIRROR" ]; then
        ui_print warn "未检测到有效选择，默认使用官方源。"
        SELECTED_MIRROR="https://github.com/"
    fi

    echo ""
    ui_print success "已选定: $SELECTED_MIRROR"
    export SELECTED_MIRROR
    return 0
}

_auto_heal_network_config() {
    reset_proxy_cache
    local network_conf="$TAVX_DIR/config/network.conf"
    local need_scan=false
    if [ -f "$network_conf" ]; then
        local c=$(cat "$network_conf")
        if [[ "$c" == PROXY* ]]; then
            local val=${c#*|}; val=$(echo "$val"|tr -d '\n\r')
            local p_port=$(echo "$val"|awk -F':' '{print $NF}')
            local p_host="127.0.0.1"
            [[ "$val" == *"://"* ]] && p_host=$(echo "$val"|sed -e 's|^[^/]*//||' -e 's|:.*$||')
            if ! is_port_open "$p_host" "$p_port"; then need_scan=true; fi
        fi
    else need_scan=true; fi
    
    if [ "$need_scan" == "true" ]; then
        local new_proxy=$(get_active_proxy)
        if [ -n "$new_proxy" ]; then echo "PROXY|$new_proxy" > "$network_conf"; fi
    fi
}

git_clone_smart() {
    local branch_arg=$1
    local repo_input=$2
    local target_dir=$3
    
    if [[ "$repo_input" == "file://"* ]]; then
        git clone $branch_arg "$repo_input" "$target_dir"
        return $?
    fi
    
    local clean_path=${repo_input#*github.com/}
    clean_path=${clean_path#/}
    local official_url="https://github.com/${clean_path}"
    local clone_url="$official_url"
    
    prepare_network_strategy
    auto_load_proxy_env
    local proxy_active=$?
    
    if [ -n "$SELECTED_MIRROR" ] && [ "$SELECTED_MIRROR" == "$_FAILED_MIRROR" ]; then
        unset SELECTED_MIRROR
    fi

    local GIT_CMD="git -c http.proxy=$http_proxy -c https.proxy=$https_proxy clone --progress --depth 1 $branch_arg"

    if [ $proxy_active -ne 0 ] && [ -n "$SELECTED_MIRROR" ]; then
        if [[ "$SELECTED_MIRROR" != *"github.com"* ]]; then
            clone_url="${SELECTED_MIRROR}${official_url}"
            GIT_CMD="git -c http.proxy= -c https.proxy= clone --progress --depth 1 $branch_arg"
        fi
    fi
    
    if ui_stream_task "正在拉取仓库: ${clean_path}" "$GIT_CMD '$clone_url' '$target_dir'"; then
        (
            cd "$target_dir" || exit
            git remote set-url origin "$official_url"
        )
        return 0
    else
        if [ -n "$SELECTED_MIRROR" ] && [[ "$SELECTED_MIRROR" != *"github.com"* ]]; then
            export _FAILED_MIRROR="$SELECTED_MIRROR"
            ui_print warn "镜像节点任务失败，已将其临时屏蔽并尝试回落..."
            unset SELECTED_MIRROR
        fi
        
        ui_print info "正在尝试回落至官方源/代理模式..."
        
        clone_url="$official_url"
        safe_rm "$target_dir"
        
        auto_load_proxy_env
        GIT_CMD="git -c http.proxy=$http_proxy -c https.proxy=$https_proxy clone --progress --depth 1 $branch_arg"
        
        if ui_stream_task "官方源回落下载..." "$GIT_CMD '$clone_url' '$target_dir'"; then
             (cd "$target_dir" || exit; git remote set-url origin "$official_url")
             return 0
        else
             return 1
        fi
    fi
}

export -f git_clone_smart

get_dynamic_repo_url() {
    local repo_input=$1
    if [[ "$repo_input" == "file://"* ]]; then
        echo "$repo_input"
        return
    fi
    
    local clean_path=${repo_input#*github.com/}
    local official_url="https://github.com/${clean_path}"
    
    auto_load_proxy_env
    local proxy_active=$?
    
    if [ $proxy_active -eq 0 ]; then
        echo "$official_url"
        return
    fi
    
    if [ -n "$SELECTED_MIRROR" ] && [[ "$SELECTED_MIRROR" != *"github.com"* ]]; then
        echo "${SELECTED_MIRROR}${official_url}"
    else
        echo "$official_url"
    fi
}
export -f get_dynamic_repo_url

reset_to_official_remote() {
    local dir=$1
    local repo_input=$2
    [ ! -d "$dir/.git" ] && return 1
    
    local clean_path=${repo_input#*github.com/}
    local official_url="https://github.com/${clean_path}"
    (
        cd "$dir" || exit
        git remote set-url origin "$official_url"
    )
}
export -f reset_to_official_remote


download_file_smart() {
    local url=$1; local filename=$2
    local try_mirror=${3:-true}

    auto_load_proxy_env
    local proxy_active=$?

    local base_name=$(basename "$filename")

    if [ $proxy_active -eq 0 ]; then
        if ui_spinner "正在通过代理获取: $base_name" "curl -fsSL -o '$filename' --proxy '$http_proxy' --retry 2 --max-time 300 '$url'"; then return 0; fi
        ui_print warn "代理下载失败，尝试镜像..."
    fi
    
    if [ "$try_mirror" == "true" ] && [[ "$url" == *"github.com"* ]]; then
        if [ -n "$SELECTED_MIRROR" ] && [[ "$SELECTED_MIRROR" != *"github.com"* ]]; then
             local final_url="${SELECTED_MIRROR}${url}"
             if ui_spinner "正在通过镜像获取: $base_name" "curl -fsSL -o '$filename' --noproxy '*' --max-time 300 '$final_url'"; then return 0; fi
             ui_print warn "镜像下载失败，尝试官方直连..."
        fi
    fi
    
    if ui_spinner "正在直连获取: $base_name" "curl -fsSL -o '$filename' --noproxy '*' --retry 2 --max-time 300 '$url'"; then 
        return 0
    else
        ui_print error "文件下载失败: $base_name"
        return 1
    fi
}

npm_install_smart() {
    local target_dir=${1:-.}
    cd "$target_dir" || return 1
    auto_load_proxy_env
    local proxy_active=$?
    local NPM_BASE="npm install --no-audit --no-fund --quiet --production"
    
    if [ $proxy_active -eq 0 ]; then
        npm config delete registry
        if ui_stream_task "NPM 安装..." "env http_proxy='$http_proxy' https_proxy='$https_proxy' $NPM_BASE"; then return 0; fi
    fi
    
    npm config set registry "https://registry.npmmirror.com"
    if ui_stream_task "NPM 安装中 (淘宝源)..." "$NPM_BASE"; then
        npm config delete registry; return 0
    else
        ui_print error "依赖安装失败。"; npm config delete registry; return 1
    fi
}
export -f npm_install_smart

check_process_smart() {
    local pid_file="$1"
    local pattern="$2"

    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null;
        then
            return 0
        fi
        rm -f "$pid_file"
    fi

    if [ -z "$pattern" ]; then return 1; fi

    local real_pid=$(pgrep -f "$pattern" | grep -v "pgrep" | head -n 1)
    
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
        local pid=$(cat "$pid_file")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            local cmdline=$(get_process_cmdline "$pid")
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
        gum style --border double --border-foreground 196 --padding "0 1" --foreground 220 "$TARGET_PHRASE"
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
get_modules_status_line() {
    local running_apps=()
    local run_dir="$TAVX_DIR/run"
    if [ ! -d "$run_dir" ]; then return; fi
    
    for pid_file in "$run_dir"/*.pid; do
        [ ! -f "$pid_file" ] && continue
        local name=$(basename "$pid_file" .pid)
        # 排除系统级/监控级进程
        if [[ "$name" == "cf_manager" || "$name" == "audio_heartbeat" || "$name" == "cloudflare_monitor" ]]; then 
            continue
        fi
        
        local pid=$(cat "$pid_file")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then 
            running_apps+=("$name")
        fi
    done
    
    local count=${#running_apps[@]}
    if [ $count -eq 0 ]; then
        echo ""
    elif [ $count -eq 1 ]; then
        echo -e "${GREEN}● ${NC}${running_apps[0]}"
    else
        echo -e "${GREEN}● ${NC}${running_apps[0]} 等 ${count} 个应用正在运行"
    fi
}

ensure_backup_dir() {
    local backup_path=""
    if [ "$OS_TYPE" == "TERMUX" ]; then
        if [ ! -d "$HOME/storage/downloads" ]; then
            ui_print warn "备份需要访问外部存储权限。"
            termux-setup-storage
            sleep 3
            if [ ! -d "$HOME/storage/downloads" ]; then
                ui_print error "获取存储权限失败。请授权后重试。"
                return 1
            fi
        fi
        backup_path="$HOME/storage/downloads/TAVX_Backup"
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

export -f sys_install_pkg
export -f sys_remove_pkg

get_sys_resources_info() {
    local mem_info=$(free -m | grep Mem)
    local mem_total=$(echo "$mem_info" | awk '{print $2}')
    local mem_used=$(echo "$mem_info" | awk '{print $3}')
    local mem_pct=0
    [ -n "$mem_total" ] && [ "$mem_total" -gt 0 ] && mem_pct=$(( mem_used * 100 / mem_total ))
    
    echo "${mem_pct}%"
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

export -f download_file_smart
export -f get_dynamic_repo_url
stop_all_services_routine() {
    ui_print info "正在停止所有服务..."
    
    local run_dir="$TAVX_DIR/run"
    if [ -d "$run_dir" ]; then
        for pid_file in "$run_dir"/*.pid; do
            [ ! -f "$pid_file" ] && continue
            
            local pid=$(cat "$pid_file")
            local name=$(basename "$pid_file" .pid)
            
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

