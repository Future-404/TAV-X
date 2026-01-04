#!/bin/bash
# [METADATA]
# MODULE_NAME: 🐍 Python 环境管理
# MODULE_ENTRY: python_mgr_menu
# [END_METADATA]

source "$TAVX_DIR/core/utils.sh"
source "$TAVX_DIR/core/deps.sh"

PY_CONFIG="$TAVX_DIR/config/python.conf"

select_pypi_mirror() {
    local current_mirror=""
    if [ -f "$PY_CONFIG" ]; then
        current_mirror=$(grep "^PYPI_INDEX_URL=" "$PY_CONFIG" | cut -d'=' -f2)
    fi

    if [ "$1" == "quiet" ] && [ -n "$current_mirror" ]; then
        echo "$current_mirror"
        return
    fi

    ui_header "PyPI 镜像源设置"
    echo -e "当前源: ${CYAN}${current_mirror:-官方源}${NC}"
    echo "选择靠近您的镜像源可以显著加速依赖安装。"
    echo "----------------------------------------"

    local CHOICE=$(ui_menu "请选择镜像源" \
        "🇨🇳 清华大学 (Tuna) - 推荐" \
        "🇨🇳 阿里云 (Aliyun)" \
        "🇨🇳 腾讯云 (Tencent)" \
        "🌐 官方源 (PyPI)" \
        "✏️  自定义输入" \
    )
    
    local new_url=""
    case "$CHOICE" in
        *"清华"*) new_url="https://pypi.tuna.tsinghua.edu.cn/simple" ;;
        *"阿里"*) new_url="https://mirrors.aliyun.com/pypi/simple/" ;;
        *"腾讯"*) new_url="https://mirrors.cloud.tencent.com/pypi/simple" ;;
        *"官方"*) new_url="https://pypi.org/simple" ;;
        *"自定义"*) new_url=$(ui_input "请输入完整 Index URL" "" "false") ;;
    esac

    if [ -n "$new_url" ]; then
        write_env_safe "$PY_CONFIG" "PYPI_INDEX_URL" "$new_url"
        ui_print success "已保存首选源。"
        if command -v pip &>/dev/null; then
            pip config set global.index-url "$new_url" >/dev/null 2>&1
        fi
        echo "$new_url"
    else
        echo "${current_mirror:-https://pypi.org/simple}"
    fi
}

ensure_python_build_deps() {
    if [ "$OS_TYPE" == "TERMUX" ]; then
        ui_print info "正在检查编译环境 (Rust/Clang)..."
        local missing=false
        for cmd in rustc cargo clang make; do
            if ! command -v $cmd &>/dev/null; then missing=true; break; fi
        done
        if [ "$missing" == "false" ]; then
            local test_file="$TMP_DIR/rust_test_$$"
            echo 'fn main(){}' > "$test_file.rs"
            if ! rustc "$test_file.rs" -o "$test_file.bin" >/dev/null 2>&1; then
                missing=true
            fi
            rm -f "$test_file.rs" "$test_file.bin"
        fi

        if [ "$missing" == "true" ]; then
            ui_print warn "编译环境缺失或损坏，正在尝试自动修复..."
            (
                pkg uninstall rust -y
                pkg clean && pkg update -y
                pkg install -y rust binutils clang make python
            ) > "$TMP_DIR/rust_fix.log" 2>&1
            
            if [ $? -eq 0 ]; then
                ui_print success "编译环境修复成功。"
            else
                ui_print error "环境修复失败，请查看日志: $TMP_DIR/rust_fix.log"
                return 1
            fi
        fi
    else
        if ! command -v make &>/dev/null; then
             ui_print warn "未检测到 make/gcc，编译可能会失败。"
             if ui_confirm "尝试安装 build-essential?"; then
                 $SUDO_CMD apt-get update && $SUDO_CMD apt-get install -y build-essential python3-dev
             fi
        fi
    fi
    return 0
}

create_venv_smart() {
    local venv_path="$1"
    local use_system_site="${2:-false}" # true/false
    
    if [ -d "$venv_path" ]; then
        echo ">>> 清理旧环境..."
        safe_rm "$venv_path"
    fi
    
    local args=""
    [ "$use_system_site" == "true" ] && args="--system-site-packages"
    
    echo ">>> 创建虚拟环境..."
    python3 -m venv "$venv_path" $args
    
    if [ ! -f "$venv_path/bin/activate" ]; then
        echo ">>> 虚拟环境创建失败！"
        return 1
    fi
    return 0
}

install_requirements_smart() {
    local venv_path="$1"
    local req_file="$2"
    local mode="${3:-standard}"
    local log_file="${4:-/dev/null}"
    local pypi_url=$(grep "^PYPI_INDEX_URL=" "$PY_CONFIG" 2>/dev/null | cut -d'=' -f2)
    if [ -z "$pypi_url" ]; then
        pypi_url="https://pypi.org/simple"
    fi
    
    source "$venv_path/bin/activate"
    export PIP_INDEX_URL="$pypi_url"
    export PIP_DISABLE_PIP_VERSION_CHECK=1
    
    if [ "$OS_TYPE" == "TERMUX" ]; then
        export CC="clang"
        export CXX="clang++"
        export CFLAGS="-Wno-implicit-function-declaration"
        export RUSTFLAGS="-C lto=no"
        export CARGO_BUILD_JOBS=2
    fi

    echo ">>> 正在安装依赖 (Mode: $mode, Mirror: $pypi_url)..." >> "$log_file"

    if [ "$OS_TYPE" != "TERMUX" ] && command -v uv &>/dev/null && [ "$mode" == "optimized" ]; then
        echo ">>> 使用 UV 加速安装..." >> "$log_file"
        uv pip install -U pip >> "$log_file" 2>&1
        uv pip install -r "$req_file" >> "$log_file" 2>&1
        return $?
    fi
    
    pip install -U pip >> "$log_file" 2>&1
    if [ "$OS_TYPE" == "TERMUX" ] && [ "$mode" == "optimized" ]; then
        echo ">>> Termux 混合模式优化..." >> "$log_file"
        pip install maturin >> "$log_file" 2>&1
    fi
    
    pip install -r "$req_file" >> "$log_file" 2>&1
    return $?
}

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
