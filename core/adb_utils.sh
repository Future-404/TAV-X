#!/bin/bash
# TAV-X Core: ADB & Keepalive Utils
[ -n "$_TAVX_ADB_UTILS_LOADED" ] && return
_TAVX_ADB_UTILS_LOADED=true

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

PKG="com.termux"
LOG_FILE="$LOGS_DIR/adb_manager.log"
HEARTBEAT_PID="$RUN_DIR/audio_heartbeat.pid"
SILENCE_FILE="$CONFIG_DIR/silence.wav"
LEGACY_ADB_DIR="$TAVX_DIR/adb_tools"
OPTIMIZED_FLAG="$CONFIG_DIR/.adb_optimized"

revert_optimization_core() {
    local PKG="com.termux"
    adb shell device_config set_sync_disabled_for_tests none 2>/dev/null
    adb shell device_config delete activity_manager max_phantom_processes 2>/dev/null
    adb shell device_config delete activity_manager settings_enable_monitor_phantom_procs 2>/dev/null
    adb shell dumpsys deviceidle whitelist -$PKG 2>/dev/null
    adb shell cmd appops set $PKG RUN_IN_BACKGROUND default 2>/dev/null
    adb shell cmd appops set $PKG RUN_ANY_IN_BACKGROUND default 2>/dev/null
    adb shell cmd appops set $PKG WAKE_LOCK default 2>/dev/null
    adb shell pm enable com.huawei.powergenie 2>/dev/null
    adb shell pm enable com.huawei.android.hwaps 2>/dev/null
    adb shell pm enable com.xiaomi.joyose 2>/dev/null
    adb shell pm enable com.xiaomi.powerchecker 2>/dev/null
    adb shell pm enable com.coloros.athena 2>/dev/null
    adb shell pm enable com.vivo.pem 2>/dev/null
    adb shell pm enable com.vivo.abe 2>/dev/null
    
    if command -v termux-wake-unlock &> /dev/null; then termux-wake-unlock; fi
    safe_rm "$OPTIMIZED_FLAG"
}
export -f revert_optimization_core

apply_universal_fixes() {
    local PKG="com.termux"
    local SDK_VER=$(adb shell getprop ro.build.version.sdk | tr -d '\r')
    [ -z "$SDK_VER" ] && SDK_VER=0
    
    if [ "$SDK_VER" -ge 31 ]; then
        adb shell device_config set_sync_disabled_for_tests persistent
        adb shell device_config put activity_manager max_phantom_processes 2147483647
        adb shell device_config put activity_manager settings_enable_monitor_phantom_procs false
    fi

    adb shell dumpsys deviceidle whitelist +$PKG >/dev/null 2>&1
    adb shell cmd appops set $PKG RUN_IN_BACKGROUND allow
    adb shell cmd appops set $PKG RUN_ANY_IN_BACKGROUND allow
    adb shell cmd appops set $PKG WAKE_LOCK allow
    adb shell cmd appops set $PKG START_FOREGROUND allow
    adb shell am set-standby-bucket $PKG active >/dev/null 2>&1
    if command -v termux-wake-lock &> /dev/null; then termux-wake-lock; fi
}
export -f apply_universal_fixes

apply_vendor_fixes() {
    local MANUFACTURER=$(adb shell getprop ro.product.manufacturer | tr '[:upper:]' '[:lower:]')
    local SDK_VER=$(adb shell getprop ro.build.version.sdk | tr -d '\r')
    [ -z "$SDK_VER" ] && SDK_VER=0

    ui_print info "正在应用厂商深度策略: ${CYAN}$MANUFACTURER${NC}"
    
    case "$MANUFACTURER" in
        *huawei*|*honor*) 
            ui_print info ">>> 执行华为/荣耀 PowerGenie 冻结..."
            adb shell pm disable-user --user 0 com.huawei.powergenie 2>/dev/null
            adb shell pm disable-user --user 0 com.huawei.android.hwaps 2>/dev/null
            adb shell am stopservice hwPfwService 2>/dev/null
            echo -e "${YELLOW}💡 提示: 建议在【电池管理】中将 Termux 设为【手动管理】。${NC}"
            ;;
            
        *xiaomi*|*redmi*) 
            ui_print info ">>> 执行小米 Joyose/云控 冻结..."
            adb shell pm disable-user --user 0 com.xiaomi.joyose 2>/dev/null
            adb shell pm disable-user --user 0 com.xiaomi.powerchecker 2>/dev/null
            adb shell am start -n com.miui.securitycenter/com.miui.permcenter.autostart.AutoStartManagementActivity >/dev/null 2>&1
            echo -e "${YELLOW}💡 提示: 请务必在弹出的界面中开启 Termux 的【自启动】。${NC}"
            ;;
            
        *oppo*|*realme*|*oneplus*) 
            ui_print info ">>> 执行 ColorOS Athena 调优..."
            if [ "$SDK_VER" -ge 34 ]; then
                ui_print warn "Android 14+ 检测: 跳过禁用 Athena (防砖保护)。"
                adb shell settings put global coloros_super_power_save 0
            else
                adb shell pm disable-user --user 0 com.coloros.athena 2>/dev/null
            fi
            adb shell am start -n com.coloros.safecenter/.startupapp.StartupAppListActivity >/dev/null 2>&1
            echo -e "${YELLOW}💡 提示: 请在弹出的窗口中允许 Termux 自启动。${NC}"
            ;; 

        *vivo*|*iqoo*) 
            ui_print info ">>> 执行 OriginOS PEM/ABE 调优..."
            ui_print warn "注意：正在尝试禁用核心保活组件以实现深度驻留..."
            adb shell pm disable-user --user 0 com.vivo.pem 2>/dev/null
            adb shell pm disable-user --user 0 com.vivo.abe 2>/dev/null
            adb shell am start -a android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS >/dev/null 2>&1
            echo -e "${YELLOW}💡 提示: 请在弹出的界面中确认 Termux 为【不优化电池】。${NC}"
            ;; 

        *)
            ui_print info "非主流机型，仅应用 AOSP 通用保活。"
            ;;
    esac
}

export -f apply_vendor_fixes

ensure_silence_file() {
    if [ -f "$SILENCE_FILE" ]; then return 0; fi
    ui_print info "生成静音配置文件..."
    mkdir -p "$(dirname "$SILENCE_FILE")"
    echo "UklGRigAAABXQVZFRm10IBAAAAABAAEARKwAAIhYAQACABAAZGF0YQAAAAA=" | base64 -d > "$SILENCE_FILE"
    return 0
}
check_adb_binary() {
    command -v adb &> /dev/null
}

check_adb_connection() {
    check_adb_binary || return 1
    timeout 2 adb devices 2>/dev/null | grep -q "device$"
}

ensure_adb_installed() {
    if [ -d "$LEGACY_ADB_DIR" ]; then 
        safe_rm "$LEGACY_ADB_DIR"
        sed -i '/adb_tools\/platform-tools/d' "$HOME/.bashrc" 2>/dev/null
    fi

    if check_adb_binary; then return 0; fi
    ui_header "ADB 组件安装"
    ui_print info "正在尝试自动安装 ADB 工具包..."
    
    local pkg_name="android-tools"
    [ "$OS_TYPE" == "LINUX" ] && pkg_name="adb"
    
    sys_install_pkg "$pkg_name"
    check_adb_binary
}

start_heartbeat() {
    if [ "$OS_TYPE" == "LINUX" ]; then
        ui_print warn "Linux 环境通常无需音频保活，除非您正在调试。"
        if ! ui_confirm "仍要启动吗？"; then return; fi
    fi

    source "$TAVX_DIR/core/deps.sh"
    command -v mpv &>/dev/null || { 
        ui_print info "安装音频组件..."; 
        sys_install_pkg "mpv"
    }
    
    ensure_silence_file || { ui_pause; return 1; }
    ui_header "启动音频心跳"
    setsid nohup bash -c "while true; do mpv --no-terminal --volume=0 --loop=inf \"$SILENCE_FILE\"; sleep 1; done" > /dev/null 2>&1 &
    echo $! > "$HEARTBEAT_PID"
    ui_print success "音频心跳已在后台开启，正在模拟前台占用..."
    ui_pause
}

stop_heartbeat() {
    kill_process_safe "$HEARTBEAT_PID" "mpv"
    if command -v termux-wake-unlock &> /dev/null; then termux-wake-unlock; fi
    ui_print success "音频心跳已停止。"
}

adb_refrigerator_ui() {
    if ! check_adb_connection; then
        ui_print error "未检测到 ADB 连接！请先执行 [无线配对] 或 [快速连接]。"
        ui_pause; return
    fi

    ui_header "🥶 应用小冰箱 (App Freezer)"
    echo -e "${RED}⚠️  高危功能免责声明${NC}"
    echo "----------------------------------------"
    echo -e "1. 本功能通过 ADB 强行禁用应用，可能导致${RED}系统卡死、无限重启或无法开机${NC}。"
    echo -e "2. 请务必清楚目标应用的用途。${YELLOW}切勿冻结系统关键组件！${NC}"
    echo -e "3. 因误操作导致的任何设备损坏或数据丢失，${RED}与脚本作者无关${NC}。"
    echo "----------------------------------------"
    
    if ! ui_confirm "我已阅读并知晓上述风险，后果自负"; then return; fi

    while true; do
        ui_header "小冰箱管理面板"
        
        local frozen_count=$(adb shell pm list packages -d -3 2>/dev/null | wc -l)
        local all_count=$(adb shell pm list packages -3 2>/dev/null | wc -l)
        
        echo -e "已冻结应用: ${CYAN}$frozen_count${NC} / 总第三方应用: $all_count"
        echo "----------------------------------------"
        
        local OPT=$(ui_menu "请选择操作" "🧊 冻结应用 (Disable)" "🔥 解冻应用 (Enable)" "🔙 返回")
        
        case "$OPT" in
            *"冻结"*) _adb_freeze_workflow ;;
            *"解冻"*) _adb_unfreeze_workflow ;;
            *"返回"*) return ;;
        esac
    done
}

_adb_get_pkg_list() {
    local mode="$1"
    adb shell pm list packages -3 $mode | cut -d: -f2 | sort
}

_adb_freeze_workflow() {
    ui_print info "正在扫描可冻结的第三方应用..."
    mapfile -t RAW_PKG_LIST < <(_adb_get_pkg_list "-e")
    
    if [ ${#RAW_PKG_LIST[@]} -eq 0 ]; then
        ui_print warn "没有找到可冻结的应用。"
        ui_pause; return
    fi
    
    local KEYWORD=$(ui_input "输入包名关键词 (如 tencent, 留空列出所有)" "" "false")
    
    local MATCHED_LIST=()
    for pkg in "${RAW_PKG_LIST[@]}"; do
        if [[ "$pkg" == *"$KEYWORD"* ]]; then
            MATCHED_LIST+=("$pkg")
        fi
    done
    
    if [ ${#MATCHED_LIST[@]} -eq 0 ]; then
        ui_print warn "未找到匹配的应用。"
        ui_pause; return
    fi
    
    local SELECTED=""
    
    if [ ${#MATCHED_LIST[@]} -eq 1 ]; then
        SELECTED="${MATCHED_LIST[0]}"
    else
        if [ ${#MATCHED_LIST[@]} -gt 50 ]; then
            ui_print warn "匹配结果过多 (${#MATCHED_LIST[@]} 个)，请优化关键词。"
            ui_pause; return
        fi
        
        local MENU_OPTS=()
        for p in "${MATCHED_LIST[@]}"; do MENU_OPTS+=("📦 $p"); done
        MENU_OPTS+=("🔙 返回")
        
        local CHOICE=$(ui_menu "请选择目标应用" "${MENU_OPTS[@]}")
        if [[ "$CHOICE" == *"返回"* ]]; then return; fi
        
        SELECTED=$(echo "$CHOICE" | awk '{print $2}')
    fi
    
    [ -z "$SELECTED" ] && return
    
    ui_header "⚠️  高危操作确认"
    echo -e "目标应用: ${RED}$SELECTED${NC}"
    echo -e "此操作将使其从桌面消失并停止运行。"
    echo ""
    local CONFIRM=$(ui_input "请输入 [YES] 确认冻结" "" "false")
    
    if [ "$CONFIRM" == "YES" ]; then
        if adb shell pm disable-user --user 0 "$SELECTED" &>/dev/null; then
            ui_print success "已成功冻结: $SELECTED"
        else
            ui_print error "操作失败，可能权限不足。"
        fi
    else
        ui_print warn "操作已取消。"
    fi
    ui_pause
}

_adb_unfreeze_workflow() {
    ui_print info "正在获取已冻结列表..."
    mapfile -t RAW_PKG_LIST < <(_adb_get_pkg_list "-d")
    
    if [ ${#RAW_PKG_LIST[@]} -eq 0 ]; then
        ui_print warn "当前没有被冻结的第三方应用。"
        ui_pause; return
    fi

    local KEYWORD=$(ui_input "输入包名关键词 (留空列出所有)" "" "false")
    
    local MATCHED_LIST=()
    for pkg in "${RAW_PKG_LIST[@]}"; do
        if [[ "$pkg" == *"$KEYWORD"* ]]; then
            MATCHED_LIST+=("$pkg")
        fi
    done
    
    if [ ${#MATCHED_LIST[@]} -eq 0 ]; then
        ui_print warn "未找到匹配的应用。"
        ui_pause; return
    fi
    
    local SELECTED=""
    
    if [ ${#MATCHED_LIST[@]} -eq 1 ]; then
        SELECTED="${MATCHED_LIST[0]}"
    else
        if [ ${#MATCHED_LIST[@]} -gt 50 ]; then
            ui_print warn "匹配结果过多 (${#MATCHED_LIST[@]} 个)，请优化关键词。"
            ui_pause; return
        fi
        
        local MENU_OPTS=()
        for p in "${MATCHED_LIST[@]}"; do MENU_OPTS+=("❄️  $p"); done
        MENU_OPTS+=("🔙 返回")
        
        local CHOICE=$(ui_menu "请选择目标应用" "${MENU_OPTS[@]}")
        if [[ "$CHOICE" == *"返回"* ]]; then return; fi
        
        SELECTED=$(echo "$CHOICE" | awk '{print $2}')
    fi
    
    [ -z "$SELECTED" ] && return
    
    if adb shell pm enable "$SELECTED" &>/dev/null; then
        ui_print success "已成功解冻: $SELECTED"
    else
        ui_print error "解冻失败。"
    fi
    ui_pause
}

uninstall_adb() {
    ui_header "卸载 ADB 保活模块"

    if ! verify_kill_switch; then return; fi

    if [ -f "$HEARTBEAT_PID" ] && kill -0 $(cat "$HEARTBEAT_PID") 2>/dev/null; then
        ui_print info "正在停止后台音频心跳..."
        stop_heartbeat
    fi

    echo ""
    echo -e "${YELLOW}🔍 正在检查残留配置...${NC}"

    echo -e "您之前可能应用了系统级保活策略。"
    if ui_confirm "是否将系统参数恢复为默认状态?"; then
        ui_spinner "正在回滚系统设置..." "revert_optimization_core"
        ui_print success "系统设置已恢复。"
    else
        ui_print info "保留系统优化设置。"
    fi

    if command -v mpv &> /dev/null; then
        echo ""
        echo -e "${YELLOW}检测到已安装 mpv 播放器。${NC}"
        echo -e "如果是专为保活安装的，建议卸载。"
        if ui_confirm "是否卸载 mpv ?"; then
            sys_remove_pkg "mpv"
            ui_print success "依赖已清理。"
        fi
    fi

    echo ""
    if [ -d "$LEGACY_ADB_DIR" ] || [ -f "$LOG_FILE" ]; then
        ui_spinner "清理模块文件..." "
            safe_rm '$LEGACY_ADB_DIR'
            safe_rm '$LOG_FILE'
            safe_rm '$HEARTBEAT_PID'
            sed -i '/adb_tools\/platform-tools/d' '$HOME/.bashrc'
        "
        ui_print success "模块文件已清理。"
    fi

    if command -v adb &> /dev/null; then
        echo ""
        if ui_confirm "是否连同系统 ADB 一起卸载？"; then
            local pkg_name="android-tools"
            [ "$OS_TYPE" == "LINUX" ] && pkg_name="adb"
            sys_remove_pkg "$pkg_name"
            ui_print success "ADB 已卸载。"
        fi
    fi

    ui_print success "卸载完成。"
    ui_pause
}

adb_manager_ui() {
    ensure_adb_installed || { ui_print error "ADB 未安装且无法自动修复。"; ui_pause; return; }
    while true; do
        ui_header "ADB 助手"
        local state="stopped"; local text="未连接"; local info=()
        if check_adb_connection; then
            state="success"; text="已连接"
            local dev_count=$(adb devices | grep "device$" | wc -l)
            info+=( "设备数: $dev_count" )
        elif ! check_adb_binary; then
            state="error"; text="未安装"
        fi

        if [ -f "$HEARTBEAT_PID" ] && kill -0 $(cat "$HEARTBEAT_PID") 2>/dev/null; then
            info+=( "音频心跳: ⚡ 运行中" )
            [ "$state" == "success" ] && state="running" || state="warn"
        fi

        [ -f "$OPTIMIZED_FLAG" ] && info+=( "保活策略: 🔥 激进模式" )
        ui_status_card "$state" "$text" "${info[@]}"
        
        local CHOICE=$(ui_menu "请选择操作" "🥶 应用小冰箱" "🤝 无线配对" "🔗 快速连接" "⚡ 执行智能保活" "🎵 开启音频心跳" "🔇 关闭音频心跳" "♻️  撤销所有优化" "🗑️  重置环境" "🔙 返回")
        case "$CHOICE" in
            *"小冰箱"*) adb_refrigerator_ui ;;
            *"配对"*)
                local host=$(ui_input_validated "输入 IP:端口" "127.0.0.1:" "host")
                local code=$(ui_input_validated "输入 6 位配对码" "" "numeric")
                [ -n "$code" ] && ui_spinner "配对中..." "adb pair '$host' '$code'" && ui_pause ;;
            *"连接"*)
                local target=$(ui_input_validated "输入 IP:端口" "127.0.0.1:" "host")
                [ -n "$target" ] && ui_spinner "连接中..." "adb connect '$target'" && ui_pause ;;
            *"智能保活"*)
                if ! check_adb_connection; then ui_print error "请先连接设备！"; ui_pause; continue; fi
                local sub=$(ui_menu "方案" "🛡️ 通用保活" "🔥 激进保活" "🔙 返回")
                if [[ "$sub" == *"通用"* ]]; then
                    ui_spinner "应用通用策略..." "apply_universal_fixes" && {
                        touch "$OPTIMIZED_FLAG"
                        ui_print success "已应用，建议重启。"
                    }
                    ui_pause
                elif [[ "$sub" == *"激进"* ]]; then
                    if ui_confirm "激进模式可能影响发热和快充，确认执行？"; then
                        ui_spinner "应用通用策略..." "apply_universal_fixes"
                        apply_vendor_fixes
                        touch "$OPTIMIZED_FLAG"
                        ui_print success "激进策略执行完毕，请务必重启手机。"; ui_pause
                    fi
                fi ;; 
            *"开启音频"*) start_heartbeat ;; 
            *"关闭音频"*) stop_heartbeat; ui_pause ;; 
            *"撤销"*) 
                if ui_confirm "是否恢复系统默认参数？"; then
                    ui_spinner "正在回滚..." "revert_optimization_core"
                    ui_print success "已恢复。"; ui_pause
                fi ;; 
            *"清理"*|*"卸载"*) uninstall_adb ;; 
            *"返回"*) return ;; 
        esac
    done
}
