#!/bin/bash
# [METADATA]
# MODULE_NAME: 🤖 AutoGLM 智能体
# MODULE_ENTRY: autoglm_menu
# [END_METADATA]

source "$TAVX_DIR/core/utils.sh"
source "$TAVX_DIR/modules/python_mgr.sh"

AUTOGLM_DIR="$TAVX_DIR/autoglm"
VENV_DIR="$AUTOGLM_DIR/venv"
CONFIG_FILE="$TAVX_DIR/config/autoglm.env"
INSTALL_LOG="$TAVX_DIR/autoglm_install.log"
LAUNCHER_SCRIPT="$TAVX_DIR/core/ai_launcher.sh"
ADB_KEYBOARD_URL="https://github.com/senzhk/ADBKeyBoard/raw/master/ADBKeyboard.apk"

monitor_process() {
    local pid=$1
    local log_file=$2
    local spin='-\|/'
    local i=0
    
    echo -e "${YELLOW}⚠️  正在安装依赖，请勿关闭终端或切换到后台！${NC}"
    echo -e "${YELLOW}☕  此过程可能需要 5-10 分钟，请耐心等待...${NC}"
    echo ""
    
    tput civis
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) %4 ))
        local last_line=$(tail -n 1 "$log_file" | cut -c 1-80)
        echo -ne "\r\033[K[${spin:$i:1}] 正在处理: ${last_line}"
        sleep 0.5
    done
    tput cnorm
    echo -e "\r\033[K"
}

check_adb_keyboard() {
    if ! command -v adb &>/dev/null || ! adb devices | grep -q "device$"; then
        ui_print warn "检测到 ADB 未连接！"
        echo -e "${YELLOW}AutoGLM 必须通过 ADB 才能控制手机。${NC}"
        if ui_confirm "是否跳转到 [📱 ADB 连接助手] 进行修复？"; then
            source "$TAVX_DIR/modules/adb_keepalive.sh"
            adb_menu_loop
            check_adb_keyboard; return
        else
            ui_print error "您选择了跳过 ADB 连接。${NC}"; return 0
        fi
    fi
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
        source "$TAVX_DIR/modules/adb_keepalive.sh"; adb_menu_loop
        if ! adb devices | grep -q "device$"; then ui_print error "连接失败"; exit 1; fi
    fi
}

main() {
    if [ ! -d "$AUTOGLM_DIR" ]; then ui_print error "未安装"; exit 1; fi
    check_dependencies
    [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"
    source "$VENV_DIR/bin/activate"
    echo ""; ui_print success "🚀 智能体已就绪！"
    echo -e "${CYAN}>>> 3秒倒计时...${NC}"; sleep 3
    cd "$AUTOGLM_DIR" || exit
    if [ $# -eq 0 ]; then python main.py; else python main.py "$*"; fi
    EXIT_CODE=$?
    echo ""; [ $EXIT_CODE -eq 0 ] && send_feedback "success" "任务执行结束。" || send_feedback "error" "程序异常退出 [Code $EXIT_CODE]。"
}
main "$@"
EOF
    chmod +x "$LAUNCHER_SCRIPT"
    local ALIAS_CMD="alias ai='bash $LAUNCHER_SCRIPT'"
    if ! grep -Fq "alias ai=" "$HOME/.bashrc"; then echo "" >> "$HOME/.bashrc"; echo "$ALIAS_CMD" >> "$HOME/.bashrc"; fi
}

perform_install_task() {
    local MODE="$1"
    
    auto_load_proxy_env

    local USE_SYSTEM_SITE="false"
    local WHEEL_ARGS=""
    local WHEEL_DIR="$AUTOGLM_DIR/wheels"
    
    if [ "$OS_TYPE" == "TERMUX" ] && [ "$MODE" == "optimized" ]; then
        USE_SYSTEM_SITE="true"
        echo ">>> [Phase 0] 安装系统级加速库..."
        pkg install -y python-pip python-numpy python-pillow python-cryptography >> "$INSTALL_LOG" 2>&1
        
        echo ">>> [Phase 0.5] 检查加速包..."
        local WHEEL_URL="https://github.com/Future-404/TAV-X/releases/download/assets-v1/autoglm_wheels.tar.gz"
        
        if [ ! -f "$AUTOGLM_DIR/wheels.tar.gz" ] && [ ! -d "$WHEEL_DIR" ]; then
            if download_file_smart "$WHEEL_URL" "$AUTOGLM_DIR/wheels.tar.gz"; then
                echo ">>> 下载成功"
            else
                echo ">>> 下载失败 (将尝试在线编译)"
            fi
        fi
        
        if [ -f "$AUTOGLM_DIR/wheels.tar.gz" ]; then
            tar -xzf "$AUTOGLM_DIR/wheels.tar.gz" -C "$AUTOGLM_DIR"
            [ -d "$WHEEL_DIR" ] && WHEEL_ARGS="--find-links=$WHEEL_DIR"
            rm -f "$AUTOGLM_DIR/wheels.tar.gz"
        fi
    fi

    set -e
    cd "$AUTOGLM_DIR" || exit 1
    
    if ! create_venv_smart "$VENV_DIR" "$USE_SYSTEM_SITE"; then
        echo "创建虚拟环境失败"
        exit 1
    fi
    
    local target_req="requirements.txt"
    
    if [ "$USE_SYSTEM_SITE" == "true" ]; then
        cp requirements.txt requirements.tmp
        sed -i '/numpy/d' requirements.tmp
        sed -i '/Pillow/d' requirements.tmp
        sed -i '/cryptography/d' requirements.tmp
        target_req="requirements.tmp"
        
        echo ">>> [Phase 2] 预安装特殊依赖 (jiter)..."
        source "$VENV_DIR/bin/activate"
        local success=0
        for i in {1..3}; do
            if pip install $WHEEL_ARGS jiter >> "$INSTALL_LOG" 2>&1; then success=1; break; fi
            echo "Retrying jiter ($i/3)..."
            sleep 3
        done
        if [ -n "$WHEEL_ARGS" ]; then
            export PIP_FIND_LINKS="$WHEEL_DIR"
        fi
    fi

    install_requirements_smart "$VENV_DIR" "$target_req" "$MODE" "$INSTALL_LOG"
    local ret=$?
    
    rm -f requirements.tmp
    safe_rm "$WHEEL_DIR"
    
    exit $ret
}

setup_autoglm_venv() {
    ui_header "AutoGLM 环境配置"
    if [ ! -d "$AUTOGLM_DIR" ]; then ui_print error "请先执行 [⬇️ 安装/更新 核心代码]。"; ui_pause; return; fi
    if ! command -v python3 &>/dev/null; then ui_print error "系统未检测到 Python3。"; ui_pause; return; fi
    if ! ensure_python_build_deps; then return; fi
    select_pypi_mirror
    
    echo -e "${YELLOW}请选择依赖安装策略:${NC}"
    echo -e "1. ${GREEN}标准模式 (Pip)${NC}"
    if [ "$OS_TYPE" == "TERMUX" ]; then
        echo -e "2. ${CYAN}混合模式 (System + Pip)${NC} - ${YELLOW}推荐${NC}"
    else
        echo -e "2. ${CYAN}极速模式 (UV)${NC}"
    fi
    echo "----------------------------------------"
    local choice=$(ui_input "请输入序号 [1/2]" "2" "false")
    local MODE="standard"; [ "$choice" == "2" ] && MODE="optimized"

    rm -f "$INSTALL_LOG"; touch "$INSTALL_LOG"
    ( perform_install_task "$MODE" ) >> "$INSTALL_LOG" 2>&1 &
    local PID=$!
    monitor_process "$PID" "$INSTALL_LOG"
    
    wait "$PID"
    local EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        ui_print success "环境配置成功！"
        echo -e "输入 ${CYAN}ai${NC} 启动。"
    else
        ui_print error "安装失败。"
        echo -e "${YELLOW}--- 错误日志 (最后20行) ---${NC}"
        tail -n 20 "$INSTALL_LOG"
    fi
    ui_pause
}

install_autoglm() {
    ui_header "部署 Open-AutoGLM (Core)"
    rm -f "$INSTALL_LOG"; touch "$INSTALL_LOG"
    ui_print info "正在下载核心组件..."
    (
        set -e
        echo ">>> [Phase 1] 安装系统基础库..."
        if [ "$OS_TYPE" == "TERMUX" ]; then
            pkg update -y
            pkg install -y termux-api libjpeg-turbo libpng libxml2 libxslt rust binutils clang
        else
            local SYS_PKGS="libjpeg-dev zlib1g-dev libxml2-dev libxslt1-dev"
            command -v apt-get &>/dev/null && { $SUDO_CMD apt-get update -y; $SUDO_CMD apt-get install -y $SYS_PKGS; }
        fi
    ) >> "$INSTALL_LOG" 2>&1

    if [ -d "$AUTOGLM_DIR" ]; then safe_rm "$AUTOGLM_DIR"; fi
    if git_clone_smart "" "https://github.com/zai-org/Open-AutoGLM" "$AUTOGLM_DIR"; then
        check_adb_keyboard; create_ai_launcher
        ui_print success "核心文件已就绪！"
    else
        ui_print error "源码下载失败，请检查网络。"
    fi
    ui_pause
}

configure_autoglm() {
    ui_header "AutoGLM 配置"
    local current_key=""; local current_base=""; local current_model="autoglm-phone"; local current_feedback="true"
    if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"
        current_key="$PHONE_AGENT_API_KEY"; current_base="$PHONE_AGENT_BASE_URL"; [ -n "$PHONE_AGENT_MODEL" ] && current_model="$PHONE_AGENT_MODEL"; [ -n "$PHONE_AGENT_FEEDBACK" ] && current_feedback="$PHONE_AGENT_FEEDBACK"; fi
    echo -e "${CYAN}配置信息:${NC}"
    local new_key=$(ui_input "API Key" "$current_key" "true")
    local new_base=$(ui_input "Base URL" "${current_base:-https://open.bigmodel.cn/api/paas/v4}" "false")
    local new_model=$(ui_input "Model Name" "${current_model:-glm-4v-flash}" "false")
    echo -e "${YELLOW}是否启用反馈 (通知/震动/气泡)?${NC}"
    local new_feedback=$(ui_input "启用反馈 (true/false)" "$current_feedback" "false")
    write_env_safe "$CONFIG_FILE" "PHONE_AGENT_API_KEY" "$new_key"
    write_env_safe "$CONFIG_FILE" "PHONE_AGENT_BASE_URL" "$new_base"
    write_env_safe "$CONFIG_FILE" "PHONE_AGENT_MODEL" "$new_model"
    write_env_safe "$CONFIG_FILE" "PHONE_AGENT_LANG" "cn"
    write_env_safe "$CONFIG_FILE" "PHONE_AGENT_FEEDBACK" "$new_feedback"
    create_ai_launcher; ui_print success "已保存"; ui_pause
}

uninstall_autoglm() {
    ui_header "卸载 AutoGLM 智能体"
    
    if [ ! -d "$AUTOGLM_DIR" ]; then
        ui_print warn "未检测到 AutoGLM 模块。"
        ui_pause; return
    fi

    if ! verify_kill_switch; then return; fi
    
    if ui_spinner "正在清除 AutoGLM 模块..." "safe_rm '$AUTOGLM_DIR'"; then
        sed -i '/alias ai=/d' "$HOME/.bashrc"
        ui_print success "AutoGLM 已卸载，ai 命令已移除。"
        return 2
    else
        ui_print error "删除失败。"
        ui_pause
    fi
}

autoglm_menu() {
    while true; do
        ui_header "AutoGLM 智能体"
        
        local state_type="stopped"
        local status_text="未就绪"
        local info_list=()
        
        local core_ok=false
        local env_ok=false
        
        if [ -d "$AUTOGLM_DIR" ]; then core_ok=true; info_list+=( "核心代码: 已安装" ); else info_list+=( "核心代码: 未安装" ); fi
        if [ -f "$VENV_DIR/bin/activate" ]; then env_ok=true; info_list+=( "环境依赖: 已配置" ); else info_list+=( "环境依赖: 未配置" ); fi
        
        if $core_ok && $env_ok; then
            state_type="success"
            status_text="已就绪"
            info_list+=( "快捷指令: 输入 'ai' 启动" )
        elif $core_ok || $env_ok; then
            state_type="warn"
            status_text="部分安装"
        fi
        
        ui_status_card "$state_type" "$status_text" "${info_list[@]}"

        CHOICE=$(ui_menu "请选择操作" \
            "🚀 启动智能体" \
            "⬇️  安装/更新 核心代码" \
            "📦 安装/更新 依赖" \
            "⚙️  编辑配置文件" \
            "🗑️  卸载 AutoGLM 模块" \
            "🔙 返回上级" \
        )
        case "$CHOICE" in
            *"启动"*) if [ -f "$LAUNCHER_SCRIPT" ]; then bash "$LAUNCHER_SCRIPT"; else ui_print error "请先安装！"; ui_pause; fi ;;
            *"核心代码"*) install_autoglm ;; 
            *"依赖"*) setup_autoglm_venv ;; 
            *"配置"*) configure_autoglm ;; 
            *"卸载"*) uninstall_autoglm; [ $? -eq 2 ] && return ;;
            *"返回"*) return ;; 
        esac
    done
}
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then autoglm_menu; fi
