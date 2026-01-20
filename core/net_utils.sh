#!/bin/bash
# TAV-X Core: Network Utilities

[ -n "$_TAVX_NET_UTILS_LOADED" ] && return
_TAVX_NET_UTILS_LOADED=true

if [ -n "$TAVX_DIR" ]; then
    [ -f "$TAVX_DIR/core/env.sh" ] && source "$TAVX_DIR/core/env.sh"
    [ -f "$TAVX_DIR/core/ui.sh" ] && source "$TAVX_DIR/core/ui.sh"
fi

get_local_ip() {
    local ip=""
    
    if command -v ip &>/dev/null; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
        if [ -n "$ip" ]; then echo "$ip"; return; fi
    fi
    
    local ips=""
    if command -v ifconfig &>/dev/null; then
        ips=$(ifconfig 2>/dev/null | grep -w inet | grep -v 127.0.0.1 | awk '{print $2}' | cut -d: -f2)
    fi
    
    if [ -z "$ips" ] && command -v hostname &>/dev/null; then
        ips=$(hostname -I 2>/dev/null)
    fi
    
    local best_ip=""
    local fallback_ip=""
    
    for cand in $ips; do
        if [[ "$cand" == 192.168.* ]] || [[ "$cand" == 10.* ]]; then
            best_ip="$cand"
            break
        fi
        if [ -z "$fallback_ip" ]; then fallback_ip="$cand"; fi
    done
    
    echo "${best_ip:-${fallback_ip:-127.0.0.1}}"
}
export -f get_local_ip

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
        if [ "$_PROXY_CACHE_RESULT" == "NONE" ]; then
            return 1
        else
            echo "$_PROXY_CACHE_RESULT"
            return 0
        fi
    fi

    local network_conf="$TAVX_DIR/config/network.conf"
    if [ -f "$network_conf" ]; then
        local c
        c=$(cat "$network_conf")
        if [[ "$c" == PROXY* ]]; then
            local val
            val=${c#*|}; val=$(echo "$val"|tr -d '\n\r')
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
        if timeout 0.1 bash -c "</dev/tcp/127.0.0.1/$port" 2>/dev/null;
        then
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
    local choice
    choice=$(ui_menu "请选择正确的代理地址" "${found_proxies[@]}" "🚫 都不正确 (手动输入)")
    
    if [[ "$choice" == *"手动输入"* ]]; then
        return 1
    else
        _PROXY_CACHE_RESULT="$choice"
        echo "$choice"; return 0
    fi
}
export -f get_active_proxy

auto_load_proxy_env() {
    local proxy
    proxy=$(get_active_proxy)
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
export -f auto_load_proxy_env

check_github_speed() {
    local THRESHOLD=819200
    local TEST_URL="https://raw.githubusercontent.com/Future-404/TAV-X/main/core/env.sh"
    echo -e "${CYAN}正在测试 GitHub 直连速度 (阈值: 800KB/s)...${NC}"
    
    local speed
    speed=$(curl -s -L -m 5 -w "%{speed_download}" -o /dev/null "$TEST_URL" 2>/dev/null)
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
export -f check_github_speed

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
export -f prepare_network_strategy

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
        local mirrors
        if [ "${BASH_VERSINFO:-0}" -ge 4 ]; then
            read -r -a mirrors <<< "$mirrors_str"
        else
            # shellcheck disable=SC2206
            mirrors=($mirrors_str)
        fi
        
        local tmp_race_file="$2"
        
        for mirror in "${mirrors[@]}"; do
            local start
            start=$(date +%s%N)
            local test_url="${mirror}https://github.com/Future-404/TAV-X/info/refs?service=git-upload-pack"
            echo -n -e "  Testing: ${mirror} ... \r"
            if curl -fsL -A "Mozilla/5.0" -r 0-10 -o /dev/null -m 5 "$test_url" 2>/dev/null;
            then
                local end
                end=$(date +%s%N)
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
            local domain
            domain=$(echo "$url" | awk -F/ '{print $3}')
            local item="${mark} ${dur}ms | ${domain}"
            MENU_OPTIONS+=("$item")
            URL_MAP+=("$url")
        done < "$tmp_race_file"
    else
        echo -e "${RED}⚠️  所有镜像源测速均超时。${NC}"
    fi

    MENU_OPTIONS+=("🌐 官方源")
    URL_MAP+=("https://github.com/")
    
    rm -f "$tmp_race_file"
    echo -e "${GREEN}请根据测速结果选择一个节点:${NC}"
    local CHOICE_STR
    CHOICE_STR=$(ui_menu "使用方向键选择，回车确认" "${MENU_OPTIONS[@]}")
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
export -f select_mirror_interactive

_auto_heal_network_config() {
    reset_proxy_cache
    local network_conf="$TAVX_DIR/config/network.conf"
    local need_scan=false
    if [ -f "$network_conf" ]; then
        local c
        c=$(cat "$network_conf")
        if [[ "$c" == PROXY* ]]; then
            local val
            val=${c#*|}; val=$(echo "$val"|tr -d '\n\r')
            local p_port
            p_port=$(echo "$val"|awk -F: '{print $NF}')
            local p_host="127.0.0.1"
            [[ "$val" == *"://"* ]] && p_host=$(echo "$val"|sed -e 's|^[^/]*//||' -e 's|:.*$||')
            if ! is_port_open "$p_host" "$p_port"; then need_scan=true; fi
        fi
    else need_scan=true; fi
    
    if [ "$need_scan" == "true" ]; then
        local new_proxy
        new_proxy=$(get_active_proxy)
        if [ -n "$new_proxy" ]; then echo "PROXY|$new_proxy" > "$network_conf"; fi
    fi
}
export -f _auto_heal_network_config

git_clone_smart() {
    local branch_arg=$1
    local repo_input=$2
    local target_dir=$3
    
    if [[ "$repo_input" == "file://"* ]]; then
        git clone "$branch_arg" "$repo_input" "$target_dir"
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

    local base_name
    base_name=$(basename "$filename")

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
export -f download_file_smart

npm_install_smart() {
    local target_dir=${1:-.}
    cd "$target_dir" || return 1
    auto_load_proxy_env
    local proxy_active=$?
    
    local NPM_CMD="npm install --no-audit --no-fund --quiet --production"
    local NPM_RELAXED="$NPM_CMD --legacy-peer-deps"
    
    if [ $proxy_active -eq 0 ]; then
        npm config delete registry
        if ui_stream_task "NPM 安装..." "env http_proxy='$http_proxy' https_proxy='$https_proxy' $NPM_CMD"; then return 0; fi
        
        ui_print warn "标准安装失败，尝试宽松模式 (Legacy Peer Deps)..."
        if ui_stream_task "NPM 安装 (宽松模式)..." "env http_proxy='$http_proxy' https_proxy='$https_proxy' $NPM_RELAXED"; then return 0; fi
    fi
    
    npm config set registry "https://registry.npmmirror.com"
    if ui_stream_task "NPM 安装 (镜像源)..." "$NPM_CMD"; then
        npm config delete registry; return 0
    fi
    
    ui_print warn "镜像安装失败，尝试宽松模式..."
    if ui_stream_task "NPM 安装 (镜像+宽松)..." "$NPM_RELAXED"; then
        npm config delete registry; return 0
    else
        ui_print error "依赖安装失败 (已尝试所有策略)。"
        npm config delete registry; return 1
    fi
}
export -f npm_install_smart