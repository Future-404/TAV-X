#!/bin/bash
# TAV-X Core: Utilities (V6.4 Git Params Fix)

# --- UI Helpers ---
print_banner() {
    clear
    echo -e "${PURPLE}"
    cat << "BANNER"
   d8P
d888888P  Termux Audio Visual eXperience
  ?88'    [ v2.0.0-Beta | Architecture Refactored ]
  88P   
  88b   
  `?8b  
BANNER
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
}

pause() { echo ""; read -n 1 -s -r -p "按任意键继续..."; echo ""; }
header() { clear; print_banner; echo -e "${CYAN}>>> $1 ${NC}"; echo -e "${BLUE}────────────────────────────────────────────────────${NC}"; }

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
        warn "暂无日志文件: $(basename "$file")"
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
    if timeout 0.5 bash -c "</dev/tcp/$1/$2" 2>/dev/null; then return 0; else return 1; fi
}

get_dynamic_proxy() {
    local PORTS=("7890:http" "7891:socks5" "10808:socks5" "10809:http" "20171:http" "20170:socks5")
    for entry in "${PORTS[@]}"; do
        local port=${entry%%:*}
        local proto=${entry#*:}
        if is_port_open "127.0.0.1" "$port"; then echo "${proto}://127.0.0.1:${port}"; return 0; fi
    done
    return 1
}

git_clone_smart() {
    local branch_arg=$1
    local raw_url=$2
    local target_dir=$3
    
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
        local p_port=$(echo "$VALUE"|awk -F':' '{print $NF}')
        local p_host="127.0.0.1"
        [[ "$VALUE" == *"://"* ]] && p_host=$(echo "$VALUE"|sed -e 's|^[^/]*//||' -e 's|:.*$||')
        if is_port_open "$p_host" "$p_port"; then
            info "使用代理: $VALUE"
            if $GIT_BASE -c http.proxy="$VALUE" "https://github.com/${clean_repo}" "$target_dir"; then return 0; else return 1; fi
        else
            warn "代理未运行，降级自动。"
            MODE="AUTO"
        fi
    fi

    if [ "$MODE" == "MIRROR" ]; then
        info "使用线路: $VALUE"
        if $GIT_BASE "${VALUE}https://github.com/${clean_repo}" "$target_dir"; then return 0; fi
    fi

    local success=false
    for mirror in "${GLOBAL_MIRRORS[@]}"; do
        echo -ne "${BLUE}[AUTO]${NC} 尝试: $mirror ... "
        if $GIT_BASE "${mirror}https://github.com/${clean_repo}" "$target_dir" >/dev/null 2>&1; then
            echo -e "${GREEN}成功${NC}"; success="true"; break
        else echo -e "${RED}失败${NC}"; rm -rf "$target_dir"; fi
    done
    
    if [ "$success" == "true" ]; then return 0; fi
    info "尝试直连..."; $GIT_BASE "https://github.com/${clean_repo}" "$target_dir"
}

fix_git_remote() {
    local target_dir=$1; local repo_path=$2
    local network_conf="$TAVX_DIR/config/network.conf"
    [ ! -d "$target_dir/.git" ] && return 1
    cd "$target_dir" || return 1
    info "正在优化网络连接..."
    local proxy_url=""
    if [ -f "$network_conf" ]; then
        local c=$(cat "$network_conf"); [[ "$c" == PROXY* ]] && proxy_url=${c#*|} && proxy_url=$(echo "$proxy_url"|tr -d '\n\r')
    fi
    local use_proxy=false
    if [ -n "$proxy_url" ]; then
        local p_port=$(echo "$proxy_url"|awk -F':' '{print $NF}')
        local p_host="127.0.0.1"
        [[ "$proxy_url" == *"://"* ]] && p_host=$(echo "$proxy_url"|sed -e 's|^[^/]*//||' -e 's|:.*$||')
        is_port_open "$p_host" "$p_port" && use_proxy=true || echo -e "${YELLOW}[WARN] 代理失效，切换镜像模式。${NC}"
    fi
    if [ "$use_proxy" == "true" ]; then
        echo -e "${CYAN}[Mode]${NC} 本地代理"; git remote set-url origin "https://github.com/$repo_path"
        git config http.proxy "$proxy_url"; git config https.proxy "$proxy_url"
    else
        echo -e "${CYAN}[Mode]${NC} 镜像加速"; git config --unset http.proxy; git config --unset https.proxy
        local best_mirror=""; local min_time=9999
        echo -ne "正在寻找最佳线路..."
        for mirror in "${GLOBAL_MIRRORS[@]}"; do
            local start_tm=$(date +%s%N)
            if curl -s -I -m 2 "${mirror}https://github.com/${repo_path}" >/dev/null; then
                local end_tm=$(date +%s%N); local dur=$(( (end_tm - start_tm) / 1000000 ))
                [ "$dur" -lt "$min_time" ] && { min_time=$dur; best_mirror=$mirror; }
            fi
        done
        echo ""
        [ -n "$best_mirror" ] && { echo -e "${GREEN}✔ 选中: $best_mirror${NC}"; git remote set-url origin "${best_mirror}https://github.com/${repo_path}"; } || warn "镜像超时。"
    fi
}

download_file_smart() {
    local url=$1; local filename=$2; local network_conf="$TAVX_DIR/config/network.conf"
    local MODE="AUTO"; local VALUE=""
    if [ -f "$network_conf" ]; then
        local str=$(cat "$network_conf"); MODE=${str%%|*}; VALUE=${str#*|}; VALUE=$(echo "$VALUE"|tr -d '\n\r')
    fi
    if [ "$MODE" == "PROXY" ]; then
        local p_port=$(echo "$VALUE"|awk -F':' '{print $NF}')
        local p_host="127.0.0.1"
        [[ "$VALUE" == *"://"* ]] && p_host=$(echo "$VALUE"|sed -e 's|^[^/]*//||' -e 's|:.*$||')
        if is_port_open "$p_host" "$p_port"; then
            info "使用代理下载: $VALUE"
            if curl -L -o "$filename" --proxy "$VALUE" "$url"; then return 0; fi
        else
            warn "代理未运行，降级自动。"
            MODE="AUTO"
        fi
    fi
    if [ "$MODE" == "MIRROR" ]; then
        info "使用线路: $VALUE"
        if curl -L -o "$filename" "${VALUE}${url}"; then return 0; fi
    fi
    local success=false
    for mirror in "${GLOBAL_MIRRORS[@]}"; do
        echo -ne "${BLUE}[AUTO]${NC} 尝试: $mirror ... "
        if curl -L -o "$filename" "${mirror}${url}"; then
            echo -e "${GREEN}成功${NC}"; success="true"; break
        else echo -e "${RED}失败${NC}"; fi
    done
    if [ "$success" == "true" ]; then return 0; fi
    info "尝试直连..."; if curl -L -o "$filename" "$url"; then return 0; else return 1; fi
}
