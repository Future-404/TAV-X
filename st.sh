#!/bin/bash
# TAV-X v1.9.3 - 修复代理加速嵌套

# --- 常量定义 ---
MIRROR_CONFIG="$HOME/.st_mirror_url"
PROXY_CONFIG_FILE="$HOME/.st_download_proxy"
INSTALL_DIR="$HOME/SillyTavern"
CONFIG_FILE="$INSTALL_DIR/config.yaml"
CF_LOG="$INSTALL_DIR/cf_tunnel.log"
SERVER_LOG="$INSTALL_DIR/server.log"
BACKUP_DIR="$HOME/storage/downloads/ST_Backup"
# 默认使用直连稳定源
DEFAULT_MIRROR="https://mirror.ghproxy.com/"

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- 信号捕获 ---
BREAK_LOOP=false
trap 'BREAK_LOOP=true' SIGINT

# --- 插件注册表 ---
PLUGIN_LIST=(
    "AIStudioBuildProxy (汉化/API代理) | https://github.com/il1umi/AIStudioBuildProxy.git | server | client | AIStudioBuildProxy"
    "对话文本着色 (Dialogue Colorizer) | https://github.com/XanadusWorks/SillyTavern-Dialogue-Colorizer.git | - | HEAD | SillyTavern-Dialogue-Colorizer"
    "顶部信息栏 (TopInfoBar) | https://github.com/SillyTavern/Extension-TopInfoBar.git | - | HEAD | Extension-TopInfoBar"
    "界面元素隐藏 (Hide UI) | https://github.com/uhhhh15/hide.git | - | HEAD | hide"
    "自定义模型列表 (Custom Models) | https://github.com/LenAnderson/SillyTavern-CustomModels.git | - | HEAD | SillyTavern-CustomModels"
    "聊天统计面板 (Chat Stats) | https://github.com/Junejulyz/chat-companion-stats.git | - | HEAD | chat-companion-stats"
    "快速回复 (QR) | https://github.com/uhhhh15/QR.git | - | HEAD | QR"
    "强力快速回复 (QR Force) | https://github.com/AlbusKen/quick-response-force.git | - | HEAD | quick-response-force"
    "输入辅助助手 (Input Helper) | https://github.com/Mooooooon/st-input-helper.git | - | HEAD | st-input-helper"
    "提示词模板管理 (Prompt Template) | https://github.com/zonde306/ST-Prompt-Template.git | - | HEAD | ST-Prompt-Template"
    "消息收藏/星标 (Star Message) | https://github.com/uhhhh15/star.git | - | HEAD | star"
    "Amily2 聊天优化 (Chat Opt) | https://github.com/Wx-2025/ST-Amily2-Chat-Optimisation.git | - | HEAD | ST-Amily2-Chat-Optimisation"
    "记忆增强扩展 (Memory Enhance) | https://github.com/muyoou/st-memory-enhancement.git | HEAD | - | st-memory-enhancement"
    "上下文消息限制 (Message Limit) | https://github.com/SillyTavern/Extension-MessageLimit.git | - | HEAD | Extension-MessageLimit"
    "前端 Token 计数 (Tokenizer) | https://github.com/GoldenglowMeow/ST-Frontend-Tokenizer.git | - | HEAD | ST-Frontend-Tokenizer"
    "预设管理器 Momo (Preset Mgr) | https://github.com/1830488003/preset-manager-momo.git | - | HEAD | preset-manager-momo"
    "世界书扩展 Momo (World Book) | https://github.com/1830488003/my-world-book-momo.git | - | HEAD | my-world-book-momo"
    "JS 脚本运行器 (Slash Runner) | https://github.com/n0vi028/JS-Slash-Runner.git | - | HEAD | JS-Slash-Runner"
    "Bincooo 执行器 (JsRunner) | https://github.com/bincooo/SillyTavernExtension-JsRunner.git | - | HEAD | SillyTavernExtension-JsRunner"
    "拒绝助手废话 (No Assistant) | https://gitgud.io/Monblant/noass.git | - | HEAD | noass"
    "定时提醒工具 (Reminder) | https://github.com/Mooooooon/silly-tavern-reminder.git | - | HEAD | silly-tavern-reminder"
    "生成失败通知 (Fail Notify) | https://github.com/RealSubstantiality/fail-notification.git | - | HEAD | fail-notification"
    "小白盒工具箱 (LittleWhiteBox) | https://github.com/RT15548/LittleWhiteBox.git | - | HEAD | LittleWhiteBox"
    "快捷人格切换 (Quick Persona) | https://github.com/SillyTavern/Extension-QuickPersona.git | - | HEAD | Extension-QuickPersona"
    "聊天记录备份 (Chat Backup) | https://github.com/uhhhh15/chat-history-backup.git | - | HEAD | chat-history-backup"
    "静音/停止生成 (Silence) | https://github.com/SillyTavern/Extension-Silence.git | - | HEAD | Extension-Silence"
)

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

    # 0. 自愈逻辑：清理旧的镜像配置
    if [ -f "$MIRROR_CONFIG" ]; then
        if grep -q "gh-proxy.com" "$MIRROR_CONFIG" || grep -q "gh-proxy.org" "$MIRROR_CONFIG"; then
            echo -e "${YELLOW}>>> 检测到不稳定镜像源，已自动重置。${NC}"
            rm -f "$MIRROR_CONFIG"
        fi
    fi

    # 1. 环境检查
    if command -v node &> /dev/null && command -v git &> /dev/null && command -v cloudflared &> /dev/null && command -v setsid &> /dev/null; then
        return 0
    fi

    echo -e "${YELLOW}>>> 环境初始化...${NC}"
    pkg update -y
    pkg install nodejs-lts git cloudflared util-linux tar nmap -y

    # 2. 二次核验
    MISSING=""
    if ! command -v git &> /dev/null; then MISSING="$MISSING git"; fi
    if ! command -v node &> /dev/null; then MISSING="$MISSING node"; fi
    if ! command -v cloudflared &> /dev/null; then MISSING="$MISSING cloudflared"; fi

    if [ -n "$MISSING" ]; then
        echo -e "${RED}❌ 致命错误：组件安装失败:$MISSING${NC}"
        echo -e "${YELLOW}尝试手动运行：pkg update -y && pkg install nodejs-lts git cloudflared util-linux -y${NC}"
        exit 1
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

# --- 核心逻辑函数 ---

apply_global_optimizations() {
    ensure_minimal_config
    sed -i 's/enableUserAccounts: false/enableUserAccounts: true/' "$CONFIG_FILE"
    sed -i 's/lazyLoadCharacters: false/lazyLoadCharacters: true/' "$CONFIG_FILE"
    sed -i 's/useDiskCache: true/useDiskCache: false/' "$CONFIG_FILE"
    sed -i 's/enableDiscreetLogin: false/enableDiscreetLogin: true/' "$CONFIG_FILE"
}

ensure_whitelist_off() {
    ensure_minimal_config
    if grep -q "whitelistMode: true" "$CONFIG_FILE"; then
        sed -i 's/whitelistMode: true/whitelistMode: false/' "$CONFIG_FILE"
        sleep 0.5
    fi
}

enable_server_plugins() {
    ensure_minimal_config
    if grep -q "enableServerPlugins: true" "$CONFIG_FILE"; then return; fi
    sed -i 's/enableServerPlugins: false/enableServerPlugins: true/' "$CONFIG_FILE"
    if ! grep -q "enableServerPlugins" "$CONFIG_FILE"; then
         echo "enableServerPlugins: true" >> "$CONFIG_FILE"
    fi
}

install_plugin_core() {
    local name=$1
    local repo=$2
    local branch_server=$3
    local branch_client=$4
    local dir_name=$5

    echo -e "${CYAN}>>> 正在安装: $name${NC}"

    CONFIG_STR=$(get_current_config)
    TYPE=${CONFIG_STR%%:*}
    VALUE=${CONFIG_STR#*:}

    # 沙盒模式：强制 GIT_CONFIG_GLOBAL 指向空，彻底屏蔽用户配置
    local SAFE_ENV="env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null"

    if [ "$TYPE" == "PROXY" ]; then
        GIT_CMD="$SAFE_ENV git clone -c http.proxy=$VALUE"
        echo -e "${YELLOW}   使用代理: $VALUE${NC}"
    else
        # 镜像模式：同时清理代理变量
        GIT_CMD="$SAFE_ENV env -u http_proxy -u https_proxy git clone -c http.proxy="
        TARGET_REPO="${VALUE}${repo}"
        echo -e "${YELLOW}   使用镜像: $VALUE${NC}"
    fi

    # 2. 服务端
    if [ "$branch_server" != "-" ]; then
        enable_server_plugins
        SERVER_PATH="$INSTALL_DIR/plugins/$dir_name"
        if [ -d "$SERVER_PATH" ]; then rm -rf "$SERVER_PATH"; fi
        mkdir -p "$INSTALL_DIR/plugins"
        BRANCH_ARG=""
        if [ "$branch_server" != "HEAD" ]; then BRANCH_ARG="-b $branch_server"; fi
        
        if $GIT_CMD $BRANCH_ARG --depth 1 "$TARGET_REPO" "$SERVER_PATH"; then
            echo -e "${GREEN}   √ 服务端部署成功${NC}"
        else
            echo -e "${RED}   ❌ 服务端下载失败！${NC}"
            return 1
        fi
    fi

    # 3. 客户端
    if [ "$branch_client" != "-" ]; then
        CLIENT_BASE="$INSTALL_DIR/public/scripts/extensions/third-party"
        CLIENT_PATH="$CLIENT_BASE/$dir_name"
        if [ -d "$CLIENT_PATH" ]; then rm -rf "$CLIENT_PATH"; fi
        mkdir -p "$CLIENT_BASE"
        BRANCH_ARG=""
        if [ "$branch_client" != "HEAD" ]; then BRANCH_ARG="-b $branch_client"; fi

        if $GIT_CMD $BRANCH_ARG --depth 1 "$TARGET_REPO" "$CLIENT_PATH"; then
            echo -e "${GREEN}   √ 客户端部署成功${NC}"
        else
            echo -e "${RED}   ❌ 客户端下载失败！${NC}"
            return 1
        fi
    fi
    echo -e "${GREEN}🎉 安装完成！${NC}"; read -p "回车继续..."
}

plugin_menu() {
    while true; do
        clear
        echo -e "${CYAN}=== 🧩 插件管理中心 ===${NC}"
        i=1
        for item in "${PLUGIN_LIST[@]}"; do
            name=$(echo "$item" | awk -F "|" '{print $1}')
            printf "%-2s. %s\n" "$i" "$name"
            ((i++))
        done
        echo "----------------------------------------"
        echo "0. 🔙 返回主菜单"
        echo ""
        read -p "选择编号: " p_idx
        if [ "$p_idx" == "0" ]; then return; fi
        if ! [[ "$p_idx" =~ ^[0-9]+$ ]]; then continue; fi
        real_idx=$((p_idx-1))
        if [ -n "${PLUGIN_LIST[$real_idx]}" ]; then
            IFS='|' read -r p_name p_repo p_s_branch p_c_branch p_dir <<< "${PLUGIN_LIST[$real_idx]}"
            install_plugin_core "$(echo "$p_name"|xargs)" "$(echo "$p_repo"|xargs)" "$(echo "$p_s_branch"|xargs)" "$(echo "$p_c_branch"|xargs)" "$(echo "$p_dir"|xargs)"
        fi
    done
}

# --- 验证工具函数 ---
validate_proxy_format() {
    if [[ "$1" =~ ^(http|https|socks5|socks5h)://.+ ]]; then return 0; else return 1; fi
}
test_proxy_connection() {
    echo -e "${YELLOW}>>> 测试代理 ($1)...${NC}"
    if curl -s -o /dev/null --connect-timeout 5 --proxy "$1" https://www.google.com; then return 0; else return 1; fi
}
test_mirror_connection() {
    echo -e "${YELLOW}>>> 测试镜像...${NC}"
    # 强制不使用代理测速
    if env -u http_proxy -u https_proxy curl -s -o /dev/null --noproxy "*" --connect-timeout 5 "${1}https://github.com"; then return 0; else return 1; fi
}

# --- 功能菜单函数 ---

select_mirror() {
    clear
    echo -e "${CYAN}=== 🌐 Github 下载线路配置 ===${NC}"
    echo -e "正在测试线路连通性..."
    mirrors=(
        "https://mirror.ghproxy.com/"
        "https://gh.likk.cc/"
        "https://edgeone.gh-proxy.com/"
        "https://hk.gh-proxy.com/"
        "https://github.moeyy.xyz/"
    )
    printf "%-4s %-10s %-30s\n" "编号" "状态" "线路地址"
    echo "------------------------------------------------"
    i=1
    valid_indices=()
    for mirror in "${mirrors[@]}"; do
        if env -u http_proxy -u https_proxy curl -s -o /dev/null --noproxy "*" --connect-timeout 5 "${mirror}https://github.com"; then
            status="${GREEN}🟢 通畅${NC}"
        else
            status="${RED}🔴 超时${NC}"
        fi
        printf "%-4s %-15b %-30s\n" "$i." "$status" "$mirror"
        valid_indices+=($i)
        ((i++))
    done
    echo "------------------------------------------------"
    echo -e "7. 自定义镜像地址"
    echo -e "8. 使用代理直连"
    echo -e "0. 退出脚本"
    echo ""
    read -p "请选择: " choice

    case $choice in
        0) exit 0 ;; # 直接退出脚本，防止死循环
        8)
            while true; do
                echo -e "${YELLOW}输入代理 (示例: socks5://127.0.0.1:10808)${NC}"
                read -p "地址 (0 取消): " user_proxy
                if [ "$user_proxy" == "0" ]; then break; fi
                if ! validate_proxy_format "$user_proxy"; then echo -e "${RED}格式错误${NC}"; continue; fi
                if test_proxy_connection "$user_proxy"; then
                    sed -i '/^requestProxy:/,/^  bypass:/ s/enabled: false/enabled: true/' "$CONFIG_FILE" 2>/dev/null
                    sed -i "/^requestProxy:/,/^  bypass:/ s|^  url:.*|  url: \"$user_proxy\"|" "$CONFIG_FILE" 2>/dev/null
                    echo "$user_proxy" > "$PROXY_CONFIG_FILE"
                    rm -f "$MIRROR_CONFIG"
                    echo -e "${GREEN}✅ 设置成功${NC}"; sleep 1; break
                else
                    echo -e "${RED}❌ 连接失败${NC}"
                fi
            done
            ;;
        7)
            while true; do
                echo -e "${YELLOW}输入自定义前缀 (以 / 结尾)${NC}"
                read -p "地址 (0 取消): " custom_url
                if [ "$custom_url" == "0" ]; then return; fi
                if [[ $custom_url == http* ]]; then
                    [[ "${custom_url}" != */ ]] && custom_url="${custom_url}/"
                    if test_mirror_connection "$custom_url"; then
                        echo "$custom_url" > "$MIRROR_CONFIG"
                        rm -f "$PROXY_CONFIG_FILE"
                        echo -e "${GREEN}✅ 已切换${NC}"; break
                    else
                         echo -e "${RED}❌ 镜像不可用${NC}"
                    fi
                else
                    echo -e "${RED}格式错误${NC}"
                fi
            done
            ;;
        *)
            if [[ " ${valid_indices[*]} " =~ " ${choice} " ]]; then
                idx=$((choice - 1))
                echo "${mirrors[$idx]}" > "$MIRROR_CONFIG"
                rm -f "$PROXY_CONFIG_FILE"
                echo -e "${GREEN}√ 已切换: ${mirrors[$idx]}${NC}"
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
    if [ ! -f "recover.js" ]; then echo -e "${RED}错误：找不到 recover.js${NC}"; read -p "回车返回..."; return; fi
    clear
    echo -e "${CYAN}=== 🔐 密码重置 ===${NC}"
    if [ -d "data" ]; then ls -F data/ | grep "/" | sed 's/\///g'; fi
    echo "------------------------"
    read -p "用户名 [default-user]: " TARGET_USER
    TARGET_USER=${TARGET_USER:-default-user}
    read -p "新密码 [123456]: " NEW_PASS
    NEW_PASS=${NEW_PASS:-123456}
    node recover.js "$TARGET_USER" "$NEW_PASS"
    echo -e "${GREEN}完成${NC}"; read -p "回车返回..."
}

security_menu() {
    while true; do
        clear; echo -e "${CYAN}=== 🛠️ 安全配置 ===${NC}"
        echo -e "1. 🔓 修复白名单/免密"; echo -e "2. 🔑 重置密码"; echo -e "0. 🔙 返回"
        read -p "选择: " sec_choice
        case $sec_choice in
            1) configure_security_original; echo -e "${GREEN}完成${NC}"; sleep 1 ;;
            2) reset_password_logic ;;
            0) return ;;
        esac
    done
}

configure_proxy() {
    if [ ! -f "$CONFIG_FILE" ]; then echo -e "${RED}无配置${NC}"; sleep 1; return; fi
    clear; echo -e "${CYAN}=== 代理配置 ===${NC}"
    grep -A 5 "requestProxy:" "$CONFIG_FILE" | grep -E "enabled|url"
    echo ""; echo -e "1. 🟢 开启/设置"; echo -e "2. 🔴 关闭"; echo -e "0. 🔙 返回"
    read -p "选择: " pc
    case $pc in
        1)
            while true; do
                read -p "代理URL (0返回): " PURL
                if [ "$PURL" == "0" ]; then break; fi
                if ! validate_proxy_format "$PURL"; then echo -e "${RED}格式错误${NC}"; continue; fi
                if test_proxy_connection "$PURL"; then
                    sed -i '/^requestProxy:/,/^  bypass:/ s/enabled: false/enabled: true/' "$CONFIG_FILE"
                    sed -i "/^requestProxy:/,/^  bypass:/ s|^  url:.*|  url: \"$PURL\"|" "$CONFIG_FILE"
                    echo "$PURL" > "$PROXY_CONFIG_FILE"
                    echo -e "${GREEN}✅ 设置成功${NC}"; sleep 1; break
                else
                    echo -e "${RED}❌ 连接失败${NC}"
                fi
            done ;;
        2)
            sed -i '/^requestProxy:/,/^  bypass:/ s/enabled: true/enabled: false/' "$CONFIG_FILE"
            rm -f "$PROXY_CONFIG_FILE"
            echo -e "${GREEN}已关闭${NC}"; sleep 1 ;;
        *) return ;;
    esac
}

check_storage_permission() {
    if [ ! -d "$HOME/storage" ]; then
        echo -e "${CYAN}请点击【允许】授权存储访问。${NC}"
        termux-setup-storage; sleep 2
        if [ ! -d "$HOME/storage" ]; then echo -e "${RED}无存储权限${NC}"; return 1; fi
    fi
    return 0
}

perform_backup() {
    check_storage_permission || return
    if [ ! -d "$INSTALL_DIR/data" ]; then echo -e "${RED}无数据目录${NC}"; read -p "回车返回..."; return; fi
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/ST_Backup_$TIMESTAMP.tar.gz"
    echo -e "${CYAN}正在备份...${NC}"
    cd "$INSTALL_DIR" || return
    tar -czf "$BACKUP_FILE" data
    if [ -f "$BACKUP_FILE" ]; then echo -e "${GREEN}✅ 备份: $(basename "$BACKUP_FILE")${NC}"; else echo -e "${RED}失败${NC}"; fi
    read -p "回车返回..."
}

perform_restore() {
    check_storage_permission || return
    if [ ! -d "$BACKUP_DIR" ]; then echo -e "${RED}无备份目录${NC}"; read -p "回车返回..."; return; fi
    files=("$BACKUP_DIR"/ST_Backup_*.tar.gz)
    if [ ! -e "${files[0]}" ]; then echo -e "${RED}无有效备份文件${NC}"; read -p "回车返回..."; return; fi
    clear; echo -e "${CYAN}=== 恢复备份 ===${NC}"
    i=1
    for file in "${files[@]}"; do echo -e "$i. $(basename "$file")"; ((i++)); done
    echo "0. 返回"; echo ""
    read -p "选择: " file_idx
    if [[ "$file_idx" == "0" ]]; then return; fi
    SELECTED_FILE="${files[$((file_idx-1))]}"
    if [ -z "$SELECTED_FILE" ] || [ ! -f "$SELECTED_FILE" ]; then echo -e "${RED}无效${NC}"; sleep 1; return; fi
    echo -e "${RED}⚠️  警告: 将覆盖当前数据！${NC}"
    read -p "输入 'yes' 确认: " confirm
    if [[ "$confirm" != "yes" ]]; then return; fi
    rm -rf "$INSTALL_DIR/data"
    mkdir -p "$INSTALL_DIR/data"
    tar -xzf "$SELECTED_FILE" -C "$INSTALL_DIR"
    echo -e "${GREEN}✅ 恢复完成${NC}"; read -p "回车返回..."
}

backup_menu() {
    while true; do
        clear; echo -e "${CYAN}=== 💾 备份与恢复 ===${NC}"
        echo -e "1. 📤 备份"; echo -e "2. 📥 恢复"; echo -e "0. 🔙 返回"
        read -p "选择: " bc
        case $bc in
            1) perform_backup ;; 2) perform_restore ;; 0) return ;;
        esac
    done
}

# --- 核心操作函数 ---

install_st() {
    CONFIG_STR=$(get_current_config)
    TYPE=${CONFIG_STR%%:*}
    VALUE=${CONFIG_STR#*:}

    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${CYAN}>>> 开始部署...${NC}"

        # 沙盒模式：屏蔽所有全局配置，解决 URL 解析错误和代理嵌套问题
        local SAFE_ENV="env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null"
        
        if [ "$TYPE" == "PROXY" ]; then
            echo -e "${YELLOW}>>> 代理模式: $VALUE${NC}"
            GIT_CMD="$SAFE_ENV git clone --depth 1 -c http.proxy=$VALUE"
            URL="https://github.com/SillyTavern/SillyTavern.git"
        else
            echo -e "${YELLOW}>>> 镜像模式: $VALUE${NC}"
            GIT_CMD="$SAFE_ENV env -u http_proxy -u https_proxy git clone --depth 1 -c http.proxy="
            URL="${VALUE}https://github.com/SillyTavern/SillyTavern.git"
        fi

        if ! $GIT_CMD "$URL" "$INSTALL_DIR"; then
            echo -e "${RED}❌ 下载失败，进入线路选择...${NC}"
            sleep 2
            select_mirror
            install_st # 递归重试
            return
        fi
        cd "$INSTALL_DIR" || return
        npm config set registry https://registry.npmmirror.com
        npm install --no-audit --fund
        if [ -f "$INSTALL_DIR/default/config.yaml" ]; then cp "$INSTALL_DIR/default/config.yaml" "$CONFIG_FILE"; fi
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
    echo -e "${CYAN}>>> 更新酒馆...${NC}"
    cd "$INSTALL_DIR" || exit

    # 使用纯净环境进行 pull
    local SAFE_ENV="env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null"

    if [ "$TYPE" == "PROXY" ]; then git config http.proxy "$VALUE"; else git config --unset http.proxy; fi
    if [[ -n $(git status -s) ]]; then git stash; STASHED=1; fi

    # 修复：使用沙盒环境执行 pull
    if ! $SAFE_ENV git pull; then
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
    npm install --no-audit --fund
    echo -e "${GREEN}完成${NC}"; read -p "回车返回..."
}

stop_services() {
    pkill -f "node server.js"; pkill -f "cloudflared"; termux-wake-unlock 2>/dev/null
}

start_server_background() {
    stop_services; termux-wake-lock
    cd "$INSTALL_DIR" || exit
    echo -e "${CYAN}>>> 启动服务...${NC}"
    setsid nohup node server.js > "$SERVER_LOG" 2>&1 &
}

start_share() {
    ensure_whitelist_off; start_server_background
    echo "正在连接..." > "$CF_LOG"
    setsid nohup cloudflared tunnel --protocol http2 --url http://127.0.0.1:8000 --no-autoupdate >> "$CF_LOG" 2>&1 &
    echo -e "${GREEN}服务已启动！${NC}"; sleep 3
}

start_local() {
    start_server_background; echo -e "${GREEN}本地模式已启动！${NC}"; sleep 1.5
}

view_logs() {
    BREAK_LOOP=false
    clear
    if [ -f "$SERVER_LOG" ]; then
        while true; do
            if [ "$BREAK_LOOP" = "true" ]; then BREAK_LOOP=false; break; fi
            clear; echo -e "${CYAN}=== 日志 (Ctrl+C 退出) ===${NC}"
            tail -n 20 "$SERVER_LOG"; sleep 1
        done
    else
        echo -e "${RED}无日志${NC}"; read -p "回车返回..."
    fi
}

exit_script() { exec bash; }

show_menu() {
    while true; do
        BREAK_LOOP=false; clear; print_banner
        echo -e "${CYAN}             Version 1.9.3${NC}"
        if pgrep -f "node server.js" > /dev/null; then echo -e "状态: ${GREEN}● 运行中${NC}"; IS_RUNNING=true
        else echo -e "状态: ${RED}● 已停止${NC}"; IS_RUNNING=false; fi
        echo ""; echo -e "  1. 🚀 远程分享"; echo -e "  2. 🏠 本地模式"
        echo -e "  3. 📜 运行日志"; echo -e "  4. 🛑 停止服务"
        echo -e "  5. 🔄 无损更新"; echo -e "  6. 🛠️  安全配置"
        echo -e "  7. 🌐 API代理"; echo -e "  8. 💾 备份恢复"
        echo -e "  9. 🌐 切换线路"; echo -e " 10. 🧩 插件管理"; echo -e "  0. 退出"
        echo ""
        if [ "$IS_RUNNING" = true ]; then
             echo -e "${CYAN}====== [ 实时链接 ] ======${NC}"
             LINK=$(grep -o "https://[-a-zA-Z0-9]*\.trycloudflare\.com" "$CF_LOG" 2>/dev/null | grep -v "api" | tail -n 1)
             if [ -n "$LINK" ]; then echo -e "🌍 ${GREEN}$LINK${NC}"; else echo -e "📡 ${YELLOW}获取中...${NC}"; fi
             echo ""
        fi
        read -p "选择: " choice
        case $choice in
            1) check_env; install_st; start_share ;; 2) check_env; install_st; start_local ;;
            3) view_logs ;; 4) stop_services; sleep 1 ;; 5) check_env; update_st ;;
            6) security_menu ;; 7) configure_proxy ;; 8) backup_menu ;;
            9) select_mirror ;; 10) plugin_menu ;; 0) exit_script ;; *) ;;
        esac
    done
}

# --- 主执行流 ---
check_env
auto_setup_alias
if [ ! -d "$INSTALL_DIR" ]; then install_st; fi
if [ -d "$INSTALL_DIR" ]; then apply_global_optimizations; fi
show_menu