#!/bin/bash
# TAV-X Core: About & Support

AUTHOR_QQ="317032529"
GROUP_QQ="616353694"
CONTACT_EMAIL="29006900lz@gmail.com"
PROJECT_URL="https://github.com/Future-404/TAV-X"
SLOGAN="别让虚拟的温柔，偷走了你在现实里本该拥有的温暖。"
UPDATE_SUMMARY="v2.6.0 LTS 重大更新：
  1. Linux 完美适配: 全面支持 Debian/Ubuntu，自动识别系统环境。
  2. 进程管理重构: 引入 PID 精准控制，彻底解决误杀进程问题，完美兼容 Docker。
  3. 网络系统升级: 新增系统/PIP/NPM 一键换源；优化代理探测 (HTTP优先)。
  4. 依赖安装优化: Linux 下 AutoGLM 极速安装；Clewd 自动切换源码模式。"

show_about_page() {
    ui_header "帮助与支持"

    if [ "$HAS_GUM" = true ]; then
        echo ""
        gum style --foreground 212 --bold "  🚀 本次更新预览"
        gum style --foreground 250 --padding "0 2" "• $UPDATE_SUMMARY"
        echo ""

        local label_style="gum style --foreground 99 --width 10"
        local value_style="gum style --foreground 255"

        echo -e "  $($label_style "作者 QQ:")  $($value_style "$AUTHOR_QQ")"
        echo -e "  $($label_style "反馈 Q群:")  $($value_style "$GROUP_QQ")"
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
        echo -e "👤 作者 QQ:  ${CYAN}$AUTHOR_QQ${NC}"
        echo -e "💬 反馈 Q群: ${CYAN}$GROUP_QQ${NC}"
        echo -e "📮 反馈邮箱: ${CYAN}$CONTACT_EMAIL${NC}"
        echo -e "🐙 项目地址: ${BLUE}$PROJECT_URL${NC}"
        echo "----------------------------------------"
        echo ""
        echo -e "   ${C_BRIGHT_GREEN}\"$SLOGAN\"${NC}"
        echo ""
    fi

    echo ""
    local ACTION=""
    
    if [ "$HAS_GUM" = true ]; then
        ACTION=$(gum choose "🔙 返回主菜单" "🔥 加入 Q 群" "🐙 GitHub 项目主页")
    else
        echo "1. 返回主菜单"
        echo "2. 一键加入 Q 群"
        echo "3. 打开 GitHub 项目主页"
        read -p "请选择: " idx
        case "$idx" in
            "2") ACTION="加入 Q 群" ;;
            "3") ACTION="GitHub" ;;
            *)   ACTION="返回" ;;
        esac
    fi

    case "$ACTION" in
        *"Q 群"*)
            ui_print info "正在尝试唤起 QQ..."
            local qq_scheme="mqqapi://card/show_pslcard?src_type=internal&version=1&uin=${GROUP_QQ}&card_type=group&source=qrcode"
            if command -v termux-open &> /dev/null; then
                termux-open "$qq_scheme"
                if command -v termux-clipboard-set &> /dev/null; then
                    termux-clipboard-set "$GROUP_QQ"
                    ui_print success "群号已复制到剪贴板！"
                fi
            else
                ui_print warn "未检测到 termux-tools，无法自动唤起。"
                echo -e "请手动添加群号: ${CYAN}$GROUP_QQ${NC}"
            fi
            ui_pause
            ;;
            
        *"GitHub"*)
            termux-open "$PROJECT_URL" 2>/dev/null || start "$PROJECT_URL" 2>/dev/null
            ui_print info "已尝试在浏览器中打开链接。"
            ui_pause
            ;;
            
        *) return ;;
    esac
}