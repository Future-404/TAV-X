the#!/bin/bash
# TAV-X v1.7.1 - 更新逻辑修复版

# --- 常量定义 ---
MIRROR_CONFIG="$HOME/.st_mirror_url"
PROXY_CONFIG_FILE="$HOME/.st_download_proxy"
INSTALL_DIR="$HOME/SillyTavern"
CONFIG_FILE="$INSTALL_DIR/config.yaml"
CF_LOG="$INSTALL_DIR/cf_tunnel.log"
SERVER_LOG="$INSTALL_DIR/server.log"
BACKUP_DIR="$HOME/storage/downloads/ST_Backup"
DEFAULT_MIRROR="https://gh-proxy.com/"

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- 信号捕获 ---
BREAK_LOOP=false
trap 'BREAK_LOOP=true' SIGINT

# --- 辅助函数 ---

get_current_config() {
    if [ -f "$PROXY_CONFIG_FILE" ]; then
        echo "PROXY:$(cat "$PROXY_CONFIG_FILE")"
    elif [ -f "$MIRROR_CONFIG" ]; then
        echo "MIRROR:$(cat "$MIRROR_CONFIG")"
    else
        echo "MIRROR:$DEFAULT_MIRROR"
    fi
}

auto_setup_alias() {
    SCRIPT_PATH=$(readlink -f "$0")
    RC_FILE="$HOME/.bashrc"
    sed -i '/alias st=/d' "$RC_FILE"
    echo "alias st='bash $SCRIPT_PATH'" >> "$RC_FILE"
    source "$RC_FILE" 2>/dev/null
}

check_env() {
    auto_setup_alias
    if command -v node &> /dev/null && command -v git &> /dev/null && command -v cloudflared &> /dev/null && command -v setsid &> /dev/null; then
        return 0
    fi
    echo -e "${YELLOW}>>> 正在初始化环境...${NC}"
    pkg update -y
    pkg install nodejs-lts git cloudflared util-linux tar nmap -y
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

# --- 核心逻辑函数 ---

apply_global_optimizations() {
    if [ ! -f "$CONFIG_FILE" ]; then return; fi
    sed -i 's/enableUserAccounts: false/enableUserAccounts: true/' "$CONFIG_FILE"
    sed -i 's/lazyLoadCharacters: false/lazyLoadCharacters: true/' "$CONFIG_FILE"
    sed -i 's/useDiskCache: true/useDiskCache: false/' "$CONFIG_FILE"
    sed -i 's/enableDiscreetLogin: false/enableDiscreetLogin: true/' "$CONFIG_FILE"
}

ensure_whitelist_off() {
    if [ ! -f "$CONFIG_FILE" ]; then return; fi
    if grep -q "whitelistMode: true" "$CONFIG_FILE"; then
        echo -e "${YELLOW}>>> 检测到白名单已开启，正在为远程模式关闭它...${NC}"
        sed -i 's/whitelistMode: true/whitelistMode: false/' "$CONFIG_FILE"
        sleep 0.5
    fi
}

# --- 验证工具函数 ---

validate_proxy_format() {
    local proxy=$1
    if [[ "$proxy" =~ ^(http|https|socks5|socks5h)://.+ ]]; then
        return 0
    else
        return 1
    fi
}

test_proxy_connection() {
    local proxy=$1
    echo -e "${YELLOW}>>> 正在测试代理连通性 ($proxy)...${NC}"
    if curl -s -o /dev/null --connect-timeout 5 --proxy "$proxy" https://www.google.com; then
        return 0
    else
        return 1
    fi
}

test_mirror_connection() {
    local mirror=$1
    echo -e "${YELLOW}>>> 正在测试镜像连通性...${NC}"
    if curl -s -o /dev/null --connect-timeout 5 "${mirror}https://github.com"; then
        return 0
    else
        return 1
    fi
}

# --- 功能菜单函数 ---

select_mirror() {
    clear
    echo -e "${CYAN}=== 🌐 Github 下载线路配置 ===${NC}"
    echo -e "正在测试线路连通性 (超时限制: 5秒)..."
    mirrors=(
        "https://gh-proxy.com/"
        "https://edgeone.gh-proxy.com/"
        "https://hk.gh-proxy.com/"
        "https://gh.likk.cc/"
        "https://github.moeyy.xyz/"
        "https://mirror.ghproxy.com/"
    )

    printf "%-4s %-10s %-30s\n" "编号" "状态" "线路地址"
    echo "------------------------------------------------"

    i=1
    valid_indices=()
    for mirror in "${mirrors[@]}"; do
        if curl -s -o /dev/null --connect-timeout 5 "${mirror}https://github.com"; then
            status="${GREEN}🟢 通畅${NC}"
        else
            status="${RED}🔴 超时${NC}"
        fi
        printf "%-4s %-15b %-30s\n" "$i." "$status" "$mirror"
        valid_indices+=($i)
        ((i++))
    done

    echo "------------------------------------------------"
    echo -e "${YELLOW}如果上方全是🔴，请选择选项 8 使用您自己的梯子${NC}"
    echo -e "7. 自定义镜像地址"
    echo -e "8. 使用代理直连 (Use Proxy) ${GREEN}[推荐]${NC}"
    echo -e "0. 返回"
    echo ""
    read -p "请选择: " choice

    case $choice in
        0) return ;;
        8)
            while true; do
                echo -e "${YELLOW}请输入您的代理地址 (支持 http/https/socks5/socks5h)${NC}"
                echo -e "示例: socks5://127.0.0.1:10808"
                read -p "代理地址 (输入 0 取消): " user_proxy
                
                if [ "$user_proxy" == "0" ]; then return; fi

                if ! validate_proxy_format "$user_proxy"; then
                    echo -e "${RED}❌ 格式错误！必须以 http:// 或 socks5:// 等开头。${NC}"
                    continue
                fi

                if test_proxy_connection "$user_proxy"; then
                    echo "$user_proxy" > "$PROXY_CONFIG_FILE"
                    rm -f "$MIRROR_CONFIG"
                    echo -e "${GREEN}✅ 测试通过！已设置为代理模式。${NC}"
                    sleep 1
                    break
                else
                    echo -e "${RED}❌ 连接测试失败！请检查您的梯子软件是否开启。${NC}"
                fi
            done
            ;;
        7)
            while true; do
                echo -e "${YELLOW}请输入自定义加速前缀 (必须以 http 开头，以 / 结尾)${NC}"
                read -p "地址 (输入 0 取消): " custom_url
                
                if [ "$custom_url" == "0" ]; then return; fi

                if [[ $custom_url == http* ]]; then
                    [[ "${custom_url}" != */ ]] && custom_url="${custom_url}/"
                    
                    if test_mirror_connection "$custom_url"; then
                        echo "$custom_url" > "$MIRROR_CONFIG"
                        rm -f "$PROXY_CONFIG_FILE"
                        echo -e "${GREEN}✅ 镜像可用！已切换。${NC}"
                        break
                    else
                         echo -e "${RED}❌ 镜像不可用或超时。${NC}"
                    fi
                else
                    echo -e "${RED}地址格式错误！${NC}"
                fi
            done
            ;;
        *)
            if [[ " ${valid_indices[*]} " =~ " ${choice} " ]]; then
                idx=$((choice - 1))
                echo "${mirrors[$idx]}" > "$MIRROR_CONFIG"
                rm -f "$PROXY_CONFIG_FILE"
                echo -e "${GREEN}√ 已切换至镜像: ${mirrors[$idx]}${NC}"
            else
                echo -e "${RED}无效选择${NC}"
            fi
            ;;
    esac
    sleep 1
}

configure_security_original() {
    if [ ! -f "$CONFIG_FILE" ]; then return; fi
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    sed -i 's/whitelistMode: true/whitelistMode: false/' "$CONFIG_FILE"
    sed -i 's/enableUserAccounts: false/enableUserAccounts: true/' "$CONFIG_FILE"
    sed -i 's/enableDiscreetLogin: false/enableDiscreetLogin: true/' "$CONFIG_FILE"
    sed -i '/^browserLaunch:/,/^  [a-z]/ s/enabled: true/enabled: false/' "$CONFIG_FILE"
}

reset_password_logic() {
    cd "$INSTALL_DIR" || return
    if [ ! -f "recover.js" ]; then
        echo -e "${RED}错误：找不到 recover.js 脚本。${NC}"
        read -p "按回车返回..."
        return
    fi
    clear
    echo -e "${CYAN}=== 🔐 用户密码重置工具 ===${NC}"
    echo "------------------------"
    if [ -d "data" ]; then ls -F data/ | grep "/" | sed 's/\///g'; else echo "无法读取数据目录"; fi
    echo "------------------------"
    read -p "用户名 [默认: default-user]: " TARGET_USER
    TARGET_USER=${TARGET_USER:-default-user}
    read -p "新密码 [默认: 123456]: " NEW_PASS
    NEW_PASS=${NEW_PASS:-123456}
    node recover.js "$TARGET_USER" "$NEW_PASS"
    echo -e "${GREEN}✅ 操作完成！${NC}"
    read -p "按回车返回..."
}

security_menu() {
    while true; do
        clear
        echo -e "${CYAN}=== 🛠️ 安全配置菜单 ===${NC}"
        echo -e "1. 🔓 修复白名单/免密登录"
        echo -e "2. 🔑 重置用户密码"
        echo -e "0. 🔙 返回"
        read -p "请选择: " sec_choice
        case $sec_choice in
            1) configure_security_original; echo -e "${GREEN}完成。${NC}"; sleep 1 ;;
            2) reset_password_logic ;;
            0) return ;;
        esac
    done
}

configure_proxy() {
    if [ ! -f "$CONFIG_FILE" ]; then echo -e "${RED}找不到配置文件。${NC}"; sleep 1; return; fi
    clear
    echo -e "${CYAN}=== 代理配置向导 ===${NC}"
    grep -A 5 "requestProxy:" "$CONFIG_FILE" | grep -E "enabled|url"
    echo ""
    echo -e "1. 🟢 开启/设置代理"
    echo -e "2. 🔴 关闭代理"
    echo -e "0. 🔙 返回"
    read -p "请选择: " pc
    case $pc in
        1)
            while true; do
                echo -e "请输入完整代理地址 (支持 http/https/socks5)"
                echo -e "示例: http://127.0.0.1:7890"
                read -p "URL (输入 0 返回): " PURL
                
                if [ "$PURL" == "0" ]; then break; fi

                if ! validate_proxy_format "$PURL"; then
                    echo -e "${RED}❌ 格式错误！必须以 http:// 或 socks5:// 开头。${NC}"
                    continue
                fi

                if test_proxy_connection "$PURL"; then
                    sed -i '/^requestProxy:/,/^  bypass:/ s/enabled: false/enabled: true/' "$CONFIG_FILE"
                    sed -i "/^requestProxy:/,/^  bypass:/ s|^  url:.*|  url: \"$PURL\"|" "$CONFIG_FILE"
                    echo "$PURL" > "$PROXY_CONFIG_FILE"
                    echo -e "${GREEN}✅ 设置成功并已同步至下载代理。${NC}"
                    sleep 1
                    break
                else
                    echo -e "${RED}❌ 连接测试失败，无法连接到 Google。请检查端口。${NC}"
                fi
            done
            ;;
        2)
            sed -i '/^requestProxy:/,/^  bypass:/ s/enabled: true/enabled: false/' "$CONFIG_FILE"
            rm -f "$PROXY_CONFIG_FILE"
            echo -e "${GREEN}已关闭。${NC}"; sleep 1
            ;;
        *) return ;;
    esac
}

check_storage_permission() {
    if [ ! -d "$HOME/storage" ]; then
        echo -e "${CYAN}请在弹窗中点击【允许】以访问存储。${NC}"
        termux-setup-storage
        sleep 2
        [ ! -d "$HOME/storage" ] && return 1
    fi
    return 0
}

perform_backup() {
    check_storage_permission || return
    [ ! -d "$INSTALL_DIR/data" ] && return
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/ST_Backup_$TIMESTAMP.tar.gz"
    echo -e "${CYAN}正在备份...${NC}"
    cd "$INSTALL_DIR" || return
    tar -czf "$BACKUP_FILE" data
    if [ -f "$BACKUP_FILE" ]; then
        echo -e "${GREEN}✅ 备份成功: $(basename "$BACKUP_FILE")${NC}"
    else
        echo -e "${RED}❌ 备份失败${NC}"
    fi
    read -p "按回车返回..."
}

perform_restore() {
    check_storage_permission || return
    [ ! -d "$BACKUP_DIR" ] && echo "${RED}无备份目录${NC}" && sleep 1 && return
    files=("$BACKUP_DIR"/ST_Backup_*.tar.gz)
    [ ! -e "${files[0]}" ] && echo "${RED}无备份文件${NC}" && sleep 1 && return
    
    clear
    echo -e "${CYAN}选择备份恢复:${NC}"
    i=1
    for file in "${files[@]}"; do
        echo "$i. $(basename "$file")"
        ((i++))
    done
    echo "0. 返回"
    read -p "选择: " idx
    [ "$idx" == "0" ] && return
    
    SELECTED="${files[$((idx-1))]}"
    [ -z "$SELECTED" ] && return

    echo -e "${RED}⚠️  警告: 将覆盖当前数据!${NC}"
    read -p "输入 yes 确认: " confirm
    if [ "$confirm" == "yes" ]; then
        rm -rf "$INSTALL_DIR/data"
        mkdir -p "$INSTALL_DIR/data"
        tar -xzf "$SELECTED" -C "$INSTALL_DIR"
        echo -e "${GREEN}✅ 恢复完成${NC}"
    fi
    read -p "按回车返回..."
}

install_st() {
    CONFIG_STR=$(get_current_config)
    TYPE=${CONFIG_STR%%:*}
    VALUE=${CONFIG_STR#*:}

    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${CYAN}>>> 开始部署...${NC}"
        GIT_CMD="git clone --depth 1"
        URL=""
        if [ "$TYPE" == "PROXY" ]; then
            echo -e "${YELLOW}>>> 使用代理下载模式: $VALUE${NC}"
            GIT_CMD="git clone --depth 1 -c http.proxy=$VALUE"
            URL="https://github.com/SillyTavern/SillyTavern.git"
        else
            echo -e "${YELLOW}>>> 使用镜像下载模式: $VALUE${NC}"
            URL="${VALUE}https://github.com/SillyTavern/SillyTavern.git"
        fi
        
        if ! $GIT_CMD "$URL" "$INSTALL_DIR"; then
            echo -e "${RED}❌ 下载失败，进入线路选择...${NC}"
            sleep 2
            select_mirror
            install_st
            return
        fi
        cd "$INSTALL_DIR" || return
        npm config set registry https://registry.npmmirror.com
        npm install --no-audit --fund
        if [ -f "$INSTALL_DIR/default/config.yaml" ]; then
            cp "$INSTALL_DIR/default/config.yaml" "$CONFIG_FILE"
        fi
    else
        if [ ! -d "$INSTALL_DIR/node_modules" ]; then
            echo -e "${YELLOW}>>> 修复依赖...${NC}"
            cd "$INSTALL_DIR" || return
            npm install --no-audit --fund
        fi
    fi
}

update_st() {
    CONFIG_STR=$(get_current_config)
    TYPE=${CONFIG_STR%%:*}
    VALUE=${CONFIG_STR#*:}
    echo -e "${CYAN}>>> [1/2] 更新酒馆程序...${NC}"
    cd "$INSTALL_DIR" || exit
    
    if [ "$TYPE" == "PROXY" ]; then git config http.proxy "$VALUE"; else git config --unset http.proxy; fi
    
    if [[ -n $(git status -s) ]]; then git stash; STASHED=1; fi
    
    # === 更新的核心逻辑修改 ===
    if ! git pull; then
        echo -e "${RED}❌ 更新失败！网络超时或代理配置错误。${NC}"
        if [ "$TYPE" == "PROXY" ]; then git config --unset http.proxy; fi
        
        echo -e "${YELLOW}>>> 是否进入线路/代理切换向导？(y/n)${NC}"
        read -p "选择: " retry_choice
        if [[ "$retry_choice" == "y" ]]; then
            select_mirror
            # 递归重试，使用新配置
            update_st
            return
        else
            echo -e "${RED}更新中止。${NC}"
            if [[ "$STASHED" == "1" ]]; then git stash pop; fi
            read -p "按回车返回..."
            return
        fi
    fi
    # ========================

    if [ "$TYPE" == "PROXY" ]; then git config --unset http.proxy; fi
    if [[ "$STASHED" == "1" ]]; then git stash pop; fi
    
    npm install --no-audit --fund
    echo -e "${GREEN}完成。${NC}"; read -p "按回车返回..."
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
    echo -e "${CYAN}>>> 启动酒馆...${NC}"
    setsid nohup node server.js > "$SERVER_LOG" 2>&1 &
}

start_share() {
    ensure_whitelist_off
    start_server_background
    echo "正在连接 Cloudflare..." > "$CF_LOG"
    setsid nohup cloudflared tunnel --protocol http2 --url http://127.0.0.1:8000 --no-autoupdate >> "$CF_LOG" 2>&1 &
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
    echo -e "${CYAN}=== 实时日志 (Ctrl+C 退出) ===${NC}"
    if [ -f "$SERVER_LOG" ]; then
        while true; do
            if [ "$BREAK_LOOP" = "true" ]; then BREAK_LOOP=false; break; fi
            clear; echo -e "${CYAN}=== 实时日志 (Ctrl+C 退出) ===${NC}"
            tail -n 20 "$SERVER_LOG"
            sleep 1
        done
    else
        echo -e "${RED}无日志文件${NC}"; read -p "回车返回..."
    fi
}

exit_script() {
    exec bash
}

show_menu() {
    while true; do
        BREAK_LOOP=false
        clear
        print_banner
        echo -e "${CYAN}             Version 1.7.1${NC}"
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
        echo -e "  6. 🛠️  安全与密码配置"
        echo -e "  7. 🌐 设置 API 代理配置"
        echo -e "  8. 💾 数据备份与恢复"
        echo -e "  9. 🌐 切换 下载 线路/代理"
        echo -e "  0. 退出"
        echo ""
        
        if [ "$IS_RUNNING" = true ]; then
             echo -e "${CYAN}====== [ 实时链接仪表盘 ] ======${NC}"
             LINK=$(grep -o "https://[-a-zA-Z0-9]*\.trycloudflare\.com" "$CF_LOG" 2>/dev/null | grep -v "api" | tail -n 1)
             if [ -n "$LINK" ]; then
                 echo -e "🌍 ${GREEN}$LINK${NC}"
                 echo -e "(长按上方链接可复制)"
             else
                 echo -e "📡 ${YELLOW}正在获取链接... (按回车刷新)${NC}"
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
            6) security_menu ;;
            7) configure_proxy ;;
            8) backup_menu ;;
            9) select_mirror ;;
            0) exit_script ;;
            *) ;;
        esac
    done
}

# --- 主执行流 ---
check_env
auto_setup_alias
if [ ! -d "$INSTALL_DIR" ]; then install_st; fi
if [ -d "$INSTALL_DIR" ]; then apply_global_optimizations; fi
show_menu