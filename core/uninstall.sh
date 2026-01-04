#!/bin/bash

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

uninstall_st() {
    if ! verify_kill_switch; then return; fi
    
    if ui_spinner "正在删除酒馆数据..." "safe_rm '$INSTALL_DIR'"; then
        ui_print success "SillyTavern 已卸载。"
    else
        ui_print error "删除失败，请检查权限。"
    fi
    ui_pause
}

full_wipe() {
    ui_header "一键彻底卸载 (Factory Reset)"
    echo -e "${RED}危险等级：⭐⭐⭐⭐⭐${NC}"
    echo -e "此操作将执行以下所有动作："
    echo -e "  1. 删除 SillyTavern 所有数据"
    echo -e "  2. 删除 ClewdR、Gemini、AutoGLM 等扩展模块"
    echo -e "  3. 删除 TAV-X 脚本及配置"
    echo -e "  4. 清理环境变量 (.bashrc)"
    echo ""
    
    if ! verify_kill_switch; then return; fi
    
    kill_process_safe "$ST_PID_FILE" "node.*server.js"
    kill_process_safe "$CF_PID_FILE" "cloudflared"
    kill_process_safe "$CLEWD_PID_FILE" "clewd"
    kill_process_safe "$GEMINI_PID_FILE" "run.py"
    
    ui_spinner "正在执行清理..." "
        source \"$TAVX_DIR/core/utils.sh\"
        safe_rm '$INSTALL_DIR'
        safe_rm '$TAVX_DIR/clewdr'
        safe_rm '$TAVX_DIR/gemini_proxy'
        safe_rm '$TAVX_DIR/autoglm'
        safe_rm '$TAVX_DIR/adb_tools'
        sed -i '/alias st=/d' '$HOME/.bashrc'
        sed -i '/alias ai=/d' '$HOME/.bashrc'
        sed -i '/adb_tools\/platform-tools/d' '$HOME/.bashrc'
    "
    
    ui_print success "业务数据已清除。"
    echo ""
    echo -e "${YELLOW}最后一步：自毁程序启动...${NC}"
    echo -e "感谢您的使用，再见！👋"
    sleep 2
    safe_rm "$TAVX_DIR"
    
    exit 0
}

uninstall_menu() {
    while true; do
        ui_header "卸载与重置中心"
        echo -e "${RED}⚠️  请谨慎操作，数据无价！${NC}"
        echo ""
        
        CHOICE=$(ui_menu "请选择操作" \
            "🗑️ 卸载 SillyTavern" \
            "💥 一键彻底毁灭(全清)" \
            "🔙 返回上级" \
        )
        
        case "$CHOICE" in
            *"SillyTavern"*) uninstall_st ;;
            *"彻底毁灭"*) full_wipe ;;
            *"返回"*) return ;;
        esac
    done
}
