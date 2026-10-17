#!/bin/bash
# [METADATA]
# MODULE_ID: gemini
# MODULE_NAME: Gemini CLI官方版
# MODULE_ENTRY: gemini_menu
# APP_CATEGORY: 命令行工具
# APP_AUTHOR: Google
# APP_PROJECT_URL: https://github.com/google-gemini/gemini-cli
# APP_DESC: Google 官方提供的Gemini命令行工具，支持在终端直接调用Gemini系列模型。TAV-X为其提供了自动化安装及智能网络加速支持。
# [END_METADATA]

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

_go_check_env() {
    if ! command -v node &>/dev/null; then
        ui_print info "未找到 Node.js，正在尝试安装..."
        if [ "$OS_TYPE" == "TERMUX" ]; then
            pkg install nodejs -y
        else
            ui_print error "请手动安装 Node.js 后再试。"
            return 1
        fi
    fi
    if ! command -v pnpm &>/dev/null; then
        ui_print info "正在安装 pnpm..."
        npm install -g pnpm || return 1
        
        ui_print info "初始化 pnpm 环境..."
        pnpm setup >/dev/null 2>&1
        # shellcheck disable=SC1091
        [ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc"
        
        export PNPM_HOME="$HOME/.local/share/pnpm"
        case ":$PATH:" in
            *":$PNPM_HOME:"*) ;; 
            *) export PATH="$PNPM_HOME:$PATH" ;; 
        esac
    fi
    return 0
}

gemini_install() {
    ui_header "部署 Gemini CLI 官方版"
    
    if ! ui_confirm "确定要安装/更新 Gemini CLI 吗？"; then return; fi
    
    _go_check_env || return 1

    ui_print info "正在应用智能网络策略..."
    prepare_network_strategy "NPM"

    ui_print info "正在通过 pnpm 全局安装 @google/gemini-cli..."
    if pnpm add -g @google/gemini-cli; then
        local app_path
        app_path=$(get_app_path "gemini")
        mkdir -p "$app_path"
        touch "$app_path/.installed"

        ui_print success "安装完成！"
        ui_print info "提示：您可以直接输入 'gemini' 启动官方原版。"
        ui_print info "      或者输入 'st gemini' 启动带智能网络的增强版。"
        ui_print info "注意：若终端未识别 'gemini' 命令，请执行 'source ~/.bashrc' 或重启终端。"
    else
        ui_print error "安装失败，请检查网络。"
    fi
    ui_pause
}

gemini_start() {
    if ! command -v gemini &>/dev/null; then
        ui_print error "未检测到 gemini 命令，请先安装。"
        ui_pause
        return
    fi
    
    ui_header "启动 Gemini CLI 指南"
    echo -e "${CYAN}Gemini CLI 官方版已安装。您可以按以下方式启动：${NC}\n"
    
    echo -e "${YELLOW}1. 官方原版 (直连)${NC}"
    echo -e "   直接在任何终端输入: ${GREEN}gemini${NC}"
    echo -e "   ${GRAY}(注意：国内网络环境可能无法直接连接)${NC}\n"
    
    echo -e "${YELLOW}2. TAV-X 加速版 (推荐)${NC}"
    echo -e "   在任何终端输入: ${GREEN}st gemini${NC}"
    echo -e "   ${GRAY}(会自动应用智能网络策略，确保连通性)${NC}\n"
    
    echo -e "------------------------------------------------"
    echo -e "${PINK}提示：首次运行时，程序会引导您进行认证 (支持 Google 登录或 API Key)。${NC}"
    echo -e "------------------------------------------------"
    
    ui_pause
}

gemini_uninstall() {
    if verify_kill_switch; then
        ui_print info "正在卸载 @google/gemini-cli..."
        pnpm remove -g @google/gemini-cli

        local app_path
        app_path=$(get_app_path "gemini")
        safe_rm "$app_path"

        ui_print success "已卸载。"
        return 2
    fi
}

gemini_menu() {
    if [[ "${FUNCNAME[1]}" == "app_drawer_menu" || "${FUNCNAME[1]}" == "while" ]]; then
        while true; do
            ui_header "Gemini CLI 官方版"
            local status="未安装"
            command -v gemini &>/dev/null && status="已就绪"
            ui_status_card "info" "状态: $status" "包名: @google/gemini-cli" "运行指令: gemini"
            
            local CHOICE
            CHOICE=$(ui_menu "功能菜单" "🚀 安装/更新" "💬 启动指南" "🗑️  卸载模块" "🧭 关于模块" "🔙 返回")
            case "$CHOICE" in
                *"安装"*) gemini_install ;; 
                *"启动"*) gemini_start ;; 
                *"卸载"*) gemini_uninstall && [ $? -eq 2 ] && return ;; 
                *"关于"*) show_module_about_info "${BASH_SOURCE[0]}" ;; 
                *"返回"*) return ;; 
            esac
        done
    else
        if ! command -v gemini &>/dev/null; then
            ui_print error "未检测到 gemini 命令，请先运行 'st' 进入菜单安装。"
            return 1
        fi
        ui_print info "正在应用智能网络策略并启动 Gemini..."
        prepare_network_strategy
        curl -s -I -m 2 https://generativelanguage.googleapis.com >/dev/null 2>&1
        exec gemini "$@"
    fi
}
