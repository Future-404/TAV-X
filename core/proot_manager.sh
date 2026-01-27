#!/bin/bash
# TAV-X PRoot Manager (The Bridge)
# [架构说明]
# 该模块充当 Termux 与 PRoot Debian 之间的适配器。
# 它允许 TAV-X 在原生环境指挥 Debian 容器内的进程，实现"文件互通，指令透传"。
# 
# [路径映射]
# Termux: $HOME/TAV-X
# Debian: /root/TAV-X
# (proot-distro 默认行为)

pr_ensure_env() {
    if [ "$OS_TYPE" != "TERMUX" ]; then
        ui_print warn "PRoot 仅在 Termux 环境下有效。"
        return 1
    fi

    if ! command -v proot-distro &>/dev/null; then
        ui_print info "正在安装 proot-distro..."
        pkg install proot-distro -y || return 1
    fi
    
    if [ -d "$PREFIX/var/lib/proot-distro/installed-rootfs/debian" ]; then
        return 0
    fi

    ui_print info "正在初始化 Debian 容器 (需下载约 200MB)..."
    if ! proot-distro install debian; then
        ui_print error "Debian 安装失败，请检查网络。"
        return 1
    fi
    ui_print success "Debian 容器初始化完成。"
    ui_print info "正在更新容器软件源..."
    pr_exec "apt-get update -qq && apt-get install -y curl wget git build-essential"
}

pr_exec() {
    local cmd="$1"
    local inner_cwd="${PWD/$HOME/\/root}"
    local proxy_env=""
    [ -n "$http_proxy" ] && proxy_env="export http_proxy='$http_proxy';"
    [ -n "$https_proxy" ] && proxy_env="${proxy_env} export https_proxy='$https_proxy';"
    [ -n "$all_proxy" ] && proxy_env="${proxy_env} export all_proxy='$all_proxy';"
    [ -n "$no_proxy" ] && proxy_env="${proxy_env} export no_proxy='$no_proxy';"
    local final_cmd="$proxy_env $cmd"
    proot-distro login debian --user root --shared-tmp --bind "$HOME:/root" -- bash -c "cd \"$inner_cwd\" && $final_cmd"
}
pr_install_pkg() {
    local pkgs="$1"
    ui_print info "[Debian] 正在安装系统库: $pkgs"
    pr_exec "export DEBIAN_FRONTEND=noninteractive && apt-get update -qq && apt-get install -y $pkgs"
}

pr_command_exists() {
    local cmd="$1"
    pr_exec "command -v $cmd >/dev/null"
}

pr_ensure_uv() {
    if pr_command_exists "uv"; then
        return 0
    fi
    
    ui_print info "[Debian] 正在安装 uv 包管理器 (Via Astral)..."
    pr_exec "curl -LsSf https://astral.sh/uv/install.sh | sh"
}
