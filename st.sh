#!/bin/bash
# TAV-X Universal Installer

DEFAULT_POOL=(
    "https://ghproxy.net/"
    "https://mirror.ghproxy.com/"
    "https://ghproxy.cc/"
    "https://gh.likk.cc/"
    "https://hub.gitmirror.com/"
    "https://hk.gh-proxy.com/"
    "https://ui.ghproxy.cc/"
    "https://gh.ddlc.top/"
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
)

: "${REPO_PATH:=Future-404/TAV-X.git}"
: "${TAV_VERSION:=Latest}"

if [ -n "$TERMUX_VERSION" ]; then
    export TAVX_DIR="/data/data/com.termux/files/home/TAV-X"
else
    export TAVX_DIR="${HOME}/TAV-X"
fi

if [ -f "$TAVX_DIR/core/main.sh" ]; then
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
    
    # curl 参数说明:
    # -s: 静默模式
    # -L: 跟随跳转
    # -w %{speed_download}: 输出平均下载速度(B/s)
    # -o /dev/null: 不保存文件
    # -m 5: 最多测试5秒
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
            if curl -s -I -m 2 "${url}https://github.com/${REPO_PATH}" >/dev/null 2>&1; then
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
        echo -e "\n\033[1;36m可用镜像列表 (按延迟排序):\033[0m"
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
    
    echo -e "$i. 🌐 官方源 (无视速度强制直连)"
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

if [ -d "$TAVX_DIR" ]; then rm -rf "$TAVX_DIR"; fi
echo -e "\n\033[1;36m>>> Cloning Core ($TAV_VERSION)...\033[0m"
echo -e "Source: $DL_URL"

if git clone --depth 1 "$DL_URL" "$TAVX_DIR"; then
    (
        cd "$TAVX_DIR" || exit
        git remote set-url origin "https://github.com/${REPO_PATH}"
    )
    chmod +x "$TAVX_DIR/st.sh" "$TAVX_DIR"/core/*.sh "$TAVX_DIR"/modules/*.sh 2>/dev/null

    SHELL_RC="$HOME/.bashrc"
    [ -f "$HOME/.zshrc" ] && SHELL_RC="$HOME/.zshrc"
    if ! grep -q "alias st=" "$SHELL_RC"; then
        echo "" >> "$SHELL_RC"
        echo "alias st='bash $TAVX_DIR/st.sh'" >> "$SHELL_RC"
    fi

    echo -e "\n\033[1;32m✔ Installation Complete!\033[0m"
    exec bash "$TAVX_DIR/core/main.sh"
else
    echo -e "\n\033[1;31m✘ Installation Failed.\033[0m"
    exit 1
fi
