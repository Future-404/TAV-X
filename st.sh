#!/bin/bash
# TAV-X v1.12.5
CURRENT_VERSION="v1.12.5"
MIRROR_CONFIG="$HOME/.st_mirror_url"
PROXY_CONFIG_FILE="$HOME/.st_download_proxy"
INSTALL_DIR="$HOME/SillyTavern"
CONFIG_FILE="$INSTALL_DIR/config.yaml"
TAVX_DIR="$HOME/.tav_x"
CACHE_DIR="$TAVX_DIR/cache"
VERSION_FILE="$CACHE_DIR/latest_version"
CF_LOG="$INSTALL_DIR/cf_tunnel.log"
SERVER_LOG="$INSTALL_DIR/server.log"
BACKUP_DIR="$HOME/storage/downloads/ST_Backup"
DEFAULT_MIRROR="https://mirror.ghproxy.com/"
SCRIPT_URL_BASE="https://gh-proxy.org/https://raw.githubusercontent.com/Future-404/TAV-X/main/st.sh"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BREAK_LOOP=false
trap 'BREAK_LOOP=true' SIGINT
NEW_VERSION_AVAILABLE=""
PLUGIN_LIST=(
    "AIStudioBuildProxy (汉化/API代理) | https://gh-proxy.org/https://github.com/il1umi/AIStudioBuildProxy.git | server | client | AIStudioBuildProxy"
    "对话文本着色 | https://gh-proxy.org/https://github.com/XanadusWorks/SillyTavern-Dialogue-Colorizer.git | - | HEAD | SillyTavern-Dialogue-Colorizer"
    "顶部信息栏 | https://gh-proxy.org/https://github.com/SillyTavern/Extension-TopInfoBar.git | - | HEAD | Extension-TopInfoBar"
    "界面元素隐藏 | https://gh-proxy.org/https://github.com/uhhhh15/hide.git | - | HEAD | hide"
    "自定义模型列表 | https://gh-proxy.org/https://github.com/LenAnderson/SillyTavern-CustomModels.git | - | HEAD | SillyTavern-CustomModels"
    "聊天统计面板 | https://gh-proxy.org/https://github.com/Junejulyz/chat-companion-stats.git | - | HEAD | chat-companion-stats"
    "快速回复 | https://gh-proxy.org/https://github.com/uhhhh15/QR.git | - | HEAD | QR"
    "强力快速回复 | https://gh-proxy.org/https://github.com/AlbusKen/quick-response-force.git | - | HEAD | quick-response-force"
    "输入辅助助手 | https://gh-proxy.org/https://github.com/Mooooooon/st-input-helper.git | - | HEAD | st-input-helper"
    "提示词模板管理 | https://gh-proxy.org/https://github.com/zonde306/ST-Prompt-Template.git | - | HEAD | ST-Prompt-Template"
    "消息收藏/星标 | https://gh-proxy.org/https://github.com/uhhhh15/star.git | - | HEAD | star"
    "Amily2 聊天优化 | https://gh-proxy.org/https://github.com/Wx-2025/ST-Amily2-Chat-Optimisation.git | - | HEAD | ST-Amily2-Chat-Optimisation"
    "记忆增强扩展 | https://gh-proxy.org/https://github.com/muyoou/st-memory-enhancement.git | HEAD | - | st-memory-enhancement"
    "上下文消息限制 | https://gh-proxy.org/https://github.com/SillyTavern/Extension-MessageLimit.git | - | HEAD | Extension-MessageLimit"
    "前端 Token 计数 | https://gh-proxy.org/https://github.com/GoldenglowMeow/ST-Frontend-Tokenizer.git | - | HEAD | ST-Frontend-Tokenizer"
    "预设管理器 Momo | https://gh-proxy.org/https://github.com/1830488003/preset-manager-momo.git | - | HEAD | preset-manager-momo"
    "世界书扩展 Momo | https://gh-proxy.org/https://github.com/1830488003/my-world-book-momo.git | - | HEAD | my-world-book-momo"
    "JS 脚本运行器 | https://gh-proxy.org/https://github.com/n0vi028/JS-Slash-Runner.git | - | HEAD | JS-Slash-Runner"
    "Bincooo 执行器 | https://gh-proxy.org/https://github.com/bincooo/SillyTavernExtension-JsRunner.git | - | HEAD | SillyTavernExtension-JsRunner"
    "拒绝助手废话 | https://gitgud.io/Monblant/noass.git | - | HEAD | noass"
    "定时提醒工具 | https://gh-proxy.org/https://github.com/Mooooooon/silly-tavern-reminder.git | - | HEAD | silly-tavern-reminder"
    "生成失败通知 | https://gh-proxy.org/https://github.com/RealSubstantiality/fail-notification.git | - | HEAD | fail-notification"
    "小白盒工具箱 | https://gh-proxy.org/https://github.com/RT15548/LittleWhiteBox.git | - | HEAD | LittleWhiteBox"
    "快捷人格切换 | https://gh-proxy.org/https://github.com/SillyTavern/Extension-QuickPersona.git | - | HEAD | Extension-QuickPersona"
    "聊天记录备份 | https://gh-proxy.org/https://github.com/uhhhh15/chat-history-backup.git | - | HEAD | chat-history-backup"
    "静音/停止生成 | https://gh-proxy.org/https://github.com/SillyTavern/Extension-Silence.git | - | HEAD | Extension-Silence"
)

retry_cmd() {
    local max_attempts=3
    local attempt=1
    local cmd="$@"
    while [ $attempt -le $max_attempts ]; do
        if eval "$cmd"; then return 0; fi
        echo -e "${YELLOW}   ⚠️  操作失败，正在重试 ($attempt/$max_attempts)...${NC}"
        sleep 3
        ((attempt++))
    done
    echo -e "${RED}   ❌ 超过最大重试次数。${NC}"
    return 1
}

start_update_check_async() {
    if [ ! -d "$CACHE_DIR" ]; then mkdir -p "$CACHE_DIR"; fi
    (
        local check_mirrors=(
            "https://mirror.ghproxy.com/"
            "https://ghproxy.net/"
            "https://ghproxy.cc/"
            "https://gh.likk.cc/"
            "https://gh.rs/"
            "https://edgeone.gh-proxy.com/"
        )
        local remote_info=""
        for mirror in "${check_mirrors[@]}"; do
            local check_url="${mirror}${SCRIPT_URL_BASE}"
            remote_info=$(env -u http_proxy -u https_proxy curl -s -f -L -m 5 "$check_url" | grep "# TAV-X v" | head -n 1)
            if [[ -n "$remote_info" ]]; then break; fi
        done

        if [[ -n "$remote_info" ]]; then
            local remote_ver=$(echo "$remote_info" | grep -o "v[0-9.]*")
            if [[ -n "$remote_ver" && "$remote_ver" != "$CURRENT_VERSION" ]]; then
                echo "$remote_ver" > "$VERSION_FILE"
            fi
        fi
    ) > /dev/null 2>&1 &
}

get_current_config() {
    if [ -f "$PROXY_CONFIG_FILE" ]; then
        echo "PROXY:$(cat "$PROXY_CONFIG_FILE")"
    elif [ -f "$MIRROR_CONFIG" ]; then
        echo "MIRROR:$(cat "$MIRROR_CONFIG")"
    else
        echo "MIRROR:$DEFAULT_MIRROR"
    fi
}

ensure_minimal_config() {
    if [ -f "$CONFIG_FILE" ]; then return; fi
    mkdir -p "$(dirname "$CONFIG_FILE")"
    echo "whitelistMode: false" > "$CONFIG_FILE"
    echo "enableUserAccounts: true" >> "$CONFIG_FILE"
    echo "enableServerPlugins: true" >> "$CONFIG_FILE"
    echo "enableDiscreetLogin: true" >> "$CONFIG_FILE"
    echo "requestProxy:" >> "$CONFIG_FILE"
    echo "  enabled: false" >> "$CONFIG_FILE"
    echo "  url: \"\"" >> "$CONFIG_FILE"
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
    if [ -f "$MIRROR_CONFIG" ]; then
        if [ ! -s "$MIRROR_CONFIG" ]; then rm -f "$MIRROR_CONFIG"; fi
    fi
    if command -v node &> /dev/null && command -v git &> /dev/null && command -v cloudflared &> /dev/null && command -v setsid &> /dev/null; then return 0; fi
    echo -e "${YELLOW}>>> 检测到环境缺失，正在初始化...${NC}"
    pkg update -y; pkg install nodejs-lts git cloudflared util-linux tar nmap -y
    MISSING=""
    if ! command -v git &> /dev/null; then MISSING="$MISSING git"; fi
    if ! command -v node &> /dev/null; then MISSING="$MISSING node"; fi
    if ! command -v cloudflared &> /dev/null; then MISSING="$MISSING cloudflared"; fi
    if [ -n "$MISSING" ]; then
        echo -e "${RED}❌ 致命错误：核心组件安装失败:$MISSING${NC}"
        exit 1
    fi
}

send_analytics() {
    local STAT_URL="https://tav-api.future404.qzz.io"
    if command -v curl &> /dev/null; then
        curl -s -m 5 "${STAT_URL}?ver=${CURRENT_VERSION}&type=startup" > /dev/null 2>&1 &
    fi
}

print_banner() {
    clear
    echo -e "${PURPLE}"
    cat << "EOF"
   d8P
d888888P
EOF
    echo -ne "${BLUE}"
    cat << "EOF"
  ?88'   d888b8b  ?88   d8P?88,  88P
  88P   d8P' ?88  d88  d8P' `?8bd8P'
EOF
    echo -ne "${CYAN}"
    cat << "EOF"
  88b   88b  ,88b ?8b ,88'  d8P?8b,
  `?8b  `?88P'`88b`?888P'  d8P' `?8b
EOF
    echo -e "${NC}"
    echo -e "${WHITE}   Termux Audio Visual eXperience ${PURPLE}│${CYAN} v${CURRENT_VERSION}${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"

    if [ -f "$VERSION_FILE" ]; then
        local cached_ver=$(cat "$VERSION_FILE")
        if [[ -n "$cached_ver" && "$cached_ver" != "$CURRENT_VERSION" ]]; then
            NEW_VERSION_AVAILABLE="$cached_ver"
        fi
    fi

    if [[ -n "$NEW_VERSION_AVAILABLE" ]]; then
        echo -e "${YELLOW}🔔 新版本可用: ${NEW_VERSION_AVAILABLE} (当前: ${CURRENT_VERSION})"
        echo -e "   请在菜单选择 [5] 进行更新${NC}"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
    fi
}

apply_global_optimizations() {
    ensure_minimal_config
    sed -i 's/^enableUserAccounts:[[:space:]]*false/enableUserAccounts: true/' "$CONFIG_FILE"
    sed -i 's/^lazyLoadCharacters:[[:space:]]*false/lazyLoadCharacters: true/' "$CONFIG_FILE"
    sed -i 's/^useDiskCache:[[:space:]]*true/useDiskCache: false/' "$CONFIG_FILE"
    sed -i 's/^enableDiscreetLogin:[[:space:]]*false/enableDiscreetLogin: true/' "$CONFIG_FILE"
}

ensure_whitelist_off() {
    ensure_minimal_config
    if grep -q "whitelistMode: true" "$CONFIG_FILE"; then
        sed -i 's/^whitelistMode:[[:space:]]*true/whitelistMode: false/' "$CONFIG_FILE"
        sleep 0.5
    fi
}

enable_server_plugins() {
    ensure_minimal_config
    if grep -q "enableServerPlugins: true" "$CONFIG_FILE"; then return; fi
    sed -i 's/^enableServerPlugins:[[:space:]]*false/enableServerPlugins: true/' "$CONFIG_FILE"
    if ! grep -q "enableServerPlugins" "$CONFIG_FILE"; then echo "enableServerPlugins: true" >> "$CONFIG_FILE"; fi
}

is_plugin_installed() {
    local dir_name=$1
    if [ -d "$INSTALL_DIR/plugins/$dir_name" ] || [ -d "$INSTALL_DIR/public/scripts/extensions/third-party/$dir_name" ]; then
        return 0
    else
        return 1
    fi
}

install_plugin_core() {
    local name=$1
    local repo=$2
    local branch_server=$3
    local branch_client=$4
    local dir_name=$5
    local batch_mode=$6

    if [ "$batch_mode" == "true" ]; then
        if [ -d "$INSTALL_DIR/plugins/$dir_name" ] || [ -d "$INSTALL_DIR/public/scripts/extensions/third-party/$dir_name" ]; then
            echo -e "${YELLOW}>>> 跳过: $name (已安装)${NC}"
            return 0
        fi
    fi

    echo -e "${CYAN}>>> 正在安装: $name${NC}"

    CONFIG_STR=$(get_current_config)
    TYPE=${CONFIG_STR%%:*}
    VALUE=${CONFIG_STR#*:}

    local SAFE_ENV="env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null"

    if [ "$TYPE" == "PROXY" ]; then
        GIT_CMD="$SAFE_ENV git clone -c http.proxy=$VALUE"
        TARGET_REPO="$repo"
        if [ "$batch_mode" != "true" ]; then echo -e "${YELLOW}   使用代理: $VALUE${NC}"; fi
    else
        GIT_CMD="$SAFE_ENV env -u http_proxy -u https_proxy git clone -c http.proxy="
        TARGET_REPO="${VALUE}${repo}"
        if [ "$batch_mode" != "true" ]; then echo -e "${YELLOW}   使用镜像: $VALUE${NC}"; fi
    fi

    exec_git_with_retry() {
        local cmd="$GIT_CMD $@"
        if [ "$batch_mode" == "true" ]; then retry_cmd "$cmd" >/dev/null 2>&1; else retry_cmd "$cmd"; fi
    }
    local install_success=false

    if [ "$branch_server" != "-" ]; then
        enable_server_plugins
        SERVER_PATH="$INSTALL_DIR/plugins/$dir_name"
        if [ -d "$SERVER_PATH" ]; then rm -rf "$SERVER_PATH"; fi
        mkdir -p "$INSTALL_DIR/plugins"
        BRANCH_ARG=""; if [ "$branch_server" != "HEAD" ]; then BRANCH_ARG="-b $branch_server"; fi
        if exec_git_with_retry $BRANCH_ARG --depth 1 "$TARGET_REPO" "$SERVER_PATH"; then
            if [ "$batch_mode" != "true" ]; then echo -e "${GREEN}   √ 服务端部署成功${NC}"; fi
            install_success=true
        else
            if [ "$batch_mode" != "true" ]; then echo -e "${RED}   ❌ 服务端下载失败！${NC}"; fi
        fi
    fi
    if [ "$branch_client" != "-" ]; then
        CLIENT_BASE="$INSTALL_DIR/public/scripts/extensions/third-party"
        CLIENT_PATH="$CLIENT_BASE/$dir_name"
        if [ -d "$CLIENT_PATH" ]; then rm -rf "$CLIENT_PATH"; fi
        mkdir -p "$CLIENT_BASE"
        BRANCH_ARG=""; if [ "$branch_client" != "HEAD" ]; then BRANCH_ARG="-b $branch_client"; fi
        if exec_git_with_retry $BRANCH_ARG --depth 1 "$TARGET_REPO" "$CLIENT_PATH"; then
            if [ "$batch_mode" != "true" ]; then echo -e "${GREEN}   √ 客户端部署成功${NC}"; fi
            install_success=true
        else
            if [ "$batch_mode" != "true" ]; then echo -e "${RED}   ❌ 客户端下载失败！${NC}"; fi
        fi
    fi
    if [ "$batch_mode" == "true" ]; then
        if [ "$install_success" == "true" ]; then echo -e "${GREEN}   ✅ 安装成功${NC}"; else echo -e "${RED}   ❌ 安装失败${NC}"; fi
    else
        if [ "$install_success" == "true" ]; then echo -e "${GREEN}🎉  操作结束${NC}"; else echo -e "${RED}⚠️  操作结束，请检查上方报错信息${NC}"; fi
        read -p "回车继续..."
    fi
}

install_all_plugins() {
    echo -e "${CYAN}=== 🚀 正在批量安装所有插件 ===${NC}"
    echo -e "${YELLOW}提示: 已安装的插件将自动跳过。${NC}"
    echo -e "${RED}提示: 按 Ctrl+C 可随时强行停止。${NC}"
    echo "----------------------------------------"

    BREAK_LOOP=false
    trap 'BREAK_LOOP=true; echo -e "\n${RED}🛑 检测到中断信号，正在停止...${NC}";' SIGINT

    for item in "${PLUGIN_LIST[@]}"; do
        if [ "$BREAK_LOOP" = true ]; then break; fi
        IFS='|' read -r p_name p_repo p_s_branch p_c_branch p_dir <<< "$item"
        install_plugin_core "$(echo "$p_name"|xargs)" "$(echo "$p_repo"|xargs)" "$(echo "$p_s_branch"|xargs)" "$(echo "$p_c_branch"|xargs)" "$(echo "$p_dir"|xargs)" "true"
        if [ "$BREAK_LOOP" = true ]; then break; fi
    done

    trap 'BREAK_LOOP=true' SIGINT

    echo "----------------------------------------"
    if [ "$BREAK_LOOP" = true ]; then
        echo -e "${RED}⚠️  批量安装已强制终止。${NC}"
    else
        echo -e "${GREEN}✅ 所有任务处理完毕！${NC}"
    fi
    read -p "回车返回..."
}

plugin_menu() {
    while true; do
        clear
        echo -e "${CYAN}=== 🧩 插件管理中心 ===${NC}"
        echo -e "${RED}⚠️  提示: 卸载插件请在酒馆前端 Extensions/插件 页面手动操作${NC}"
        echo "----------------------------------------"
        i=1
        for item in "${PLUGIN_LIST[@]}"; do
            IFS='|' read -r p_name p_repo p_s_branch p_c_branch p_dir <<< "$item"
            clean_name=$(echo "$p_name" | xargs)
            clean_dir=$(echo "$p_dir" | xargs)
            if is_plugin_installed "$clean_dir"; then printf "${GREEN}%-2s. %s [已安装]${NC}\n" "$i" "$clean_name"; else printf "%-2s. %s\n" "$i" "$clean_name"; fi
            ((i++))
        done
        echo "----------------------------------------"
        echo -e "99. 🔥 一键安装所有插件 (All in One)"
        echo "0.  🔙 返回主菜单"
        echo ""
        read -p "选择编号: " p_idx
        if [[ -z "$p_idx" ]]; then continue; fi
        if [ "$p_idx" == "0" ]; then return; fi
        if [ "$p_idx" == "99" ]; then install_all_plugins; continue; fi
        if ! [[ "$p_idx" =~ ^[0-9]+$ ]]; then echo -e "${RED}输入无效${NC}"; sleep 0.5; continue; fi
        real_idx=$((p_idx-1))
        if [ -n "${PLUGIN_LIST[$real_idx]}" ]; then
            IFS='|' read -r p_name p_repo p_s_branch p_c_branch p_dir <<< "${PLUGIN_LIST[$real_idx]}"
            install_plugin_core "$(echo "$p_name"|xargs)" "$(echo "$p_repo"|xargs)" "$(echo "$p_s_branch"|xargs)" "$(echo "$p_c_branch"|xargs)" "$(echo "$p_dir"|xargs)" "false"
        else echo -e "${RED}无效的选择${NC}"; sleep 1; fi
    done
}

validate_proxy_format() { if [[ "$1" =~ ^(http|https|socks5|socks5h)://.+ ]]; then return 0; else return 1; fi; }
test_proxy_connection() {
    echo -e "${YELLOW}>>> 测试代理 ($1)...${NC}"
    if curl -s -o /dev/null --connect-timeout 5 --proxy "$1" https://www.google.com; then return 0; else return 1; fi
}

get_mirror_status_code() {
    local target="$1"
    local test_url="${target}https://edgecname.gh-proxy.com/https://github.com/SillyTavern/SillyTavern.git/info/refs?service=git-upload-pack"
    env -u http_proxy -u https_proxy curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$test_url"
}

select_mirror() {
    clear
    echo -e "${CYAN}=== 🌐 Github 下载线路配置 ===${NC}"
    echo -e "${YELLOW}正在检测线路延迟... (沙盒模式)${NC}"
    mirrors=(
        "https://mirror.ghproxy.com/"
        "https://ghproxy.net/"
        "https://ghproxy.cc/"
        "https://gh.likk.cc/"
        "https://gh.rs/"
        "https://edgeone.gh-proxy.com/"
        "https://hk.gh-proxy.com/"
        "https://gh-proxy.com/"
        "https://gh.idayer.com/"
    )
    printf "%-4s %-10s %-30s\n" "编号" "状态" "线路地址"
    echo "------------------------------------------------"
    i=1
    for mirror in "${mirrors[@]}"; do
        code=$(get_mirror_status_code "$mirror")
        if [ "$code" == "200" ]; then
            status="${GREEN}🟢 极佳${NC}"
        elif [[ "$code" == "301" || "$code" == "302" ]]; then
            status="${YELLOW}🟡 跳转${NC}"
        elif [ "$code" == "000" ]; then
            status="${RED}🔴 超时${NC}"
        else
            status="${RED}🔴 失败($code)${NC}"
        fi
        printf "%-4s %-15b %-30s\n" "$i." "$status" "$mirror"
        ((i++))
    done
    echo "------------------------------------------------"
    echo -e "99. 自定义镜像地址"
    echo -e "88. 使用代理直连"
    echo -e "66.  返回主菜单"
    echo -e "0.  退出脚本"
    echo ""
    read -p "请选择最佳线路: " choice
    case $choice in
        0) exit 0 ;;
        66) return ;;
        88)
            while true; do
                echo -e "${YELLOW}输入代理 (示例: socks5://127.0.0.1:10808)${NC}"
                read -p "地址 (0 取消): " user_proxy
                if [[ -z "$user_proxy" ]]; then continue; fi
                if [ "$user_proxy" == "0" ]; then break; fi
                if ! validate_proxy_format "$user_proxy"; then echo -e "${RED}格式错误${NC}"; continue; fi
                if test_proxy_connection "$user_proxy"; then
                    sed -i '/^requestProxy:/,/^  bypass:/ s/enabled:[[:space:]]*false/enabled: true/' "$CONFIG_FILE" 2>/dev/null
                    sed -i "/^requestProxy:/,/^  bypass:/ s|^  url:.*|  url: \"$user_proxy\"|" "$CONFIG_FILE" 2>/dev/null
                    echo "$user_proxy" > "$PROXY_CONFIG_FILE"
                    rm -f "$MIRROR_CONFIG"
                    echo -e "${GREEN}✅ 设置成功${NC}"
                    sleep 1
                    break
                else
                    echo -e "${RED}❌ 连接失败${NC}"
                fi
            done
            ;;
        99)
            while true; do
                echo -e "${YELLOW}输入自定义前缀 (以 / 结尾)${NC}"
                read -p "地址 (0 取消): " custom_url
                if [[ -z "$custom_url" ]]; then continue; fi
                if [ "$custom_url" == "0" ]; then return; fi
                if [[ $custom_url == http* ]]; then
                    [[ "${custom_url}" != */ ]] && custom_url="${custom_url}/"
                    code=$(get_mirror_status_code "$custom_url")
                    if [[ "$code" == "200" || "$code" == "301" || "$code" == "302" ]]; then
                        echo "$custom_url" > "$MIRROR_CONFIG"
                        rm -f "$PROXY_CONFIG_FILE"
                        echo -e "${GREEN}✅ 验证通过，已切换${NC}"
                        break
                    else
                        echo -e "${RED}❌ 镜像不可用${NC}"
                    fi
                else
                    echo -e "${RED}格式错误${NC}"
                fi
            done
            ;;
        *)
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#mirrors[@]}" ]; then
                idx=$((choice - 1))
                echo "${mirrors[$idx]}" > "$MIRROR_CONFIG"
                rm -f "$PROXY_CONFIG_FILE"
                echo -e "${GREEN}√ 已切换至: ${mirrors[$idx]}${NC}"
            else
                echo -e "${RED}无效选择${NC}"
                sleep 1
            fi
            ;;
    esac
    sleep 1
}

configure_security_original() {
    if [ ! -f "$CONFIG_FILE" ]; then return; fi
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    sed -i 's/^whitelistMode:[[:space:]]*true/whitelistMode: false/' "$CONFIG_FILE"
    sed -i 's/^enableUserAccounts:[[:space:]]*false/enableUserAccounts: true/' "$CONFIG_FILE"
    sed -i 's/^enableDiscreetLogin:[[:space:]]*false/enableDiscreetLogin: true/' "$CONFIG_FILE"
    sed -i '/^browserLaunch:/,/^  [a-z]/ s/enabled:[[:space:]]*true/enabled: false/' "$CONFIG_FILE"
}

reset_password_logic() {
    cd "$INSTALL_DIR" || return
    if [ ! -f "recover.js" ]; then echo -e "${RED}错误：找不到 recover.js${NC}"; read -p "回车返回..."; return; fi
    clear; echo -e "${CYAN}=== 🔐 密码重置 ===${NC}"
    echo -e "${YELLOW}当前已注册用户列表:${NC}"
    if [ -d "data" ]; then
        ls -F data/ | grep "/" | grep -v "^_" | sed 's/\///g' | sed 's/^/  - /'
    else
        echo -e "${RED}  (未找到 data 目录)${NC}"
    fi
    echo "------------------------"
    read -p "用户名 [default-user]: " TARGET_USER
    TARGET_USER=${TARGET_USER:-default-user}
    read -p "新密码 [Gemini@12345]: " NEW_PASS
    NEW_PASS=${NEW_PASS:-Gemini@12345}
    echo -e "${CYAN}>>> 正在重置...${NC}"
    node recover.js "$TARGET_USER" "$NEW_PASS"
    echo -e "${GREEN}✅ 操作完成${NC}"; read -p "回车返回..."
}

security_menu() {
    while true; do
        clear; echo -e "${CYAN}=== 🛠️ 安全配置 ===${NC}"
        echo -e "1. 🔓 修复白名单/免密"; echo -e "2. 🔑 重置密码"; echo -e "0. 🔙 返回"
        read -p "选择: " sec_choice
        if [[ -z "$sec_choice" ]]; then continue; fi
        case $sec_choice in 1) configure_security_original; echo -e "${GREEN}完成${NC}"; sleep 1 ;; 2) reset_password_logic ;; 0) return ;; *) echo -e "${RED}无效输入${NC}"; sleep 0.5 ;; esac
    done
}

configure_proxy() {
    if [ ! -f "$CONFIG_FILE" ]; then echo -e "${RED}无配置${NC}"; sleep 1; return; fi
    clear; echo -e "${CYAN}=== 代理配置 ===${NC}"
    grep -A 5 "requestProxy:" "$CONFIG_FILE" | grep -E "enabled|url"
    echo ""; echo -e "1. 🟢 开启/设置"; echo -e "2. 🔴 关闭"; echo -e "0. 🔙 返回"
    read -p "选择: " pc
    if [[ -z "$pc" ]]; then return; fi
    case $pc in
        1)
            while true; do
                read -p "代理URL (0返回): " PURL;
                if [[ -z "$PURL" ]]; then continue; fi
                if [ "$PURL" == "0" ]; then break; fi
                if ! validate_proxy_format "$PURL"; then echo -e "${RED}格式错误${NC}"; continue; fi
                if test_proxy_connection "$PURL"; then
                    sed -i '/^requestProxy:/,/^  bypass:/ s/enabled:[[:space:]]*false/enabled: true/' "$CONFIG_FILE"
                    sed -i "/^requestProxy:/,/^  bypass:/ s|^  url:.*|  url: \"$PURL\"|" "$CONFIG_FILE"
                    echo "$PURL" > "$PROXY_CONFIG_FILE"; echo -e "${GREEN}✅ 设置成功${NC}"; sleep 1; break
                else echo -e "${RED}❌ 连接失败${NC}"; fi
            done ;;
        2)
            sed -i '/^requestProxy:/,/^  bypass:/ s/enabled:[[:space:]]*true/enabled: false/' "$CONFIG_FILE"
            rm -f "$PROXY_CONFIG_FILE"; echo -e "${GREEN}已关闭${NC}"; sleep 1 ;;
        *) return ;;
    esac
}

check_storage_permission() {
    if [ ! -d "$HOME/storage" ]; then
        echo -e "${CYAN}请点击【允许】授权存储访问。${NC}"; termux-setup-storage; sleep 2
        if [ ! -d "$HOME/storage" ]; then echo -e "${RED}无存储权限${NC}"; return 1; fi
    fi
    return 0
}

perform_backup() {
    check_storage_permission || return
    if [ ! -d "$INSTALL_DIR/data" ]; then echo -e "${RED}无数据目录${NC}"; read -p "回车返回..."; return; fi
    mkdir -p "$BACKUP_DIR"; TIMESTAMP=$(date +%Y%m%d_%H%M%S); BACKUP_FILE="$BACKUP_DIR/ST_Backup_$TIMESTAMP.tar.gz"
    echo -e "${CYAN}正在备份...${NC}"; cd "$INSTALL_DIR" || return; tar -czf "$BACKUP_FILE" data
    if [ -f "$BACKUP_FILE" ]; then echo -e "${GREEN}✅ 备份: $(basename "$BACKUP_FILE")${NC}"; else echo -e "${RED}失败${NC}"; fi
    read -p "回车返回..."
}

perform_restore() {
    check_storage_permission || return
    if [ ! -d "$BACKUP_DIR" ]; then echo -e "${RED}无备份目录${NC}"; read -p "回车返回..."; return; fi
    files=("$BACKUP_DIR"/ST_Backup_*.tar.gz)
    if [ ! -e "${files[0]}" ]; then echo -e "${RED}无有效备份文件${NC}"; read -p "回车返回..."; return; fi
    clear; echo -e "${CYAN}=== 恢复备份 ===${NC}"; i=1
    for file in "${files[@]}"; do echo -e "$i. $(basename "$file")"; ((i++)); done
    echo "0. 返回"; echo ""; read -p "选择: " file_idx
    if [[ -z "$file_idx" ]]; then return; fi
    if [[ "$file_idx" == "0" ]]; then return; fi
    SELECTED_FILE="${files[$((file_idx-1))]}"
    if [ -z "$SELECTED_FILE" ] || [ ! -f "$SELECTED_FILE" ]; then echo -e "${RED} 无效${NC}"; sleep 1; return; fi
    echo -e "${RED}⚠️  警告: 将覆盖当前数据！${NC}"; read -p "输入 'yes' 确认: " confirm
    if [[ "$confirm" != "yes" ]]; then return; fi
    rm -rf "$INSTALL_DIR/data"; mkdir -p "$INSTALL_DIR/data"; tar -xzf "$SELECTED_FILE" -C "$INSTALL_DIR"
    echo -e "${GREEN}✅ 恢复完成${NC}"; read -p "回车返回..."
}

backup_menu() {
    while true; do
        clear; echo -e "${CYAN}=== 💾 备份与恢复 ===${NC}"
        echo -e "1. 📤 备份"; echo -e "2. 📥 恢复"; echo -e "0. 🔙 返回"
        read -p "选择: " bc
        if [[ -z "$bc" ]]; then continue; fi
        case $bc in 1) perform_backup ;; 2) perform_restore ;; 0) return ;; *) echo -e "${RED}无效输入${NC}"; sleep 0.5 ;; esac
    done
}

run_adb_module() {
    LOCAL_MODULE_DIR="$HOME/.tav_x/modules"
    MODULE_FILE="$LOCAL_MODULE_DIR/adb_keepalive.sh"
    mkdir -p "$LOCAL_MODULE_DIR"

    if [ -f "$MODULE_FILE" ]; then
        bash "$MODULE_FILE"
        return
    fi

    echo -e "${CYAN}>>> 本地模块缺失，正在从云端拉取...${NC}"
    CONFIG_STR=$(get_current_config)
    TYPE=${CONFIG_STR%%:*}
    VALUE=${CONFIG_STR#*:}
    RAW_URL="https://gh-proxy.org/https://raw.githubusercontent.com/Future-404/TAV-X/main/modules/adb_keepalive.sh"

    if [ "$TYPE" == "PROXY" ]; then
        DOWNLOAD_CMD="curl -s -f -L --proxy $VALUE"
        FINAL_URL="$RAW_URL"
    else
        DOWNLOAD_CMD="env -u http_proxy -u https_proxy curl -s -f -L --noproxy '*'"
        if [[ "$VALUE" == *"raw.githubusercontent.com"* ]]; then
             FINAL_URL="$VALUE"
        else
             FINAL_URL="${VALUE}${RAW_URL}"
        fi
    fi

    echo -e "${YELLOW}>>> 正在下载: adb_keepalive.sh ...${NC}"
    if $DOWNLOAD_CMD "$FINAL_URL" -o "${MODULE_FILE}.tmp"; then
        if grep -q "bash" "${MODULE_FILE}.tmp"; then
            mv "${MODULE_FILE}.tmp" "$MODULE_FILE"
            chmod +x "$MODULE_FILE"
            echo -e "${GREEN}✅ 模块安装成功！${NC}"
            sleep 1
            bash "$MODULE_FILE"
        else
            echo -e "${RED}❌ 下载失败：文件校验未通过。${NC}"
            rm -f "${MODULE_FILE}.tmp"
            read -p "回车返回..."
        fi
    else
        echo -e "${RED}❌ 网络错误：无法连接到下载服务器。${NC}"
        rm -f "${MODULE_FILE}.tmp"
        read -p "回车返回..."
    fi
}

rollback_st() {
    if [ ! -d "$INSTALL_DIR/.git" ]; then
        echo -e "${RED}❌ 目录无效或不是Git仓库，无法回退。${NC}"
        read -p "回车返回..."
        return
    fi
    echo -e "${CYAN}>>> 正在获取版本列表...${NC}"
    cd "$INSTALL_DIR" || return
    CONFIG_STR=$(get_current_config)
    TYPE=${CONFIG_STR%%:*}
    VALUE=${CONFIG_STR#*:}
    local SAFE_ENV="env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null"
    if [ "$TYPE" == "PROXY" ]; then
        git config http.proxy "$VALUE"
    else
        git config --unset http.proxy
    fi
    if ! retry_cmd "$SAFE_ENV git fetch --tags"; then
        echo -e "${RED}❌ 获取版本列表失败，请检查网络。${NC}"
        if [ "$TYPE" == "PROXY" ]; then git config --unset http.proxy; fi
        read -p "回车返回..."
        return
    fi
    if [ "$TYPE" == "PROXY" ]; then git config --unset http.proxy; fi
    while true; do
        clear
        echo -e "${CYAN}=== 🔙 版本回退时光机 ===${NC}"
        echo -e "${YELLOW}⚠️  警告: 回退版本可能导致部分新版插件不兼容。${NC}"
        echo -e "${YELLOW}⚠️  建议在回退前先 [备份数据]。${NC}"
        echo "----------------------------------------"
        mapfile -t tags < <(git tag --sort=-creatordate | grep -v "staging" | head -n 15)
        if [ ${#tags[@]} -eq 0 ]; then
            echo -e "${RED}未找到可用版本标签。${NC}"
            read -p "回车返回..."
            return
        fi
        for i in "${!tags[@]}"; do
            echo -e "$((i+1)). ${tags[$i]}"
        done
        echo "----------------------------------------"
        echo -e "r. 🔄 恢复到最新发布版 (release branch)"
        echo -e "0. 🔙 返回上一级"
        echo ""
        read -p "请选择要回退的版本编号: " r_idx
        if [ "$r_idx" == "0" ]; then return; fi
        if [ "$r_idx" == "r" ]; then
            echo -e "${CYAN}>>> 正在切换回 release 分支...${NC}"
            git checkout release
            git pull
            echo -e "${YELLOW}>>> 刷新依赖...${NC}"
            npm install --no-audit --fund
            echo -e "${GREEN}✅ 已恢复到最新版${NC}"
            read -p "回车返回..."
            return
        fi
        if ! [[ "$r_idx" =~ ^[0-9]+$ ]] || [ "$r_idx" -lt 1 ] || [ "$r_idx" -gt "${#tags[@]}" ]; then
            echo -e "${RED}无效选择${NC}"; sleep 1; continue
        fi
        TARGET_TAG="${tags[$((r_idx-1))]}"
        echo -e "${CYAN}>>> 正在穿越到: $TARGET_TAG ...${NC}"
        if git checkout "$TARGET_TAG"; then
            echo -e "${YELLOW}>>> 正在重装依赖 (防止版本不匹配)...${NC}"
            rm -rf node_modules package-lock.json
            npm install --no-audit --fund
            echo -e "${GREEN}✅ 穿越成功！当前版本: $TARGET_TAG${NC}"
            echo -e "${CYAN}提示: 如需恢复最新版，请再次进入此菜单选择 'r'${NC}"
        else
            echo -e "${RED}❌ 切换失败，请检查 git 状态。${NC}"
        fi
        read -p "回车返回..."
        return
    done
}

install_st() {
    CONFIG_STR=$(get_current_config)
    TYPE=${CONFIG_STR%%:*}
    VALUE=${CONFIG_STR#*:}

    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${CYAN}>>> 开始部署...${NC}"
        local SAFE_ENV="env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null"
        local ST_RAW_URL="https://gh-proxy.org/https://github.com/SillyTavern/SillyTavern.git"

        if [ "$TYPE" == "PROXY" ]; then
            echo -e "${YELLOW}>>> 代理模式: $VALUE${NC}"
            GIT_CMD="$SAFE_ENV git clone --depth 1 -c http.proxy=$VALUE"
            URL="$ST_RAW_URL"
        else
            echo -e "${YELLOW}>>> 镜像模式: $VALUE${NC}"
            GIT_CMD="$SAFE_ENV env -u http_proxy -u https_proxy git clone --depth 1 -c http.proxy="
            URL="${VALUE}${ST_RAW_URL}"
        fi

        if ! retry_cmd "$GIT_CMD \"$URL\" \"$INSTALL_DIR\""; then
            echo -e "${RED}❌ 下载失败，进入线路选择...${NC}"
            sleep 2
            select_mirror
            install_st
            return
        fi

        cd "$INSTALL_DIR" || return
        npm config set registry https://registry.npmmirror.com
        retry_cmd "npm install --no-audit --fund"
        if [ -f "$INSTALL_DIR/default/config.yaml" ]; then cp "$INSTALL_DIR/default/config.yaml" "$CONFIG_FILE"; fi
    else
        if [ ! -d "$INSTALL_DIR/node_modules" ]; then
            echo -e "${YELLOW}>>> 修复依赖...${NC}"
            cd "$INSTALL_DIR" || return
            retry_cmd "npm install --no-audit --fund"
        fi
    fi
}

update_st() {
    CONFIG_STR=$(get_current_config)
    TYPE=${CONFIG_STR%%:*}
    VALUE=${CONFIG_STR#*:}
    echo -e "${CYAN}>>> 更新酒馆...${NC}"
    cd "$INSTALL_DIR" || exit
    local SAFE_ENV="env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null"
    if [ "$TYPE" == "PROXY" ]; then git config http.proxy "$VALUE"; else git config --unset http.proxy; fi
    if [[ -n $(git status -s) ]]; then git stash; STASHED=1; fi
    if ! retry_cmd "$SAFE_ENV git pull"; then
        echo -e "${RED}❌ 更新失败！${NC}"
        if [ "$TYPE" == "PROXY" ]; then git config --unset http.proxy; fi
        echo -e "${YELLOW}是否切换线路重试？(y/n)${NC}"
        read -p "选择: " retry_choice
        if [[ "$retry_choice" == "y" ]]; then
            select_mirror
            update_st
            return
        else
            if [[ "$STASHED" == "1" ]]; then git stash pop; fi
            read -p "回车返回..."
            return
        fi
    fi
    if [ "$TYPE" == "PROXY" ]; then git config --unset http.proxy; fi
    if [[ "$STASHED" == "1" ]]; then git stash pop; fi
    retry_cmd "npm install --no-audit --fund"
    echo -e "${GREEN}完成${NC}"; read -p "回车返回..."
}

update_script() {
    echo -e "${CYAN}>>> 正在更新 TAV-X 脚本...${NC}"
    SCRIPT_PATH=$(readlink -f "$0")
    CONFIG_STR=$(get_current_config)
    TYPE=${CONFIG_STR%%:*}
    VALUE=${CONFIG_STR#*:}
    if [ "$TYPE" == "PROXY" ]; then
        DOWNLOAD_CMD="curl -s -f -L --proxy $VALUE"
        URL="$SCRIPT_URL_BASE"
    else
        DOWNLOAD_CMD="env -u http_proxy -u https_proxy curl -s -f -L --noproxy '*'"
        if [[ "$VALUE" == *"raw.githubusercontent.com"* ]]; then
             URL="$VALUE"
        else
             URL="${VALUE}${SCRIPT_URL_BASE}"
        fi
    fi
    local attempt=1
    while [ $attempt -le 2 ]; do
        if $DOWNLOAD_CMD "$URL" -o "${SCRIPT_PATH}.tmp"; then
            mv "${SCRIPT_PATH}.tmp" "$SCRIPT_PATH"
            chmod +x "$SCRIPT_PATH"
            echo -e "${GREEN}✅ 脚本更新成功！即将重启...${NC}"
            sleep 1
            exec bash "$SCRIPT_PATH"
        fi
        ((attempt++))
        sleep 1
    done
    rm -f "${SCRIPT_PATH}.tmp"
    echo -e "${RED}❌ 脚本下载失败，请检查网络。${NC}"
    read -p "回车返回..."
}

update_menu() {
    while true; do
        clear
        echo -e "${CYAN}=== 🔄 更新与版本管理 ===${NC}"
        echo -e "1. 🍷 更新 SillyTavern (更新到最新版)"
        echo -e "2. 🔙 版本回退/切换 (降级到旧版)"
        echo -e "3. 📜 更新 TAV-X (本脚本)"
        echo -e "0. 🔙 返回"
        echo ""
        read -p "请选择: " uc
        if [[ -z "$uc" ]]; then continue; fi
        case $uc in
            1) check_env; update_st ;;
            2) check_env; rollback_st ;;
            3) update_script ;;
            0) return ;;
            *) echo -e "${RED}无效输入${NC}"; sleep 0.5 ;;
        esac
    done
}

stop_services() {
    pkill -f "node server.js"
    pkill -f "cloudflared"
    termux-wake-unlock 2>/dev/null
    rm -f "$CF_LOG"
    rm -f "$SERVER_LOG"
    echo -e "${YELLOW}🛑 服务已停止，缓存日志已清理。${NC}"
}

start_server_background() {
    stop_services; termux-wake-lock
    cd "$INSTALL_DIR" || exit
    echo -e "${CYAN}>>> 启动服务...${NC}"
    setsid nohup node server.js > "$SERVER_LOG" 2>&1 &
}

start_share() {
    ensure_whitelist_off
    start_server_background
    rm -f "$CF_LOG"
    echo "正在连接..." > "$CF_LOG"
    setsid nohup cloudflared tunnel --protocol http2 --url http://127.0.0.1:8000 --no-autoupdate >> "$CF_LOG" 2>&1 &
    echo -e "${GREEN}✅ 远程服务已启动！正在获取链接...${NC}"; sleep 3
}

start_local() {
    start_server_background
    rm -f "$CF_LOG"
    echo -e "${GREEN}✅ 本地模式已启动！${NC}"; sleep 1.5
}

view_logs() {
    clear
    echo -e "${CYAN}=== 实时日志 (按 Ctrl+C 返回菜单) ===${NC}"
    if [ -f "$SERVER_LOG" ]; then
        BREAK_LOOP=false
        tail -n 50 -f "$SERVER_LOG"
        echo -e "\n${YELLOW}正在返回菜单...${NC}"
        sleep 1
    else
        echo -e "${RED}❌ 暂无日志文件 (服务可能未启动)${NC}"
        read -p "按回车返回..."
    fi
}

exit_script() { exec bash; }

show_menu() {
    while true; do
        BREAK_LOOP=false; clear; print_banner
        echo -e "                                  ${YELLOW}by Future404${NC}"
        if pgrep -f "node server.js" > /dev/null; then echo -e "状态: ${GREEN}● 运行中${NC}"; IS_RUNNING=true
        else echo -e "状态: ${RED}● 已停止${NC}"; IS_RUNNING=false; fi
        echo ""; echo -e "  1. 🚀 穿透启动"; echo -e "  2. 🏠 本地模式"
        echo -e "  3. 📜 监控日志"; echo -e "  4. 🛑 停止服务"
        echo -e "  5. 🔄 更新管理"; echo -e "  6. 🛠️  安全配置"
        echo -e "  7. 🌐 API代理"; echo -e "  8. 💾 备份与恢复"
        echo -e "  9. 🌐 切换线路"; echo -e " 10. 🧩 插件管理"
        echo -e " 11. 🛡️  ADB保活"; echo -e " 12. 🦀 ClewdR代理"
        echo -e "  0. 退出"
        echo ""
        if [ "$IS_RUNNING" = true ]; then
             echo -e "${CYAN}====== [ 实时链接 ] ======${NC}"
             if pgrep -f "cloudflared" > /dev/null && [ -f "$CF_LOG" ]; then
                 LINK=$(grep -o "https://[-a-zA-Z0-9]*\.trycloudflare\.com" "$CF_LOG" 2>/dev/null | grep -v "api" | tail -n 1)
                 if [ -n "$LINK" ]; then
                     echo -e "🌍 ${GREEN}$LINK${NC}"
                 else
                     echo -e "📡 ${YELLOW}获取中... (请稍候)${NC}"
                     echo -e "🥰 ${GREEN}按回车刷新链接${NC}"
                 fi
             else
                 echo -e "🏠 ${GREEN}http://127.0.0.1:8000${NC}"
             fi
             echo ""
        fi
        read -p "选择: " choice
        if [[ -z "$choice" ]]; then continue; fi
        case $choice in
            1) check_env; install_st; start_share ;; 2) check_env; install_st; start_local ;;
            3) view_logs ;; 4) stop_services; sleep 1 ;; 5) update_menu ;;
            6) security_menu ;; 7) configure_proxy ;; 8) backup_menu ;;
            9) select_mirror ;; 10) plugin_menu ;;
            11) check_env; run_adb_module ;;
            12) 
                echo -e "${YELLOW}>>> 🚧 正在开发中...${NC}"
                echo -e "${CYAN}ClewdR 模块即将上线，将支持本地运行 Clewd 并在酒馆直接调用。${NC}"
                read -p "回车返回..." 
                ;;
            0) exit_script ;; *) echo -e "${RED}无效输入${NC}"; sleep 0.5 ;;
        esac
    done
}

start_update_check_async
check_env
auto_setup_alias
send_analytics
if [ ! -d "$INSTALL_DIR" ]; then install_st; fi
if [ -d "$INSTALL_DIR" ]; then apply_global_optimizations; fi
show_menu
