#!/bin/bash
# TAV-X Core: ADB & Keepalive Utils (Migrated from Module)
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
    # 生成 1 秒静音 wav 文件的 base64 
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
        ui_header "ADB 智能助手 (保活与修复)"
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
        
        local CHOICE=$(ui_menu "请选择操作" "🤝 无线配对" "🔗 快速连接" "⚡ 执行智能保活" "🎵 开启音频心跳" "🔇 关闭音频心跳" "♻️  撤销所有优化" "🗑️  重置环境" "🔙 返回")
        case "$CHOICE" in
            *"配对"*)
                local host=$(ui_input_validated "输入 IP:端口" "127.0.0.1:" "ip")
                local code=$(ui_input_validated "输入 6 位配对码" "" "numeric")
                [ -n "$code" ] && ui_spinner "配对中..." "adb pair '$host' '$code'" && ui_pause ;;
            *"连接"*)
                local target=$(ui_input_validated "输入 IP:端口" "127.0.0.1:" "ip")
                [ -n "$target" ] && ui_spinner "连接中..." "adb connect '$target'" && ui_pause ;;
            *"智能保活"*)
                if ! check_adb_connection; then ui_print error "请先连接设备！"; ui_pause; continue; fi
                local sub=$(ui_menu "方案" "🛡️ 通用保活 (AOSP)" "🔥 激进保活 (含厂商策略)" "🔙 返回")
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
