#!/bin/bash
# SillyTavern Module: Plugin Manager

[ -z "$TAVX_DIR" ] && source "$HOME/.tav_x/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

_h="aHR0cHM6Ly90YXYteC1hcGk="
_b="LmZ1dHVyZTQwNC5xenouaW8="
API_URL=$(echo "${_h}${_b}" | base64 -d 2>/dev/null)

CURRENT_MODULE_DIR="$(dirname "${BASH_SOURCE[0]}")"
PLUGIN_LIST_FILE="$CURRENT_MODULE_DIR/plugins.list"

_st_plugin_is_installed() {
    local d=$1
    if [ -d "$ST_DIR/plugins/$d" ] || [ -d "$ST_DIR/public/scripts/extensions/third-party/$d" ]; then return 0; else return 1; fi
}

_st_extract_repo_path() {
    local url=$1
    local short=${url#*github.com/}
    echo "$short"
}

app_plugin_install_single() {
    _st_vars
    local name=$1; local repo_url=$2; local s=$3; local c=$4; local dir=$5
    
    if [[ "$dir" == *".."* || "$dir" == *"/"* ]]; then
        ui_print error "非法插件目录名: $dir"
        ui_pause; return
    fi

    ui_header "安装插件: $name"
    
    if _st_plugin_is_installed "$dir"; then
        if ! ui_confirm "插件已存在，是否重新安装？"; then return; fi
    fi

    local repo_path
    repo_path=$(_st_extract_repo_path "$repo_url")

    prepare_network_strategy "SillyTavern Plugin"
    
    # Ensure we are in a safe directory to avoid getcwd errors
    cd "$TAVX_DIR" || return

    if [ "$s" != "-" ]; then
        local b_arg=""; [ "$s" != "HEAD" ] && b_arg="-b $s"
        safe_rm "$ST_DIR/plugins/$dir"
        if ! git_clone_smart "$b_arg" "$repo_path" "$ST_DIR/plugins/$dir"; then
            ui_print error "插件核心文件下载失败。"
            ui_print info "提示：如果直连 GitHub 失败，请在 [系统设置 -> 网络设置] 中测试并启用加速镜像源。"
            ui_pause; return
        fi
    fi
    
    if [ "$c" != "-" ]; then
        local b_arg=""; [ "$c" != "HEAD" ] && b_arg="-b $c"
        safe_rm "$ST_DIR/public/scripts/extensions/third-party/$dir"
        if ! git_clone_smart "$b_arg" "$repo_path" "$ST_DIR/public/scripts/extensions/third-party/$dir"; then
            ui_print error "插件前端扩展下载失败。"
            ui_print info "提示：如果直连 GitHub 失败，请在 [系统设置 -> 网络设置] 中测试并启用加速镜像源。"
            ui_pause; return
        fi
    fi
    
    local plugin_path="$ST_DIR/plugins/$dir"
    [ "$s" == "-" ] && plugin_path="$ST_DIR/public/scripts/extensions/third-party/$dir"
    
    if [ -f "$plugin_path/package.json" ]; then
        ui_print info "检测到插件依赖，正在自动安装..."
        if npm_install_smart "$plugin_path"; then
            ui_print success "安装完成！"
        else
            ui_print warn "虽然插件已下载，但依赖安装失败。插件可能无法正常工作。"
        fi
    else
        ui_print success "安装完成！"
    fi
    ui_pause
}

app_plugin_list_menu() {
    if [ ! -f "$PLUGIN_LIST_FILE" ]; then ui_print error "未找到插件列表: $PLUGIN_LIST_FILE"; ui_pause; return; fi

    while true; do
        ui_header "插件仓库 (Repository)"
        MENU_ITEMS=()
        local map_file="$TAVX_DIR/.plugin_map"
        safe_rm "$map_file"
        
        while IFS= read -r line; do
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            # shellcheck disable=SC2034
            IFS='|' read -r name repo s c dir <<< "$line"
            name=$(echo "$name"|xargs); dir=$(echo "$dir"|xargs)
            
            if _st_plugin_is_installed "$dir"; then ICON="✅"; else ICON="📦"; fi
            ITEM="$ICON $name  [$dir]"
            MENU_ITEMS+=("$ITEM")
            echo "$ITEM|$line" >> "$map_file"
        done < "$PLUGIN_LIST_FILE"
        
        MENU_ITEMS+=("🔙 返回上级")
        CHOICE=$(ui_menu "输入关键词搜索" "${MENU_ITEMS[@]}")
        if [[ "$CHOICE" == *"返回上级"* ]]; then return; fi
        
        RAW_LINE=$(grep -F "$CHOICE|" "$map_file" | head -n 1 | cut -d'|' -f2-)
        if [ -n "$RAW_LINE" ]; then
            IFS='|' read -r n r s c d <<< "$RAW_LINE"
            app_plugin_install_single "$(echo "$n"|xargs)" "$(echo "$r"|xargs)" "$(echo "$s"|xargs)" "$(echo "$c"|xargs)" "$(echo "$d"|xargs)"
        else
            ui_print error "数据解析错误"
            ui_pause
        fi
    done
}

app_plugin_submit() {
    ui_header "提交新插件"
    echo -e "${YELLOW}欢迎贡献插件！${NC}"
    echo -e "数据将提交至: $API_URL"
    echo ""
    local name
    name=$(ui_input "1. 插件名称 (必填)" "" "false")
    if [[ -z "$name" || "$name" == "0" ]]; then ui_print info "已取消"; ui_pause; return; fi
    local url
    url=$(ui_input "2. GitHub 地址 (必填)" "https://github.com/" "false")
    if [[ -z "$url" || "$url" == "0" || "$url" == "https://github.com/" ]]; then ui_print info "已取消"; ui_pause; return; fi
    if [[ "$url" != http* ]]; then ui_print error "地址格式错误"; ui_pause; return; fi
    local dir
    dir=$(ui_input "3. 英文目录名 (选填，0取消)" "" "false")
    if [[ "$dir" == "0" ]]; then ui_print info "已取消"; ui_pause; return; fi
    
    echo -e "------------------------"
    echo -e "名称: $name"
    echo -e "地址: $url"
    echo -e "目录: ${dir:-自动推断}"
    echo -e "------------------------"
    
    if ! ui_confirm "确认提交吗？"; then ui_print info "已取消"; ui_pause; return; fi
    
    local JSON
    JSON=$(printf '{"name":"%s", "url":"%s", "dirName":"%s"}' "$name" "$url" "$dir")
    
    _auto_heal_network_config
    local network_conf="$TAVX_DIR/config/network.conf"
    local proxy_args=""
    if [ -f "$network_conf" ]; then
        local c
        c=$(cat "$network_conf")
        if [[ "$c" == PROXY* ]]; then
            local val
            val=${c#*|}; val=$(echo "$val"|tr -d '\n\r')
            proxy_args="-x $val"
        fi
    fi
    
    if ui_spinner "正在提交..." "curl -s $proxy_args -X POST -H 'Content-Type: application/json' -d '$JSON' '$API_URL/submit' > $TAVX_DIR/.api_res"; then
        RES=$(cat "$TAVX_DIR/.api_res")
        if echo "$RES" | grep -q "success"; then
            ui_print success "提交成功！请等待审核。"
        else
            ui_print error "提交失败: $RES"
        fi
    else
        ui_print error "连接 API 失败，请检查网络。"
    fi
    ui_pause
}

app_plugin_reset() {
    local PLUGIN_ROOT="$ST_DIR/public/scripts/extensions/third-party"
    if [ -z "$(ls -A "$PLUGIN_ROOT" 2>/dev/null)" ]; then ui_print info "插件目录已经是空的了。"; ui_pause; return; fi

    ui_header "💥 插件工厂重置"
    echo -e "${RED}警告：将删除所有第三方扩展！${NC}"
    if ui_confirm "确认清空吗？"; then
        if ui_spinner "正在粉碎文件..." "safe_rm '$PLUGIN_ROOT'; mkdir -p '$PLUGIN_ROOT'"; then
            ui_print success "清理完成。请重启酒馆。"
        else
            ui_print error "操作失败。";
        fi
    fi
    ui_pause
}

app_plugin_menu() {
    _st_vars
    if [ ! -d "$ST_DIR" ]; then ui_print error "请先安装酒馆！"; ui_pause; return; fi
    while true; do
        ui_header "插件生态中心"
        CHOICE=$(ui_menu "请选择" \
            "📥 在线安装插件" \
            "➕ 提交新插件" \
            "💥 重置所有插件" \
            "🔙 返回"
        )
        case "$CHOICE" in
            *"安装"*) app_plugin_list_menu ;; 
            *"提交"*) app_plugin_submit ;; 
            *"重置"*) app_plugin_reset ;; 
            *"返回"*) return ;; 
        esac 
    done
}