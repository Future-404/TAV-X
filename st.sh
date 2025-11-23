#!/bin/bash

# ================= 配置区域 =================
REPO_URL="https://gh-proxy.com/https://github.com/SillyTavern/SillyTavern.git"
INSTALL_DIR="$HOME/SillyTavern"
CONFIG_FILE="$INSTALL_DIR/config.yaml"
CF_LOG="$INSTALL_DIR/cf_tunnel.log"
SERVER_LOG="$INSTALL_DIR/server.log"
# ===========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# === 全局中断控制 ===
BREAK_LOOP=false
trap 'BREAK_LOOP=true' SIGINT

# === 0. 自动化快捷指令 ===
auto_setup_alias() {
    SCRIPT_PATH=$(readlink -f "$0")
    RC_FILE="$HOME/.bashrc"
    if ! grep -q "alias st=" "$RC_FILE" 2>/dev/null; then
        echo "" >> "$RC_FILE"
        echo "# SillyTavern Shortcut" >> "$RC_FILE"
        echo "alias st='bash $SCRIPT_PATH'" >> "$RC_FILE"
    fi
}

# === 1. 环境检查 ===
check_env() {
    auto_setup_alias
    if command -v node &> /dev/null && command -v git &> /dev/null && command -v cloudflared &> /dev/null && command -v setsid &> /dev/null; then
        return 0
    fi
    echo -e "${YELLOW}>>> 正在初始化环境...${NC}"
    pkg update -y
    pkg install nodejs-lts git cloudflared util-linux -y
}

# === 2. 安全配置 ===
configure_security() {
    if [ ! -f "$CONFIG_FILE" ]; then return; fi
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    sed -i 's/whitelistMode: true/whitelistMode: false/' "$CONFIG_FILE"
    sed -i 's/enableUserAccounts: false/enableUserAccounts: true/' "$CONFIG_FILE"
    sed -i 's/enableDiscreetLogin: false/enableDiscreetLogin: true/' "$CONFIG_FILE"
    sed -i 's/enabled: true/enabled: false/' "$CONFIG_FILE"
}

# === 3. 安装/重装 ===
install_st() {
    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${CYAN}>>> 正在下载 SillyTavern...${NC}"
        git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
        cd "$INSTALL_DIR"
        npm config set registry https://registry.npmmirror.com
        npm install --no-audit --fund
        if [ ! -f "$CONFIG_FILE" ] && [ -f "$INSTALL_DIR/default/config.yaml" ]; then
            cp "$INSTALL_DIR/default/config.yaml" "$CONFIG_FILE"
        fi
        configure_security
    fi
}

# === 4. 无损更新 ===
update_st() {
    echo -e "${CYAN}>>> 正在无损更新...${NC}"
    cd "$INSTALL_DIR" || exit
    if [[ -n $(git status -s) ]]; then
        git stash
        STASHED=1
    fi
    git pull
    npm install --no-audit --fund
    if [[ "$STASHED" == "1" ]]; then git stash pop; fi
    echo -e "${GREEN}更新完成！${NC}"
    read -p "按回车继续..."
}

# === 5. 停止服务 ===
stop_services() {
    pkill -f "node server.js"
    pkill -f "cloudflared tunnel"
    termux-wake-unlock 2>/dev/null
}

# === 6. 启动逻辑 ===
start_server_background() {
    stop_services
    termux-wake-lock
    cd "$INSTALL_DIR" || exit
    echo -e "${CYAN}>>> 正在后台启动酒馆...${NC}"
    setsid nohup node server.js > "$SERVER_LOG" 2>&1 &
}

start_share() {
    start_server_background
    echo "正在连接 Cloudflare..." > "$CF_LOG"
    setsid nohup cloudflared tunnel --protocol http2 --url http://localhost:8000 >> "$CF_LOG" 2>&1 &
    echo -e "${GREEN}服务已在后台启动！请在主菜单下方查看链接。${NC}"
    sleep 1.5
}

start_local() {
    start_server_background
    echo -e "${GREEN}本地模式已启动！${NC}"
    sleep 1.5
}

# === 7. 查看日志 ===
view_logs() {
    BREAK_LOOP=false
    clear
    echo -e "${CYAN}=== 酒馆实时日志 ===${NC}"
    echo -e "${YELLOW}按 Ctrl + C 返回主菜单${NC}"
    echo ""
    if [ -f "$SERVER_LOG" ]; then
        while true; do
            if [ "$BREAK_LOOP" = "true" ]; then BREAK_LOOP=false; break; fi
            clear
            echo -e "${CYAN}=== 酒馆实时日志 (Ctrl+C 退出) ===${NC}"
            tail -n 20 "$SERVER_LOG"
            sleep 1
        done
    else
        echo -e "${RED}暂无日志文件。${NC}"
        read -p "按回车返回..."
    fi
}

# === 8. 艺术字标题 ===
print_banner() {
    echo -e "${CYAN}"
    echo '  ______ ___   _   _      __  __'
    echo ' /_  __//   | | | / /     \ \/ /'
    echo '  / /  / /| | | |/ /       \  / '
    echo ' / /  / ___ | |   /        /  \ '
    echo '/_/  /_/  |_| |__/        /_/\_\'
    echo -e "${NC}"
    # 署名靠右 (34个空格)
    echo -e "                                  ${YELLOW}by Future404${NC}"
    echo -e "${CYAN}======================================${NC}"
}

# === 9. 主菜单 (集成仪表盘) ===
show_menu() {
    while true; do
        BREAK_LOOP=false
        clear
        print_banner
        
        # 检查运行状态
        if pgrep -f "node server.js" > /dev/null; then
            echo -e "状态: ${GREEN}● 运行中${NC}"
            IS_RUNNING=true
        else
            echo -e "状态: ${RED}● 已停止${NC}"
            IS_RUNNING=false
        fi
        
        echo ""
        echo -e "  1. 🚀 启动远程分享"
        echo -e "  2. 🏠 启动本地模式"
        echo -e "  3. 📜 查看运行日志"
        echo -e "  4. 🛑 停止所有服务"
        echo -e "  5. 🔄 无损更新"
        echo -e "  6. 🛠️  重置安全配置"
        echo -e "  0. 退出"
        echo ""
        
        # === 实时链接显示区域 ===
        if [ "$IS_RUNNING" = true ]; then
             echo -e "${CYAN}====== [ 实时链接仪表盘 ] ======${NC}"
             # 1. 检查 Cloudflare 日志
             LINK=$(grep -o "https://[-a-zA-Z0-9]*\.trycloudflare\.com" "$CF_LOG" 2>/dev/null | grep -v "api" | tail -n 1)
             
             if [ -n "$LINK" ]; then
                 echo -e "🌍 ${GREEN}$LINK${NC}"
                 echo -e "(长按上方链接可复制)"
             else
                 # 如果没有链接，判断是不是在跑本地模式
                 if pgrep -f "cloudflared" > /dev/null; then
                     echo -e "📡 ${YELLOW}正在获取链接... (按回车刷新)${NC}"
                 else
                     echo -e "🏠 ${GREEN}本地模式运行中: http://127.0.0.1:8000${NC}"
                 fi
             fi
             echo ""
        fi
        # ==========================

        read -p "请选择: " choice
        case $choice in
            1) check_env; install_st; start_share ;;
            2) check_env; install_st; start_local ;;
            3) view_logs ;;
            4) stop_services; echo -e "${RED}已停止${NC}"; sleep 1 ;;
            5) check_env; update_st ;;
            6) configure_security; echo "完成"; sleep 1 ;;
            0) exit 0 ;;
            *) ;;
        esac
    done
}

# === 入口 ===
check_env
if [ ! -d "$INSTALL_DIR" ]; then install_st; fi
show_menu
