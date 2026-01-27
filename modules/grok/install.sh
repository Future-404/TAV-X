#!/bin/bash
# Grok2API Installer: Dual-Mode (PRoot/Native) Logic

grok_install() {
    _grok_vars
    ui_header "安装 Grok2API"
    
    local GIT_REPO="https://github.com/chenyme/grok2api.git"
    
    # 基础环境检查
    if ! command -v python3 &>/dev/null; then
        ui_print warn "未检测到 Python3，正在安装..."
        sys_install_pkg "python3"
    fi
    
    prepare_network_strategy
    
    # 拉取代码
    if [ -d "$GROK_DIR" ]; then
        if ui_confirm "检测到旧版本，是否更新源码 (git pull)?\n选 [No] 将完全重装"; then
            cd "$GROK_DIR" || return 1
            git_clone_smart "" "$GIT_REPO" "$GROK_DIR"
        else
            grok_stop
            [ "$OS_TYPE" == "TERMUX" ] && tavx_service_remove "grok"
            safe_rm "$GROK_DIR"
            git_clone_smart "" "$GIT_REPO" "$GROK_DIR"
        fi
    else
        git_clone_smart "" "$GIT_REPO" "$GROK_DIR"
    fi
    
    if [ ! -f "$GROK_DIR/main.py" ]; then
        ui_print error "源码获取失败。"
        return 1
    fi
    
    cd "$GROK_DIR" || return 1

    # 应用补丁 (动态端口)
    if ! grep -q 'os.getenv("PORT"' main.py; then
        cp main.py main.py.bak
        sed -i 's/port=8001/port=int(os.getenv("PORT", 8001))/' main.py
        ui_print success "已注入动态端口逻辑。"
    fi

    # --- 安装依赖 (双模分流) ---
    if [ "$OS_TYPE" == "TERMUX" ]; then
        ui_print info "检测到 Termux 环境，切换至 PRoot Debian 容器..."
        
        # 1. 确保系统基础库
        if ! pr_ensure_env; then
            ui_print error "PRoot 环境初始化失败。"
            return 1
        fi
        pr_install_pkg "python3 python3-pip python3-venv curl git build-essential libcurl4-openssl-dev libssl-dev"
        
        # 2. 确保 UV 已安装
        pr_ensure_uv
        
        # 生成依赖文件
        local req_file="$GROK_DIR/requirements.txt"
        sed -n '/dependencies = [/,/]/p' pyproject.toml | grep -v 'dependencies =' | grep -v ']' | tr -d '", ' | sed 's/^[ 	]*//' > "$req_file"
        [ ! -s "$req_file" ] && echo "fastapi uvicorn python-dotenv pydantic requests aiofiles aiomysql curl-cffi redis starlette toml uvloop portalocker fastmcp cryptography orjson aiohttp" | tr ' ' '\n' > "$req_file"
        
        # [Debian] 执行 UV 安装
        ui_print info "正在 Debian 容器内使用 UV 高速安装依赖..."
        
        local install_cmd="
        [ -f \"$HOME/.cargo/env\" ] && source \"$HOME/.cargo/env\"
        uv venv .venv
        source .venv/bin/activate
        uv pip install -r requirements.txt
        "
        
        if ! pr_exec "$install_cmd"; then
            ui_print error "依赖安装失败。"
            ui_pause; return 1
        fi
        
    else
        # [Linux] 原生安装逻辑
        ui_print info "检测到 Linux 环境，启用原生 UV 高速安装..."
        
        # 1. 确保基础工具
        sys_install_pkg "python3-venv python3-pip git build-essential"
        
        # 2. 确保 UV
        if ! command -v uv &>/dev/null; then
            ui_print info "正在安装 UV..."
            curl -LsSf https://astral.sh/uv/install.sh | sh
            source "$HOME/.cargo/env" 2>/dev/null || source "$HOME/.local/bin/env" 2>/dev/null
        fi
        
        # 3. 安装依赖
        cd "$GROK_DIR" || return
        local req_file="requirements.txt"
        sed -n '/dependencies = [/,/]/p' pyproject.toml | grep -v 'dependencies =' | grep -v ']' | tr -d '", ' | sed 's/^[ 	]*//' > "$req_file"
        
        ui_print info "正在创建虚拟环境并安装依赖..."
        uv venv .venv
        source .venv/bin/activate
        if ! uv pip install -r "$req_file"; then
            ui_print error "依赖安装失败。"
            ui_pause; return 1
        fi
        
        ui_print success "原生依赖安装完成！"
    fi
    
    # 初始化配置
    if [ ! -f "$GROK_CONF" ]; then
        echo "PORT=8001" > "$GROK_CONF"
        echo "WORKERS=1" >> "$GROK_CONF"
        ui_print info "已生成默认配置文件 (.env)"
    fi
    
    # [新增] 部署启动脚本 (静态文件)
    ui_print info "部署启动脚本..."
    cp "$GROK_MODULE_DIR/boot.py" "$GROK_DIR/boot.py"
    cp "$GROK_MODULE_DIR/run.sh" "$GROK_DIR/run.sh"
    chmod +x "$GROK_DIR/run.sh"
    
    ui_print success "安装完成！"
    ui_pause
}
