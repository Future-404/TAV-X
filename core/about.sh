#!/bin/bash
# TAV-X Core: About & Support

AUTHOR_QQ="317032529"
GROUP_QQ="616353694"
CONTACT_EMAIL="future_404@outlook.com"
PROJECT_URL="https://github.com/Future-404/TAV-X"
SLOGAN="别让虚拟的温柔，偷走了你在现实里本该拥有的温暖。"
UPDATE_SUMMARY="v3.4.2 (Beta Feature Update)
  1. [新增] Gemini Business 2 OpenAI 接口网关模块 (Testing Phase)
  2. [新增] 模块内置智能账号导入逻辑，支持三段式手动导入
  3. [优化] 核心服务启动逻辑，解决 nohup 模式下 PID 获取异常
  4. [优化] 依赖管理机制，提供针对轻量级模块的精简版依赖安装"

show_shortcuts_help() {
    ui_header "快捷指令用法"
    echo -e "${YELLOW}无需进入主菜单，直接在终端输入即可快速操作：${NC}"
    echo ""
    printf "  ${CYAN}%-15s${NC} %s\n" "st" "进入交互式管理面板"
    printf "  ${CYAN}%-15s${NC} %s\n" "st ps" "查看当前运行中的服务"
    printf "  ${CYAN}%-15s${NC} %s\n" "st re" "重启所有运行中的服务"
    printf "  ${CYAN}%-15s${NC} %s\n" "st stop" "一键停止所有服务"
    printf "  ${CYAN}%-15s${NC} %s\n" "st hb" "快捷开关音频保活 (audio_keeper)"
    printf "  ${CYAN}%-15s${NC} %s\n" "st update" "强制进入脚本更新模式"
    printf "  ${CYAN}%-15s${NC} %s\n" "st log" "查看可用日志的应用 ID"
    printf "  ${CYAN}%-15s${NC} %s\n" "st log [ID]" "实时监控指定应用日志"
    echo ""
    echo -e "${BLUE}💡 提示:${NC} 日志监控界面按 ${YELLOW}q${NC} 键即可退出。"
    ui_pause
}

show_about_page() {
    ui_header "帮助与支持"

    if [ "$HAS_GUM" = true ]; then
        echo ""
        "$GUM_BIN" style --foreground 212 --bold "  🚀 本次更新预览"
        "$GUM_BIN" style --foreground 250 --padding "0 2" "• $UPDATE_SUMMARY"
        echo ""

        local label_style="$GUM_BIN style --foreground 99 --width 10"
        local value_style="$GUM_BIN style --foreground 255"

        echo -e "  $($label_style "作者 QQ:")  $($value_style "$AUTHOR_QQ")"
        echo -e "  $($label_style "反馈 Q群:")  $($value_style "$GROUP_QQ")"
        echo -e "  $($label_style "反馈邮箱:")  $($value_style "$CONTACT_EMAIL")"
        echo -e "  $($label_style "项目地址:")  $($value_style "$PROJECT_URL")"
        echo ""
        echo ""

        "$GUM_BIN" style \
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
        ACTION=$("$GUM_BIN" choose "🔙 返回主菜单" "⌨️ 快捷指令用法" "🛡️ Project Aegis (Alpha)" "🔥 加入 Q 群" "🐙 GitHub 项目主页")
    else
        echo "1. 返回主菜单"
        echo "2. ⌨️  快捷指令用法"
        echo "3. 🛡️  Project Aegis (Alpha)"
        echo "4. 一键加入 Q 群"
        echo "5. 打开 GitHub 项目主页"
        read -r -p "请选择: " idx
        case "$idx" in
            "2") ACTION="快捷指令" ;;
            "3") ACTION="Project Aegis" ;;
            "4") ACTION="加入 Q 群" ;;
            "5") ACTION="GitHub" ;;
            *)   ACTION="返回" ;;
        esac
    fi

    case "$ACTION" in
        *"Project Aegis"*)
            open_browser "https://aegis.future404.space/"
            show_about_page
            ;;
        *"快捷指令"*)
            show_shortcuts_help
            show_about_page
            ;;
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
