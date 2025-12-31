#!/bin/bash
# [METADATA]
# MODULE_NAME: 🐍 Python 环境管理
# MODULE_ENTRY: python_mgr_menu
# [END_METADATA]

source "$TAVX_DIR/core/utils.sh"
source "$TAVX_DIR/core/deps.sh"

install_system_python() {
    ui_header "安装系统级 Python"
    
    local install_cmd=""
    
    if [ "$OS_TYPE" == "TERMUX" ]; then
        echo -e "${YELLOW}检测到 Termux 环境:${NC}"
        echo -e "正在准备安装 Python 及编译工具链 (用于构建 uv 等依赖)..."
        install_cmd="pkg install -y python rust binutils clang make"
    else
        echo -e "${YELLOW}检测到 Linux 环境:${NC}"
        echo -e "正在通过 APT 安装 Python3 全家桶..."
        if command -v apt-get &>/dev/null; then
            install_cmd="$SUDO_CMD apt-get update && $SUDO_CMD apt-get install -y python3 python3-pip python3-venv build-essential"
        else
            ui_print error "非 Apt 系统，请手动安装: python3, pip, venv"
            ui_pause; return
        fi
    fi
    
    echo "----------------------------------------"
    if ui_spinner "正在安装..." "$install_cmd"; then
        ui_print success "Python 环境安装完成！"
        
        if command -v pip &>/dev/null || command -v pip3 &>/dev/null; then
            ui_print info "正在优化 PIP 源 (清华源)..."
            pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple >/dev/null 2>&1
        fi
    else
        ui_print error "安装失败，请检查网络或软件源。"
    fi
    ui_pause
}

install_global_uv() {
    ui_header "安装/编译 UV (极速包管理器)"
    
    if [ "$OS_TYPE" == "TERMUX" ]; then
        echo -e "${RED}⚠️  Termux 兼容性提示${NC}"
        echo -e "Astral 官方未提供 Android/Termux 平台的 UV 预编译包。"
        echo -e "且本地编译 UV 极其耗时并极易失败。"
        echo ""
        echo -e "${YELLOW}因此，TAV-X 在 Termux 上仅支持标准 PIP 模式。${NC}"
        echo -e "这足以满足日常使用，且稳定性最高。"
        ui_pause
        return
    fi
    
    if command -v uv &>/dev/null; then
        ui_print success "UV 已安装: $(uv --version)"
        if ! ui_confirm "是否强制重新安装?"; then return; fi
    fi

    echo -e "${YELLOW}UV 安装策略:${NC}"
    echo -e "Linux 系统将尝试使用官方脚本安装预编译二进制。"
    echo -e "这可以避免 'externally-managed-environment' 错误。"
    echo "----------------------------------------"
    
    if ui_confirm "开始安装 UV?"; then
        ui_print info "正在下载官方安装脚本..."
        if command -v curl &>/dev/null; then
            curl -LsSf https://astral.sh/uv/install.sh | sh
            if [ -f "$HOME/.cargo/bin/uv" ]; then
                $SUDO_CMD ln -sf "$HOME/.cargo/bin/uv" /usr/local/bin/uv
            elif [ -f "$HOME/.local/bin/uv" ]; then
                $SUDO_CMD ln -sf "$HOME/.local/bin/uv" /usr/local/bin/uv
            fi
            
            if command -v uv &>/dev/null; then
                ui_print success "UV 安装成功！"
            else
                ui_print warn "安装脚本执行完毕，但 'uv' 命令未生效。"
                echo -e "请尝试重启终端或手动添加 ~/.local/bin 到 PATH。"
            fi
        else
            ui_print error "缺少 curl，无法下载安装脚本。"
        fi
    fi
    ui_pause
}

check_python_status() {
    ui_header "环境诊断"
    
    local py_status="${RED}未安装${NC}"
    if command -v python3 &>/dev/null; then py_status="${GREEN}已安装 ($(python3 --version))${NC}"; fi
    
    local pip_status="${RED}未安装${NC}"
    if command -v pip3 &>/dev/null; then pip_status="${GREEN}已安装${NC}"; fi
    
    local uv_status="${YELLOW}未安装${NC}"
    if command -v uv &>/dev/null; then uv_status="${GREEN}已安装 ($(uv --version | awk '{print $2}'))${NC}"; fi
    
    echo -e "Python3: $py_status"
    echo -e "Pip3:    $pip_status"
    echo -e "UV:      $uv_status"
    
    if [ "$OS_TYPE" == "TERMUX" ]; then
        local rust_status="${RED}未安装${NC}"
        if command -v rustc &>/dev/null; then rust_status="${GREEN}已安装${NC}"; fi
        echo -e "Rust:    $rust_status (Termux编译必需)"
    fi
    
    ui_pause
}

python_mgr_menu() {
    while true; do
        ui_header "🐍 Python 环境管理器"
        echo -e "统一管理 Python 运行时、编译工具链及包管理器。"
        echo "----------------------------------------"
        
        CHOICE=$(ui_menu "请选择操作" \
            "🛠️ 安装/修复 系统 Python" \
            "⚡ 安装/更新 UV" \
            "🔍 环境完整性诊断" \
            "🔙 返回主菜单" \
        )
        
        case "$CHOICE" in
            *"系统"*) install_system_python ;; 
            *"UV"*) install_global_uv ;; 
            *"诊断"*) check_python_status ;; 
            *"返回"*) return ;; 
        esac 
    done 
}
