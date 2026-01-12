#!/bin/bash
# [METADATA]
# MODULE_ID: sillytavern
# MODULE_NAME: SillyTavern 酒馆
# MODULE_ENTRY: sillytavern_menu
# APP_CATEGORY="Frontend"
# APP_VERSION="Standard"
# APP_DESC="下一代 LLM 沉浸式前端界面"
# [END_METADATA]

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

_st_vars() {
    ST_APP_ID="sillytavern"
    ST_DIR=$(get_app_path "$ST_APP_ID")
    ST_PID_FILE="$RUN_DIR/sillytavern.pid"
    ST_LOG="$ST_DIR/server.log"
}

[ -f "$(dirname "${BASH_SOURCE[0]}")/plugins.sh" ] && source "$(dirname "${BASH_SOURCE[0]}")/plugins.sh"

sillytavern_install() {
    _st_vars
    ui_header "SillyTavern 安装向导"
    
    if [ -d "$ST_DIR" ]; then
        ui_print warn "检测到旧版本或已存在目录: $ST_DIR"
        if ! ui_confirm "确认覆盖安装吗？(将清空该目录下所有数据)"; then return; fi
        safe_rm "$ST_DIR"
    fi
    
    mkdir -p "$(dirname "$ST_DIR")"
    
    # 提前准备网络策略 (交互式选源)，防止在进度条中触发 UI 崩坏
    prepare_network_strategy
    
    local CLONE_CMD="source \"$TAVX_DIR/core/utils.sh\"; git_clone_smart '-b release' 'SillyTavern/SillyTavern' '$ST_DIR'"
    
    if ! ui_stream_task "正在拉取源码..." "$CLONE_CMD"; then
        ui_print error "源码下载失败。"
        return 1
    fi
    
    ui_print info "正在安装依赖..."
    if npm_install_smart "$ST_DIR"; then
        chmod +x "$ST_DIR/start.sh" 2>/dev/null
        sillytavern_configure_recommended
        ui_print success "安装成功！"
    else
        ui_print error "依赖安装失败。"
        return 1
    fi
}

sillytavern_update() {
    _st_vars
    ui_header "SillyTavern 智能更新"
    if [ ! -d "$ST_DIR/.git" ]; then ui_print error "未检测到有效的 Git 仓库。"; ui_pause; return; fi
    
    cd "$ST_DIR" || return
    if ! git symbolic-ref -q HEAD >/dev/null; then
        local current_tag=$(git describe --tags --exact-match 2>/dev/null || git rev-parse --short HEAD)
        ui_print warn "当前处于版本锁定状态 ($current_tag)"
        echo -e "${YELLOW}请先 [解除锁定] 后再尝试更新。${NC}"; ui_pause; return
    fi
    
    # 提前准备网络策略
    prepare_network_strategy
    
    local TEMP_URL=$(get_dynamic_repo_url "SillyTavern/SillyTavern")
    local UPDATE_CMD="cd \"$ST_DIR\"; git pull --autostash \"$TEMP_URL\""
    
    if ui_stream_task "正在同步最新代码..." "$UPDATE_CMD"; then
        ui_print success "代码同步完成。"
        npm_install_smart "$ST_DIR"
    else
        ui_print error "更新失败！可能存在冲突或网络问题。"
    fi
    ui_pause
}

sillytavern_rollback() {
    _st_vars
    while true; do
        ui_header "酒馆版本时光机"
        cd "$ST_DIR" || return
        
        local CURRENT_DESC=""
        local IS_DETACHED=false
        if git symbolic-ref -q HEAD >/dev/null; then
            local branch=$(git rev-parse --abbrev-ref HEAD)
            CURRENT_DESC="${GREEN}分支: $branch (最新)${NC}"
        else
            IS_DETACHED=true
            local tag=$(git describe --tags --exact-match 2>/dev/null || git rev-parse --short HEAD)
            CURRENT_DESC="${YELLOW}🔒 已锁定: $tag${NC}"
        fi
        
        local TAG_CACHE="$TMP_DIR/.st_tag_cache"
        echo -e "当前状态: $CURRENT_DESC"
        echo "----------------------------------------"
        
        local MENU_ITEMS=()
        [ "$IS_DETACHED" = true ] && MENU_ITEMS+=("🔓 解除锁定 (切换最新版)")
        MENU_ITEMS+=("⏳ 回退至历史版本" "🔀 切换通道: Release" "🔀 切换通道: Staging" "🔙 返回")
        
        local CHOICE=$(ui_menu "选择操作" "${MENU_ITEMS[@]}")
        
        # 提前准备网络策略
        if [[ "$CHOICE" != *"返回"* ]]; then
             prepare_network_strategy
        fi

        local TEMP_URL=$(get_dynamic_repo_url "SillyTavern/SillyTavern")
        
        case "$CHOICE" in
            *"解除锁定"*) 
                if ui_confirm "确定恢复到最新 Release 版？"; then
                    local CMD="git config remote.origin.fetch \"+refs/heads/*:refs/remotes/origin/*\"; git fetch \"$TEMP_URL\" release --depth=1; git reset --hard FETCH_HEAD; git checkout release"
                    ui_stream_task "正在归队..." "$CMD" && npm_install_smart "$ST_DIR"
                fi ;;
            *"历史版本"*) 
                ui_stream_task "拉取版本列表中..." "git fetch \"$TEMP_URL\" --tags"
                git tag --sort=-v:refname | head -n 10 > "$TAG_CACHE"
                mapfile -t TAG_LIST < "$TAG_CACHE"
                local TAG_CHOICE=$(ui_menu "选择版本" "${TAG_LIST[@]}" "🔙 取消")
                if [[ "$TAG_CHOICE" != *"取消"* ]]; then
                    local CMD="git fetch \"$TEMP_URL\" tag \"$TAG_CHOICE\" --depth=1; git reset --hard FETCH_HEAD; git checkout \"$TAG_CHOICE\""
                    ui_stream_task "回退到 $TAG_CHOICE..." "$CMD" && npm_install_smart "$ST_DIR"
                fi ;;
            *"切换通道"*) 
                local TARGET="release"; [[ "$CHOICE" == *"Staging"* ]] && TARGET="staging"
                local CMD="git config remote.origin.fetch \"+refs/heads/*:refs/remotes/origin/*\"; git fetch \"$TEMP_URL\" $TARGET --depth=1; git reset --hard FETCH_HEAD; git checkout $TARGET"
                ui_stream_task "切换至 $TARGET..." "$CMD" && npm_install_smart "$ST_DIR" ;;
            *"返回"*) return ;;
        esac
        ui_pause
    done
}

sillytavern_start() {
    _st_vars
    [ ! -d "$ST_DIR" ] && { ui_print error "未安装酒馆"; return 1; }
    
    local mem_conf="$CONFIG_DIR/memory.conf"
    local mem_args=""
    if [ -f "$mem_conf" ]; then
        local m=$(cat "$mem_conf")
        [[ "$m" =~ ^[0-9]+$ ]] && mem_args="--max-old-space-size=$m"
    fi
    
    cd "$ST_DIR" || return 1
    sillytavern_stop
    
    rm -f "$ST_LOG"
    local START_CMD="setsid nohup node $mem_args server.js > '$ST_LOG' 2>&1 & echo \$! > '$ST_PID_FILE'"
    
    if ui_spinner "启动酒馆服务..." "eval \"$START_CMD\""; then
        sleep 2
        if check_process_smart "$ST_PID_FILE" "node.*server.js"; then
            ui_print success "服务已启动。"
            return 0
        fi
    fi
    ui_print error "启动失败，请检查日志。"; return 1
}

sillytavern_stop() {
    _st_vars
    kill_process_safe "$ST_PID_FILE" "node.*server.js"
}

sillytavern_uninstall() {
    _st_vars
    ui_header "卸载 SillyTavern"
    [ ! -d "$ST_DIR" ] && { ui_print error "未安装。"; return; }
    
    if ! verify_kill_switch; then return; fi
    
    sillytavern_stop
    if ui_spinner "正在抹除酒馆数据..." "safe_rm '$ST_DIR'" ;
then
        ui_print success "卸载完成。"
        return 2
    fi
}

sillytavern_backup() {
    _st_vars
    ui_header "数据备份"
    [ ! -d "$ST_DIR" ] && { ui_print error "请先安装酒馆！"; ui_pause; return; }
    local dump_dir=$(ensure_backup_dir)
    if [ $? -ne 0 ]; then ui_pause; return; fi
    
    cd "$ST_DIR" || return
    local TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
    local BACKUP_FILE="$dump_dir/TAVX_Backup_SillyTavern_${TIMESTAMP}.tar.gz"
    
    local TARGETS="data"
    [ -f "secrets.json" ] && TARGETS="$TARGETS secrets.json"
    [ -d "plugins" ] && TARGETS="$TARGETS plugins"
    if [ -d "public/scripts/extensions/third-party" ]; then TARGETS="$TARGETS public/scripts/extensions/third-party"; fi
    
    echo -e "${CYAN}正在备份:${NC}"
    echo -e "$TARGETS" | tr ' ' '\n' | sed 's/^/  - /'
    echo ""
    if ui_spinner "正在打包..." "tar -czf '$BACKUP_FILE' $TARGETS 2>/dev/null"; then
        ui_print success "备份成功！"
        echo -e "位置: ${GREEN}$BACKUP_FILE${NC}"
    else
        ui_print error "备份失败。"
    fi
    ui_pause
}

sillytavern_restore() {
    _st_vars
    ui_header "数据恢复"
    [ ! -d "$ST_DIR" ] && { ui_print error "请先安装酒馆！"; ui_pause; return; }
    local dump_dir=$(ensure_backup_dir)
    if [ $? -ne 0 ]; then ui_pause; return; fi
    
    local files=($dump_dir/TAVX_Backup_*.tar.gz "$dump_dir/ST_Data_*.tar.gz"); local valid_files=()
    for f in "${files[@]}"; do [ -e "$f" ] && valid_files+=("$f"); done
    
    if [ ${#valid_files[@]} -eq 0 ]; then ui_print warn "无备份文件。"; ui_pause; return; fi
    
    local MENU_ITEMS=(); local FILE_MAP=()
    for file in "${valid_files[@]}"; do
        local fname=$(basename "$file")
        local fsize=$(du -h "$file" | awk '{print $1}')
        MENU_ITEMS+=("📦 $fname ($fsize)")
        FILE_MAP+=("$file")
    done
    MENU_ITEMS+=("🔙 返回")
    
    local CHOICE=$(ui_menu "选择备份文件" "${MENU_ITEMS[@]}")
    if [[ "$CHOICE" == *"返回"* ]]; then return; fi
    
    local selected_file=""
    for i in "${!MENU_ITEMS[@]}"; do if [[ "${MENU_ITEMS[$i]}" == "$CHOICE" ]]; then selected_file="${FILE_MAP[$i]}"; break; fi; done
    
    echo ""
    ui_print warn "警告: 这将覆盖现有的聊天记录！"
    if ! ui_confirm "确定要继续吗？"; then return; fi
    
    local TEMP_DIR="$TAVX_DIR/temp_restore"
    safe_rm "$TEMP_DIR"; mkdir -p "$TEMP_DIR"
    
    if ui_spinner "解压校验..." "tar -xzf '$selected_file' -C '$TEMP_DIR'"; then
        cd "$ST_DIR" || return
        ui_print info "正在导入..."
        if [ -d "$TEMP_DIR/data" ]; then
            if [ -d "data" ]; then mv data data_old_bak; fi
            if cp -r "$TEMP_DIR/data" .; then safe_rm "data_old_bak"; ui_print success "Data 恢复成功"; else safe_rm "data"; mv data_old_bak data; ui_print error "Data 恢复失败，已回滚"; ui_pause; return; fi
        fi
        if [ -f "$TEMP_DIR/secrets.json" ]; then cp "$TEMP_DIR/secrets.json" .; ui_print success "API Key 已恢复"; fi
        if [ -d "$TEMP_DIR/plugins" ]; then cp -r "$TEMP_DIR/plugins" .; ui_print success "服务端插件已恢复"; fi
        if [ -d "$TEMP_DIR/public/scripts/extensions/third-party" ]; then mkdir -p "public/scripts/extensions/third-party"; cp -r "$TEMP_DIR/public/scripts/extensions/third-party/." "public/scripts/extensions/third-party/"; ui_print success "前端扩展已恢复"; fi
        
        safe_rm "$TEMP_DIR"
        echo ""
        ui_print success "🎉 恢复完成！建议重启服务。"
    else
        ui_print error "解压失败！文件损坏。"
        safe_rm "$TEMP_DIR"
    fi
    ui_pause
}

sillytavern_configure_recommended() {
    _st_vars
    local BATCH_JSON='{ "extensions.enabled": true, "enableServerPlugins": true, "performance.useDiskCache": false }'
    _st_config_set_batch "$BATCH_JSON"
}

sillytavern_enable_public_access() {
    _st_vars
    ui_header "公网访问配置"
    echo -e "${YELLOW}此操作将执行以下变更：${NC}"
    echo -e "  1. 允许 0.0.0.0 外部访问 (穿透可用)"
    echo -e "  2. 自动开启[多用户系统]以保护数据安全"
    echo -e "  3. 开启隐私登录模式"
    echo ""
    
    if ! ui_confirm "确认立即开启吗？"; then return; fi
    
    local has_accounts=$(_st_config_get "enableUserAccounts")
    local has_auth=$(_st_config_get "basicAuthMode")
    
    if [[ "$has_accounts" != "true" && "$has_auth" != "true" ]]; then
        ui_print warn "检测到您尚未开启任何身份验证。为了公网安全，请立即设置一个管理员密码。"
        local u=$(ui_input "设置管理员账号" "default-user" "false")
        local p=$(ui_input "设置管理员密码" "" "true")
        if [ -n "$p" ]; then
            cd "$ST_DIR" || return
            node recover.js "$u" "$p" >/dev/null 2>&1
            ui_print success "管理员账号已创建：$u"
        else
            ui_print error "必须设置密码才能开启公网访问。操作已取消。"
            ui_pause; return 1
        fi
    fi

    ui_print info "正在应用安全网络配置..."
    local BATCH_JSON='{ "listen": true, "whitelistMode": false, "enableUserAccounts": true, "enableDiscreetLogin": true, "basicAuthMode": false }'
    
    if _st_config_set_batch "$BATCH_JSON"; then
        ui_print success "公网访问模式已开启！"
        echo -e "${GREEN}✅ 安全防护已就绪：${NC}"
        echo -e "   - 强制身份验证 [ON]"
        echo -e "   - 账号隔离系统 [ON]"
    else
        ui_print error "配置应用失败。"
    fi
    ui_pause
}

sillytavern_configure_advanced() {
    _st_vars
    [ ! -f "$ST_DIR/config.yaml" ] && { ui_print error "配置文件不存在，请先安装酒馆。"; ui_pause; return; }
    local CONFIG_MAP=( "SEPARATOR|--- 基础连接设置 ---" "listen|允许外部网络连接" "whitelistMode|白名单模式" "basicAuthMode|强制密码登录" "enableUserAccounts|多用户账号系统" "enableDiscreetLogin|谨慎登录模式" "SEPARATOR|--- 网络与安全进阶 ---" "disableCsrfProtection|禁用 CSRF 保护" "enableCorsProxy|启用 CORS 代理" "protocol.ipv6|启用 IPv6 协议支持" "ssl.enabled|启用 SSL/HTTPS" "hostWhitelist.enabled|Host 头白名单检查" "SEPARATOR|--- 性能与更新优化 ---" "performance.lazyLoadCharacters|懒加载角色卡 (启用极大提升启动速度)" "performance.useDiskCache|启用硬盘缓存 (termux建议关闭)" "extensions.enabled|加载扩展插件" "extensions.autoUpdate|自动更新扩展 (建议关闭)" "enableServerPlugins|加载服务端插件" "enableServerPluginsAutoUpdate|自动更新服务端插件" "SEPARATOR|--- 危险区域 ---" "RESET_CONFIG|⚠️ 恢复默认配置" )
    while true; do
        ui_header "酒馆配置管理"
        echo -e "${CYAN}点击条目即可切换状态${NC}"; echo "----------------------------------------"
        local MENU_OPTS=(); local KEY_LIST=()
        for item in "${CONFIG_MAP[@]}"; do
            local key="${item%%|*}"; local label="${item#*|}"
            if [ "$key" == "SEPARATOR" ]; then MENU_OPTS+=("📂 $label"); KEY_LIST+=("SEPARATOR"); continue; fi
            if [ "$key" == "RESET_CONFIG" ]; then MENU_OPTS+=("💥 $label"); KEY_LIST+=("RESET_CONFIG"); continue; fi
            local val=$(_st_config_get "$key"); local icon="🔴"; local stat="[关闭]"
            if [ "$val" == "true" ]; then icon="🟢"; stat="[开启]"; fi
            if [[ "$key" == "whitelistMode" || "$key" == "performance.useDiskCache" ]]; then if [ "$val" == "true" ]; then icon="🟡"; fi; fi
            MENU_OPTS+=("$icon $label $stat"); KEY_LIST+=("$key")
        done
        MENU_OPTS+=("🔙 返回上级")
        local CHOICE_IDX
        if [ "$HAS_GUM" = true ]; then
            local SELECTED_TEXT=$(gum choose "${MENU_OPTS[@]}" --header "" --cursor.foreground 212)
            for i in "${!MENU_OPTS[@]}"; do if [[ "${MENU_OPTS[$i]}" == "$SELECTED_TEXT" ]]; then CHOICE_IDX=$i; break; fi; done
        else
            local i=1; for opt in "${MENU_OPTS[@]}"; do echo "$i. $opt"; ((i++)); done
            read -p "请输入序号: " input_idx; if [[ "$input_idx" =~ ^[0-9]+$ ]]; then CHOICE_IDX=$((input_idx - 1)); fi
        fi
        if [[ "${MENU_OPTS[$CHOICE_IDX]}" == *"返回"* ]]; then return; fi
        if [ -n "$CHOICE_IDX" ] && [ "$CHOICE_IDX" -ge 0 ] && [ "$CHOICE_IDX" -lt "${#KEY_LIST[@]}" ]; then
            local target_key="${KEY_LIST[$CHOICE_IDX]}"
            if [ "$target_key" == "SEPARATOR" ]; then continue; fi
            if [ "$target_key" == "RESET_CONFIG" ]; then
                if ui_confirm "是否重置 config.yaml 至默认值？"; then 
                    rm -f "$ST_DIR/config.yaml"
                    ui_print success "配置已重置，正在自动重启服务以重新生成..."
                    sillytavern_start
                    return
                fi
                continue
            fi
            local current_val=$(_st_config_get "$target_key"); local new_val="true"
            if [ "$current_val" == "true" ]; then new_val="false"; fi
            if _st_config_set "$target_key" "$new_val"; then sleep 0.1; fi
        fi
    done
}

sillytavern_configure_memory() {
    ui_header "运行内存配置"
    local mem_info=$(free -m | grep "Mem:"); local total_mem=$(echo "$mem_info" | awk '{print $2}'); local avail_mem=$(echo "$mem_info" | awk '{print $7}')
    [[ -z "$total_mem" ]] && total_mem=0; [[ -z "$avail_mem" ]] && avail_mem=0
    local safe_max=$((total_mem - 2048)); if [ "$safe_max" -lt 1024 ]; then safe_max=1024; fi
    local curr_set="默认 (Node.js Auto)"; if [ -f "$TAVX_DIR/config/memory.conf" ]; then curr_set="$(cat "$TAVX_DIR/config/memory.conf") MB"; fi
    echo -e "物理内存: ${GREEN}${total_mem} MB${NC} | 可用: ${YELLOW}${avail_mem} MB${NC} | 当前: ${PURPLE}${curr_set}${NC}"
    echo "----------------------------------------"
    echo -e "请输入分配给酒馆的最大内存 (单位 MB)，输入 0 恢复默认。"
    local input_mem=$(ui_input "请输入 (例如 4096)" "" "false")
    if [[ ! "$input_mem" =~ ^[0-9]+$ ]]; then ui_print error "无效数字"; ui_pause; return; fi
    if [ "$input_mem" -eq 0 ]; then rm -f "$TAVX_DIR/config/memory.conf"; ui_print success "已恢复默认策略。"; else echo "$input_mem" > "$TAVX_DIR/config/memory.conf"; ui_print success "已设置: ${input_mem} MB"; fi
    ui_pause
}

sillytavern_configure_browser() {
    local BROWSER_CONF="$TAVX_DIR/config/browser.conf"
    while true; do
        ui_header "浏览器启动方式"
        local current_mode="ST"; if [ -f "$BROWSER_CONF" ]; then current_mode=$(cat "$BROWSER_CONF"); fi
        local yaml_stat=$(_st_config_get "browserLaunch.enabled"); [ -z "$yaml_stat" ] && yaml_stat="未知"
        echo -e "当前策略: $current_mode (Config: $yaml_stat)"; echo "----------------------------------------"
        local OPTS=("🚀 脚本接管" "🍷 SillyTavern 原生" "🚫 禁止自动跳转" "🔙 返回")
        local CHOICE=$(ui_menu "选择方式" "${OPTS[@]}")
        case "$CHOICE" in
            *"脚本"*) _st_config_set "browserLaunch.enabled" "false"; echo "SCRIPT" > "$BROWSER_CONF"; ui_print success "已切换：脚本接管"; ui_pause ;; 
            *"原生"*) _st_config_set "browserLaunch.enabled" "true"; echo "ST" > "$BROWSER_CONF"; ui_print success "已切换：原生模式"; ui_pause ;; 
            *"禁止"*) _st_config_set "browserLaunch.enabled" "false"; echo "NONE" > "$BROWSER_CONF"; ui_print success "已关闭自动跳转"; ui_pause ;; 
            *"返回"*) return ;; 
        esac
    done
}

sillytavern_change_port() {
    _st_vars
    local cur=$(_st_get_port)
    local new_p=$(ui_input_validated "设置新端口 (1024-65535)" "$cur" "numeric")
    [ -z "$new_p" ] && return
    
    if [ "$new_p" -lt 1024 ]; then ui_print error "端口过低"; ui_pause; return; fi
    if _st_config_set "port" "$new_p"; then
        ui_print success "端口已修改为 $new_p，请重启酒馆。"
        ui_pause
    fi
}

sillytavern_reset_password() {
    ui_header "重置密码"
    [ ! -d "$ST_DIR" ] && { ui_print error "未安装酒馆"; ui_pause; return; }
    cd "$ST_DIR" || return
    echo -e "${YELLOW}当前用户列表:${NC}"
    ls -F data/ | grep "/" | grep -v "^_" | sed 's|/||g' | sed 's/^/  - /'
    echo ""
    local u=$(ui_input "请输入要重置的用户名" "default-user" "false")
    local p=$(ui_input "请输入新密码" "" "true")
    
    if [[ -n "$u" && -n "$p" ]]; then
        echo ""
        if node recover.js "$u" "$p"; then
            ui_print success "密码已重置。"
        else
            ui_print error "重置失败，请确认用户名是否正确。"
        fi
    else
        ui_print warn "操作已取消。"
    fi
    ui_pause
}

sillytavern_configure_proxy() {
    while true; do
        ui_header "API 代理配置"
        local is_enabled=$(_st_config_get requestProxy.enabled)
        local current_url=$(_st_config_get requestProxy.url)
        [ -z "$current_url" ] && current_url="未设置"
        if [ "$is_enabled" == "true" ]; then echo -e "状态: ${GREEN}已开启${NC} | 地址: ${CYAN}$current_url${NC}"; else echo -e "状态: ${RED}已关闭${NC}"; fi
        echo "----------------------------------------"
        local OPTS=("🔄 同步系统代理" "✏️ 手动输入" "🚫 关闭代理" "🔙 返回")
        local CHOICE=$(ui_menu "选择操作" "${OPTS[@]}")
        case "$CHOICE" in
            *"同步"*) 
                local dyn=$(get_active_proxy "interactive")
                if [ -n "$dyn" ]; then 
                    _st_config_set requestProxy.enabled true
                    _st_config_set requestProxy.url "$dyn"
                    ui_print success "已同步代理: $dyn"
                else 
                    ui_print warn "未发现可用代理，请手动配置。"
                fi; ui_pause ;; 
            *"手动"*) local i=$(ui_input "代理地址" "" "false"); if [[ "$i" =~ ^http.* ]]; then _st_config_set requestProxy.enabled true; _st_config_set requestProxy.url "$i"; ui_print success "已保存"; else ui_print error "格式错误"; fi; ui_pause ;; 
            *"关闭"*) _st_config_set requestProxy.enabled false; ui_print success "已关闭"; ui_pause ;; 
            *"返回"*) return ;; 
        esac
    done
}

sillytavern_menu() {
    _st_vars
    if [ ! -d "$ST_DIR" ]; then
        ui_header "SillyTavern"
        ui_print warn "应用尚未安装。"
        if ui_confirm "立即安装？"; then sillytavern_install; else return; fi
    fi
    
    while true; do
        _st_vars
        local port=$(_st_get_port)
        local state="stopped"; local text="已停止"; local info=()
        
        if check_process_smart "$ST_PID_FILE" "node.*server.js"; then
            state="running"
            text="运行中"
        fi
        info+=( "端口: $port" )
        
        ui_header "SillyTavern 管理面板"
        ui_status_card "$state" "$text" "${info[@]}"
        
        local CHOICE=$(ui_menu "操作菜单" "🚀 启动/重启" "🛑 停止服务" "⚙️  应用配置" "🧩 插件管理" "⬇️  更新与版本" "💾 备份与恢复" "📜 查看日志" "🗑️  卸载模块" "🔙 返回")
        case "$CHOICE" in
            *"启动"*) sillytavern_start; ui_pause ;;
            *"停止"*) sillytavern_stop; ui_print success "已停止"; ui_pause ;;
            *"配置"*) _st_config_submenu ;;
            *"插件"*) app_plugin_menu ;;
            *"更新"*) _st_update_submenu ;;
            *"备份"*) _st_backup_submenu ;;
            *"日志"*) safe_log_monitor "$ST_LOG" ;;
            *"卸载"*) sillytavern_uninstall && [ $? -eq 2 ] && return ;;
            *"返回"*) return ;;
        esac
    done
}
_st_config_submenu() {
    while true; do
        ui_header "酒馆配置管理"
        local opt=$(ui_menu "选择项" "🌍 一键公网访问" "🔧 Config参数" "🧠 运行内存配置" "🌐 浏览器启动方式" "🔗 API 代理设置" "🔐 重置登录密码" "🔌 修改服务端口" "🔙 返回")
        case "$opt" in
            *"公网"*) sillytavern_enable_public_access ;; 
            *"参数"*) sillytavern_configure_advanced ;; 
            *"内存"*) sillytavern_configure_memory ;; 
            *"浏览器"*) sillytavern_configure_browser ;; 
            *"API"*) sillytavern_configure_proxy ;; 
            *"密码"*) sillytavern_reset_password ;; 
            *"端口"*) sillytavern_change_port ;; 
            *"返回"*) return ;; 
        esac
    done
}

_st_update_submenu() {
    local opt=$(ui_menu "更新管理" "🆕 检查并更新" "⏳ 版本时光机" "🔙 取消")
    case "$opt" in *"检查"*) sillytavern_update ;; *"时光机"*) sillytavern_rollback ;; esac
}

_st_backup_submenu() {
    local opt=$(ui_menu "备份管理" "📤 备份数据" "📥 恢复数据" "🔙 取消")
    case "$opt" in *"备份"*) sillytavern_backup ;; *"恢复"*) sillytavern_restore ;; esac
}

_st_get_port() {
    _st_vars
    local p=$(_st_config_get port)
    [[ "$p" =~ ^[0-9]+$ ]] && echo "$p" || echo "8000"
}

_st_config_ensure_yq() {
    if ! command -v yq &>/dev/null; then
        source "$TAVX_DIR/core/deps.sh"
        install_yq >/dev/null 2>&1
    fi
}

_st_config_get() {
    _st_vars
    _st_config_ensure_yq
    local key=".$1"
    local file="$ST_DIR/config.yaml"
    [ ! -f "$file" ] && return 1
    
    local val=$(yq "$key" "$file" 2>/dev/null)
    
    if [ "$val" == "null" ] || [ -z "$val" ]; then
        return 1
    else
        echo "$val"
        return 0
    fi
}

_st_config_set() {
    _st_vars
    _st_config_ensure_yq
    local key=".$1"
    local val="$2"
    local file="$ST_DIR/config.yaml"
    [ ! -f "$file" ] && return 1
    
    if [[ "$val" == "true" || "$val" == "false" ]]; then
        yq -i "$key = $val" "$file"
    elif [[ "$val" =~ ^[0-9]+$ ]]; then
        yq -i "$key = $val" "$file"
    else
        yq -i "$key = \"$val\"" "$file"
    fi
}

_st_config_set_batch() {
    _st_vars
    _st_config_ensure_yq
    local json="$1"
    local file="$ST_DIR/config.yaml"
    [ ! -f "$file" ] && return 1
    
    echo "$json" | yq -i '. * load("/dev/stdin")' "$file"
}

