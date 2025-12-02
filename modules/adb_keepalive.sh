#!/bin/bash
# TAV-X Module: ADB Keep-Alive (V3.2 Native Arch & Safe Clean)

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

PKG="com.termux"
LOG_FILE="$TAVX_DIR/adb_log.txt"
LEGACY_ADB_DIR="$TAVX_DIR/adb_tools"

check_dependency() {
    if command -v adb &> /dev/null; then
        if adb --version &> /dev/null; then
            return 0
        fi
        ui_print warn "检测到 ADB 命令存在但无法运行 (可能是架构错误)。"
    fi

    ui_header "ADB 组件安装"
    
    if [ -d "$LEGACY_ADB_DIR" ]; then
        echo -e "${YELLOW}检测到旧版本/不兼容的 ADB 文件残留: $LEGACY_ADB_DIR${NC}"
        echo -e "这可能导致 'Exec format error' 错误。"
        echo ""
        if ui_confirm "是否删除旧文件以避免冲突？"; then
            ui_spinner "正在清理旧版残留..." "rm -rf '$LEGACY_ADB_DIR'"
            sed -i '/adb_tools\/platform-tools/d' "$HOME/.bashrc"
            ui_print success "清理完成。"
        else
            ui_print warn "已保留旧文件。如果连接失败，请手动清理 PATH 环境变量。"
        fi
    fi

    ui_print info "正在使用系统源安装 android-tools..."
    
    if ui_spinner "安装中..." "pkg update -y >/dev/null 2>&1; pkg install android-tools -y"; then
        if command -v adb &> /dev/null; then
            ui_print success "ADB 安装成功！"
        else
            ui_print error "安装看似成功但找不到命令，请尝试重启 Termux。"
        fi
    else
        ui_print error "安装失败，请检查 Termux 软件源配置。"
    fi
    ui_pause
}

check_adb_status() {
    if ! command -v adb &> /dev/null; then echo "${RED}未安装${NC}"; return; fi
    if adb devices 2>/dev/null | grep -q "device$"; then return 0; else return 1; fi
}

# --- 核心功能  ---
pair_device() {
    ui_header "ADB 无线配对向导"
    echo -e "${YELLOW}请前往开发者选项 -> 无线调试 -> 使用配对码配对设备${NC}"
    adb start-server >/dev/null 2>&1
    
    local host=$(ui_input "输入 IP:端口 (如 127.0.0.1:12345)" "127.0.0.1:" "false")
    local code=$(ui_input "输入 6 位配对码" "" "false")
    [[ -z "$code" ]] && return
    
    if ui_spinner "正在配对..." "adb pair '$host' '$code' > '$LOG_FILE' 2>&1"; then
        if grep -q "Successfully paired" "$LOG_FILE"; then
            ui_print success "配对成功！"
        else
            ui_print error "配对失败 (请检查配对码)。"
        fi
    else
        ui_print error "连接超时。"
    fi
    ui_pause
}

connect_adb() {
    ui_header "连接 ADB 服务"
    if check_adb_status; then ui_print success "ADB 已连接。"; ui_pause; return; fi
    
    echo -e "${YELLOW}请查看无线调试界面的【IP地址和端口】${NC}"
    local port=$(ui_input "请输入连接端口 (仅数字)" "" "false")
    [[ ! "$port" =~ ^[0-9]+$ ]] && { ui_print error "格式错误"; ui_pause; return; }
    
    if ui_spinner "正在连接 127.0.0.1:$port ..." "adb connect 127.0.0.1:$port"; then
        sleep 1
        if check_adb_status; then ui_print success "连接成功！"; else ui_print error "连接失败。"; fi
    fi
    ui_pause
}

apply_keepalive() {
    ui_header "执行系统级保活"
    if ! check_adb_status; then ui_print error "ADB 未连接。"; ui_pause; return; fi
    
    if ui_confirm "禁用幽灵进程杀手 (Phantom Process Killer)?"; then
        adb shell device_config put activity_manager max_phantom_processes 2147483647
        adb shell settings put global settings_enable_monitor_phantom_procs false
        ui_print success "已执行。"
    fi
    
    if ui_confirm "加入电池优化白名单?"; then
        adb shell dumpsys deviceidle whitelist +$PKG
        ui_print success "已执行。"
    fi
    
    if ui_confirm "允许后台运行权限 (AppOps)?"; then
        adb shell cmd appops set $PKG RUN_IN_BACKGROUND allow
        adb shell cmd appops set $PKG RUN_ANY_IN_BACKGROUND allow
        adb shell cmd appops set $PKG START_FOREGROUND allow
        ui_print success "已执行。"
    fi
    
    ui_print info "申请 CPU 唤醒锁..."
    termux-wake-lock
    ui_pause
}

revoke_permissions() {
    ui_header "释放资源与权限"
    if ! check_adb_status; then ui_print error "ADB 未连接。"; ui_pause; return; fi
    
    echo -e "${RED}即将撤销 Termux 的后台运行特权。${NC}"
    if ui_confirm "确定要撤销所有保活策略吗？"; then
        ui_spinner "正在重置系统参数..." "
            adb shell device_config delete activity_manager max_phantom_processes
            adb shell settings delete global settings_enable_monitor_phantom_procs
            adb shell dumpsys deviceidle whitelist -$PKG
            adb shell cmd appops set $PKG RUN_IN_BACKGROUND default
            adb shell cmd appops set $PKG RUN_ANY_IN_BACKGROUND default
            adb shell cmd appops set $PKG START_FOREGROUND default
        "
        termux-wake-unlock
        ui_print success "所有特权已撤销，唤醒锁已释放。"
    else
        ui_print info "已取消。"
    fi
    ui_pause
}

adb_menu_loop() {
    check_dependency
    while true; do
        ui_header "ADB 保活工具"
        if check_adb_status; then
            echo -e "状态: ${GREEN}● 已连接${NC}"
        else
            echo -e "状态: ${RED}● 未连接${NC}"
        fi
        echo ""
        
        CHOICE=$(ui_menu "请选择操作" \
            "🔗 连接 ADB" \
            "🤝 无线配对" \
            "🛡️ 执行保活" \
            "🧹 释放所有权限" \
            "🔙 返回上级"
        )
        
        case "$CHOICE" in
            *"连接"*) connect_adb ;;
            *"配对"*) pair_device ;;
            *"保活"*) apply_keepalive ;;
            *"释放"*) revoke_permissions ;;
            *"返回"*) return ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    adb_menu_loop
fi