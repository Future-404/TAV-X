#!/bin/bash
# TAV-X Bootstrapper v2.4.2 (Hybrid High-Availability)
SOURCE=${BASH_SOURCE[0]}
while [ -L "$SOURCE" ]; do
  DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
  SOURCE=$(readlink "$SOURCE")
  [[ $SOURCE != /* ]] && SOURCE=$DIR/$SOURCE
done
export TAVX_DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )

CORE_FILE="$TAVX_DIR/core/main.sh"

if [ -f "$CORE_FILE" ]; then
    chmod +x "$CORE_FILE" "$TAVX_DIR"/core/*.sh "$TAVX_DIR"/modules/*.sh 2>/dev/null
    exec bash "$CORE_FILE"
else
    clear
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'

    echo -e "${RED}"
    cat << "BANNER"
██╗░░░██╗██████╗░░██████╗░██████╗░░█████╗░██████╗░███████╗
██║░░░██║██╔══██╗██╔════╝░██╔══██╗██╔══██╗██╔══██╗██╔════╝
██║░░░██║██████╔╝██║░░██╗░██████╔╝███████║██║░░██║█████╗░░
██║░░░██║██╔═══╝░██║░░╚██╗██╔══██╗██╔══██║██║░░██║██╔══╝░░
╚██████╔╝██║░░░░░╚██████╔╝██║░░██║██║░░██║██████╔╝███████╗
░╚═════╝░╚═╝░░░░░░╚═════╝░╚═╝░░╚═╝╚═╝░░╚═╝╚═════╝░╚══════╝
BANNER
    echo -e "${NC}"
    echo -e "${YELLOW}>>> 检测到核心文件缺失。${NC}"
    echo -e "${CYAN}正在启动 [镜像直连恢复] 流程...${NC}"
    echo ""

    MIRRORS=(
        "https://mirror.ghproxy.com/"
        "https://gh-proxy.com/"
        "https://ghproxy.net/"
        "https://hub.gitmirror.com/"
        "https://github.com/"
        "https://ghproxy.net/"
        "https://mirror.ghproxy.com/"
        "https://ghproxy.cc/"
        "https://gh.likk.cc/"
        "https://github.akams.cn/"
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
    )
    
    TARGET_REPO="Future-404/TAV-X.git"
    BEST_URL=""
    
    echo -e "🔎 寻找最佳下载线路..."
    for mirror in "${MIRRORS[@]}"; do
        if [[ "$mirror" == *"github.com"* ]]; then
             TEST_URL="https://github.com/${TARGET_REPO}"
        else
             TEST_URL="${mirror}https://github.com/${TARGET_REPO}/info/refs?service=git-upload-pack"
        fi
        
        echo -ne "   Testing: $(echo $mirror | cut -d/ -f3)... "
        if curl -s -I -m 2 "$TEST_URL" >/dev/null 2>&1; then
            echo -e "${GREEN}OK${NC}"
            if [[ "$mirror" == *"github.com"* ]]; then
                BEST_URL="https://github.com/${TARGET_REPO}"
            else
                BEST_URL="${mirror}https://github.com/${TARGET_REPO}"
            fi
            break
        else
            echo -e "${RED}Fail${NC}"
        fi
    done
    
    if [ -z "$BEST_URL" ]; then
        echo -e "\n${RED}❌ 致命错误：所有线路均不可用。${NC}"
        echo -e "请检查网络连接或代理设置。"
        exit 1
    fi
    echo -e "\n${GREEN}>>> 选中线路: $BEST_URL${NC}"
    rm -rf "$TAVX_DIR/core" "$TAVX_DIR/modules" "$TAVX_DIR/scripts" 2>/dev/null
    TEMP_DIR=$(mktemp -d)
    echo -e "${YELLOW}⬇️  正在拉取文件...${NC}"
    if git clone --depth 1 "$BEST_URL" "$TEMP_DIR"; then
        mkdir -p "$TAVX_DIR"
        cp -rf "$TEMP_DIR"/* "$TAVX_DIR/"
        rm -rf "$TEMP_DIR"
        chmod +x "$TAVX_DIR"/st.sh "$TAVX_DIR"/core/*.sh 2>/dev/null
        
        echo -e "${GREEN}✅ 核心修复完成！启动中...${NC}"
        sleep 1
        exec bash "$TAVX_DIR/core/main.sh"
    else
        echo -e "${RED}❌ 下载失败。${NC}"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
fi