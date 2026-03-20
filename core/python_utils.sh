#!/bin/bash
# TAV-X Core: Python Utilities

[ -n "$_TAVX_PY_UTILS_LOADED" ] && return
_TAVX_PY_UTILS_LOADED=true

source "$TAVX_DIR/core/utils.sh"

PY_CONFIG="$TAVX_DIR/config/python.conf"

get_python_version() {
    if command -v python3 &>/dev/null;
 then
        python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
    else
        echo "0.0"
    fi
}
export -f get_python_version

check_python_version_match() {
    local target="$1"
    local current
    current=$(get_python_version)
    if [ "$current" == "$target" ]; then
        return 0
    fi
    return 1
}
export -f check_python_version_match

select_pypi_mirror() {
    local quiet_mode="${1:-interactive}"
    local current_mirror=""
    if [ -f "$PY_CONFIG" ]; then
        current_mirror=$(grep "^PYPI_INDEX_URL=" "$PY_CONFIG" | cut -d'=' -f2)
    fi

    if [ "$quiet_mode" == "quiet" ]; then
        if [ -n "$current_mirror" ]; then
            export PIP_INDEX_URL="$current_mirror"
            return 0
        fi
        return 1
    fi

    ui_header "PyPI 镜像源设置"
    echo -e "当前源: ${CYAN}${current_mirror:-官方源}${NC}"
    echo "----------------------------------------"

    local options=(
        "🇨🇳 清华大学"
        "🇨🇳 阿里云"
        "🇨🇳 腾讯云"
        "🇨🇳 华为云"
        "🇨🇳 中国科大"
        "🌐 官方源"
        "✏️  自定义输入"
        "🔙 返回"
    )

    local CHOICE
    CHOICE=$(ui_menu "请选择镜像源" "${options[@]}")
    
    if [[ "$CHOICE" == *"返回"* ]]; then return; fi
    
    local new_url=""
    case "$CHOICE" in
        *"清华"*) new_url="https://pypi.tuna.tsinghua.edu.cn/simple" ;; 
        *"阿里"*) new_url="https://mirrors.aliyun.com/pypi/simple/" ;; 
        *"腾讯"*) new_url="https://mirrors.cloud.tencent.com/pypi/simple" ;; 
        *"华为"*) new_url="https://repo.huaweicloud.com/repository/pypi/simple" ;; 
        *"科大"*) new_url="https://pypi.mirrors.ustc.edu.cn/simple/" ;; 
        *"官方"*) new_url="https://pypi.org/simple" ;; 
        *"自定义"*) new_url=$(ui_input "请输入完整 Index URL" "" "false") ;; 
    esac

    if [ -n "$new_url" ]; then
        write_env_safe "$PY_CONFIG" "PYPI_INDEX_URL" "$new_url"
        ui_print success "已保存首选源。"
        if command -v pip &>/dev/null;
 then
            pip config set global.index-url "$new_url" >/dev/null 2>&1
        fi
    fi
}
export -f select_pypi_mirror

ensure_python_build_deps() {
    if [ "$OS_TYPE" == "TERMUX" ]; then
        local missing=false
        for cmd in rustc cargo clang make;
 do
            if ! command -v $cmd &>/dev/null; then missing=true; break; fi
        done
        
        if [ "$missing" == "false" ]; then
            local test_file="$TMP_DIR/rust_test_$"
            echo 'fn main(){}' > "$test_file.rs"
            if ! rustc "$test_file.rs" -o "$test_file.bin" >/dev/null 2>&1; then
                missing=true
            fi
            rm -f "$test_file.rs" "$test_file.bin"
        fi

        if [ "$missing" == "true" ]; then
            ui_print warn "编译环境缺失或损坏，正在尝试自动修复..."
            sys_remove_pkg "rust"
            if sys_install_pkg "rust binutils clang make python"; then
                ui_print success "编译环境修复成功。"
            else
                return 1
            fi
        fi
    else
        local missing_sys=false
        if ! command -v make &>/dev/null; then missing_sys=true; fi
        if ! command -v gcc &>/dev/null; then missing_sys=true; fi
        
        if [ "$missing_sys" = true ]; then
             ui_print warn "检测到基础编译工具缺失。"
             if ui_confirm "尝试安装 build-essential?"; then
                 sys_install_pkg "build-essential python3-dev"
             fi
        fi
        
        if ! command -v cargo &>/dev/null || ! command -v rustc &>/dev/null;
 then
            ui_print warn "未检测到 Rust 编译环境。"
            if ui_confirm "是否自动安装 Rust ?"; then
                ui_print info "正在下载并安装 Rustup..."
                if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y; then
                    source "$HOME/.cargo/env"
                    if command -v rustc &>/dev/null;
 then
                        ui_print success "Rust 安装成功。"
                    else
                        ui_print error "Rust 安装脚本执行完毕但未检测到 rustc，请检查 ~/.cargo/bin 是否在 PATH 中。"
                    fi
                else
                    ui_print error "Rustup 下载/安装失败。"
                fi
            else
                ui_print warn "跳过 Rust 安装，后续依赖编译可能会失败。"
            fi
        fi
    fi
    return 0
}
export -f ensure_python_build_deps

create_venv_smart() {
    local venv_path="$1"
    local use_system_site="${2:-false}"
    
    if [ "$OS_TYPE" == "TERMUX" ] && [ -z "$2" ]; then
        use_system_site="true"
    fi
    
    if [ -d "$venv_path" ]; then
        safe_rm "$venv_path"
    fi
    
    ensure_python_build_deps
    
    local args=""
    [ "$use_system_site" == "true" ] && args="--system-site-packages"
    python3 -m venv "$venv_path" $args
    
    if [ ! -f "$venv_path/bin/activate" ]; then
        return 1
    fi
    return 0
}
export -f create_venv_smart

ensure_uv_installed() {
    if command -v uv &>/dev/null; then return 0; fi

    ui_print info "正在安装高性能包管理器 uv..."
    if [ "$OS_TYPE" == "TERMUX" ]; then
        if sys_install_pkg "uv"; then return 0; fi
        # 回退方案
        if command -v pip &>/dev/null; then
             pip install uv && return 0
        fi
    else
        if curl -LsSf https://astral.sh/uv/install.sh | sh; then
            export PATH="$HOME/.cargo/bin:$PATH"
            return 0
        fi
    fi
    ui_print warn "UV 安装失败，将降级使用 pip。"
    return 1
}
export -f ensure_uv_installed

install_requirements_smart() {
    local venv_path="$1"
    local target="$2"
    local mode="${3:-standard}"
    
    local pypi_url
    pypi_url=$(grep "^PYPI_INDEX_URL=" "$PY_CONFIG" 2>/dev/null | cut -d'=' -f2)
    if [ -n "$pypi_url" ]; then
        export PIP_INDEX_URL="$pypi_url"
        export UV_PYPI_MIRROR="$pypi_url"
        export UV_INDEX_URL="$pypi_url"
    fi
    if [ "$OS_TYPE" == "TERMUX" ]; then
        local check_file="$target"
        [ -d "$target" ] && check_file="$target/pyproject.toml"
        
        if [ -f "$check_file" ]; then
            local sys_pkgs=""
            if grep -qE "numpy|pandas" "$check_file"; then sys_pkgs="$sys_pkgs python-numpy python-pandas"; fi
            if grep -qE "pillow" "$check_file"; then sys_pkgs="$sys_pkgs python-pillow"; fi
            if grep -qE "cryptography" "$check_file"; then sys_pkgs="$sys_pkgs python-cryptography openssl"; fi
            if grep -qE "lxml" "$check_file"; then sys_pkgs="$sys_pkgs python-lxml"; fi
            
            if [ -n "$sys_pkgs" ]; then
                ui_print info "检测到需要编译的依赖，正在安装系统库以加速..."
                sys_install_pkg "tur-repo"
                sys_install_pkg "$sys_pkgs"
            fi
        fi
    fi

    if [ ! -f "$venv_path/bin/activate" ]; then
        ui_print error "虚拟环境未找到: $venv_path"
        return 1
    fi
    
    source "$venv_path/bin/activate"
    ensure_uv_installed

    local install_cmd=""
    local install_desc=""
    
    if command -v uv &>/dev/null; then
        if [ -d "$target" ] && [ -f "$target/pyproject.toml" ]; then
            install_cmd="cd '$target' && uv pip install ."
            install_desc="UV 项目安装 (pyproject.toml)..."
        elif [ -f "$target" ]; then
            install_cmd="uv pip install -r '$target'"
            install_desc="UV 依赖安装..."
        fi
    fi
    
    if [ -z "$install_cmd" ]; then
        if [ -d "$target" ] && [ -f "$target/pyproject.toml" ]; then
            install_cmd="cd '$target' && pip install ."
            install_desc="Pip 项目安装..."
        elif [ -f "$target" ]; then
            install_cmd="pip install -r '$target'"
            install_desc="Pip 依赖安装..."
        fi
    fi
    
    if [ -z "$install_cmd" ]; then
        ui_print error "无法识别的安装目标: $target"
        return 1
    fi
    
    if [ "$OS_TYPE" == "TERMUX" ]; then
        export CC="clang"
        export CXX="clang++"
        export CFLAGS="-Wno-incompatible-function-pointer-types"
        # 修复 Rust/Maturin 编译报错: Failed to determine Android API level
        export ANDROID_API_LEVEL=24
    fi

    if ui_stream_task "$install_desc" "$install_cmd"; then
        return 0
    else
        if [[ "$install_cmd" == *"uv pip"* ]]; then
            ui_print warn "UV 安装失败 (可能因环境变量被隔离)，尝试回退到标准 Pip..."
            local fallback_cmd="${install_cmd/uv pip/pip}"
            if ui_stream_task "Pip 回退安装..." "$fallback_cmd"; then
                return 0
            fi
        fi
        ui_print error "依赖安装失败。"
        return 1
    fi
}
export -f install_requirements_smart

python_environment_manager_ui() {
    while true; do
        ui_header "Python 基础设施管理"
        
        local state="stopped"; local text="环境缺失"; local info=()
        if command -v python3 &>/dev/null;
 then
            state="success"; text="环境正常"
            info+=( "版本: $(python3 --version | awk '{print $2}')" )
            command -v pip3 &>/dev/null && info+=( "Pip: 已就绪" ) || info+=( "Pip: 未安装" )
        fi
        
        ui_status_card "$state" "$text" "${info[@]}"
        local CHOICE
        CHOICE=$(ui_menu "操作菜单" "🛠️ 安装/修复系统Python" "⚙️  设置PyPI镜像源" "⚡ 安装/同步UV" "🔍 环境诊断" "💥 彻底卸载Python" "🔙 返回")
        case "$CHOICE" in
            *"安装/修复"*) 
                source "$TAVX_DIR/core/deps.sh"
                install_python_system ;; 
            *"镜像"*) select_pypi_mirror ;; 
            *"卸载"*) 
                ui_header "卸载 Python 环境"
                echo -e "${RED}警告：此操作将执行以下动作：${NC}"
                if [ "$OS_TYPE" == "TERMUX" ]; then
                    echo -e "  1. 彻底从 Termux 移除 Python & UV 及其所有二进制文件"
                    echo -e "  2. 清空全局 Pip & UV 缓存"
                else
                    echo -e "  1. 清理当前用户的 Python & UV 残留"
                    echo -e "  2. 清空全局 Pip & UV 缓存"
                    echo -e "  (注：出于安全考虑，Linux 下不会移除系统级 Python3)"
                fi
                echo ""
                if ! verify_kill_switch; then continue; fi
                
                ui_print info "正在执行清理..."
                if [ "$OS_TYPE" == "TERMUX" ]; then
                    sys_remove_pkg "python uv"
                fi
                ui_spinner "清理用户数据..." "source \"$TAVX_DIR/core/utils.sh\"; safe_rm ~/.cache/pip ~/.cache/uv ~/.local/lib/python* ~/.cargo/bin/uv"
                
                ui_print success "Python & UV 环境已归零。"
                ui_pause ;; 
            *"UV"*) 
                ui_header "UV 安装"
                if [ "$OS_TYPE" == "TERMUX" ]; then 
                    ui_print info "正在通过 pkg 安装 UV..."
                    sys_install_pkg "uv"
                else
                    ui_print info "正在获取 UV..."
                    curl -LsSf https://astral.sh/uv/install.sh | sh
                fi; ui_pause ;; 
            *"诊断"*) 
                ui_header "环境诊断"
                command -v python3 &>/dev/null && echo -e "Python3: ${GREEN}OK${NC}" || echo -e "Python3: ${RED}缺失${NC}"
                command -v pip3 &>/dev/null && echo -e "Pip3: ${GREEN}OK${NC}" || echo -e "Pip3: ${RED}缺失${NC}"
                [ "$OS_TYPE" == "TERMUX" ] && { command -v rustc &>/dev/null && echo -e "Rustc: ${GREEN}OK${NC}" || echo -e "Rustc: ${RED}缺失${NC}"; }
                ui_pause ;; 
            *"返回"*) return ;; 
        esac
    done
}