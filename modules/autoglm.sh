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
    # 1. 前置检查：ADB 连接状态
    if ! command -v adb &>/dev/null || ! adb devices | grep -q "device$"; then
        ui_print warn "检测到 ADB 未连接！"
        echo -e "${YELLOW}AutoGLM 必须通过 ADB 才能控制手机。${NC}"
        
        if ui_confirm "是否跳转到 [📱 ADB 连接助手] 进行修复？"; then
            source "$TAVX_DIR/modules/adb_keepalive.sh"
            adb_menu_loop
            # 递归重试
            check_adb_keyboard
            return
        else
            ui_print error "您选择了跳过 ADB 连接。"
            echo -e "${RED}警告：在连接 ADB 之前，AutoGLM 将无法正常工作！${NC}"
            return 0
        fi
    fi

    # 2. 检查输入法是否已安装
    if adb shell ime list -s | grep -q "com.android.adbkeyboard/.AdbIME"; then return 0; fi
    
    ui_print warn "未检测到 ADB Keyboard (AutoGLM 必需组件)"
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

# --- 依赖配置 (智能混合模式) ---
setup_autoglm_venv() {
    ui_header "AutoGLM 环境配置"
    
    if [ ! -d "$AUTOGLM_DIR" ]; then
        ui_print error "请先执行 [⬇️ 安装/更新 核心代码]。"
        ui_pause; return
    fi
    
    # 全局环境检查
    if ! command -v python3 &>/dev/null; then
        ui_print error "系统未检测到 Python3。"
        echo -e "${YELLOW}请前往 [高级工具] -> [🐍 Python 环境管理] 进行安装。${NC}"
        ui_pause; return
    fi
    
    echo -e "${YELLOW}请选择依赖安装策略:${NC}"
    echo -e "1. ${GREEN}标准模式 (Pip)${NC} - 全量下载，兼容性一般"
    
    if [ "$OS_TYPE" == "TERMUX" ]; then
        echo -e "2. ${CYAN}混合模式 (System + Pip)${NC} - ${YELLOW}强烈推荐${NC}"
        echo -e "   (复用 Termux 系统库，免编译 NumPy/Pillow，速度极快)"
    else
        echo -e "2. ${CYAN}极速模式 (UV)${NC} - 推荐 Linux 用户"
    fi
    echo "----------------------------------------"
    
    local choice=$(ui_input "请输入序号 [1/2]" "2" "false")
    local MODE="standard"
    [ "$choice" == "2" ] && MODE="optimized"
    
    # Linux 下 Optimized 模式依然尝试用 UV
    local USE_UV=false
    if [ "$OS_TYPE" != "TERMUX" ] && [ "$MODE" == "optimized" ]; then
        if command -v uv &>/dev/null; then
            USE_UV=true
        else
            ui_print warn "未检测到 UV，将回退到 Pip。"
        fi
    fi

    rm -f "$INSTALL_LOG"; touch "$INSTALL_LOG"
    ui_print info "正在构建虚拟环境..."
    echo -e "${YELLOW}日志: $INSTALL_LOG${NC}"
    
    # --- Termux 混合模式特有逻辑 ---
    local USE_SYSTEM_SITE=false
    local WHEEL_ARGS=""
    local WHEEL_DIR="$AUTOGLM_DIR/wheels"
    
    if [ "$OS_TYPE" == "TERMUX" ] && [ "$MODE" == "optimized" ]; then
        USE_SYSTEM_SITE=true
        echo ">>> [Phase 0] 预装 Termux 系统库 (避免编译)..." >> "$INSTALL_LOG"
        # 预装重型库 + 编译工具链 (应对 jiter/maturin 等 Rust 库的现场编译)
        pkg install -y python-numpy python-pillow python-cryptography libjpeg-turbo libpng libxml2 libxslt clang make rust patchelf >> "$INSTALL_LOG" 2>&1
        
        # --- 恢复离线包加速逻辑 ---
        local WHEEL_URL="https://github.com/Future-404/TAV-X/releases/download/assets-v1/autoglm_wheels.tar.gz"
        echo ">>> [Phase 0.5] 尝试下载预编译加速包..." >> "$INSTALL_LOG"
        
        # 在后台下载，不阻塞主流程太久，如果下载失败则回退在线安装
        if download_file_smart "$WHEEL_URL" "$AUTOGLM_DIR/wheels.tar.gz"; then
            echo ">>> 解压加速包..." >> "$INSTALL_LOG"
            if tar -xzf "$AUTOGLM_DIR/wheels.tar.gz" -C "$AUTOGLM_DIR"; then
                if [ -d "$WHEEL_DIR" ]; then
                    WHEEL_ARGS="--no-index --find-links=$WHEEL_DIR" # 优先用本地包
                    ui_print info "已加载预编译加速包 (Termux专用)"
                fi
            fi
            rm -f "$AUTOGLM_DIR/wheels.tar.gz"
        else
            echo ">>> 加速包下载跳过，使用在线安装。" >> "$INSTALL_LOG"
        fi
    fi

    (
        set -e
        cd "$AUTOGLM_DIR" || exit 1
        
        # 1. 清理
        if [ -d "$VENV_DIR" ]; then rm -rf "$VENV_DIR"; fi
        
        # 2. 创建 venv
        local VENV_ARGS=""
        [ "$USE_SYSTEM_SITE" == "true" ] && VENV_ARGS="--system-site-packages"
        
        echo ">>> [Phase 1] 创建虚拟环境 (Args: $VENV_ARGS)..."
        python3 -m venv "$VENV_DIR" $VENV_ARGS
        source "$VENV_DIR/bin/activate"
        
        # 3. 安装依赖
        if [ "$USE_UV" == "true" ]; then
            # Linux UV 逻辑
            echo ">>> [Phase 2] 使用 UV 安装依赖..."
            uv pip install -U pip
            uv pip install -r requirements.txt
            uv pip install "httpx[socks]"
            
        elif [ "$USE_SYSTEM_SITE" == "true" ]; then
            # Termux 混合逻辑 (System + Pip + Wheels)
            echo ">>> [Phase 2.1] 优化依赖列表..."
            
            # 关键: 限制 Rust 编译并发数 (防止 jiter/maturin 编译崩溃)
            export CARGO_BUILD_JOBS=1
            
            cp requirements.txt requirements.tmp
            sed -i '/numpy/d' requirements.tmp
            sed -i '/Pillow/d' requirements.tmp
            sed -i '/cryptography/d' requirements.tmp
            
            echo ">>> [Phase 2.2] 使用 Pip 安装剩余依赖 (混合模式)..."
            pip install --upgrade pip
            
            # 尝试先用离线包安装 (如果有)
            if [ -n "$WHEEL_ARGS" ]; then
                echo ">>> [Accelerated] 正在载入本地预编译包..."
                # 修改策略：直接指定 find-links，让 pip 自己决定是用本地还是在线
                WHEEL_ARGS="--find-links=$WHEEL_DIR" 
            fi
            
            # 关键：先单独安装构建工具 maturin (因为 jiter 依赖它)
            echo ">>> [Phase 2.1.5] 预编译构建工具 (Maturin)..."
            pip install $WHEEL_ARGS maturin
            
            pip install $WHEEL_ARGS -r requirements.tmp
            pip install $WHEEL_ARGS "httpx[socks]"
            
            rm -f requirements.tmp
            rm -rf "$WHEEL_DIR"
            
        else
            # 标准 Pip 逻辑
            echo ">>> [Phase 2] 使用 Pip 全量安装 (较慢)..."
            pip install --upgrade pip
            pip install -r requirements.txt
        fi
    ) >> "$INSTALL_LOG" 2>&1
    
    if [ $? -eq 0 ]; then
        ui_print success "环境配置成功！"
        echo -e "输入 ${CYAN}ai${NC} 启动。"
    else
        ui_print error "安装失败。"
        echo -e "${YELLOW}--- 错误日志 ---${NC}"
        tail -n 10 "$INSTALL_LOG"
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
            pkg install -y -o Dpkg::Options::="--force-confold" $SYS_PKGS
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
    if git_clone_smart "" "https://github.com/zai-org/Open-AutoGLM" "$AUTOGLM_DIR"; then
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