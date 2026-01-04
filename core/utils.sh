#!/bin/bash
# TAV-X Core: Utilities
[ -n "$_TAVX_UTILS_LOADED" ] && return
_TAVX_UTILS_LOADED=true

if [ -n "$TAVX_DIR" ]; then
    [ -f "$TAVX_DIR/core/env.sh" ] && source "$TAVX_DIR/core/env.sh"
    [ -f "$TAVX_DIR/core/ui.sh" ] && source "$TAVX_DIR/core/ui.sh"
fi

safe_rm() {
    local target="$1"
    
    if [ -z "$target" ]; then
        echo "❌ [安全拦截] 目标路径为空" >&2
        return 1
    fi

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
    )

    for bad_path in "${BLACKLIST[@]}"; do
        if [[ "$abs_target" == $bad_path ]]; then
            echo "❌ [安全拦截] 禁止删除关键系统目录: $abs_target" >&2
            return 1
        fi
    done

    if [[ "$target" == "." ]] || [[ "$target" == ".." ]] || [[ "$target" == "./" ]] || [[ "$target" == "../" ]]; then
        echo "❌ [安全拦截] 禁止删除当前/上级目录引用！" >&2
        return 1
    fi

    if [ -e "$target" ]; then
        rm -rf "$target"
    fi
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
        local STAT_URL="https://tav-api.future404.qzz.io"
        if command -v curl &> /dev/null;
        then
            curl -s -m 5 "${STAT_URL}?ver=${CURRENT_VERSION}&type=runtime&os=${OS_TYPE}" > /dev/null 2>&1
        fi
    ) &
}

safe_log_monitor() {
    local file=$1
    if [ ! -f "$file" ]; then touch "$file"; fi
    clear
    echo -e "${CYAN}=== 正在实时监控日志 ===${NC}"
    echo -e "${YELLOW}提示: 按 Ctrl+C 即可停止监控并返回菜单${NC}"
    echo "----------------------------------------"
    
    trap 'echo -e "\n${GREEN}>>> 已停止监控，正在返回...${NC}"' SIGINT
    tail -n 30 -f "$file"
    trap - SIGINT
    sleep 0.5
}

is_port_open() {
    if timeout 0.2 bash -c "</dev/tcp/$1/$2" 2>/dev/null; then return 0; else return 1; fi
}

reset_proxy_cache() {
    unset _PROXY_CACHE_RESULT
}

get_active_proxy() {
    if [ -n "$_PROXY_CACHE_RESULT" ]; then
        if [ "$_PROXY_CACHE_RESULT" == "NONE" ]; then
            return 1
        else
            echo "$_PROXY_CACHE_RESULT"
            return 0
        fi
    fi

    local network_conf="$TAVX_DIR/config/network.conf"
    if [ -f "$network_conf" ]; then
        local c=$(cat "$network_conf")
        if [[ "$c" == PROXY* ]]; then
            local val=${c#*|}; val=$(echo "$val"|tr -d '\n\r')
            _PROXY_CACHE_RESULT="$val"
            echo "$val"; return 0
        fi
    fi

    if [ -n "$http_proxy" ]; then 
        _PROXY_CACHE_RESULT="$http_proxy"
        echo "$http_proxy"; return 0
    fi
    if [ -n "$https_proxy" ]; then 
        _PROXY_CACHE_RESULT="$https_proxy"
        echo "$https_proxy"; return 0
    fi

    for entry in "${GLOBAL_PROXY_PORTS[@]}"; do
        local port=${entry%%:*}
        local proto=${entry#*:}
        if timeout 0.1 bash -c "</dev/tcp/127.0.0.1/$port" 2>/dev/null;
        then
            local result=""
            if [[ "$proto" == "socks5h" ]]; then 
                result="socks5h://127.0.0.1:$port"
            else 
                result="http://127.0.0.1:$port"
            fi
            
            _PROXY_CACHE_RESULT="$result"
            echo "$result"; return 0
        fi
    done
    
    _PROXY_CACHE_RESULT="NONE"
    return 1
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
    
    local speed=$(curl -s -L -m 5 -w "% {speed_download}\n" -o /dev/null "$TEST_URL" 2>/dev/null)
    speed=${speed%.*}
    [ -z "$speed" ] && speed=0
    
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
    reset_proxy_cache
    if [ -n "$SELECTED_MIRROR" ]; then return 0; fi

    ui_header "镜像源测速与选择"
    echo -e "${YELLOW}提示: 测速结果仅代表连接延迟，不代表下载成功率。${NC}"
    echo -e "${CYAN}正在并发测速中，请稍候...${NC}"
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
    
    for mirror in "${MIRROR_POOL[@]}"; do
        (
            local start=$(date +%s%N)
            local test_url="${mirror}https://github.com/Future-404/TAV-X/info/refs?service=git-upload-pack"
            if curl -s -I -m 2 "$test_url" >/dev/null 2>&1;
            then
                local end=$(date +%s%N)
                local dur=$(( (end - start) / 1000000 ))
                echo "$dur|$mirror" >> "$tmp_race_file"
            fi
        ) &
    done
    wait

    local MENU_OPTIONS=()
    local URL_MAP=()
    if [ -s "$tmp_race_file" ]; then
        sort -n "$tmp_race_file" -o "$tmp_race_file"
        
        while IFS='|' read -r dur url;
        do
            local mark="🟢"
            [ "$dur" -gt 800 ] && mark="🟡"
            [ "$dur" -gt 1500 ] && mark="🔴"
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
    
    local clean_path=${repo_input#*github.com/}
    local official_url="https://github.com/${clean_path}"
    local clone_url="$official_url"
    
    local tmp_base="${TMPDIR:-/tmp}"
    [ ! -w "$tmp_base" ] && tmp_base="/data/data/com.termux/files/usr/tmp"
    local err_log="${tmp_base}/tavx_git_error.log"
    : > "$err_log"
    
    prepare_network_strategy
    auto_load_proxy_env
    local proxy_active=$?
    
    local GIT_CMD="git -c http.proxy=$http_proxy -c https.proxy=$https_proxy clone --depth 1 $branch_arg"

    if [ $proxy_active -ne 0 ] && [ -n "$SELECTED_MIRROR" ]; then
        if [[ "$SELECTED_MIRROR" != *"github.com"* ]]; then
            clone_url="${SELECTED_MIRROR}${official_url}"
            GIT_CMD="git -c http.proxy= -c https.proxy= clone --depth 1 $branch_arg"
        fi
    fi
    
    if $GIT_CMD "$clone_url" "$target_dir" >> "$err_log" 2>&1; then
        (
            cd "$target_dir" || exit
            git remote set-url origin "$official_url"
        )
        return 0
    else
        echo -e "\n\n>>> 镜像/首选策略下载失败，尝试回落至官方源... \n" >> "$err_log"
        
        clone_url="$official_url"
        rm -rf "$target_dir"
        
        auto_load_proxy_env
        GIT_CMD="git -c http.proxy=$http_proxy -c https.proxy=$https_proxy clone --depth 1 $branch_arg"
        
        if $GIT_CMD "$clone_url" "$target_dir" >> "$err_log" 2>&1; then
             (cd "$target_dir" || exit; git remote set-url origin "$official_url")
             return 0
        else
             if [ -n "$TAVX_LOG_FILE" ]; then
                 echo "--- GIT ERROR DETAILS ---" >> "$TAVX_LOG_FILE"
                 cat "$err_log" >> "$TAVX_LOG_FILE"
                 echo "-------------------------" >> "$TAVX_LOG_FILE"
             fi
             
             echo -e "${YELLOW}=== 下载失败日志 (Last 20 lines) ===${NC}"
             tail -n 20 "$err_log"
             echo -e "${YELLOW}====================================${NC}"
             sleep 3
             return 1
        fi
    fi
}

get_dynamic_repo_url() {
    local repo_input=$1
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

download_file_smart() {
    local url=$1; local filename=$2
    local try_mirror=${3:-true}
    local tmp_base="${TMPDIR:-/tmp}"
    [ ! -w "$tmp_base" ] && tmp_base="/data/data/com.termux/files/usr/tmp"
    local err_log="${tmp_base}/tavx_curl_error.log"
    : > "$err_log"

    auto_load_proxy_env
    local proxy_active=$?

    if [ $proxy_active -eq 0 ]; then
        if curl -f -L -o "$filename" --proxy "$http_proxy" --retry 2 --max-time 60 "$url" 2>>"$err_log"; then return 0; fi
        echo ">>> 代理下载失败，尝试镜像..." >> "$err_log"
    fi
    
    if [ "$try_mirror" == "true" ] && [[ "$url" == *"github.com"* ]]; then
        if [ -n "$SELECTED_MIRROR" ] && [[ "$SELECTED_MIRROR" != *"github.com"* ]]; then
             local final_url="${SELECTED_MIRROR}${url}"
             if curl -f -L -o "$filename" --noproxy "*" --max-time 60 "$final_url" 2>>"$err_log"; then return 0; fi
             echo ">>> 镜像下载失败，尝试官方直连..." >> "$err_log"
        fi
    fi
    
    if curl -f -L -o "$filename" --noproxy "*" --retry 2 --max-time 60 "$url" 2>>"$err_log"; then 
        return 0
    else
        if [ -n "$TAVX_LOG_FILE" ]; then
             echo "--- CURL ERROR DETAILS ---" >> "$TAVX_LOG_FILE"
             cat "$err_log" >> "$TAVX_LOG_FILE"
             echo "--------------------------" >> "$TAVX_LOG_FILE"
        fi
        
        ui_print error "文件下载失败: $(basename "$filename")"
        echo -e "${YELLOW}=== CURL 错误日志 ===${NC}" >&2
        tail -n 5 "$err_log" >&2
        sleep 3
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
        if ui_spinner "NPM 安装 (代理加速)..." "env http_proxy='$http_proxy' https_proxy='$https_proxy' $NPM_BASE"; then return 0; fi
    fi
    
    npm config set registry "https://registry.npmmirror.com"
    if ui_spinner "NPM 安装中 (淘宝源)..." "$NPM_BASE"; then
        npm config delete registry; return 0
    else
        ui_print error "依赖安装失败。"; npm config delete registry; return 1
    fi
}

JS_TOOL="$TAVX_DIR/scripts/config_mgr.js"
config_get() {
    local key=$1
    local file="${INSTALL_DIR}/config.yaml"
    
    if [ -f "$file" ]; then
        if [[ "$key" == *"."* ]]; then
            local parent=${key%%.*}
            local child=${key#*.}
            
            local val=$(sed -n "/^[[:space:]]*$parent:/,/^[a-zA-Z0-9]/p" "$file" |
                        grep "^[[:space:]]*$child:" |
                        grep -v "^[[:space:]]*#" |
                        head -n 1 |
                        awk -F': ' '{print $2}' |
                        tr -d '\r"' | sed "s/^'//;s/'$//")
            
            if [ -n "$val" ]; then echo "$val"; return 0; fi
        else
            local val=$(grep "^$key:" "$file" |
                        grep -v "^[[:space:]]*#" |
                        head -n 1 |
                        awk -F': ' '{print $2}' |
                        tr -d '\r"' | sed "s/^'//;s/'$//")
            
            if [ -n "$val" ]; then echo "$val"; return 0; fi
        fi
    fi

    if [ ! -f "$JS_TOOL" ]; then return 1; fi
    node "$JS_TOOL" get "$key" 2>/dev/null
}

config_set() {
    local key=$1; local value=$2
    if [ ! -f "$JS_TOOL" ]; then ui_print error "找不到配置工具"; return 1; fi
    local output; output=$(node "$JS_TOOL" set "$key" "$value" 2>&1)
    local status=$?
    if [ $status -eq 0 ]; then return 0; else ui_print error "设置失败 [$key]: $output"; sleep 1; return 1; fi
}

config_set_batch() {
    local json_str=$1
    if [ ! -f "$JS_TOOL" ]; then ui_print error "找不到配置工具"; return 1; fi
    local output; output=$(node "$JS_TOOL" set-batch "$json_str" 2>&1)
    local status=$?
    if [ $status -eq 0 ]; then return 0; else ui_print error "批量配置失败: $output"; sleep 1; return 1; fi
}

pip_install_smart() {
    local pip_exe="$1"
    shift
    local pip_args="$*"
    
    auto_load_proxy_env
    
    if ui_spinner "Pip 安装中..." "$pip_exe install $pip_args"; then
        return 0
    else
        ui_print error "Pip 安装失败。"
        return 1
    fi
}

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

escape_for_sed() {
    local raw="$1"
    local safe="${raw//\\/\\\\}"
    safe="${safe//\//\\/}"
    safe="${safe//&/\&}"
    echo "$safe"
}

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

get_process_cmdline() {
    local pid=$1
    if [ -f "/proc/$pid/cmdline" ]; then
        tr "\0" " " < "/proc/$pid/cmdline"
    else
        echo ""
    fi
}

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

# === [新增] 安全验证函数 (从 uninstall.sh 迁移) ===
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