#!/bin/bash
# TAV-X Core: Main Logic (Refactored)

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"
source "$TAVX_DIR/core/deps.sh"
source "$TAVX_DIR/core/loader.sh"
source "$TAVX_DIR/core/security.sh"
source "$TAVX_DIR/core/updater.sh"
source "$TAVX_DIR/core/store.sh"
source "$TAVX_DIR/core/about.sh"

check_dependencies
scan_and_load_modules
check_for_updates
send_analytics

stop_all_services_routine() {
    ui_print info "正在停止所有服务..."
    
    local run_dir="$TAVX_DIR/run"
    if [ -d "$run_dir" ]; then
        for pid_file in "$run_dir"/*.pid; do
            [ ! -f "$pid_file" ] && continue
            
            local pid=$(cat "$pid_file")
            local name=$(basename "$pid_file" .pid)
            
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                kill -15 "$pid" 2>/dev/null
                if kill -0 "$pid" 2>/dev/null; then
                    kill -9 "$pid" 2>/dev/null
                    ui_print warn "强制停止: $name ($pid)"
                else
                    ui_print success "已停止: $name"
                fi
            fi
            rm -f "$pid_file"
        done
    fi
    
    if command -v termux-wake-unlock &> /dev/null; then termux-wake-unlock >/dev/null 2>&1; fi
    rm -f "$TAVX_DIR/.temp_link"
}
export -f stop_all_services_routine

app_drawer_menu() {
    while true; do
        if [ ${#REGISTERED_MODULE_NAMES[@]} -eq 0 ]; then
            ui_print warn "暂无已加载的模块脚本。"
            ui_pause; return
        fi

        local APP_MENU_OPTS=()
        local VALID_INDICES=()
        
        for i in "${!REGISTERED_MODULE_NAMES[@]}"; do
            local name="${REGISTERED_MODULE_NAMES[$i]}"
            local id="${REGISTERED_MODULE_IDS[$i]}"
            
            local app_path=$(get_app_path "$id")
            if [ ! -d "$app_path" ] || [ -z "$(ls -A "$app_path" 2>/dev/null)" ]; then
                continue 
            fi
            
            local icon="⚪"
            local pid_file="$TAVX_DIR/run/${id}.pid"
            if [ -f "$pid_file" ] && [ -s "$pid_file" ]; then
                local pid=$(cat "$pid_file")
                if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                    icon="🟢"
                fi
            fi
            
            APP_MENU_OPTS+=("$icon $name")
            VALID_INDICES+=("$i")
        done
        
        if [ ${#APP_MENU_OPTS[@]} -eq 0 ]; then
            ui_print warn "暂无已安装的应用。"
            echo "请前往 [🛒 应用中心] 下载并安装应用。"
            ui_pause; return
        fi
        
        APP_MENU_OPTS+=("🔙 返回主菜单")

        local CHOICE=$(ui_menu "我的应用" "${APP_MENU_OPTS[@]}")
        if [[ "$CHOICE" == *"返回"* ]]; then return; fi
        
        local found=false
        
        for idx in "${VALID_INDICES[@]}"; do
            local name="${REGISTERED_MODULE_NAMES[$idx]}"
            if [[ "$CHOICE" == *"$name" ]]; then
                local entry_func="${REGISTERED_MODULE_ENTRIES[$idx]}"
                if command -v "$entry_func" &>/dev/null; then
                    $entry_func
                else
                    ui_print error "模块入口函数丢失: $entry_func"
                    ui_pause
                fi
                found=true
                break
            fi
        done
        
        if [ "$found" = false ]; then
            ui_print error "模块匹配失败！"
            ui_pause
        fi
    done
}

while true; do
    MODULES_LINE=$(get_modules_status_line)
    MEM_STR=$(get_sys_resources_info)

    NET_DL="自动优选"
    if [ -f "$NETWORK_CONFIG" ]; then
        CONF=$(cat "$NETWORK_CONFIG"); TYPE=${CONF%%|*}
        [ "$TYPE" == "PROXY" ] && NET_DL="本地加速"
    fi

    ui_header ""
    ui_dashboard "$MODULES_LINE" "$NET_DL" "$MEM_STR"

    OPT_UPD="🔄 检查脚本更新"
    [ -f "$TAVX_DIR/.update_available" ] && OPT_UPD="🔄 检查脚本更新 🔔"

    FINAL_OPTS=()
    SHORTCUT_IDS=()
    
    if [ -f "$TAVX_DIR/config/shortcuts.list" ]; then
        shortcuts=($(cat "$TAVX_DIR/config/shortcuts.list"))
        if [ ${#shortcuts[@]} -gt 0 ]; then
            for sid in "${shortcuts[@]}"; do
                idx=-1
                for i in "${!REGISTERED_MODULE_IDS[@]}"; do
                    if [ "${REGISTERED_MODULE_IDS[$i]}" == "$sid" ]; then idx=$i; break; fi
                done
                
                if [ $idx -ge 0 ]; then
                    name="${REGISTERED_MODULE_NAMES[$idx]}"
                    icon="⚪"
                    pid_file="$TAVX_DIR/run/${sid}.pid"
                    if [ -f "$pid_file" ] && [ -s "$pid_file" ] && kill -0 $(cat "$pid_file") 2>/dev/null; then
                        icon="🟢"
                    fi
                    
                    FINAL_OPTS+=("$icon $name")
                    SHORTCUT_IDS+=("$sid")
                fi
            done
        fi
    fi

    FINAL_OPTS+=(
        "📂 我的应用"
        "🛒 应用商城"
        "$OPT_UPD"
        "⚙️  系统设置"
        "💡 帮助与支持"
        "🚪 退出程序"
    )

    CHOICE=$(ui_menu "主菜单" "${FINAL_OPTS[@]}")
    
    if [[ "$CHOICE" != *"---"* ]]; then
        for i in "${!SHORTCUT_IDS[@]}"; do
            sid="${SHORTCUT_IDS[$i]}"
            idx=-1
            for j in "${!REGISTERED_MODULE_IDS[@]}"; do
                if [ "${REGISTERED_MODULE_IDS[$j]}" == "$sid" ]; then idx=$j; break; fi
            done
            
            if [ $idx -ge 0 ]; then
                name="${REGISTERED_MODULE_NAMES[$idx]}"
                if [[ "$CHOICE" == *"$name" ]]; then
                    entry="${REGISTERED_MODULE_ENTRIES[$idx]}"
                    if command -v "$entry" &>/dev/null; then
                        $entry
                    else
                        ui_print error "无法启动模块: $entry"
                        ui_pause
                    fi
                    continue 2
                fi
            fi
        done
    fi

    case "$CHOICE" in
        *"我的应用"*) app_drawer_menu ;;
        *"应用商城"*) app_store_menu ;;
        *"检查脚本更新"*) perform_self_update ;;
        *"系统设置"*) system_settings_menu ;;
        *"帮助与支持"*) show_about_page ;;
        *"退出程序"*) 
            EXIT_OPT=$(ui_menu "请选择退出方式" "🏃 保持后台运行" "🛑 结束所有服务并退出" "🔙 取消")
            case "$EXIT_OPT" in
                *"保持后台"*)
                    write_log "EXIT" "User exited (Keeping services)"
                    ui_print info "程序已最小化，服务继续在后台运行。"
                    ui_restore_terminal
                    exit 0
                    ;;
                *"结束所有"*)
                    echo ""
                    if ui_confirm "确定要关闭所有服务吗？"; then
                        write_log "EXIT" "User requested stop all"
                        ui_spinner "正在停止所有进程..." "stop_all_services_routine"
                        ui_print success "所有服务已停止。"
                        ui_restore_terminal
                        exit 0
                    fi
                    ;;
            esac
            ;;
        *) 
            continue 
            ;;
    esac
done