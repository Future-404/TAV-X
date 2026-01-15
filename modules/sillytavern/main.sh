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

# Source Plugins
[ -f "$(dirname "${BASH_SOURCE[0]}")/plugins.sh" ] && source "$(dirname "${BASH_SOURCE[0]}")/plugins.sh"

_st_vars() {
    ST_APP_ID="sillytavern"
    ST_DIR=$(get_app_path "$ST_APP_ID")
    ST_PID_FILE="$RUN_DIR/sillytavern.pid"
    ST_LOG="$ST_DIR/server.log"
}

_st_get_port() {
    _st_vars
    if command -v yq &>/dev/null && [ -f "$ST_DIR/config.yaml" ]; then
         local p=$(yq ".port" "$ST_DIR/config.yaml" 2>/dev/null)
         [[ "$p" =~ ^[0-9]+$ ]] && echo "$p" || echo "8000"
    else
         echo "8000"
    fi
}

st_config_menu() {
    _st_vars
    export ST_DIR
    node "$TAVX_DIR/modules/sillytavern/config.js"
}

sillytavern_configure_recommended() {
    _st_vars
    export ST_DIR
    node "$TAVX_DIR/modules/sillytavern/config.js" --recommended
}

sillytavern_install() {
    _st_vars
    ui_header "SillyTavern 安装向导"
    
    if [ -d "$ST_DIR" ]; then
        ui_print warn "检测到旧版本或已存在目录: $ST_DIR"
        if ! ui_confirm "确认覆盖安装吗？(将清空该目录下所有数据)"; then return; fi
        safe_rm "$ST_DIR"
    fi
    
    mkdir -p "$(dirname "$ST_DIR")"
    
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
    
    if [ "$OS_TYPE" == "TERMUX" ]; then
        tavx_service_register "sillytavern" "node $mem_args server.js" "$ST_DIR"
        tavx_service_control "up" "sillytavern"
        ui_print success "服务启动命令已发送。"
    else
        cd "$ST_DIR" || return 1
        sillytavern_stop
        rm -f "$ST_LOG"
        local START_CMD="setsid nohup node $mem_args server.js > '$ST_LOG' 2>&1 & echo \$! > '$ST_PID_FILE'"
        ui_spinner "启动酒馆服务..." "eval \"$START_CMD\""
    fi
}

sillytavern_stop() {
    _st_vars
    if [ "$OS_TYPE" == "TERMUX" ]; then
        tavx_service_control "down" "sillytavern"
    else
        kill_process_safe "$ST_PID_FILE" "node.*server.js"
    fi
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
        MENU_ITEMS+=("$fname ($fsize)")
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
        
        if [ "$OS_TYPE" == "TERMUX" ]; then
            if sv status sillytavern 2>/dev/null | grep -q "^run:"; then
                state="running"
                text="运行中"
            fi
        elif check_process_smart "$ST_PID_FILE" "node.*server.js"; then
            state="running"
            text="运行中"
        fi
        info+=( "端口: $port" )
        
        ui_header "SillyTavern 管理面板"
        ui_status_card "$state" "$text" "${info[@]}"
        
        local CHOICE=$(ui_menu "操作菜单" "🚀 启动服务" "🛑 停止服务" "⚙️  应用配置" "🧩 插件管理" "⬇️  更新与版本" "💾 备份与恢复" "📜 查看日志" "🗑️  卸载模块" "🔙 返回")
        case "$CHOICE" in
            *"启动"*) sillytavern_start; ui_pause ;; 
            *"停止"*) sillytavern_stop; ui_print success "已停止"; ui_pause ;; 
            *"配置"*) st_config_menu ;; 
            *"插件"*) app_plugin_menu ;; 
            *"更新"*) _st_update_submenu ;; 
            *"备份"*) _st_backup_submenu ;; 
            *"日志"*) 
                local log_path="$ST_LOG"
                [ "$OS_TYPE" == "TERMUX" ] && log_path="$PREFIX/var/service/sillytavern/log/current"
                safe_log_monitor "$log_path" 
                ;; 
            *"卸载"*) sillytavern_uninstall && [ $? -eq 2 ] && return ;; 
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