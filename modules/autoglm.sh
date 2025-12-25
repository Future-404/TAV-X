#!/bin/bash
# [METADATA]
# MODULE_NAME: 🤖 AutoGLM 智能体
# MODULE_ENTRY: autoglm_menu
# [END_METADATA]

source "$TAVX_DIR/core/utils.sh"

# --- 变量定义 ---
AUTOGLM_DIR="$TAVX_DIR/autoglm"
VENV_DIR="$AUTOGLM_DIR/venv"
CONFIG_FILE="$TAVX_DIR/config/autoglm.env"
INSTALL_LOG="$TAVX_DIR/autoglm_install.log"
LAUNCHER_SCRIPT="$TAVX_DIR/core/ai_launcher.sh"
ADB_KEYBOARD_URL="https://github.com/senzhk/ADBKeyBoard/raw/master/ADBKeyboard.apk"

# --- 辅助函数 ---
check_adb_keyboard() {
    if adb shell ime list -s | grep -q "com.android.adbkeyboard/.AdbIME"; then return 0; fi
    ui_print warn "未检测到 ADB Keyboard"
    if ui_confirm "自动下载并安装 ADB Keyboard?"; then
        local apk_path="$TAVX_DIR/temp_adbkeyboard.apk"
        prepare_network_strategy "$ADB_KEYBOARD_URL"
        if download_file_smart "$ADB_KEYBOARD_URL" "$apk_path"; then
            if adb install -r "$apk_path"; then
                rm "$apk_path"
                ui_print success "安装成功！"
                adb shell ime enable com.android.adbkeyboard/.AdbIME >/dev/null 2>&1
                adb shell ime set com.android.adbkeyboard/.AdbIME >/dev/null 2>&1
                return 0
            fi
        fi
        ui_print error "安装失败"
    fi
    return 1
}

create_ai_launcher() {
cat << EOF > "$LAUNCHER_SCRIPT"
#!/bin/bash
export TAVX_DIR="$TAVX_DIR"
EOF

cat << 'EOF' >> "$LAUNCHER_SCRIPT"

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

CONFIG_FILE="$TAVX_DIR/config/autoglm.env"
AUTOGLM_DIR="$TAVX_DIR/autoglm"
VENV_DIR="$AUTOGLM_DIR/venv"

send_feedback() {
    local status="$1"; local msg="$2"
    local clean_msg=$(echo "$msg" | tr '()' '[]' | tr '"' ' ' | tr "'" " ")
    local enable_feedback="${PHONE_AGENT_FEEDBACK:-true}"
    
    [ "$status" == "success" ] && ui_print success "$msg" || ui_print error "$msg"
    [ "$enable_feedback" != "true" ] && return 0

    if [ "$status" == "success" ]; then
        command -v termux-toast &>/dev/null && termux-toast -g bottom "✅ 任务完成"
        adb shell cmd notification post -S bigtext -t "AutoGLM 完成" "AutoGLM" "$clean_msg" >/dev/null 2>&1
        command -v termux-vibrate &>/dev/null && { termux-vibrate -d 80; sleep 0.15; termux-vibrate -d 80; }
    else
        command -v termux-toast &>/dev/null && termux-toast -g bottom "❌ 任务中断"
        adb shell cmd notification post -S bigtext -t "AutoGLM 失败" "AutoGLM" "$clean_msg" >/dev/null 2>&1
        command -v termux-vibrate &>/dev/null && termux-vibrate -d 400
    fi
}

check_dependencies() {
    if ! adb devices | grep -q "device$"; then
        ui_print error "ADB 未连接，跳转修复..."
        sleep 1
        source "$TAVX_DIR/modules/adb_keepalive.sh"
        adb_menu_loop
        if ! adb devices | grep -q "device$"; then ui_print error "连接失败"; exit 1; fi
    fi
}

main() {
    if [ ! -d "$AUTOGLM_DIR" ]; then ui_print error "未安装"; exit 1; fi
    check_dependencies
    [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"
    source "$VENV_DIR/bin/activate"

    local enable_feedback="${PHONE_AGENT_FEEDBACK:-true}"
    if [ "$enable_feedback" == "true" ] && command -v termux-toast &> /dev/null; then
        termux-toast -g bottom "🚀 AutoGLM 已启动..."
    fi

    echo ""; ui_print success "🚀 智能体已就绪！"
    echo -e "${CYAN}>>> 3秒倒计时...${NC}"; sleep 3
    cd "$AUTOGLM_DIR" || exit
    
    if [ $# -eq 0 ]; then python main.py; else python main.py "$*"; fi
    
    EXIT_CODE=$?
    echo ""
    [ $EXIT_CODE -eq 0 ] && send_feedback "success" "任务执行结束。" || send_feedback "error" "程序异常退出 [Code $EXIT_CODE]。"
}
main "$@"
EOF
    chmod +x "$LAUNCHER_SCRIPT"
    local ALIAS_CMD="alias ai='bash $LAUNCHER_SCRIPT'"
    if ! grep -Fq "alias ai=" "$HOME/.bashrc"; then
        echo "" >> "$HOME/.bashrc"; echo "$ALIAS_CMD" >> "$HOME/.bashrc"
    fi
}

# --- 依赖配置 (仅负责 pip install) ---
setup_autoglm_venv() {
    ui_header "AutoGLM 环境配置"
    
    if [ ! -d "$AUTOGLM_DIR" ]; then
        ui_print error "请先执行 [⬇️ 安装/更新 AutoGLM] 下载源码。"
        ui_pause; return
    fi
    
    # 1. 检查全局 Python 环境
    if ! command -v python3 &>/dev/null; then
        ui_print error "系统未检测到 Python3。"
        echo -e "${YELLOW}请前往 [高级工具] -> [🐍 Python 环境管理] 进行安装。${NC}"
        echo -e "完成安装后，请再次回到此处继续。"
        ui_pause; return
    fi
    
    # Termux 特别检查：如果没有 rustc，uv 可能会挂
    if [ "$OS_TYPE" == "TERMUX" ] && ! command -v rustc &>/dev/null; then
        ui_print warn "检测到 Rust 编译环境缺失。"
        echo -e "${YELLOW}建议前往 [高级工具] -> [🐍 Python 环境管理] 补全编译工具。${NC}"
        if ! ui_confirm "仍要尝试强制安装依赖吗 (可能失败)?"; then return; fi
    fi

    echo -e "${YELLOW}请选择依赖安装策略:${NC}"
    echo -e "1. ${GREEN}标准模式 (Pip)${NC} - 稳定，无需编译工具 (慢)"
    echo -e "2. ${CYAN}极速模式 (UV)${NC} - 极快，但 Termux 需提前配置好编译环境"
    echo "----------------------------------------"
    
    local choice=$(ui_input "请输入序号 [1/2]" "1" "false")
    local USE_UV=false
    
    if [ "$choice" == "2" ]; then
        if command -v uv &>/dev/null; then
            USE_UV=true
        else
            ui_print error "未检测到 UV。"
            echo -e "请先去 [🐍 Python 环境管理] 中安装 UV。"
            if ! ui_confirm "回退到 pip 模式继续?"; then return; fi
        fi
    fi

    rm -f "$INSTALL_LOG"; touch "$INSTALL_LOG"
    ui_print info "正在构建虚拟环境..."
    echo -e "${YELLOW}日志已记录至: $INSTALL_LOG${NC}"
    
    (
        set -e
        cd "$AUTOGLM_DIR" || exit 1
        
        # 清理旧环境
        if [ -d "$VENV_DIR" ]; then rm -rf "$VENV_DIR"; fi
        
        # 创建 venv (使用系统自带的 python3-venv)
        python3 -m venv "$VENV_DIR"
        source "$VENV_DIR/bin/activate"
        
        # 安装依赖
        if [ "$USE_UV" == "true" ]; then
            echo ">>> [Mode: UV] 安装依赖..."
            uv pip install -U pip
            uv pip install -r requirements.txt
        else
            echo ">>> [Mode: Pip] 安装依赖 (请耐心等待)..."
            pip install --upgrade pip
            pip install -r requirements.txt
        fi
    ) >> "$INSTALL_LOG" 2>&1
    
    if [ $? -eq 0 ]; then
        ui_print success "环境配置成功！"
        echo -e "现在可以启动智能体了。"
    else
        ui_print error "环境配置失败。"
        echo -e "${YELLOW}--- 错误日志 (最后20行) ---${NC}"
        tail -n 20 "$INSTALL_LOG"
    fi
    ui_pause
}

# --- 核心流程 (只装代码) ---
install_autoglm() {
    ui_header "部署 Open-AutoGLM (Core)"
    rm -f "$INSTALL_LOG"; touch "$INSTALL_LOG"
    
    ui_print info "正在下载核心组件..."
    
    (
        set -e
        echo ">>> [Phase 1] 安装系统基础库..."
        if [ "$OS_TYPE" == "TERMUX" ]; then
            # Termux: 仅安装运行时必须的库 (移除所有编译链)
            local SYS_PKGS="termux-api libjpeg-turbo libpng libxml2 libxslt"
            pkg install root-repo science-repo -y
            pkg install -y -o Dpkg::Options::=\"--force-confold\" $SYS_PKGS
        else
            # Linux: 仅运行库
            local SYS_PKGS="libjpeg-dev zlib1g-dev libxml2-dev libxslt1-dev"
            if command -v apt-get &>/dev/null; then
                $SUDO_CMD apt-get update -y
                $SUDO_CMD apt-get install -y $SYS_PKGS
            fi
        fi
    ) >> "$INSTALL_LOG" 2>&1

    # 下载源码
    if [ -d "$AUTOGLM_DIR" ]; then rm -rf "$AUTOGLM_DIR"; fi
    if git_clone_smart "" "https://github.com/THUDM/Open-AutoGLM" "$AUTOGLM_DIR"; then
        check_adb_keyboard
        create_ai_launcher
        ui_print success "核心文件已就绪！"
        echo "----------------------------------------"
        echo -e "${YELLOW}下一步：${NC}"
        echo -e "请选择 [📦 安装/更新 依赖] 来配置 Python 环境。"
    else
        ui_print error "源码下载失败，请检查网络。"
    fi
    ui_pause
}

configure_autoglm() {
    ui_header "AutoGLM 配置"
    local current_key=""
    local current_base=""
    local current_model="autoglm-phone"
    local current_feedback="true"
    if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"
        current_key="$PHONE_AGENT_API_KEY"; current_base="$PHONE_AGENT_BASE_URL"; [ -n "$PHONE_AGENT_MODEL" ] && current_model="$PHONE_AGENT_MODEL"; [ -n "$PHONE_AGENT_FEEDBACK" ] && current_feedback="$PHONE_AGENT_FEEDBACK"; fi
    
    echo -e "${CYAN}配置信息:${NC}"
    local new_key=$(ui_input "API Key" "$current_key" "true")
    local new_base=$(ui_input "Base URL" "${current_base:-https://open.bigmodel.cn/api/paas/v4}" "false")
    local new_model=$(ui_input "Model Name" "${current_model:-glm-4v-flash}" "false")
    echo -e "${YELLOW}是否启用反馈 (通知/震动/气泡)?${NC}"
    local new_feedback=$(ui_input "启用反馈 (true/false)" "$current_feedback" "false")
    
    echo "export PHONE_AGENT_API_KEY='$new_key'" > "$CONFIG_FILE"
    echo "export PHONE_AGENT_BASE_URL='$new_base'" >> "$CONFIG_FILE"
    echo "export PHONE_AGENT_MODEL='$new_model'" >> "$CONFIG_FILE"
    echo "export PHONE_AGENT_LANG='cn'" >> "$CONFIG_FILE"
    echo "export PHONE_AGENT_FEEDBACK='$new_feedback'" >> "$CONFIG_FILE"
    
    create_ai_launcher
    ui_print success "已保存"; ui_pause
}

start_autoglm() {
    if [ ! -f "$LAUNCHER_SCRIPT" ]; then create_ai_launcher; fi
    bash "$LAUNCHER_SCRIPT"
    ui_pause
}

autoglm_menu() {
    while true; do
        ui_header "AutoGLM 智能体"
        
        local status="${RED}未安装${NC}"
        if [ -d "$AUTOGLM_DIR" ]; then
            if [ -f "$VENV_DIR/bin/activate" ]; then
                status="${GREEN}已就绪${NC}"
            else
                status="${YELLOW}缺少环境${NC}"
            fi
        fi
        
        echo -e "状态: $status"
        echo "----------------------------------------"
        
        CHOICE=$(ui_menu "请选择操作" \
            "🚀 启动智能体 (Start)" \
            "⬇️ 安装/更新 核心代码" \
            "📦 安装/更新 依赖 (pip/uv)" \
            "⚙️ 编辑配置文件" \
            "🔙 返回上级" \
        )
        
        case "$CHOICE" in
            *"启动"*) 
                if [ -f "$LAUNCHER_SCRIPT" ]; then bash "$LAUNCHER_SCRIPT"; else ui_print error "请先安装！"; ui_pause; fi ;;
            *"核心代码"*) install_autoglm ;; 
            *"依赖"*) setup_autoglm_venv ;; 
            *"配置"*) configure_autoglm ;; 
            *"返回"*) return ;; 
        esac
    done
}