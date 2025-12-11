#!/bin/bash
# TAV-X Core: About & Support
CONTACT_QQ="317032529"
CONTACT_EMAIL="29006900lz@gmail.com"
PROJECT_URL="https://github.com/Future-404/TAV-X"
SLOGAN="别让虚拟的温柔，偷走了你在现实里本该拥有的温暖。"
UPDATE_SUMMARY="稳定性重铸：彻底修复配置损坏风险，重构网络交互逻辑。"

show_about_page() {
    ui_header "帮助与支持"

    if [ "$HAS_GUM" = true ]; then
        echo ""
        gum style --foreground 212 --bold "  🚀 本次更新预览"
        gum style --foreground 250 --padding "0 2" "• $UPDATE_SUMMARY"
        echo ""
        local label_style="gum style --foreground 99 --width 10"
        local value_style="gum style --foreground 255"

        echo -e "  $($label_style "QQ 群组:")  $($value_style "$CONTACT_QQ")"
        echo -e "  $($label_style "反馈邮箱:")  $($value_style "$CONTACT_EMAIL")"
        echo -e "  $($label_style "项目地址:")  $($value_style "$PROJECT_URL")"
        echo ""
        echo ""
        gum style \
            --border rounded \
            --border-foreground 82 \
            --padding "1 4" \
            --margin "0 2" \
            --align center \
            --foreground 82 \
            --bold \
            "$SLOGAN"

    else
        local C_BRIGHT_GREEN='\033[1;32m'
        
        echo -e "${YELLOW}🚀 本次更新预览:${NC}"
        echo -e "   $UPDATE_SUMMARY"
        echo ""
        echo "----------------------------------------"
        echo -e "💬 QQ 群组:  ${CYAN}$CONTACT_QQ${NC}"
        echo -e "📮 反馈邮箱: ${CYAN}$CONTACT_EMAIL${NC}"
        echo -e "🐙 项目地址: ${BLUE}$PROJECT_URL${NC}"
        echo "----------------------------------------"
        echo ""
        echo -e "   ${C_BRIGHT_GREEN}\"$SLOGAN\"${NC}"
        echo ""
    fi

    echo ""
    if [ "$HAS_GUM" = true ]; then
        ACTION=$(gum choose "🔙 返回主菜单" "🐙 打开 GitHub 项目主页")
    else
        echo "1. 返回主菜单"
        echo "2. 打开 GitHub 项目主页"
        read -p "请选择: " idx
        [ "$idx" == "2" ] && ACTION="打开" || ACTION="返回"
    fi

    if [[ "$ACTION" == *"GitHub"* ]]; then
        termux-open "$PROJECT_URL" 2>/dev/null || start "$PROJECT_URL" 2>/dev/null
        ui_print info "已尝试在浏览器中打开链接。"
        ui_pause
    fi
}