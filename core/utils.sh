#!/bin/bash
# TAV-X Core: Utilities

if [ -n "$TAVX_DIR" ]; then
    [ -f "$TAVX_DIR/core/env.sh" ] && source "$TAVX_DIR/core/env.sh"
    [ -f "$TAVX_DIR/core/ui.sh" ] && source "$TAVX_DIR/core/ui.sh"
fi

safe_rm() {
    local target="$1"
    if [[ -z "$target" ]]; then ui_print error "安全拦截: 空路径！"; return 1; fi
    if [[ "$target" == "/" ]] || [[ "$target" == "$HOME" ]] || [[ "$target" == "/usr" ]] || [[ "$target" == "/bin" ]]; then
        ui_print error "安全拦截: 高危目录 ($target)！"; return 1; fi
    if [[ "$target" == "." ]] || [[ "$target" == ".." ]]; then
        ui_print error "安全拦截: 相对路径无效！"; return 1; fi
    rm -rf "$target"
}

pause() { echo ""; read -n 1 -s -r -p "按任意键继续..."; echo ""; }

open_browser() {
    local url=$1
    if [ "$OS_TYPE" == "TERMUX" ]; then
        command -v termux-open &>/dev/null && termux-open "$url"
    else
        # Linux / Generic
        if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
            if command -v xdg-open &>/dev/null; then 
                xdg-open "$url" >/dev/null 2>&1
                return
            elif command -v python3 &>/dev/null; then 
                python3 -m webbrowser "$url" >/dev/null 2>&1
                return
            fi
        fi
        
        # Headless fallback
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
    if [ ! -f "$file" ]; then echo "暂无日志文件: $(basename "$file")"; sleep 1; return; fi
    clear
    echo -e "${CYAN}=== 正在实时监控日志 ===${NC}"
    echo -e "${YELLOW}提示: 按 Ctrl+C 即可停止监控并返回菜单${NC}"
    echo "----------------------------------------"
    trap 'echo -e "\n${GREEN}>>> 已停止监控，正在返回...${NC}"; return' SIGINT
    tail -n 30 -f "$file"
    trap - SIGINT
}

is_port_open() {
    if timeout 0.2 bash -c "</dev/tcp/$1/$2" 2>/dev/null; then return 0; else return 1; fi
}

get_active_proxy() {
    local network_conf="$TAVX_DIR/config/network.conf"
    if [ -f "$network_conf" ]; then
        local c=$(cat "$network_conf")
        if [[ "$c" == PROXY* ]]; then
            local val=${c#*|}; val=$(echo "$val"|tr -d '\n\r')
            echo "$val"; return 0
        fi
    fi

    if [ -n "$http_proxy" ]; then echo "$http_proxy"; return 0; fi
    if [ -n "$https_proxy" ]; then echo "$https_proxy"; return 0; fi

    for entry in "${GLOBAL_PROXY_PORTS[@]}"; do
        local port=${entry%%:*}
        local proto=${entry#*:} 
        if timeout 0.1 bash -c "</dev/tcp/127.0.0.1/$port" 2>/dev/null;
 then
            if [[ "$proto" == "socks5h" ]]; then echo "socks5h://127.0.0.1:$port"; else echo "http://127.0.0.1:$port"; fi
            return 0
        fi
    done
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

prepare_network_strategy() {
    auto_load_proxy_env
    local proxy_active=$?
    
    if [ $proxy_active -ne 0 ] && [ -z "$SELECTED_MIRROR" ]; then
        select_mirror_interactive
    fi
}

select_mirror_interactive() {
    if [ -n "$SELECTED_MIRROR" ]; then return 0; fi

    ui_header "镜像源测速选择"
    echo -e "${CYAN}正在并发测速，请稍候...${NC}"
    echo "----------------------------------------"
    
    # Use global TMP_DIR if available
    local tmp_dir="${TMP_DIR:-$TAVX_DIR}"
    local tmp_race_file="$tmp_dir/.mirror_race"
    rm -f "$tmp_race_file"
    
    for mirror in "${GLOBAL_MIRRORS[@]}"; do
        (
            local start=$(date +%s%N)
            local test_url="${mirror}https://github.com/Future-404/TAV-X/info/refs?service=git-upload-pack"
            if curl -s -I -m 3 "$test_url" >/dev/null 2>&1; then
                local end=$(date +%s%N)
                local dur=$(( (end - start) / 1000000 ))
                echo "$dur|$mirror" >> "$tmp_race_file"
            fi
        ) &
    done
    wait

    if [ ! -s "$tmp_race_file" ]; then
        ui_print error "所有镜像源均连接超时！请检查网络。"
        return 1
    fi

    sort -n "$tmp_race_file" -o "$tmp_race_file"
    
    local OPTIONS=()
    local RAW_URLS=()
    
    while IFS='|' read -r dur url;
 do
        local mark="🟢"
        if [ "$dur" -gt 800 ]; then mark="🟡"; fi
        if [ "$dur" -gt 1500 ]; then mark="🔴"; fi
        
        local domain=$(echo "$url" | awk -F/ '{print $3}')
        OPTIONS+=("$mark ${dur}ms | $domain")
        RAW_URLS+=("$url")
    done < "$tmp_race_file"
    
    OPTIONS+=("🌐 官方源 (直连)")
    RAW_URLS+=("https://github.com/")

    local CHOICE_TEXT=$(ui_menu "请根据延迟选择最稳定的源" "${OPTIONS[@]}")
    
    local CHOICE_IDX=-1
    for i in "${!OPTIONS[@]}"; do
        if [[ "${OPTIONS[$i]}" == "$CHOICE_TEXT" ]]; then CHOICE_IDX=$i; break; fi
    done

    if [ "$CHOICE_IDX" -ge 0 ]; then
        SELECTED_MIRROR="${RAW_URLS[$CHOICE_IDX]}"
        export SELECTED_MIRROR
        ui_print success "已选定: $SELECTED_MIRROR"
        return 0
    else
        ui_print warn "默认使用第一项。"
        SELECTED_MIRROR="${RAW_URLS[0]}"
        export SELECTED_MIRROR
        return 0
    fi
}

_auto_heal_network_config() {
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
    local raw_url=$2
    local target_dir=$3
    
    auto_load_proxy_env
    local proxy_active=$?
    
    local clean_repo=${raw_url#"https://github.com/"}
    clean_repo=${clean_repo#"git@github.com:"}

    if [ $proxy_active -eq 0 ]; then
        if git clone --depth 1 $branch_arg "https://github.com/${clean_repo}" "$target_dir"; then return 0; fi
    fi

    if [ -n "$SELECTED_MIRROR" ]; then
        local final_url="${SELECTED_MIRROR}https://github.com/${clean_repo}"
        if [[ "$SELECTED_MIRROR" == *"github.com"* ]]; then final_url="https://github.com/${clean_repo}"; fi
        
        if env -u http_proxy -u https_proxy git clone --depth 1 $branch_arg "$final_url" "$target_dir"; then
            return 0
        fi
    fi
    
    if env -u http_proxy -u https_proxy git clone --depth 1 $branch_arg "https://github.com/${clean_repo}" "$target_dir"; then return 0; fi

    return 1
}

fix_git_remote() {
    local dir=$1
    local repo=$2
    
    [ ! -d "$dir/.git" ] && return 1
    cd "$dir" || return 1
    
    auto_load_proxy_env
    local proxy_active=$?
    
    if [ $proxy_active -eq 0 ]; then
         git remote set-url origin "https://github.com/${repo}"
         return 0
    fi
    
    if [ -n "$SELECTED_MIRROR" ]; then
         local final_url="${SELECTED_MIRROR}https://github.com/${repo}"
         if [[ "$SELECTED_MIRROR" == *"github.com"* ]]; then final_url="https://github.com/${repo}"; fi
         git remote set-url origin "$final_url"
         return 0
    fi
    
    git remote set-url origin "https://github.com/${repo}"
}

download_file_smart() {
    local url=$1; local filename=$2
    local try_mirror=${3:-true}
    auto_load_proxy_env
    local proxy_active=$?

    if [ $proxy_active -eq 0 ]; then
        if curl -L -o "$filename" --proxy "$http_proxy" --retry 2 --max-time 60 "$url"; then return 0; fi
    fi
    
    if [ "$try_mirror" == "true" ] && [[ "$url" == *"github.com"* ]]; then
        if [ -n "$SELECTED_MIRROR" ]; then
             local final_url="${SELECTED_MIRROR}${url}"
             if [[ "$SELECTED_MIRROR" == *"github.com"* ]]; then final_url="$url"; fi
             if curl -L -o "$filename" --max-time 60 "$final_url"; then return 0; fi
        fi
    fi
    
    if curl -L -o "$filename" "$url"; then return 0; else return 1; fi
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

    if [ $status -eq 0 ]; then
        return 0
    else
        ui_print error "批量配置失败: $output"; sleep 1; return 1
    fi
}