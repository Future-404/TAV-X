#!/bin/bash
# TAV-X Core: Main Logic

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
source "$TAVX_DIR/core/about.sh"

check_dependencies
check_for_updates
send_analytics

while true; do
    S_ST=0; S_CF=0; S_ADB=0; S_CLEWD=0; S_GEMINI=0; S_AUDIO=0
    pgrep -f "node server.js" >/dev/null && S_ST=1
    pgrep -f "cloudflared" >/dev/null && S_CF=1
    command -v adb &>/dev/null && adb devices 2>/dev/null | grep -q "device$" && S_ADB=1
    pgrep -f "clewd" >/dev/null && S_CLEWD=1
    pgrep -f "run.py" >/dev/null && S_GEMINI=1
    if [ -f "$TAVX_DIR/.audio_heartbeat.pid" ] && kill -0 $(cat "$TAVX_DIR/.audio_heartbeat.pid") 2>/dev/null; then
        S_AUDIO=1
    fi

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
    ui_dashboard "$S_ST" "$S_CF" "$S_ADB" "$NET_DL" "$NET_API" "$S_CLEWD" "$S_GEMINI" "$S_AUDIO"

    OPT_UPD="🔄 安装与更新"
    [ -f "$TAVX_DIR/.update_available" ] && OPT_UPD="🔄 安装与更新 🔔"

    CHOICE=$(ui_menu "功能导航" \
        "🚀 启动服务" \
        "$OPT_UPD" \
        "⚙️  系统设置" \
        "🧩 插件管理" \
        "🌐 网络设置" \
        "💾 备份与恢复" \
        "🛠️  高级工具" \
        "💡 帮助与支持" \
        "🚪 退出程序"
    )

    case "$CHOICE" in
        *"启动服务")
            if [ ! -d "$INSTALL_DIR" ]; then ui_print warn "请先安装酒馆！"; ui_pause; else start_menu; fi ;;
        *"安装与更新"*) update_center_menu ;;
        *"系统设置") security_menu ;;
        *"插件管理") plugin_menu ;;
        *"网络设置") configure_download_network ;;
        *"备份与恢复") backup_menu ;;
        *"高级工具")
            SUB=$(ui_menu "高级工具箱" \
                "🦀 ClewdR 管理" \
                "♊ Gemini CLI代理" \
                "🛡️  ADB 保活" \
                "🔙 返回上级"
            )
            case "$SUB" in
                *"ClewdR"*) source "$TAVX_DIR/modules/clewd.sh"; clewd_menu ;;
                *"Gemini"*) source "$TAVX_DIR/modules/Gemini_CLI.sh"; gemini_menu ;;
                *"ADB"*) source "$TAVX_DIR/modules/adb_keepalive.sh"; adb_menu_loop ;;
                *"返回"*) ;;
            esac ;;
        
        *"帮助与支持"*) show_about_page ;;
            
        *"退出程序"*) 
            EXIT_OPT=$(ui_menu "请选择退出方式" \
                "🏃 保持后台运行" \
                "🛑 结束所有服务并退出" \
                "🔙 取消" \
            )
            
            case "$EXIT_OPT" in
                *"保持后台"*)
                    ui_print info "程序已最小化，服务继续在后台运行。"
                    ui_print info "下次输入 'st' 即可唤回菜单。"
                    exit 0 
                    ;;
                *"结束所有"*)
                    echo ""
                    if ui_confirm "确定要关闭所有服务（酒馆、穿透、保活等）吗？"; then
                        ui_spinner "正在停止所有进程..." "
                            # 1. 优先终止音频心跳的父进程 (防止无限复活)
                            if [ -f '$TAVX_DIR/.audio_heartbeat.pid' ]; then
                                HB_PID=\$(cat '$TAVX_DIR/.audio_heartbeat.pid')
                                kill -9 \$HB_PID >/dev/null 2>&1
                                rm -f '$TAVX_DIR/.audio_heartbeat.pid'
                            fi
                            # 补刀：清理残留的播放器子进程
                            pkill -f 'mpv --no-terminal'

                            # 2. 优雅关闭 ADB 服务
                            adb kill-server >/dev/null 2>&1
                            pkill -f 'adb' # 强制补刀

                            # 3. 停止其他业务进程
                            pkill -f 'node server.js'
                            pkill -f 'cloudflared'
                            pkill -f 'clewd'
                            pkill -f 'run.py' # Gemini
                            
                            # 4. 释放资源与锁
                            termux-wake-unlock 2>/dev/null
                            rm -f '$TAVX_DIR/.temp_link'
                        "
                        ui_print success "所有服务已停止，资源已释放。"
                        exit 0
                    else
                        ui_print info "操作已取消。"
                    fi
                    ;;
                *) ;;
            esac
            ;;
            
        *) exit 0 ;;
    esac
done