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
REPO_URL="Future-404/Open-AutoGLM"
ADB_KEYBOARD_URL="https://github.com/senzhk/ADBKeyBoard/raw/master/ADBKeyboard.apk"
TERMUX_API_PKG="com.termux.api"

# --- 辅助函数 ---
check_uv_installed() {
    if command -v uv &> /dev/null; then return 0; fi
    
    ui_print info "正在尝试快速安装 uv..."
    if pip install uv >/dev/null 2>&1; then
        ui_print success "uv 安装成功 (Fast)"
        return 0
    fi

    ui_print info "快速安装失败，准备从源码编译安装..."
    echo "----------------------------------------"
    echo ">>> [Setup] 正在补全编译环境..."
    
    # 1. 只有在 pip 直接安装失败时才补全编译环境
    if [ "$OS_TYPE" == "TERMUX" ]; then
        pkg install rust binutils -y
    else
        if command -v apt-get &>/dev/null; then
            $SUDO_CMD apt-get install -y rustc cargo binutils
        fi
    fi
    
    # 2. 确保 pip 支持代理
    pip install pysocks >/dev/null 2>&1
    
    # 3. 编译安装 uv
    echo ">>> [Build] 正在编译安装 uv (耗时较长，请耐心等待)..."
    export CARGO_BUILD_JOBS=1
    if pip install uv; then
        ui_print success "uv 安装成功 (Native)"
        return 0
    else
        ui_print warn "uv 编译失败 (可能是 Rust 环境问题)。"
        ui_print info "系统将自动降级使用标准 pip 进行安装。"
        return 2
    fi
}

# ... (check_adb_keyboard 和 create_ai_launcher 保持不变) ...

# --- 核心流程 ---
install_autoglm() {
    ui_header "部署 Open-AutoGLM"
    rm -f "$INSTALL_LOG"; touch "$INSTALL_LOG"
    
    ui_print info "启动全自动安装..."
    echo -e "${YELLOW}请关注下方日志。${NC}"
    echo "----------------------------------------"

    (
        set -e
        echo ">>> [Phase 1] 安装系统基础库..."
        
        if [ "$OS_TYPE" == "TERMUX" ]; then
            # Termux: 恢复全量编译环境，确保能构建所有 Python 扩展
            local SYS_PKGS="termux-api python-numpy python-pillow python-cryptography libjpeg-turbo libpng libxml2 libxslt clang make rust binutils"
            pkg install root-repo science-repo -y
            pkg install -y -o Dpkg::Options::="--force-confold" $SYS_PKGS
        else
            # Linux: 基础运行环境 (尝试利用 PyPI 的预编译 Wheel)
            local SYS_PKGS="python3-dev python3-pip python3-venv libjpeg-dev zlib1g-dev libxml2-dev libxslt1-dev"
            if command -v apt-get &>/dev/null; then
                $SUDO_CMD apt-get update -y
                $SUDO_CMD apt-get install -y $SYS_PKGS
            else
                ui_print warn "非 Apt 系统，请手动安装运行依赖 (Python-Dev, libjpeg等)"
            fi
        fi
    ) >> "$INSTALL_LOG" 2>&1
    
    local USE_UV=true
    check_uv_installed
    local uv_status=$?
    if [ $uv_status -eq 2 ]; then USE_UV=false; elif [ $uv_status -ne 0 ]; then return 1; fi
    
    (
        set -e
        if [ -d "$AUTOGLM_DIR" ]; then
            echo ">>> [Cleanup] 清理旧版本..."
            rm -rf "$AUTOGLM_DIR"
        fi
        
        echo ">>> [Phase 2] 下载源码..."
        git_clone_smart "" "https://github.com/THUDM/Open-AutoGLM" "$AUTOGLM_DIR"

        echo ">>> [Phase 3] 创建虚拟环境..."
        if [ "$USE_UV" = true ]; then
            uv venv "$VENV_DIR" --seed
            source "$VENV_DIR/bin/activate"
            echo ">>> [Phase 4] 安装依赖 (使用 uv 加速)..."
            uv pip install -U pip
            uv pip install -r "$AUTOGLM_DIR/requirements.txt"
        else
            python3 -m venv "$VENV_DIR"
            source "$VENV_DIR/bin/activate"
            echo ">>> [Phase 4] 安装依赖 (标准 pip 模式)..."
            pip install --upgrade pip
            pip install -r "$AUTOGLM_DIR/requirements.txt"
        fi
    ) >> "$INSTALL_LOG" 2>&1

    if [ $? -eq 0 ]; then
        check_adb_keyboard
        create_ai_launcher
        ui_print success "安装完成！"
        echo -e "输入 ${CYAN}ai${NC} 或在菜单中选择启动。"
    else
        ui_print error "安装失败，请查看日志。"
        echo -e "${YELLOW}--- 错误日志 (最后20行) ---${NC}"
        tail -n 20 "$INSTALL_LOG"
    fi
    ui_pause
}

    (
        set -e
        echo ">>> [Phase 3] 下载核心代码..."
        if [ -d "$AUTOGLM_DIR" ]; then rm -rf "$AUTOGLM_DIR"; fi
        
        auto_load_proxy_env
        git clone --depth 1 "https://github.com/$REPO_URL" "$AUTOGLM_DIR"
        cd "$AUTOGLM_DIR" || exit 1
        
        echo ">>> [Phase 4] 创建虚拟环境..."
        python -m venv "$VENV_DIR" --system-site-packages
        source "$VENV_DIR/bin/activate"
        
        echo ">>> [Phase 5] 安装依赖..."
        
        local WHEEL_URL="https://github.com/Future-404/TAV-X/releases/download/assets-v1/autoglm_wheels.tar.gz"
        local USE_OFFLINE=false
        
        if download_file_smart "$WHEEL_URL" "wheels.tar.gz"; then
            if tar -xzf wheels.tar.gz; then USE_OFFLINE=true; fi
            rm -f wheels.tar.gz
        fi
        
        cp requirements.txt requirements.tmp
        sed -i '/numpy/d' requirements.tmp
        sed -i '/Pillow/d' requirements.tmp
        sed -i '/cryptography/d' requirements.tmp
        
        export CARGO_BUILD_JOBS=1
        
        if [ "$USE_OFFLINE" == "true" ] && [ -d "wheels" ]; then
            echo ">>> [Mode] 🚀 混合极速安装 (UV Native)..."
            # 这里的 uv 是本地版，它编译出来的 wheel 必定兼容 Android
            uv pip install --find-links=./wheels -r requirements.tmp
            uv pip install --find-links=./wheels "httpx[socks]"
            uv pip install --find-links=./wheels -e .
            rm -rf wheels
        else
            echo ">>> [Mode] 🐢 在线编译安装 (UV Native)..."
            if ! uv pip install -r requirements.tmp; then
                 uv pip install -r requirements.tmp -i https://pypi.tuna.tsinghua.edu.cn/simple
            fi
            uv pip install "httpx[socks]"
            uv pip install -e .
        fi
        rm requirements.tmp
        
        echo ">>> ✅ 全部安装步骤完成！"
    ) >> "$INSTALL_LOG" 2>&1 &
    
    safe_log_monitor "$INSTALL_LOG"
    
    if adb devices | grep -q "device$"; then check_adb_keyboard; fi
    if ! adb shell pm list packages | grep -q "com.termux.api"; then
        ui_print warn "推荐安装 Termux:API 应用"
    fi
    
    create_ai_launcher
    ui_print success "部署完成！输入 'ai' 启动。"
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
        [ -d "$AUTOGLM_DIR" ] && status="${GREEN}已安装${NC}"
        echo -e "状态: $status"
        echo -e "提示: 安装后可使用全局命令 ${CYAN}ai${NC} 快速启动"
        echo "----------------------------------------"
        CHOICE=$(ui_menu "操作" "🚀 启动" "⚙️  配置/设置" "📥 安装/重装" "🔙 返回")
        case "$CHOICE" in
            *"启动"*) start_autoglm ;;
            *"配置"*) configure_autoglm ;;
            *"安装"*) install_autoglm ;;
            *"返回"*) return ;;
        esac
    done
}