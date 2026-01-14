#!/bin/bash
# TAV-X Universal Installer & Launcher

DEFAULT_POOL=(
    "https://ghproxy.net/"
    "https://mirror.ghproxy.com/"
    "https://ghproxy.cc/"
    "https://gh.likk.cc/"
    "https://hub.gitmirror.com/"
    "https://hk.gh-proxy.com/"
    "https://ui.ghproxy.cc/"
    "https://gh-proxy.com/"
    "https://gh.jasonzeng.dev/"
    "https://gh.idayer.com/"
    "https://edgeone.gh-proxy.com/"
    "https://ghproxy.site/"
    "https://www.gitwarp.com/"
    "https://cors.isteed.cc/"
    "https://ghproxy.vip/"
    "https://github.com/"
)

PROXY_PORTS=(
    "7890:http"
    "7891:http"
    "10809:http"
    "10808:http"
    "20171:http"
    "20170:http"
    "9090:http"
    "8080:http"
    "1080:http"
    "2080:http"
)

: "${REPO_PATH:=Future-404/TAV-X.git}"
: "${TAV_VERSION:=Latest}"

export TAVX_DIR="${HOME}/.tav_x"

FORCE_UPDATE=false
if [ "$TAVX_INSTALLER_MODE" == "true" ]; then FORCE_UPDATE=true; fi
if [[ "$1" == "update" || "$1" == "install" || "$1" == "reinstall" ]]; then FORCE_UPDATE=true; fi

if [[ "$1" == "status" || "$1" == "ps" || "$1" == "list" || "$1" == "stop" || "$1" == "kill" || "$1" == "re" || "$1" == "log" ]]; then
    if [ -f "$HOME/.tav_x/core/env.sh" ]; then
        source "$HOME/.tav_x/core/env.sh"
        source "$HOME/.tav_x/core/utils.sh"
        
        case "$1" in
            status|ps|list)
                echo -e "${BLUE}=== TAV-X 服务状态 ===${NC}"
                if [ -d "$TAVX_DIR/modules" ]; then
                    for mod in "$TAVX_DIR/modules"/*; do
                        [ ! -d "$mod" ] && continue
                        id=$(basename "$mod")
                        if [ "$id" == "cloudflare" ]; then
                            if [ "$OS_TYPE" == "TERMUX" ]; then
                                for s in "$PREFIX/var/service"/cf_tunnel_*; do
                                    [ ! -d "$s" ] && continue
                                    sv status "$(basename "$s")" 2>/dev/null | grep -q "^run:" && echo -e "${GREEN}[RUNNING]${NC} $(basename "$s")"
                                done
                            else
                                for pid_f in "$TAVX_DIR/run"/cf_*.pid; do
                                    [ -f "$pid_f" ] && kill -0 $(cat "$pid_f") 2>/dev/null && echo -e "${GREEN}[RUNNING]${NC} $(basename "$pid_f" .pid)"
                                done
                            fi
                            continue
                        fi
                        is_app_running "$id" && echo -e "${GREEN}[RUNNING]${NC} $id"
                    done
                fi
                ;;
            stop|kill)
                echo -e "${YELLOW}正在停止所有 TAV-X 服务...${NC}"
                stop_all_services_routine
                echo -e "${GREEN}✔ 已全部停止${NC}"
                ;;
            re)
                echo -e "${CYAN}正在重启所有运行中的 TAV-X 服务...${NC}"
                if [ "$OS_TYPE" == "TERMUX" ] && command -v sv &>/dev/null; then
                    for s in "$PREFIX/var/service"/*; do
                        if [ -f "$s/.tavx_managed" ] && sv status "$(basename "$s")" 2>/dev/null | grep -q "^run:"; then
                            echo -e "重启: $(basename "$s")..."
                            sv restart "$(basename "$s")" >/dev/null
                        fi
                    done
                    echo -e "${GREEN}✔ 重启指令已发送${NC}"
                else
                    echo -e "${RED}该环境不支持快捷重启，请进入主菜单操作。${NC}"
                fi
                ;;
            log)
                if [ -z "$2" ]; then
                    echo -e "${BLUE}=== 可用日志服务 ===${NC}"
                    if [ "$OS_TYPE" == "TERMUX" ] && [ -d "$PREFIX/var/service" ]; then
                        for s in "$PREFIX/var/service"/*; do
                            [ -f "$s/.tavx_managed" ] && echo -e "  - $(basename "$s")"
                        done
                    fi
                    echo -e "\n用法: ${YELLOW}st log <应用ID>${NC}"
                else
                    LOG_PATH=""
                    if [ "$OS_TYPE" == "TERMUX" ]; then
                        LOG_PATH="$PREFIX/var/service/$2/log/current"
                    fi
                    # Fallback to legacy logs dir
                    [ ! -f "$LOG_PATH" ] && LOG_PATH="$TAVX_DIR/logs/$2.log"
                    
                    if [ -f "$LOG_PATH" ]; then
                        safe_log_monitor "$LOG_PATH"
                    else
                        echo -e "${RED}错误: 未找到日志文件 '$2'${NC}"
                        echo -e "请运行 ${CYAN}st log${NC} 查看可用 ID"
                    fi
                fi
                ;;
        esac
        exit 0
    else
        echo "Error: Core files not found."
        exit 1
    fi
fi

if [ -f "$TAVX_DIR/core/main.sh" ] && [ "$FORCE_UPDATE" == "false" ]; then
    exec bash "$TAVX_DIR/core/main.sh" "$@"
fi

echo -e "\033[1;36m>>> TAV-X Installer initializing...\033[0m"
if [ -n "$TERMUX_VERSION" ]; then
    pkg update -y >/dev/null 2>&1
    if ! command -v git &> /dev/null; then pkg install git -y; fi
    if ! command -v gum &> /dev/null; then pkg install gum -y; fi
else
    if command -v apt-get &> /dev/null; then
        if ! command -v git &> /dev/null; then 
            sudo apt-get update >/dev/null 2>&1
            sudo apt-get install git -y
        fi
    fi
fi

DL_URL=""

probe_local_ports() {
    for entry in "${PROXY_PORTS[@]}"; do
        port=${entry%%:*}
        if timeout 0.1 bash -c "</dev/tcp/127.0.0.1/$port" 2>/dev/null; then
            echo -e "\033[1;32m✔ 发现本地代理端口: $port\033[0m"
            export http_proxy="http://127.0.0.1:$port"
            export https_proxy="http://127.0.0.1:$port"
            return 0
        fi
    done
    return 1
}

check_github_speed() {
    local THRESHOLD=819200
    local CLEAN_REPO=${REPO_PATH%.git} 
    local TEST_URL="https://raw.githubusercontent.com/${CLEAN_REPO}/main/st.sh"
    
    echo -e "\033[1;33m正在测试 GitHub 直连速度 (阈值: 800KB/s)...\033[0m"
    
    local speed=$(curl -s -L -m 5 -w "%{speed_download}\n" -o /dev/null "$TEST_URL" 2>/dev/null)
    speed=${speed%.*}
    if [ -z "$speed" ]; then speed=0; fi
    local speed_kb=$((speed / 1024))
    
    if [ "$speed" -ge "$THRESHOLD" ]; then
        echo -e "\033[1;32m✔ 网速达标: ${speed_kb}KB/s (使用了直连)\033[0m"
        return 0
    else
        if [ "$speed" -eq 0 ]; then
             echo -e "\033[1;31m✘ 无法连接到 GitHub。\033[0m"
        else
             echo -e "\033[1;33m⚠ 网速不足: ${speed_kb}KB/s (低于 800KB/s)，转入镜像选择。\033[0m"
        fi
        return 1
    fi
}

select_mirror_interactive() {
    echo -e "\n\033[1;36m>>> 启动备用方案：镜像源测速选择\033[0m"
    echo -e "\033[1;33m正在并发测速，请稍候...\033[0m"
    local tmp_file=$(mktemp)
    
    for url in "${DEFAULT_POOL[@]}"; do
        (
            start=$(date +%s%N)
            if curl -fsL -I -m 2 "${url}https://github.com/${REPO_PATH}" >/dev/null 2>&1; then
                end=$(date +%s%N)
                dur=$(( (end - start) / 1000000 ))
                echo "$dur $url" >> "$tmp_file"
            fi
        ) &
    done
    wait
    
    local VALID_URLS=()
    if [ -s "$tmp_file" ]; then
        sort -n "$tmp_file" -o "$tmp_file"
        echo -e "\n\033[1;36m可用镜像列表:\033[0m"
        local i=1
        while read -r dur url; do
            local mark="\033[1;32m🟢"
            [ "$dur" -gt 800 ] && mark="\033[1;33m🟡"
            [ "$dur" -gt 1500 ] && mark="\033[1;31m🔴"
            local domain=$(echo "$url" | awk -F/ '{print $3}')
            echo -e "$i. $mark ${dur}ms \033[0m| $domain"
            VALID_URLS+=("$url")
            ((i++))
        done < "$tmp_file"
    else
        echo -e "\033[1;31m✘ 所有镜像连接超时。强制使用官方源。\033[0m"
        DL_URL="https://github.com/${REPO_PATH}"
        rm -f "$tmp_file"
        return
    fi
    rm -f "$tmp_file"
    
    echo -e "$i. 🌐 官方源"
    VALID_URLS+=("https://github.com/")
    
    echo ""
    read -p "请选择镜像编号 [默认 1]: " USER_CHOICE
    USER_CHOICE=${USER_CHOICE:-1}
    
    if [[ "$USER_CHOICE" =~ ^[0-9]+$ ]] && [ "$USER_CHOICE" -ge 1 ] && [ "$USER_CHOICE" -le "${#VALID_URLS[@]}" ]; then
        local best_url="${VALID_URLS[$((USER_CHOICE-1))]}"
        if [[ "$best_url" == *"github.com"* ]]; then
            DL_URL="https://github.com/${REPO_PATH}"
        else
            DL_URL="${best_url}https://github.com/${REPO_PATH}"
        fi
        echo -e "\033[1;32m✔ 已选定: $best_url\033[0m"
    else
        echo -e "\033[1;31m无效选择，默认使用第一项。\033[0m"
        DL_URL="${VALID_URLS[0]}https://github.com/${REPO_PATH}"
    fi
}

if probe_local_ports; then
    DL_URL="https://github.com/${REPO_PATH}"
elif check_github_speed; then
    DL_URL="https://github.com/${REPO_PATH}"
else
    select_mirror_interactive
fi

echo -e "\n\033[1;36m>>> Processing Core ($TAV_VERSION)...\033[0m"
echo -e "Source: $DL_URL"

INSTALL_SUCCESS=false
if [ -d "$TAVX_DIR/.git" ]; then
    echo -e "\033[1;33m检测到现有安装，尝试修复更新TAV-X...\033[0m"
    cd "$TAVX_DIR" || exit
    git remote set-url origin "$DL_URL"
    if git fetch origin main && git reset --hard origin/main; then
        INSTALL_SUCCESS=true
    fi
else
    if git clone --depth 1 "$DL_URL" "$TAVX_DIR"; then
        INSTALL_SUCCESS=true
    fi
fi

if [ "$INSTALL_SUCCESS" = true ]; then
    (
        cd "$TAVX_DIR" || exit
        git remote set-url origin "https://github.com/${REPO_PATH}"
    )
    
    chmod +x "$TAVX_DIR/st.sh" "$TAVX_DIR"/core/*.sh "$TAVX_DIR"/modules/*.sh 2>/dev/null
    
    if [ ! -f "$HOME/.bashrc" ]; then
        touch "$HOME/.bashrc"
    fi

    for rc_file in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -f "$rc_file" ]; then
            sed -i '/alias st=/d' "$rc_file" 2>/dev/null
            echo "alias st='bash $TAVX_DIR/st.sh'" >> "$rc_file"
        fi
    done

    echo -e "\n\033[1;32m✔ 安装完成 / Installation Complete!\033[0m"
    echo -e "------------------------------------------------"
    echo -e "💡 请执行以下命令使快捷指令生效："
    echo -e "   \033[1;33msource ~/.bashrc\033[0m"
    echo -e ""
    echo -e "🚀 然后直接输入 \033[1;33mst\033[0m 即可启动脚本菜单"
    echo -e "------------------------------------------------"
    exit 0
else
    echo -e "\n\033[1;31m✘ Installation Failed.\033[0m"
    exit 1
fi
