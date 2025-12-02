#!/bin/bash
# TAV-X Core: Utilities (V3.3 Smart NPM & Proxy-Only Download)
if [ -n "$TAVX_DIR" ] && [ -f "$TAVX_DIR/core/env.sh" ]; then
    source "$TAVX_DIR/core/env.sh"
fi
# --- UI Helpers (Cleaned) ---
pause() { echo ""; read -n 1 -s -r -p "按任意键继续..."; echo ""; }

send_analytics() {
    (
        local STAT_URL="https://tav-api.future404.qzz.io"
        if command -v curl &> /dev/null; then
            curl -s -m 5 "${STAT_URL}?ver=${CURRENT_VERSION}&type=startup" > /dev/null 2>&1
        fi
    ) &
}

safe_log_monitor() {
    local file=$1
    if [ ! -f "$file" ]; then
        echo "暂无日志文件: $(basename "$file")"
        sleep 1
        return
    fi
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

get_dynamic_proxy() {
    local PORTS=(
        "7890:socks5h"
        "7891:socks5h"
        "10808:socks5h"
        "10080:socks5h"
        "1080:socks5h"
        "8081:socks5h"
        "20170:socks5h"
        "10809:http"
        "10081:http"
        "6152:http"
        "8080:http"
        "3128:http"
        "8001:http" "8888:http" "9000:http"
    )
    for entry in "${PORTS[@]}"; do
        local port=${entry%%:*}
        local proto=${entry#*:}
        if is_port_open "127.0.0.1" "$port"; then
            echo "${proto}://127.0.0.1:${port}"
            return 0
        fi
    done
    return 1
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
            
            if ! is_port_open "$p_host" "$p_port"; then
                need_scan=true
            fi
        fi
    else
        need_scan=true
    fi
    
    if [ "$need_scan" == "true" ]; then
        local new_proxy=$(get_dynamic_proxy)
        if [ -n "$new_proxy" ]; then
            echo "PROXY|$new_proxy" > "$network_conf"
        fi
    fi
}

git_clone_smart() {
    local branch_arg=$1
    local raw_url=$2
    local target_dir=$3
    
    _auto_heal_network_config
    
    local network_conf="$TAVX_DIR/config/network.conf"
    local clean_repo=${raw_url#"https://github.com/"}
    clean_repo=${clean_repo#"git@github.com:"}
    local MODE="AUTO"; local VALUE=""
    
    local GIT_BASE="git clone --depth 1"
    if [ -n "$branch_arg" ]; then
        GIT_BASE="$GIT_BASE $branch_arg"
    fi
    
    if [ -f "$network_conf" ]; then
        local str=$(cat "$network_conf"); MODE=${str%%|*}; VALUE=${str#*|}; VALUE=$(echo "$VALUE"|tr -d '\n\r')
    fi

    if [ "$MODE" == "PROXY" ]; then
        if $GIT_BASE -c http.proxy="$VALUE" -c https.proxy="$VALUE" "https://github.com/${clean_repo}" "$target_dir"; then 
            return 0
        else
            :
        fi
    fi

    if [ "$MODE" == "MIRROR" ]; then
        if git -c http.version=HTTP/1.1 clone --depth 1 $branch_arg "${VALUE}https://github.com/${clean_repo}" "$target_dir"; then return 0; fi
    fi

    local success=false
    for mirror in "${GLOBAL_MIRRORS[@]}"; do
        echo -ne "\033[1;34m[AUTO]\033[0m 尝试: $mirror ... "
        if git -c http.version=HTTP/1.1 clone --depth 1 $branch_arg "${mirror}https://github.com/${clean_repo}" "$target_dir" >/dev/null 2>&1; then
            echo -e "\033[0;32m成功\033[0m"; success="true"; break
        else echo -e "\033[0;31m失败\033[0m"; rm -rf "$target_dir"; fi
    done
    
    if [ "$success" == "true" ]; then return 0; fi
    if $GIT_BASE "https://github.com/${clean_repo}" "$target_dir"; then return 0; else return 1; fi
}

fix_git_remote() {
    local target_dir=$1; local repo_path=$2
    local network_conf="$TAVX_DIR/config/network.conf"
    [ ! -d "$target_dir/.git" ] && return 1
    cd "$target_dir" || return 1
    
    _auto_heal_network_config
    
    local proxy_url=""
    if [ -f "$network_conf" ]; then
        local c=$(cat "$network_conf"); [[ "$c" == PROXY* ]] && proxy_url=${c#*|} && proxy_url=$(echo "$proxy_url"|tr -d '\n\r')
    fi
    
    local use_proxy=false
    if [ -n "$proxy_url" ]; then
        local p_port=$(echo "$proxy_url"|awk -F':' '{print $NF}')
        local p_host="127.0.0.1"
        [[ "$proxy_url" == *"://"* ]] && p_host=$(echo "$proxy_url"|sed -e 's|^[^/]*//||' -e 's|:.*$||')
        
        if is_port_open "$p_host" "$p_port"; then use_proxy=true; fi
    fi
    
    if [ "$use_proxy" == "true" ]; then
        echo -e "\033[1;36m[Mode]\033[0m 本地代理"
        git remote set-url origin "https://github.com/$repo_path"
        git config http.proxy "$proxy_url"
        git config https.proxy "$proxy_url"
    else
        echo -e "\033[1;36m[Mode]\033[0m 镜像加速"
        git config --unset http.proxy
        git config --unset https.proxy
        
        local best_mirror=""
        local min_time=9999
        echo -ne "正在寻找最佳线路..."
        
        for mirror in "${GLOBAL_MIRRORS[@]}"; do
            local start_tm=$(date +%s%N)
            if curl -s -I -m 2 "${mirror}https://github.com/${repo_path}" >/dev/null; then
                local end_tm=$(date +%s%N)
                local dur=$(( (end_tm - start_tm) / 1000000 ))
                if [ "$dur" -lt "$min_time" ]; then min_time=$dur; best_mirror=$mirror; fi
            fi
        done
        echo ""
        if [ -n "$best_mirror" ]; then 
            echo -e "\033[0;32m✔ 选中: $best_mirror\033[0m"
            git remote set-url origin "${best_mirror}https://github.com/${repo_path}"
        fi
    fi
}

download_file_smart() {
    local url=$1; local filename=$2
    _auto_heal_network_config
    local network_conf="$TAVX_DIR/config/network.conf"
    local MODE="AUTO"; local VALUE=""
    
    if [ -f "$network_conf" ]; then
        local str=$(cat "$network_conf"); MODE=${str%%|*}; VALUE=${str#*|}; VALUE=$(echo "$VALUE"|tr -d '\n\r')
    fi
    
    if [ "$MODE" == "PROXY" ]; then
        local p_port=$(echo "$VALUE"|awk -F':' '{print $NF}')
        local p_host="127.0.0.1"
        [[ "$VALUE" == *"://"* ]] && p_host=$(echo "$VALUE"|sed -e 's|^[^/]*//||' -e 's|:.*$||')
        
        if is_port_open "$p_host" "$p_port"; then
            if curl -L -o "$filename" --proxy "$VALUE" "$url"; then return 0; fi
        fi
        MODE="AUTO"
    fi
    
    if [ "$MODE" == "MIRROR" ]; then
        if curl -L -o "$filename" "${VALUE}${url}"; then return 0; fi
    fi
    
    local success=false
    for mirror in "${GLOBAL_MIRRORS[@]}"; do
        echo -ne "\033[1;34m[AUTO]\033[0m 尝试: $mirror ... "
        if curl -L -o "$filename" "${mirror}${url}"; then
            echo -e "\033[0;32m成功\033[0m"; success="true"; break
        else echo -e "\033[0;31m失败\033[0m"; fi
    done
    if [ "$success" == "true" ]; then return 0; fi
    if curl -L -o "$filename" "$url"; then return 0; else return 1; fi
}

download_file_proxy_only() {
    local url=$1; local filename=$2
    _auto_heal_network_config
    local network_conf="$TAVX_DIR/config/network.conf"
    
    if [ -f "$network_conf" ]; then
        local c=$(cat "$network_conf")
        if [[ "$c" == PROXY* ]]; then
            local val=${c#*|}; val=$(echo "$val"|tr -d '\n\r')
            local p_port=$(echo "$val"|awk -F':' '{print $NF}')
            local p_host="127.0.0.1"
            [[ "$val" == *"://"* ]] && p_host=$(echo "$val"|sed -e 's|^[^/]*//||' -e 's|:.*$||')
            
            if is_port_open "$p_host" "$p_port"; then
                info "使用代理下载: $val"
                if curl -L -o "$filename" --proxy "$val" "$url"; then return 0; fi
                warn "代理下载失败，切换直连..."
            fi
        fi
    fi
    
    info "正在直连下载..."
    if curl -L -o "$filename" "$url"; then return 0; else return 1; fi
}

npm_install_smart() {
    local target_dir=${1:-.}
    cd "$target_dir" || return 1
    _auto_heal_network_config
    
    local network_conf="$TAVX_DIR/config/network.conf"
    local proxy_url=""
    
    if [ -f "$network_conf" ]; then
        local c=$(cat "$network_conf")
        if [[ "$c" == PROXY* ]]; then
            proxy_url=${c#*|}; proxy_url=$(echo "$proxy_url"|tr -d '\n\r')
        fi
    fi
    
    local NPM_BASE="npm install --no-audit --no-fund --quiet --production"
    
    if [ -n "$proxy_url" ]; then
        if ui_spinner "NPM 安装中 (代理加速)..." "env https_proxy='$proxy_url' http_proxy='$proxy_url' $NPM_BASE"; then
            return 0
        else
            ui_print warn "代理安装失败。"
        fi
    fi
    
    local REGISTRY_URL=""
    local SRC_CHOICE=$(ui_menu "请选择 NPM 依赖下载源" \
        "📦 淘宝源" \
        "🏫 清华源" \
        "🌐 官方源" \
        "❌ 取消安装")
        
    case "$SRC_CHOICE" in
        *"淘宝"*) REGISTRY_URL="https://registry.npmmirror.com" ;;
        *"清华"*) REGISTRY_URL="https://registry.npmmirror.com" ;;
        *"官方"*) REGISTRY_URL="https://registry.npmjs.org/" ;;
        *"取消"*) return 1 ;;
    esac
    
    npm config set registry "$REGISTRY_URL"
    if ui_spinner "NPM 安装中 ($(echo $SRC_CHOICE|awk '{print $2}')..." "$NPM_BASE"; then
        npm config delete registry
        return 0
    else
        ui_print error "依赖安装失败。"
        npm config delete registry
        return 1
    fi
}

# --- Configuration Management ---
JS_TOOL="$TAVX_DIR/scripts/config_mgr.js"

config_get() {
    local key=$1
    if [ ! -f "$JS_TOOL" ]; then return 1; fi
    node "$JS_TOOL" get "$key" 2>/dev/null
}

config_set() {
    local key=$1
    local value=$2
    if [ ! -f "$JS_TOOL" ]; then return 1; fi
    if node "$JS_TOOL" set "$key" "$value" >/dev/null 2>&1; then return 0; else return 1; fi
}