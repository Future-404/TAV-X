#!/bin/bash
# [METADATA]
# MODULE_NAME: 🛡️  ADB 保活 (Android)
# MODULE_ENTRY: adb_menu_loop
# [END_METADATA]
source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

PKG="com.termux"
LOG_FILE="$TAVX_DIR/adb_log.txt"
LEGACY_ADB_DIR="$TAVX_DIR/adb_tools"
HEARTBEAT_PID="$TAVX_DIR/.audio_heartbeat.pid"
SILENCE_FILE="$TAVX_DIR/config/silence.wav"

check_dependency() {
    if command -v adb &> /dev/null; then
        if adb --version &> /dev/null; then return 0; fi
        ui_print warn "ADB 架构错误，尝试自动修复..."
    fi
    ui_header "ADB 组件安装"
    if [ -d "$LEGACY_ADB_DIR" ]; then rm -rf "$LEGACY_ADB_DIR"; sed -i '/adb_tools\/platform-tools/d' "$HOME/.bashrc"; fi
    
    ui_print info "正在安装 ADB 工具包..."
    if [ "$OS_TYPE" == "TERMUX" ]; then
        if ui_spinner "安装中 (pkg)..." "pkg install android-tools -y"; then
             ui_print success "ADB 安装成功！"
        else
             ui_print error "安装失败。"
        fi
    else
        if ui_spinner "安装中 (apt)..." "$SUDO_CMD apt-get install adb -y"; then
             ui_print success "ADB 安装成功！"
        else
             ui_print error "安装失败，请尝试: sudo apt install adb"
        fi
    fi
    ui_pause
}

check_adb_status() {
    if ! command -v adb &> /dev/null; then echo "${RED}未安装${NC}"; return 1; fi
    if timeout 2 adb devices 2>/dev/null | grep -q "device$"; then return 0; else return 1; fi
}

check_audio_deps() {
    local MISSING=""
    if ! command -v mpv &> /dev/null; then MISSING="$MISSING mpv"; fi
    if [ -n "$MISSING" ]; then
        ui_header "安装音频组件"
        ui_print info "安装依赖: $MISSING"
        if [ "$OS_TYPE" == "TERMUX" ]; then
            pkg install $MISSING -y
        else
            $SUDO_CMD apt-get install $MISSING -y
        fi
    fi
}

ensure_silence_file() {
    if [ -f "$SILENCE_FILE" ] && [ -s "$SILENCE_FILE" ]; then return 0; fi
    ui_print warn "静音文件丢失，正在重建..."
    mkdir -p "$(dirname "$SILENCE_FILE")"
    local RESCUE_WAV="UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA="
    echo "$RESCUE_WAV" | base64 -d > "$SILENCE_FILE"
    if [ -s "$SILENCE_FILE" ]; then return 0; else ui_print error "无法生成静音文件！"; return 1; fi
}

start_heartbeat() {
    if [ "$OS_TYPE" == "LINUX" ]; then
        ui_print warn "Linux 环境通常无需音频保活，除非您正在调试。"
        if ! ui_confirm "仍要启动吗？"; then return; fi
    fi
    
    check_audio_deps
    ensure_silence_file || { ui_pause; return; }
    if [ -f "$HEARTBEAT_PID" ]; then
        local old_pid=$(cat "$HEARTBEAT_PID")
        if kill -0 "$old_pid" 2>/dev/null; then ui_print warn "音频心跳已在运行。"; return; fi
    fi
    ui_header "启动音频心跳"
    echo -e "${YELLOW}策略：模拟前台媒体播放，强制提升进程优先级。${NC}"
    echo ""
    setsid nohup bash -c "while true; do mpv --no-terminal --volume=0 --loop=inf \"$SILENCE_FILE\"; sleep 1; done" > /dev/null 2>&1 &
    local pid=$!
    echo $pid > "$HEARTBEAT_PID"
    disown $pid
    
    if command -v termux-wake-lock &> /dev/null; then termux-wake-lock; fi
    ui_print success "心跳已启动！(PID: $pid)"
    ui_pause
}

stop_heartbeat() {
    kill_process_safe "$HEARTBEAT_PID" "mpv --no-terminal"
    
    if command -v termux-wake-unlock &> /dev/null; then termux-wake-unlock; fi
    ui_print success "音频心跳已停止。"
    ui_pause
}

pair_device() {
    ui_header "ADB 无线配对"
    adb start-server >/dev/null 2>&1
    local host=$(ui_input "输入 IP:端口" "127.0.0.1:" "false")
    local code=$(ui_input "输入 6 位配对码" "" "false")
    [[ -z "$code" ]] && return
    if ui_spinner "正在配对..." "adb pair '$host' '$code' > '$LOG_FILE' 2>&1"; then
        if grep -q "Successfully paired" "$LOG_FILE"; then ui_print success "配对成功！"; else ui_print error "配对失败。"; fi
    else ui_print error "连接超时。"; fi
    ui_pause
}

connect_adb() {
    ui_header "连接 ADB"
    if check_adb_status; then ui_print success "ADB 已连接。"; ui_pause; return; fi
    local target=$(ui_input "输入 IP:端口" "127.0.0.1:" "false")
    if [ -z "$target" ] || [ "$target" == "127.0.0.1:" ]; then return; fi
    if ui_spinner "正在连接 $target ..." "adb connect $target"; then
        sleep 1
        if check_adb_status; then ui_print success "连接成功！"; else ui_print error "连接失败。"; fi
    fi
    ui_pause
}

get_device_info() {
    MANUFACTURER=$(adb shell getprop ro.product.manufacturer | tr '[:upper:]' '[:lower:]')
    SDK_VER=$(adb shell getprop ro.build.version.sdk | tr -d '\r')
    [ -z "$SDK_VER" ] && SDK_VER=0
}

apply_universal_fixes() {
    local PKG="com.termux"
    local SDK_VER=$(adb shell getprop ro.build.version.sdk | tr -d '\r')
    [ -z "$SDK_VER" ] && SDK_VER=0
    
    if [ "$SDK_VER" -ge 32 ]; then
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

apply_vendor_fixes() {
    local PKG="com.termux"
    local MANUFACTURER=$(adb shell getprop ro.product.manufacturer | tr '[:upper:]' '[:lower:]')
    local SDK_VER=$(adb shell getprop ro.build.version.sdk | tr -d '\r')
    [ -z "$SDK_VER" ] && SDK_VER=0

    ui_print info "检测厂商策略: $MANUFACTURER"
    
    case "$MANUFACTURER" in
        *huawei*|*honor*) 
            ui_print info "正在应用华为策略..."
            adb shell pm disable-user --user 0 com.huawei.powergenie 2>/dev/null
            adb shell pm disable-user --user 0 com.huawei.android.hwaps 2>/dev/null
            adb shell am stopservice hwPfwService 2>/dev/null
            echo -e "${YELLOW}提示: 请手动检查 电池 -> 应用启动管理 -> Termux -> 改为手动管理${NC}"
            ;; 
            
        *xiaomi*|*redmi*) 
            ui_print info "正在应用小米策略..."
            adb shell pm disable-user --user 0 com.xiaomi.joyose 2>/dev/null
            adb shell pm disable-user --user 0 com.xiaomi.powerchecker 2>/dev/null
            adb shell am start -n com.miui.securitycenter/com.miui.permcenter.autostart.AutoStartManagementActivity >/dev/null 2>&1
            echo -e "${YELLOW}提示: 系统已弹窗，请务必勾选 Termux 的【自启动】权限。${NC}"
            ;; 
            
        *oppo*|*realme*|*oneplus*) 
            ui_print info "正在应用 ColorOS 策略..."
            if [ "$SDK_VER" -ge 34 ]; then
                ui_print warn "Android 14+ 检测: 跳过禁用 Athena (防砖保护)。"
                adb shell settings put global coloros_super_power_save 0
            else
                adb shell pm disable-user --user 0 com.coloros.athena 2>/dev/null
            fi
            adb shell am start -n com.coloros.safecenter/.startupapp.StartupAppListActivity >/dev/null 2>&1
            echo -e "${YELLOW}提示: 系统已弹窗，请允许自启动。${NC}"
            ;; 
            
        *vivo*|*iqoo*) 
            ui_print info "正在应用 OriginOS 策略..."
            adb shell pm disable-user --user 0 com.vivo.pem 2>/dev/null
            adb shell pm disable-user --user 0 com.vivo.abe 2>/dev/null
            adb shell am start -a android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS >/dev/null 2>&1
            ;; 
            
        *)
            ui_print info "无特定厂商策略，仅使用通用优化。"
            ;; 
    esac
}

apply_smart_keepalive() {
    ui_header "执行智能保活"
    if ! check_adb_status; then ui_print error "ADB 未连接。"; ui_pause; return; fi
    
    get_device_info
    echo -e "设备: ${CYAN}$MANUFACTURER${NC} (SDK: $SDK_VER)"
    echo "----------------------------------------"
    
    local SELF_SOURCE="source \"${BASH_SOURCE[0]}\""

    CHOICE=$(ui_menu "请选择保活方案" \
        "🛡️ 通用保活 (推荐/安全)" \
        "🔥 激进保活 (激进/可撤销)" \
        "🔙 返回" 
    )

    case "$CHOICE" in
        *"通用"*) 
            echo ""
            ui_print info "正在执行通用优化 (AOSP)..."
            ui_spinner "应用系统参数..." "$SELF_SOURCE; apply_universal_fixes"
            
            ui_print success "通用保活执行成功！"
            echo -e "${YELLOW}提示：请重启手机。如果依然杀后台，请尝试[激进保活]。${NC}"
            ui_pause
            ;; 
            
        *"激进"*) 
            echo ""
            echo -e "${RED}⚠️  激进模式副作用警告：${NC}"
            echo -e "此模式将禁用温控/云控组件，可能导致发热或私有快充失效。"
            
            if ! ui_confirm "我已知晓风险，确认执行？"; then 
                ui_print info "已取消。"; ui_pause; return
            fi
            
            ui_spinner "步骤1/2: 应用通用策略..." "$SELF_SOURCE; apply_universal_fixes"
            
            echo ""
            ui_print info "步骤2/2: 应用厂商策略..."
            apply_vendor_fixes 
            
            echo ""
            ui_print success "激进保活执行成功！"
            echo -e "${YELLOW}重要：${NC}"
            echo -e "1. 建议**重启手机**以彻底应用更改。"
            echo -e "2. 重启后无需再次执行，但需重新开启音频心跳。"
            ui_pause
            ;; 
            
        *) return ;; 
    esac
}

revert_all_changes() {
    ui_header "撤销/恢复出厂"
    if ! check_adb_status; then ui_print error "ADB 未连接。"; ui_pause; return; fi
    
    if ! ui_confirm "确定要恢复出厂默认配置吗？"; then return; fi
    
    ui_spinner "正在全量回滚..." "
        adb shell device_config set_sync_disabled_for_tests none
        adb shell device_config delete activity_manager max_phantom_processes
        adb shell device_config delete activity_manager settings_enable_monitor_phantom_procs
        adb shell dumpsys deviceidle whitelist -$PKG
        adb shell cmd appops set $PKG RUN_IN_BACKGROUND default
        adb shell cmd appops set $PKG RUN_ANY_IN_BACKGROUND default
        adb shell cmd appops set $PKG WAKE_LOCK default
        
        adb shell pm enable com.huawei.powergenie 2>/dev/null
        adb shell pm enable com.huawei.android.hwaps 2>/dev/null
        adb shell pm enable com.xiaomi.joyose 2>/dev/null
        adb shell pm enable com.xiaomi.powerchecker 2>/dev/null
        adb shell pm enable com.coloros.athena 2>/dev/null
        adb shell pm enable com.vivo.pem 2>/dev/null
        adb shell pm enable com.vivo.abe 2>/dev/null
        if command -v termux-wake-unlock &> /dev/null; then termux-wake-unlock; fi
    "
    
    ui_print success "已恢复默认设置！"
    ui_pause
}

adb_menu_loop() {
    check_dependency
    while true; do
        ui_header "ADB 智能保活"
        
        local s_adb="${RED}● 未连接${NC}"; check_adb_status && s_adb="${GREEN}● 已连接${NC}"
        local s_audio="${RED}● 关闭${NC}"
        if [ -f "$HEARTBEAT_PID" ] && kill -0 $(cat "$HEARTBEAT_PID") 2>/dev/null; then 
            s_audio="${GREEN}● 运行中${NC}"
        fi
        
        echo -e "ADB状态: $s_adb | 音频心跳: $s_audio"
        echo "----------------------------------------"
        
        if [ "$OS_TYPE" == "LINUX" ]; then
             echo -e "${BLUE}ℹ️  Linux 模式: 此工具仅用于管理远程/USB连接的 Android 设备。${NC}"
             echo "----------------------------------------"
        fi

        CHOICE=$(ui_menu "请选择操作" \
            "🤝 无线配对" \
            "🔗 连接 ADB" \
            "⚡ 执行智能保活" \
            "🎵 启动音频心跳" \
            "🔇 停止音频心跳" \
            "♻️  撤销所有优化" \
            "🔙 返回上级"
        )
        
        case "$CHOICE" in
            *"无线配对"*) pair_device ;; 
            *"连接 ADB"*) connect_adb ;; 
            *"智能保活"*) apply_smart_keepalive ;; 
            *"启动音频"*) start_heartbeat ;; 
            *"停止音频"*) stop_heartbeat ;; 
            *"撤销"*) revert_all_changes ;; 
            *"返回"*) return ;; 
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    adb_menu_loop
fi
