the#!/bin/bash
REPO_URL="https://gh-proxy.com/https://github.com/SillyTavern/SillyTavern.git"
INSTALL_DIR="$HOME/SillyTavern"
CONFIG_FILE="$INSTALL_DIR/config.yaml"
CF_LOG="$INSTALL_DIR/cf_tunnel.log"
SERVER_LOG="$INSTALL_DIR/server.log"
BACKUP_DIR="$HOME/storage/downloads/ST_Backup"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

BREAK_LOOP=false
trap 'BREAK_LOOP=true' SIGINT

auto_setup_alias() {
    SCRIPT_PATH=$(readlink -f "$0")
    RC_FILE="$HOME/.bashrc"
    sed -i '/alias st=/d' "$RC_FILE"
    echo "alias st='bash $SCRIPT_PATH'" >> "$RC_FILE"
}

check_env() {
    auto_setup_alias
    if command -v node &> /dev/null && command -v git &> /dev/null && command -v cloudflared &> /dev/null && command -v setsid &> /dev/null; then
        return 0
    fi
    echo -e "${YELLOW}>>> 正在初始化环境...${NC}"
    pkg update -y
    pkg install nodejs-lts git cloudflared util-linux tar -y
}

configure_security() {
    if [ ! -f "$CONFIG_FILE" ]; then return; fi
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    sed -i 's/whitelistMode: true/whitelistMode: false/' "$CONFIG_FILE"
    sed -i 's/enableUserAccounts: false/enableUserAccounts: true/' "$CONFIG_FILE"
    sed -i 's/enableDiscreetLogin: false/enableDiscreetLogin: true/' "$CONFIG_FILE"
    sed -i 's/enabled: true/enabled: false/' "$CONFIG_FILE"
}

configure_proxy() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}未找到配置文件，请先安装酒馆。${NC}"
        read -p "按回车返回..."
        return
    fi

    clear
    echo -e "${CYAN}=== 代理配置向导 ===${NC}"
    echo -e "当前 requestProxy 设置状态:"
    grep -A 5 "requestProxy:" "$CONFIG_FILE" | grep -E "enabled|url"
    echo ""
    echo -e "1. 🟢 开启/设置代理"
    echo -e "2. 🔴 关闭代理"
    echo -e "0. 🔙 返回"
    echo ""
    read -p "请选择: " proxy_choice

    case $proxy_choice in
        1)
            echo ""
            echo -e "${YELLOW}请输入完整的代理地址 (包含协议、IP和端口)${NC}"
            echo -e "示例:"
            echo -e " - http://127.0.0.1:7890"
            echo -e " - socks5://127.0.0.1:10808"
            echo -e " - http://192.168.1.5:8080"
            echo ""
            read -p "代理 URL: " PROXY_URL
            
            if [ -z "$PROXY_URL" ]; then
                echo -e "${RED}输入不能为空${NC}"
                sleep 1
                return
            fi

            sed -i '/^requestProxy:/,/^  bypass:/ s/enabled: false/enabled: true/' "$CONFIG_FILE"
            sed -i "/^requestProxy:/,/^  bypass:/ s|^  url:.*|  url: \"$PROXY_URL\"|" "$CONFIG_FILE"
            
            echo -e "${GREEN}√ 代理已更新为: $PROXY_URL${NC}"
            echo -e "${YELLOW}请重启服务以生效。${NC}"
            sleep 2
            ;;
        2)
            sed -i '/^requestProxy:/,/^  bypass:/ s/enabled: true/enabled: false/' "$CONFIG_FILE"
            echo -e "${GREEN}√ 代理已关闭${NC}"
            echo -e "${YELLOW}请重启服务以生效。${NC}"
            sleep 1
            ;;
        *)
            return
            ;;
    esac
}

check_storage_permission() {
    if [ ! -d "$HOME/storage" ]; then
        echo -e "${YELLOW}>>> 检测到未授权存储权限...${NC}"
        echo -e "${CYAN}请在接下来的弹窗中点击【允许】，以便将备份保存到下载目录。${NC}"
        termux-setup-storage
        sleep 2
        if [ ! -d "$HOME/storage" ]; then
            echo -e "${RED}错误：无法访问存储。请确保授予权限后重试。${NC}"
            return 1
        fi
    fi
    return 0
}

perform_backup() {
    check_storage_permission || return
    
    if [ ! -d "$INSTALL_DIR/data" ]; then
        echo -e "${RED}错误：找不到酒馆数据目录 ($INSTALL_DIR/data)${NC}"
        read -p "按回车返回..."
        return
    fi

    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
    fi

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/ST_Backup_$TIMESTAMP.tar.gz"

    echo -e "${CYAN}>>> 正在打包数据，请稍候...${NC}"
    cd "$INSTALL_DIR" || return
    # 只打包 data 目录
    tar -czf "$BACKUP_FILE" data

    if [ -f "$BACKUP_FILE" ]; then
        echo -e "${GREEN}✅ 备份成功！${NC}"
        echo -e "文件位置: ${YELLOW}内部存储/Download/ST_Backup/${NC}"
        echo -e "文件名: $(basename "$BACKUP_FILE")"
    else
        echo -e "${RED}❌ 备份失败，请检查存储权限或空间。${NC}"
    fi
    read -p "按回车返回..."
}

perform_restore() {
    check_storage_permission || return

    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${RED}未找到备份目录: $BACKUP_DIR${NC}"
        read -p "按回车返回..."
        return
    fi

    # 使用数组存储备份文件列表
    files=("$BACKUP_DIR"/ST_Backup_*.tar.gz)
    
    if [ ! -e "${files[0]}" ]; then
        echo -e "${RED}在 Download/ST_Backup 中未找到有效的备份文件。${NC}"
        read -p "按回车返回..."
        return
    fi

    clear
    echo -e "${CYAN}=== 选择要恢复的备份文件 ===${NC}"
    echo -e "${YELLOW}注意：这只显示 ST_Backup 开头的 .tar.gz 文件${NC}"
    echo ""

    i=1
    for file in "${files[@]}"; do
        filename=$(basename "$file")
        echo -e "$i. $filename"
        ((i++))
    done
    echo "0. 返回"
    echo ""
    read -p "请选择编号: " file_idx

    if [[ "$file_idx" == "0" ]]; then return; fi

    # 获取选中的文件
    SELECTED_FILE="${files[$((file_idx-1))]}"

    if [ -z "$SELECTED_FILE" ] || [ ! -f "$SELECTED_FILE" ]; then
        echo -e "${RED}无效的选择。${NC}"
        sleep 1
        return
    fi

    echo ""
    echo -e "${RED}⚠️  高危警告 ⚠️${NC}"
    echo -e "您即将从备份 [ $(basename "$SELECTED_FILE") ] 恢复数据。"
    echo -e "${RED}此操作将【彻底删除】当前酒馆内的所有聊天记录和角色！${NC}"
    echo -e "确定要继续吗？"
    read -p "输入 'yes' 确认覆盖: " confirm

    if [[ "$confirm" != "yes" ]]; then
        echo -e "${YELLOW}操作已取消。${NC}"
        sleep 1
        return
    fi

    echo -e "${CYAN}>>> 正在清空旧数据...${NC}"
    rm -rf "$INSTALL_DIR/data"
    
    echo -e "${CYAN}>>> 正在解压恢复...${NC}"
    mkdir -p "$INSTALL_DIR/data"
    tar -xzf "$SELECTED_FILE" -C "$INSTALL_DIR"

    echo -e "${GREEN}✅ 恢复完成！${NC}"
    echo -e "${YELLOW}建议您稍后重启酒馆。${NC}"
    read -p "按回车返回..."
}

backup_menu() {
    while true; do
        clear
        echo -e "${CYAN}=== 💾 数据备份与恢复 ===${NC}"
        echo -e "存储位置: ${YELLOW}手机存储/Download/ST_Backup${NC}"
        echo ""
        echo -e "1. 📤 备份当前数据 (Backup)"
        echo -e "2. 📥 恢复历史备份 (Restore)"
        echo -e "0. 🔙 返回主菜单"
        echo ""
        read -p "请选择: " bk_choice
        case $bk_choice in
            1) perform_backup ;;
            2) perform_restore ;;
            0) return ;;
            *) ;;
        esac
    done
}

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

update_st() {
    echo -e "${CYAN}>>> [1/2] 更新酒馆程序...${NC}"
    cd "$INSTALL_DIR" || exit

    if [[ -n $(git status -s) ]]; then
        git stash
        STASHED=1
    fi

    git pull

    if [[ "$STASHED" == "1" ]]; then git stash pop; fi
    npm install --no-audit --fund
    echo -e "${GREEN}√ 酒馆更新完成${NC}"
    echo ""

    echo -e "${CYAN}>>> [2/2] 检查脚本更新...${NC}"
    REMOTE_URL="https://gh-proxy.com/https://raw.githubusercontent.com/Future-404/TAV-X/main/st.sh"
    LOCAL_PATH=$(readlink -f "$0")

    if curl -s -L -o "${LOCAL_PATH}.tmp" "$REMOTE_URL"; then
        LOCAL_MD5=$(md5sum "$LOCAL_PATH" | awk '{print $1}')
        REMOTE_MD5=$(md5sum "${LOCAL_PATH}.tmp" | awk '{print $1}')

        if [ "$LOCAL_MD5" != "$REMOTE_MD5" ]; then
            echo -e "${YELLOW}发现新版本，正在升级...${NC}"
            mv "${LOCAL_PATH}.tmp" "$LOCAL_PATH"
            chmod +x "$LOCAL_PATH"
            echo -e "${GREEN}√ 脚本升级成功，正在重启...${NC}"
            sleep 1
            exec bash "$LOCAL_PATH"
        else
            echo -e "${GREEN}脚本已是最新版${NC}"
            rm "${LOCAL_PATH}.tmp"
        fi
    else
        echo -e "${RED}网络连接失败，跳过脚本检查${NC}"
    fi

    read -p "按回车返回..."
}

stop_services() {
    pkill -f "node server.js"
    pkill -f "cloudflared"
    termux-wake-unlock 2>/dev/null
}

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
    setsid nohup cloudflared tunnel --url http://127.0.0.1:8000 --no-autoupdate >> "$CF_LOG" 2>&1 &
    echo -e "${GREEN}服务已在后台启动！请在主菜单下方查看链接。${NC}"
    sleep 3
}

start_local() {
    start_server_background
    echo -e "${GREEN}本地模式已启动！${NC}"
    sleep 1.5
}

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

print_banner() {
    echo -e "${CYAN}"
    echo '  ______ ___   _   _      __  __'
    echo ' /_  __//   | | | / /     \ \/ /'
    echo '  / /  / /| | | |/ /       \  / '
    echo ' / /  / ___ | |   /        /  \ '
    echo '/_/  /_/  |_| |__/        /_/\_\'
    echo -e "${NC}"
    echo -e "                                  ${YELLOW}by Future404${NC}"
    echo -e "${CYAN}======================================${NC}"
}

show_menu() {
    while true; do
        BREAK_LOOP=false
        clear
        print_banner
        echo -e "${CYAN}             Version 1.3${NC}"

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
        echo -e "  7. 🌐 设置代理配置"
        echo -e "  8. 💾 数据备份与恢复"
        echo -e "  0. 退出"
        echo ""

        if [ "$IS_RUNNING" = true ]; then
             echo -e "${CYAN}====== [ 实时链接仪表盘 ] ======${NC}"
             LINK=$(grep -o "https://[-a-zA-Z0-9]*\.trycloudflare\.com" "$CF_LOG" 2>/dev/null | grep -v "api" | tail -n 1)

             if [ -n "$LINK" ]; then
                 echo -e "🌍 ${GREEN}$LINK${NC}"
                 echo -e "(长按上方链接可复制)"
             else
                 if pgrep -f "cloudflared" > /dev/null; then
                     echo -e "📡 ${YELLOW}正在获取链接... (按回车 刷新)${NC}"
                 else
                     echo -e "🏠 ${GREEN}本地模式运行中: http://127.0.0.1:8000${NC}"
                 fi
             fi
             echo ""
        fi

        read -p "请选择: " choice
        case $choice in
            1) check_env; install_st; start_share ;;
            2) check_env; install_st; start_local ;;
            3) view_logs ;;
            4) stop_services; echo -e "${RED}已停止${NC}"; sleep 1 ;;
            5) check_env; update_st ;;
            6) configure_security; echo "完成"; sleep 1 ;;
            7) configure_proxy ;;
            8) backup_menu ;;
            0) exec bash ;;
            *) ;;
        esac
    done
}

check_env
if [ ! -d "$INSTALL_DIR" ]; then install_st; fi
show_menu