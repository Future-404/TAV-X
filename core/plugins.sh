#!/bin/bash
# TAV-X Core: Plugin Manager

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

API_URL="https://tav-x-api.future404.qzz.io"
PLUGIN_LIST_FILE="$TAVX_DIR/config/plugins.list"

is_installed() {
    local d=$1
    if [ -d "$INSTALL_DIR/plugins/$d" ] || [ -d "$INSTALL_DIR/public/scripts/extensions/third-party/$d" ]; then return 0; else return 1; fi
}

extract_repo_path() {
    local url=$1
    local short=${url#*github.com/}
    echo "$short"
}

install_single_plugin() {
    local name=$1; local repo_url=$2; local s=$3; local c=$4; local dir=$5
    ui_header "安装插件: $name"
    
    if is_installed "$dir"; then
        if ! ui_confirm "插件已存在，是否重新安装？"; then return; fi
    fi

    local repo_path=$(extract_repo_path "$repo_url")

    prepare_network_strategy
    
    local TASKS=""
    
    if [ "$s" != "-" ]; then
        local b_arg=""; [ "$s" != "HEAD" ] && b_arg="-b $s"
        TASKS+="safe_rm '$INSTALL_DIR/plugins/$dir'; git_clone_smart '$b_arg' '$repo_path' '$INSTALL_DIR/plugins/$dir' || exit 1;"
    fi
    
    if [ "$c" != "-" ]; then
        local b_arg=""; [ "$c" != "HEAD" ] && b_arg="-b $c"
        TASKS+="safe_rm '$INSTALL_DIR/public/scripts/extensions/third-party/$dir'; git_clone_smart '$b_arg' '$repo_path' '$INSTALL_DIR/public/scripts/extensions/third-party/$dir' || exit 1;"
    fi
    
    local WRAP_CMD="source \"$TAVX_DIR/core/utils.sh\"; $TASKS"
    
    if ui_spinner "正在下载插件 (智能优选)..." "$WRAP_CMD"; then
        ui_print success "安装完成！"
    else
        ui_print error "安装失败，请检查网络。"
    fi
    ui_pause
}

list_install_menu() {
    if [ ! -f "$PLUGIN_LIST_FILE" ]; then ui_print error "未找到插件列表"; ui_pause; return; fi

    while true; do
        ui_header "插件仓库 (Repository)"
        MENU_ITEMS=()
        rm -f "$TAVX_DIR/.plugin_map"
        
        while IFS= read -r line; do
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            IFS='|' read -r name repo s c dir <<< "$line"
            name=$(echo "$name"|xargs); dir=$(echo "$dir"|xargs)
            
            if is_installed "$dir"; then ICON="✅"; else ICON="📦"; fi
            ITEM="$ICON $name  [$dir]"
            MENU_ITEMS+=("$ITEM")
            echo "$ITEM|$line" >> "$TAVX_DIR/.plugin_map"
        done < "$PLUGIN_LIST_FILE"
        
        MENU_ITEMS+=("🔙 返回上级")
        CHOICE=$(ui_menu "输入关键词搜索" "${MENU_ITEMS[@]}")
        if [[ "$CHOICE" == *"返回上级"* ]]; then return; fi
        
        RAW_LINE=$(grep -F "$CHOICE|" "$TAVX_DIR/.plugin_map" | head -n 1 | cut -d'|' -f2-)
        if [ -n "$RAW_LINE" ]; then
            IFS='|' read -r n r s c d <<< "$RAW_LINE"
            install_single_plugin "$(echo "$n"|xargs)" "$(echo "$r"|xargs)" "$(echo "$s"|xargs)" "$(echo "$c"|xargs)" "$(echo "$d"|xargs)"
        else
            ui_print error "数据解析错误"
            ui_pause
        fi
    done
}

submit_plugin() {
    ui_header "提交新插件"
    echo -e "${YELLOW}欢迎贡献插件！${NC}"
    echo -e "${CYAN}提示: 必填项留空或输入 '0' 可取消操作。${NC}"
    echo ""
    local name=$(ui_input "1. 插件名称 (必填)" "" "false")
    if [[ -z "$name" || "$name" == "0" ]]; then ui_print info "已取消"; ui_pause; return; fi
    local url=$(ui_input "2. GitHub 地址 (必填)" "https://github.com/" "false")
    if [[ -z "$url" || "$url" == "0" || "$url" == "https://github.com/" ]]; then ui_print info "已取消"; ui_pause; return; fi
    if [[ "$url" != http* ]]; then ui_print error "地址格式错误"; ui_pause; return; fi
    local dir=$(ui_input "3. 英文目录名 (选填，0取消)" "" "false")
    if [[ "$dir" == "0" ]]; then ui_print info "已取消"; ui_pause; return; fi
    
    echo -e "------------------------"
    echo -e "名称: $name"
    echo -e "地址: $url"
    echo -e "目录: ${dir:-自动推断}"
    echo -e "------------------------"
    
    if ! ui_confirm "确认提交吗？"; then ui_print info "已取消"; ui_pause; return; fi
    
    local JSON=$(printf '{"name":"%s", "url":"%s", "dirName":"%s"}' "$name" "$url" "$dir")
    
    _auto_heal_network_config
    local network_conf="$TAVX_DIR/config/network.conf"
    local proxy_args=""
    if [ -f "$network_conf" ]; then
        local c=$(cat "$network_conf")
        if [[ "$c" == PROXY* ]]; then
            local val=${c#*|}; val=$(echo "$val"|tr -d '\n\r')
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

plugin_menu() {
    while true; do
        ui_header "插件生态中心"
        CHOICE=$(ui_menu "请选择" "📥 安装插件" "➕ 提交插件" "🔙 返回主菜单")
        case "$CHOICE" in
            *"安装"*) list_install_menu ;; 
            *"提交"*) submit_plugin ;; 
            *"返回"*) return ;; 
        esac 
    done
}
