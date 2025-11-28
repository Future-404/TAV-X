#!/bin/bash
# TAV-X Module: ClewdR Manager
# 依赖环境变量: TAV_DL_CMD, TAV_DL_MODE, TAV_MIRROR_PREFIX

# --- 基础配置 ---
# 安装目录放在 .tav_x 下，保持整洁
INSTALL_DIR="$HOME/.tav_x/clewdr"
BIN_FILE="$INSTALL_DIR/clewdr"
CONF_FILE="$INSTALL_DIR/clewdr.toml"
LOG_FILE="$INSTALL_DIR/clewdr.log"
SECRETS_FILE="$INSTALL_DIR/secrets.env"

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- 核心函数 ---

check_env() {
    mkdir -p "$INSTALL_DIR"
    if ! command -v unzip &> /dev/null; then
        echo -e "${YELLOW}>>> 检测到缺失解压工具，正在安装...${NC}"
        pkg install unzip -y
    fi
}

download_clewdr() {
    echo -e "${CYAN}>>> 正在下载 ClewdR (Android版)...${NC}"
    
    # 目标 URL (使用 latest 保证最新)
    # 注意：这里我们只下载基础版 zip，不带数据库功能，最适合 Termux
    TARGET_URL="https://github.com/Xerxes-2/clewdr/releases/latest/download/clewdr-android-aarch64.zip"
    
    cd "$INSTALL_DIR" || return

    # === [核心] 复用主脚本传递的下载策略 ===
    if [ -z "$TAV_DL_CMD" ]; then
        # 如果单独运行此脚本没有环境变量，回退到默认 curl
        TAV_DL_CMD="curl -L -O" 
    fi

    if [ "$TAV_DL_MODE" == "MIRROR" ]; then
        # 镜像模式：拼接前缀
        FULL_URL="${TAV_MIRROR_PREFIX}${TARGET_URL}"
        echo -e "${YELLOW}使用镜像源加速下载...${NC}"
        $TAV_DL_CMD "$FULL_URL"
    else
        # 代理/直连模式：直接下载
        echo -e "${YELLOW}使用代理/直连下载...${NC}"
        $TAV_DL_CMD "$TARGET_URL"
    fi
    # =======================================

    if [ -f "clewdr-android-aarch64.zip" ]; then
        echo -e "${YELLOW}>>> 解压中...${NC}"
        unzip -o clewdr-android-aarch64.zip
        chmod +x clewdr
        rm clewdr-android-aarch64.zip
        echo -e "${GREEN}✅ 安装/更新完成！${NC}"
    else
        echo -e "${RED}❌ 下载失败，请检查网络或代理设置。${NC}"
    fi
}

start_clewdr() {
    if [ ! -f "$BIN_FILE" ]; then
        echo -e "${RED}❌ 未找到程序，请先执行 [5] 强制重装。${NC}"
        read -p "按回车返回..."
        return
    fi

    stop_clewdr "silent" # 先停止旧进程

    echo -e "${CYAN}>>> 正在启动服务...${NC}"
    cd "$INSTALL_DIR" || return
    
    # 后台运行，覆盖日志
    nohup ./clewdr > "$LOG_FILE" 2>&1 &
    
    echo -e "${YELLOW}⏳ 正在等待服务初始化并提取密码 (约3秒)...${NC}"
    sleep 3
    
    if pgrep -f "./clewdr" > /dev/null; then
        # === [核心] 提取密码并缓存 ===
        # 提取 API Password
        API_PASS=$(grep "API Password:" "$LOG_FILE" | head -n 1 | awk '{print $3}')
        # 提取 Web Admin Password
        WEB_PASS=$(grep "Web Admin Password:" "$LOG_FILE" | head -n 1 | awk '{print $4}')
        
        # 写入缓存文件
        echo "API_PASS=$API_PASS" > "$SECRETS_FILE"
        echo "WEB_PASS=$WEB_PASS" >> "$SECRETS_FILE"
        
        echo -e "${GREEN}✅ 服务启动成功！${NC}"
        echo -e "----------------------------------------"
        echo -e "管理面板: ${CYAN}http://127.0.0.1:8484${NC}"
        echo -e "管理密码: ${YELLOW}$WEB_PASS${NC}"
        echo -e "酒馆 Key: ${YELLOW}$API_PASS${NC}"
        echo -e "----------------------------------------"
        echo -e "提示：密码已缓存，后续可在菜单 [2] 中查看。"
    else
        echo -e "${RED}❌ 启动失败，请查看日志。${NC}"
        cat "$LOG_FILE"
    fi
    read -p "按回车返回..."
}

stop_clewdr() {
    if pgrep -f "./clewdr" > /dev/null; then
        pkill -f "./clewdr"
        if [ "$1" != "silent" ]; then echo -e "${GREEN}✅ 服务已停止。${NC}"; sleep 1; fi
    else
        if [ "$1" != "silent" ]; then echo -e "${RED}未检测到运行中的服务。${NC}"; sleep 1; fi
    fi
}

show_secrets() {
    if [ -f "$SECRETS_FILE" ]; then
        source "$SECRETS_FILE"
        echo -e "${CYAN}=== 🔑 身份凭证 (缓存) ===${NC}"
        echo -e "Web 管理面板: ${GREEN}http://127.0.0.1:8484${NC}"
        echo -e "Web 登录密码: ${YELLOW}${WEB_PASS}${NC}"
        echo "----------------------------------------"
        echo -e "酒馆 API 地址: ${GREEN}http://127.0.0.1:8484/v1${NC}"
        echo -e "酒馆 API 密钥: ${YELLOW}${API_PASS}${NC}"
        echo "----------------------------------------"
        echo -e "提示: 如果密码不正确，请尝试 [1] 重启服务以刷新缓存。"
    else
        echo -e "${RED}❌ 暂无缓存信息。请先启动服务。${NC}"
    fi
    read -p "按回车返回..."
}

uninstall_clewdr() {
    echo -e "${RED}⚠️  警告: 这将删除 ClewdR 程序及所有配置文件！${NC}"
    read -p "确认卸载吗？(y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        stop_clewdr "silent"
        rm -rf "$INSTALL_DIR"
        echo -e "${GREEN}✅ 已彻底卸载。${NC}"
    else
        echo -e "已取消。"
    fi
    sleep 1
}

view_logs() {
    if [ -f "$LOG_FILE" ]; then
        clear
        echo -e "${CYAN}=== 📜 实时日志 (Ctrl+C 退出) ===${NC}"
        tail -n 30 -f "$LOG_FILE"
    else
        echo -e "${RED}暂无日志文件。${NC}"
        sleep 1
    fi
}

# --- 菜单逻辑 ---
check_env

# 首次运行如果没文件，自动进入下载流程
if [ ! -f "$BIN_FILE" ]; then
    echo -e "${YELLOW}>>> 检测到未安装 ClewdR，开始初始化...${NC}"
    download_clewdr
fi

while true; do
    clear
    echo -e "${CYAN}=== 🦀 ClewdR 管理面板 ===${NC}"
    
    if pgrep -f "./clewdr" > /dev/null; then
        PID=$(pgrep -f "./clewdr" | head -n 1)
        echo -e "状态: ${GREEN}● 运行中 (PID: $PID)${NC}"
    else
        echo -e "状态: ${RED}● 已停止${NC}"
    fi
    echo "----------------------------------------"
    echo -e "1. 🚀 启动/重启服务 (Start/Restart)"
    echo -e "2. 🔑 查看连接信息 (Show Secrets)"
    echo -e "3. 📜 查看实时日志 (View Logs)"
    echo -e "4. 🛑 停止服务 (Stop)"
    echo -e "5. 📥 强制更新/重装 (Update/Reinstall)"
    echo -e "6. 🗑️ 卸载 ClewdR (Uninstall)"
    echo -e "0. 🔙 返回主菜单"
    echo ""
    
    read -p "选择: " choice
    case $choice in
        1) start_clewdr ;;
        2) show_secrets ;;
        3) view_logs ;;
        4) stop_clewdr ;;
        5) download_clewdr; read -p "按回车继续..." ;;
        6) uninstall_clewdr; exit 0 ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效输入${NC}"; sleep 0.5 ;;
    esac
done
