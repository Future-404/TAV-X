#!/bin/bash
# TAV-X Core: Installer

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

install_sillytavern() {
    ui_header "SillyTavern 安装向导"

    if [ -d "$INSTALL_DIR" ]; then
        ui_print warn "检测到旧版本目录: $INSTALL_DIR"
        echo -e "${RED}继续安装将清空旧目录！${NC}"
        if ! ui_confirm "确认覆盖安装吗？"; then return; fi
        safe_rm "$INSTALL_DIR"
    fi

    prepare_network_strategy "SillyTavern/SillyTavern"

    local CLONE_CMD="source \"$TAVX_DIR/core/utils.sh\"; git_clone_smart '-b release' 'SillyTavern/SillyTavern' '$INSTALL_DIR'"
    
    if ui_spinner "正在拉取酒馆源码 (Release)..." "$CLONE_CMD"; then
        ui_print success "源码下载完成！"
    else
        ui_print error "源码下载失败，请检查网络连接。"
        ui_pause; return 1
    fi

    echo ""
    ui_print info "准备安装依赖库..."
    
    if npm_install_smart "$INSTALL_DIR"; then
        echo ""
        ui_print success "依赖安装完成！"
        chmod +x "$INSTALL_DIR/start.sh" 2>/dev/null
        
        if ui_confirm "是否应用推荐配置 (自动优化)?"; then
             source "$TAVX_DIR/core/launcher.sh"
             apply_recommended_settings
        fi

        ui_print success "🎉 SillyTavern 安装成功！"
        echo -e "您现在可以使用主菜单的 [🚀 启动服务] 来运行了。"
    else
        echo ""
        ui_print error "依赖安装失败。"
        echo -e "${YELLOW}提示: 您可以稍后在 [安装与更新] -> [版本切换/修复] 中重试。${NC}"
    fi
    ui_pause
}