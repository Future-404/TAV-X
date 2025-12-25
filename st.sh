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

if [ -n "$MIRROR_LIST" ]; then
    IFS=' ' read -r -a MIRRORS <<< "$MIRROR_LIST"
else
    MIRRORS=("${DEFAULT_POOL[@]}")
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# --- OS Detection ---
if [ -n "$TERMUX_VERSION" ]; then
    OS_TYPE="TERMUX"
    TMP_DIR="/data/data/com.termux/files/usr/tmp"
    [ ! -d "$TMP_DIR" ] && TMP_DIR="$PREFIX/tmp"
else
    OS_TYPE="LINUX"
    TMP_DIR="/tmp"
fi
mkdir -p "$TMP_DIR"

if [ -f "$SCRIPT_DIR/core/main.sh" ]; then
    echo -e "\033[1;35m🔧 [DEV MODE] 开发者模式已激活\033[0m"
    echo -e "📂 使用此目录作为运行环境: $SCRIPT_DIR"

    export TAVX_DIR="$SCRIPT_DIR"

    chmod +x "$TAVX_DIR"/core/*.sh "$TAVX_DIR"/modules/*.sh 2>/dev/null
    exec bash "$TAVX_DIR/core/main.sh"
    exit 0
fi

export TAVX_DIR="$HOME/.tav_x"
CORE_FILE="$TAVX_DIR/core/main.sh"

if [ -f "$CORE_FILE" ]; then
    chmod +x "$CORE_FILE" "$TAVX_DIR"/core/*.sh "$TAVX_DIR"/modules/*.sh 2>/dev/null
    exec bash "$CORE_FILE"
fi


clear
echo -e "${RED}"
cat << "BANNER"
██╗░░░██╗██████╗░░██████╗░██████╗░░█████╗░██████╗░███████╗
██║░░░██║██╔══██╗██╔════╝░██╔══██╗██╔══██╗██╔══██╗██╔════╝
██║░░░██║██████╔╝██║░░██╗░██████╔╝███████║██║░░██║█████╗░░
██║░░░██║██╔═══╝░██║░░╚██╗██╔══██╗██╔══██║██║░░██║██╔══╝░░
╚██████╔╝██║░░░░░╚██████╔╝██║░░██║██║░░██║██████╔╝███████╗
░╚═════╝░╚═╝░░░░░░╚═════╝░╚═╝░░╚═╝╚═════╝░╚══════╝
BANNER
echo -e "${NC}"
echo -e "${CYAN}TAV-X 智能安装程序${NC} [Ver: ${TAV_VERSION}]"
echo "------------------------------------------------"

# --- Git Installation ---
if ! command -v git &> /dev/null; then
    echo -e "${YELLOW}>>> 正在安装基础依赖 (Git)...${NC}"
    if [ "$OS_TYPE" == "TERMUX" ]; then
        pkg update -y >/dev/null 2>&1
        pkg install git -y
    else
        # Linux (Debian/Ubuntu)
        if command -v apt-get &> /dev/null; then
            SUDO=""
            [ "$EUID" -ne 0 ] && command -v sudo &> /dev/null && SUDO="sudo"
            $SUDO apt-get update -y >/dev/null 2>&1
            $SUDO apt-get install git -y
        else
             echo -e "${RED}❌ 未检测到 apt 包管理器，请手动安装 git。${NC}"
             exit 1
        fi
    fi
fi

test_connection() {
    curl -I -s --max-time 3 "https://github.com" >/dev/null 2>&1
}

probe_direct_or_env() {
    echo -e "${YELLOW}>>> [1/3] 探测现有网络环境...${NC}"

    if [ -n "$http_proxy" ] || [ -n "$https_proxy" ]; then
        echo -e "    检测到环境变量代理: ${CYAN}${https_proxy:-$http_proxy}${NC}"
        if test_connection; then
            echo -e "${GREEN}    ✔ 代理有效！${NC}"
            return 0
        else
            echo -e "${RED}    ✘ 环境变量代理不可用${NC}"
            unset http_proxy https_proxy all_proxy
        fi
    fi

    echo -ne "    尝试直连 GitHub... "
    if test_connection; then
        echo -e "${GREEN}成功${NC}"
        return 0
    else
        echo -e "${RED}失败${NC}"
        return 1
    fi
}

probe_local_ports() {
    echo -e "\n${YELLOW}>>> [2/3] 扫描本地代理端口...${NC}"

    for entry in "${PROXY_PORTS[@]}"; do
        local port=${entry%%:*}
        local proto=${entry#*:}

        if timeout 0.2 bash -c "</dev/tcp/127.0.0.1/$port" 2>/dev/null; then
            echo -e "    🔍 发现端口: ${CYAN}$port ($proto)${NC}"

            if [[ "$proto" == "socks5h" ]]; then
                proxy_url="socks5h://127.0.0.1:$port"
            else
                proxy_url="http://127.0.0.1:$port"
            fi

            export http_proxy="$proxy_url"
            export https_proxy="$proxy_url"
            export all_proxy="$proxy_url"

            echo -ne "    🧪 测试代理... "
            if test_connection; then
                echo -e "${GREEN}可用${NC}"
                return 0
            else
                echo -e "${RED}失败${NC}"
                unset http_proxy https_proxy all_proxy
            fi
        fi
    done

    echo -e "    ⚠️ 未发现可用代理端口"
    return 1
}

select_mirror_interactive() {
    echo -e "\n${YELLOW}>>> [3/3] 启动镜像并发测速 (Smart Race)...${NC}"
    echo "------------------------------------------------"

    # Use Dynamic Path
    local tmp_race_file="$TMP_DIR/tav_mirror_race"
    rm -f "$tmp_race_file"
    mkdir -p "$(dirname "$tmp_race_file")"

    for mirror in "${MIRRORS[@]}"; do
        (
            if [[ "$mirror" == *"github.com"* ]]; then
                 TEST_URL="${mirror}${REPO_PATH}"
            else
                 TEST_URL="${mirror}https://github.com/${REPO_PATH}/info/refs?service=git-upload-pack"
            fi
            
            TIME_START=$(date +%s%N)
            if curl -s -I -m 3 "$TEST_URL" >/dev/null 2>&1; then
                TIME_END=$(date +%s%N)
                DURATION=$(( (TIME_END - TIME_START) / 1000000 ))
                echo "$DURATION|$mirror" >> "$tmp_race_file"
                echo -ne "."
            fi
        ) & 
    done
    wait
    echo ""
    if [ ! -s "$tmp_race_file" ]; then
        echo -e "${RED}❌ 所有线路均连接超时，请检查网络或开启/关闭飞行模式。${NC}"
        exit 1
    fi

    sort -n "$tmp_race_file" -o "$tmp_race_file"

    echo "------------------------------------------------"
    echo -e " 延迟(ms) | 镜像源"
    echo "------------------------------------------------"

    VALID_URLS=()
    local idx=1
    while IFS='|' read -r dur url; do
        if [ $dur -lt 500 ]; then C_CODE=$GREEN;
        elif [ $dur -lt 1000 ]; then C_CODE=$YELLOW;
        else C_CODE=$RED; fi
        if [[ "$url" == *"github.com"* ]]; then
             DISPLAY_NAME="GitHub 官方"
             DL_LINK="https://github.com/${REPO_PATH}"
        else
             DISPLAY_NAME=$(echo $url | awk -F/ '{print $3}')
             DL_LINK="${url}https://github.com/${REPO_PATH}"
        fi

        printf " [%2d] %b%4d%b | %s\n" "$idx" "$C_CODE" "$dur" "$NC" "$DISPLAY_NAME"
        
        VALID_URLS+=("$DL_LINK")
        ((idx++))
    done < "$tmp_race_file"
    rm -f "$tmp_race_file"

    echo "------------------------------------------------"
    echo -e "${CYAN}系统已自动排序，建议选择前几项。${NC}"
    echo -e "${CYAN}请输入序号选择下载源 (默认 1)：${NC}"
    read -p ">>> " USER_CHOICE
    if [[ -z "$USER_CHOICE" ]]; then
        USER_CHOICE=1
    fi

    if [[ "$USER_CHOICE" =~ ^[0-9]+$ ]] && [ "$USER_CHOICE" -ge 1 ] && [ "$USER_CHOICE" -le "${#VALID_URLS[@]}" ]; then
        DL_URL="${VALID_URLS[$((USER_CHOICE-1))]}"
        echo -e "${GREEN}✔ 已选择: $DL_URL${NC}"
    else
        echo -e "${RED}无效输入，自动选择最快线路 (第1项)${NC}"
        DL_URL="${VALID_URLS[0]}"
    fi
}

if probe_direct_or_env; then
    DL_URL="https://github.com/${REPO_PATH}"

elif probe_local_ports; then
    DL_URL="https://github.com/${REPO_PATH}"

else
    select_mirror_interactive
fi

if [ -d "$TAVX_DIR" ]; then rm -rf "$TAVX_DIR"; fi

echo -e "\n${CYAN}>>> 正在拉取核心组件...${NC}"
echo -e "源地址: $DL_URL"

if git clone --depth 1 "$DL_URL" "$TAVX_DIR"; then
    chmod +x "$TAVX_DIR/st.sh" "$TAVX_DIR"/core/*.sh "$TAVX_DIR"/modules/*.sh 2>/dev/null

    SHELL_RC="$HOME/.bashrc"
    [ -f "$HOME/.zshrc" ] && SHELL_RC="$HOME/.zshrc"

    sed -i '/alias st=/d' "$SHELL_RC" 2>/dev/null
    echo "alias st='bash $TAVX_DIR/st.sh'" >> "$SHELL_RC"

    # --- Gum Installation (Termux Only in Bootstrap) ---
    if ! command -v gum &> /dev/null; then
        if [ "$OS_TYPE" == "TERMUX" ]; then
            echo -e "${YELLOW}>>> 部署 UI 引擎 (Gum)...${NC}"
            pkg install gum -y >/dev/null 2>&1
        else
            # Linux: gum is not usually in default apt repos.
            # We defer this to core/deps.sh, or user can install manually.
            echo -e "${YELLOW}>>> 提示: 正在准备环境...${NC}"
        fi
    fi

    echo ""
    echo -e "${GREEN}🎉 TAV-X 安装成功！${NC}"
    echo -e "👉 请输入 ${CYAN}source $SHELL_RC${NC} 生效，然后输入 ${CYAN}st${NC} 启动。"

else
    echo -e "\n${RED}❌ 下载失败${NC}"
    echo -e "请重新运行脚本并选择其他线路。"
    exit 1
fi
