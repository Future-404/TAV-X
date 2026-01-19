#!/bin/bash
# [METADATA]
# MODULE_ID: example_demo
# MODULE_NAME: 示例模块 (Demo)
# MODULE_ENTRY: example_demo_menu
# APP_AUTHOR: TAV-X Dev
# APP_PROJECT_URL: https://github.com/Future-404/TAV-X
# APP_DESC: 这是一个最小化的开发示例，展示了模块的基本结构、元数据格式以及如何调用核心 UI 组件。
# [END_METADATA]

# 引入核心组件 (必需)
source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"

# 1. 安装生命周期 (可选)
# 当用户在“应用中心”点击下载并确认安装时，或手动调用安装时触发
example_demo_install() {
    ui_header "示例模块安装"
    ui_print info "正在执行安装逻辑..."
    
    # 模拟一个耗时任务
    ui_spinner "正在配置环境..." "sleep 2"
    
    # 关键步骤：创建应用目录以标记为“已安装”
    local app_dir=$(get_app_path "example_demo")
    mkdir -p "$app_dir"
    touch "$app_dir/readme.txt"
    echo "This is a demo app." > "$app_dir/readme.txt"
    
    ui_print success "安装完成！"
    ui_pause
}

# 2. 启动生命周期 (可选)
# 用于后台服务类应用，通常注册到系统服务
example_demo_start() {
    ui_print info "此模块是一个纯交互演示，没有后台服务。"
    ui_pause
}

# 3. 菜单入口 (必需)
# 对应元数据中的 MODULE_ENTRY，是模块的主界面
example_demo_menu() {
    while true; do
        ui_header "示例模块面板"
        
        # 使用 ui_menu 创建交互菜单
        local choice=$(ui_menu "功能演示" "✨ 测试打印" "❓ 测试确认框" "📝 测试输入框" "🔙 返回主菜单")
        
        case "$choice" in
            *"测试打印"*)
                ui_print info "这是一条普通信息"
                ui_print success "这是一条成功信息"
                ui_print warn "这是一条警告信息"
                ui_print error "这是一条错误信息"
                ui_pause
                ;;
            *"测试确认框"*)
                if ui_confirm "你觉得 TAV-X 开发简单吗？"; then
                    ui_print success "英雄所见略同！"
                else
                    ui_print info "没关系，多看文档就熟悉了。"
                fi
                ui_pause
                ;;
            *"测试输入框"*)
                # 参数：提示语，默认值，是否校验(IP/URL等，此处为any)
                local name=$(ui_input "请输入你的昵称" "Guest" "false")
                ui_print success "你好，$name！"
                ui_pause
                ;;
            *"返回"*)
                return
                ;;
        esac
    done
}
