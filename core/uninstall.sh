#!/bin/bash
# TAV-X Core: Uninstall Center (V3.1 + ADB Removal)

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

verify_kill_switch() {
    local TARGET_PHRASE="我已知此操作风险并且已做好备份"
    
    ui_header "⚠️ 高危操作安全确认"
    echo -e "${RED}警告：此操作不可逆！数据将永久丢失！${NC}"
    echo -e "为了确认是您本人操作，请准确输入以下文字："
    echo ""
    if [ "$HAS_GUM" = true ]; then
        gum style --border double --border-foreground 196 --padding "0 1" --foreground 220 "$TARGET_PHRASE"
    else
        echo ">>> $TARGET_PHRASE"
    fi
    echo ""
    
    local input=$(ui_input "在此输入确认语" "" "false")
    
    if [ "$input" == "$TARGET_PHRASE" ]; then
        return 0
    else
        ui_print error "验证失败！文字不匹配，操作已取消。"
        ui_pause
        return 1
    fi
}

uninstall_st() {
    if ! verify_kill_switch; then return; fi
    
    if ui_spinner "正在删除酒馆数据..." "rm -rf '$INSTALL_DIR'"; then
        ui_print success "SillyTavern 已卸载。"
    else
        ui_print error "删除失败，请检查权限。"
    fi
    ui_pause
}

uninstall_clewd() {
    local CLEWD_DIR="$TAVX_DIR/clewdr"
    if ! verify_kill_switch; then return; fi
    
    pkill -f "clewdr"
    
    if ui_spinner "正在清除 ClewdR..." "rm -rf '$CLEWD_DIR'"; then
        ui_print success "ClewdR 模块已卸载。"
    else
        ui_print error "删除失败。"
    fi
    ui_pause
}

uninstall_adb() {
    local ADB_DIR="$TAVX_DIR/adb_tools"
    ui_header "卸载 ADB 组件"
    
    if [ ! -d "$ADB_DIR" ] && ! command -v adb &> /dev/null; then
        ui_print warn "未检测到 ADB 组件。"
        ui_pause; return
    fi

    echo -e "此操作将清理 TAV-X 管理的 ADB 文件及配置。"
    if ! ui_confirm "确认继续吗？"; then return; fi

    if [ -d "$ADB_DIR" ]; then
        ui_spinner "正在删除本地文件..." "rm -rf '$ADB_DIR'"
        sed -i '/adb_tools\/platform-tools/d' "$HOME/.bashrc"
        ui_print success "本地组件及环境变量已清理。"
    fi

    if command -v adb &> /dev/null; then
        echo ""
        echo -e "${YELLOW}检测到系统已安装 android-tools (pkg)。${NC}"
        if ui_confirm "是否连同Google  ADB 一起卸载？"; then
            if ui_spinner "卸载系统包..." "pkg uninstall android-tools -y"; then
                ui_print success "Google ADB 已卸载。"
            else
                ui_print error "卸载失败。"
            fi
        else
            ui_print info "已保留系统 ADB。"
        fi
    fi
    
    ui_pause
}

uninstall_deps() {
    ui_header "卸载环境依赖"
    echo -e "${RED}警告：这将卸载 Node.js, Cloudflared 等组件。${NC}"
    echo -e "如果您的 Termux 中有其他软件依赖它们，可能会导致崩溃。"
    echo ""
    
    if ! verify_kill_switch; then return; fi
    
    local PKGS="nodejs nodejs-lts cloudflared git android-tools"
    
    if ui_spinner "正在卸载系统包..." "pkg uninstall $PKGS -y"; then
        ui_print success "依赖环境已清理。"
        echo "提示: Gum (UI组件) 被保留以维持脚本运行。"
    else
        ui_print error "卸载过程出现错误。"
    fi
    ui_pause
}

full_wipe() {
    ui_header "一键彻底卸载 (Factory Reset)"
    echo -e "${RED}危险等级：⭐⭐⭐⭐⭐${NC}"
    echo -e "此操作将执行以下所有动作："
    echo -e "  1. 删除 SillyTavern 所有数据"
    echo -e "  2. 删除 ClewdR、ADB 等扩展模块"
    echo -e "  3. 删除 TAV-X 脚本及配置"
    echo -e "  4. 清理环境变量 (.bashrc)"
    echo ""
    
    if ! verify_kill_switch; then return; fi
    
    pkill -f "node server.js"
    pkill -f "cloudflared"
    pkill -f "clewdr"
    
    ui_spinner "正在执行清理..." "
        rm -rf '$INSTALL_DIR'
        rm -rf '$TAVX_DIR/clewdr'
        rm -rf '$TAVX_DIR/adb_tools'
        sed -i '/alias st=/d' '$HOME/.bashrc'
        sed -i '/adb_tools\/platform-tools/d' '$HOME/.bashrc'
    "
    
    ui_print success "业务数据已清除。"
    echo ""
    echo -e "${YELLOW}最后一步：自毁程序启动...${NC}"
    echo -e "感谢您的使用，再见！👋"
    sleep 2
    
    rm -rf "$TAVX_DIR"
    
    exit 0
}

# --- 菜单入口 ---
uninstall_menu() {
    while true; do
        ui_header "卸载与重置中心"
        echo -e "${RED}⚠️  请谨慎操作，数据无价！${NC}"
        echo ""
        
        CHOICE=$(ui_menu "请选择操作" \
            "🗑️ 卸载 SillyTavern" \
            "🦀 卸载 ClewdR 模块" \
            "🤖 卸载 ADB 组件" \
            "📦 卸载环境依赖" \
            "💥 一键彻底毁灭(全清)" \
            "🔙 返回上级"
        )
        
        case "$CHOICE" in
            *"SillyTavern"*) uninstall_st ;;
            *"ClewdR"*) uninstall_clewd ;;
            *"ADB"*) uninstall_adb ;;
            *"环境依赖"*) uninstall_deps ;;
            *"彻底毁灭"*) full_wipe ;;
            *"返回"*) return ;;
        esac
    done
}