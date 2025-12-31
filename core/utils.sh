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
        if command -v curl &> /dev/null; then
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
        if timeout 0.1 bash -c "</dev/tcp/127.0.0.1/$port" 2>/dev/null; then
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

check_github_speed() {
    local THRESHOLD=819200
    local TEST_URL="https://raw.githubusercontent.com/Future-404/TAV-X/main/core/env.sh"
    echo -e "${CYAN}正在测试 GitHub 直连速度 (阈值: 800KB/s)...${NC}"
    
    local speed=$(curl -s -L -m 5 -w "%{speed_download}\n" -o /dev/null "$TEST_URL" 2>/dev/null)
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
            if check_github_speed; then
                return 0
            else
                select_mirror_interactive
            fi
        fi
    fi
}

select_mirror_interactive() {
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
            if curl -s -I -m 2 "$test_url" >/dev/null 2>&1; then
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
        
        while IFS='|' read -r dur url; do
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
    
    prepare_network_strategy
    auto_load_proxy_env
    local proxy_active=$?

    if [ $proxy_active -ne 0 ] && [ -n "$SELECTED_MIRROR" ]; then
        if [[ "$SELECTED_MIRROR" != *"github.com"* ]]; then
            clone_url="${SELECTED_MIRROR}${official_url}"
        fi
    fi
    
    if git clone --depth 1 $branch_arg "$clone_url" "$target_dir"; then
        (
            cd "$target_dir" || exit
            git remote set-url origin "$official_url"
        )
        return 0
    else
        ui_print warn "下载失败，尝试重选镜像..."
        unset SELECTED_MIRROR
        select_mirror_interactive
        clone_url="$official_url"
        if [ -n "$SELECTED_MIRROR" ] && [[ "$SELECTED_MIRROR" != *"github.com"* ]]; then
             clone_url="${SELECTED_MIRROR}${official_url}"
        fi
        
        if git clone --depth 1 $branch_arg "$clone_url" "$target_dir"; then
             (cd "$target_dir" || exit; git remote set-url origin "$official_url")
             return 0
        else
             ui_print error "下载再次失败。"
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
    if [ $status -eq 0 ]; then return 0; else ui_print error "批量配置失败: $output"; sleep 1; return 1; fi
}
