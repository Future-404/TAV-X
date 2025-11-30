#!/bin/bash
# TAV-X Core: Main Logic (V6.2 Final Clean)

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"
source "$TAVX_DIR/core/deps.sh"
source "$TAVX_DIR/core/security.sh"
source "$TAVX_DIR/core/plugins.sh"
source "$TAVX_DIR/core/backup.sh"
source "$TAVX_DIR/core/updater.sh"
source "$TAVX_DIR/core/install.sh"
source "$TAVX_DIR/core/launcher.sh"
source "$TAVX_DIR/core/uninstall.sh"
source "$TAVX_DIR/modules/clewd.sh"

check_dependencies
check_for_updates
send_analytics

while true; do
    if [ -d "$INSTALL_DIR" ]; then ST_STATUS="${GREEN}已安装${NC}"; else ST_STATUS="${YELLOW}未安装${NC}"; fi
    S_ST=0; S_CF=0; S_ADB=0
    pgrep -f "node server.js" >/dev/null && S_ST=1
    pgrep -f "cloudflared" >/dev/null && S_CF=1
    command -v adb &>/dev/null && adb devices 2>/dev/null | grep -q "device$" && S_ADB=1

    NET_DL="自动优选"
    if [ -f "$NETWORK_CONFIG" ]; then
        CONF=$(cat "$NETWORK_CONFIG"); TYPE=${CONF%%|*}; VAL=${CONF#*|}
        [ ${#VAL} -gt 25 ] && VAL="...${VAL: -22}"
        [ "$TYPE" == "PROXY" ] && NET_DL="本地代理 ($VAL)"
        [ "$TYPE" == "MIRROR" ] && NET_DL="指定镜像 ($VAL)"
    fi

    NET_API="直连 (System)"
    if [ -f "$CONFIG_FILE" ]; then
        if grep -A 4 "requestProxy:" "$CONFIG_FILE" | grep -q "enabled: true"; then
            URL=$(grep -A 4 "requestProxy:" "$CONFIG_FILE" | grep "url:" | awk '{print $2}' | tr -d '"')
            [ -z "$URL" ] && URL="已开启"
            NET_API="代理 ($URL)"
        fi
    fi

    ui_header ""
    ui_dashboard "$S_ST" "$S_CF" "$S_ADB" "$NET_DL" "$NET_API"

    OPT_UPD="🔄 安装与更新"
    [ -f "$TAVX_DIR/.update_available" ] && OPT_UPD="🔄 安装与更新 🔔"

    CHOICE=$(ui_menu "功能导航" \
        "🚀 启动服务" \
        "$OPT_UPD" \
        "⚙️ 系统设置" \
        "🧩 插件管理" \
        "🌐 网络设置" \
        "💾 备份与恢复" \
        "🛠️ 高级工具" \
        "🚪 退出程序"
    )

    case "$CHOICE" in
        *"启动服务")
            if [ ! -d "$INSTALL_DIR" ]; then ui_print warn "请先安装酒馆！"; ui_pause; else start_menu; fi ;;
        *"安装与更新"*) update_center_menu ;;
        *"系统设置") security_menu ;;
        *"插件管理") plugin_menu ;;
        *"网络设置") configure_download_network ;; # 修正调用
        *"备份与恢复") backup_menu ;;
        *"高级工具")
            SUB=$(ui_menu "高级工具箱" "🦀 ClewdR 管理" "🛡️ ADB 保活" "🔙 返回上级")
            case "$SUB" in
                *"ClewdR"*) clewd_menu ;;
                *"ADB"*) source "$TAVX_DIR/modules/adb_keepalive.sh"; adb_menu_loop ;;
                *"返回"*) ;;
            esac ;;
        *"退出程序") ui_print info "再见！"; exit 0 ;;
        *) exit 0 ;;
    esac
done
