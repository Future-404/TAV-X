#!/bin/bash
# TAV-X Core: PRoot UI Component
# 提供 Debian 容器管理界面

_pd_vars() {
    [ -f "$TAVX_DIR/core/proot_manager.sh" ] && source "$TAVX_DIR/core/proot_manager.sh"
}

proot_settings_menu() {
    _pd_vars
    while true; do
        ui_header "Debian 容器 (Core Infrastructure)"
        
        local status_text="⚪ 未安装"
        local disk_usage="N/A"
        local install_path="$PREFIX/var/lib/proot-distro/installed-rootfs/debian"
        
        if [ -d "$install_path" ]; then
            status_text="🟢 运行就绪"
            disk_usage=$(du -sh "$install_path" 2>/dev/null | awk '{print $1}')
        fi
        
        local info=( "状态: $status_text" "占用: $disk_usage" "映射: /root ⇄ $HOME" )
        ui_status_card "working" "环境概览" "${info[@]}"
        
        local options=(
            "💻 进入终端"
            "📦 更新软件包"
            "🐍 安装Python开发环境"
            "📥 初始化/重装容器"
            "🗑️  卸载容器"
            "🔙 返回设置"
        )
        
        local choice
        choice=$(ui_menu "容器操作" "${options[@]}")
        
        case "$choice" in
            *"进入终端"*) 
                if [ "$status_text" != "🟢 运行就绪" ]; then
                    ui_print warn "容器未安装，请先初始化。"
                else
                    ui_print info "正在进入 Debian Shell (输入 exit 退出)..."
                    proot-distro login debian --user root --shared-tmp --bind "$HOME:/root"
                fi
                ;;
            *"更新软件包"*) 
                if [ "$status_text" == "🟢 运行就绪" ]; then
                    pr_exec "apt-get update && apt-get upgrade -y"
                    ui_pause
                else
                    ui_print warn "容器未安装。"
                fi
                ;;
            *"Python"*) 
                if [ "$status_text" == "🟢 运行就绪" ]; then
                    if ui_confirm "即将安装 python3, pip, venv, build-essential..."; then
                        pr_install_pkg "python3 python3-pip python3-venv build-essential git curl"
                        ui_pause
                    fi
                else
                    ui_print warn "容器未安装。"
                fi
                ;;
            *"初始化"*) 
                if [ "$status_text" == "🟢 运行就绪" ]; then
                    if ! ui_confirm "容器已存在。确定要重装吗？\n警告：容器内的所有数据将被清空！"; then
                        continue
                    fi
                    proot-distro remove debian
                fi
                pr_ensure_env
                ui_pause
                ;;
            *"卸载容器"*) 
                if [ "$status_text" == "🟢 运行就绪" ]; then
                    if ui_confirm "确定要完全删除 Debian 容器吗？\n所有数据将丢失！"; then
                        proot-distro remove debian
                        ui_print success "已删除。"
                    fi
                else
                    ui_print warn "容器未安装。"
                fi
                ;;
            *"返回"*) return ;; 
        esac
    done
}
