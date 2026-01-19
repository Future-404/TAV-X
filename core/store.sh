#!/bin/bash
# TAV-X Core: App Store

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

INDEX_FILE="$TAVX_DIR/config/store.csv"

STORE_IDS=()
STORE_NAMES=()
STORE_DESCS=()
STORE_URLS=()
STORE_BRANCHES=()

_load_store_data() {
    STORE_IDS=()
    STORE_NAMES=()
    STORE_DESCS=()
    STORE_URLS=()
    STORE_BRANCHES=()
    
    if [ -f "$INDEX_FILE" ]; then
        while IFS=, read -r id name desc url branch; do
            [[ "$id" =~ ^#.*$ || -z "$id" ]] && continue
            STORE_IDS+=("$id")
            STORE_NAMES+=("$name")
            STORE_DESCS+=("$desc")
            STORE_URLS+=("$url")
            STORE_BRANCHES+=("$branch")
        done < "$INDEX_FILE"
    fi
    
    for mod_dir in "$TAVX_DIR/modules/"*; do
        [ ! -d "$mod_dir" ] && continue
        local id=$(basename "$mod_dir")
        local main_sh="$mod_dir/main.sh"
        [ ! -f "$main_sh" ] && continue
        local exists=false
        for existing_id in "${STORE_IDS[@]}"; do
            if [ "$existing_id" == "$id" ]; then exists=true; break; fi
        done
        if [ "$exists" = false ]; then
            local meta_name=$(grep "MODULE_NAME:" "$main_sh" | cut -d: -f2- | xargs)
            [ -z "$meta_name" ] && meta_name="$id"
            STORE_IDS+=("$id")
            STORE_NAMES+=("$meta_name")
            STORE_DESCS+=("本地已安装模块")
            STORE_URLS+=("local")
            STORE_BRANCHES+=("-")
        fi
    done
}

manage_shortcuts_menu() {
    local SHORTCUT_FILE="$TAVX_DIR/config/shortcuts.list"
    local raw_list=()
    
    for mod_dir in "$TAVX_DIR/modules/"*; do
        [ ! -d "$mod_dir" ] && continue
        local id=$(basename "$mod_dir")
        local main_sh="$mod_dir/main.sh"
        [ ! -f "$main_sh" ] && continue
        
        local name=$(grep "MODULE_NAME:" "$main_sh" | cut -d ':' -f 2- | xargs)
        [ -z "$name" ] && name="$id"
        
        local status="🟡"
        local app_path=$(get_app_path "$id")
        if [ -d "$app_path" ] && [ -n "$(ls -A "$app_path" 2>/dev/null)" ]; then
            status="🟢"
        fi
        
        raw_list+=("$status $name|$id")
    done
    
    if [ ${#raw_list[@]} -eq 0 ]; then
        ui_print warn "本地未发现任何模块。"
        ui_pause
        return
    fi
    
    IFS=$'\n' sorted_list=($(printf "%s\n" "${raw_list[@]}" | sort))
    
    local display_names=()
    local mapping_ids=()
    for item in "${sorted_list[@]}"; do
        display_names+=("${item%|*}")
        mapping_ids+=("${item#*|}")
    done
    
    local current_shortcuts=()
    if [ -f "$SHORTCUT_FILE" ]; then
        mapfile -t current_shortcuts < "$SHORTCUT_FILE"
    fi
    
    ui_header "⭐ 主页快捷方式"
    echo -e "  ${CYAN}勾选要固定在主菜单顶部的应用 (🟢=已安装 🟡=未安装)${NC}"
    if [ "$HAS_GUM" = true ]; then
        "$GUM_BIN" style --foreground "$C_DIM" "  按 <空格> 勾选，按 <回车> 提交保存"
        echo ""
    else
        echo "----------------------------------------"
    fi
    
    local new_selection=()
    
    if [ "$HAS_GUM" = true ]; then
        local selected_labels=()
        for cur in "${current_shortcuts[@]}"; do
            for i in "${!mapping_ids[@]}"; do
                if [ "${mapping_ids[$i]}" == "$cur" ]; then
                    selected_labels+=("${display_names[$i]}")
                    break
                fi
            done
        done
        
        export GUM_CHOOSE_SELECTED=$(IFS=,; echo "${selected_labels[*]}")
        local choices=$("$GUM_BIN" choose --no-limit --header="" --cursor="👉 " --cursor.foreground="$C_PINK" --selected.foreground="$C_PINK" -- "${display_names[@]}")
        unset GUM_CHOOSE_SELECTED
        
        new_selection=()
        IFS=$'\n' read -rd '' -a choices_arr <<< "$choices"
        for choice in "${choices_arr[@]}"; do
            [ -z "$choice" ] && continue
            for i in "${!display_names[@]}"; do
                if [ "${display_names[$i]}" == "$choice" ]; then
                    new_selection+=("${mapping_ids[$i]}")
                    break
                fi
            done
        done
    else
        for i in "${!display_names[@]}"; do
             local id="${mapping_ids[$i]}"
             local name="${display_names[$i]}"
             local is_pinned="false"
             for cur in "${current_shortcuts[@]}"; do [[ "$cur" == "$id" ]] && is_pinned="true"; done
             
             local mark="[ ]"; [ "$is_pinned" == "true" ] && mark="[x]"
             if ui_confirm "$mark 显示 $name ?"; then
                 new_selection+=("$id")
             fi
        done
    fi
    
    printf "%s\n" "${new_selection[@]}" > "$SHORTCUT_FILE"
    ui_print success "快捷方式已更新！"
    ui_pause
}

app_store_menu() {
    while true; do
        _load_store_data
        ui_header "🛒 应用中心"
        
        local MENU_OPTS=()
        MENU_OPTS+=("⭐ 管理主页快捷方式")
        MENU_OPTS+=("------------------------")
        
        for i in "${!STORE_IDS[@]}"; do
            local id="${STORE_IDS[$i]}"
            local name="${STORE_NAMES[$i]}"
            local status="☁️"
            local mod_path="$TAVX_DIR/modules/$id"
            local app_path=$(get_app_path "$id")
            if [ -d "$mod_path" ] && [ -f "$mod_path/main.sh" ]; then
                if [ -d "$app_path" ] && [ -n "$(ls -A "$app_path" 2>/dev/null)" ]; then
                    status="🟢"
                else
                    status="🟡"
                fi
            fi
            
            MENU_OPTS+=("$status $name")
        done
        
        MENU_OPTS+=("🔄 刷新列表")
        MENU_OPTS+=("🔙 返回主菜单")
        
        local CHOICE=$(ui_menu "全部应用" "${MENU_OPTS[@]}")
        
        if [[ "$CHOICE" == *"快捷方式"* ]]; then manage_shortcuts_menu; continue; fi
        if [[ "$CHOICE" == *"----"* ]]; then continue; fi
        if [[ "$CHOICE" == *"返回"* ]]; then return; fi
        if [[ "$CHOICE" == *"刷新"* ]]; then _refresh_store_index; continue; fi
        
        local selected_idx=-1
        local offset=2
        
        for i in "${!MENU_OPTS[@]}"; do
            if [ $i -lt $offset ]; then continue; fi
            local clean_opt="${MENU_OPTS[$i]}"
            if [[ "$CHOICE" == *"$clean_opt"* ]] || [[ "$CHOICE" == "$clean_opt" ]]; then
                selected_idx=$((i - offset))
                break
            fi
        done
        
        if [ $selected_idx -ge 0 ] && [ $selected_idx -lt ${#STORE_IDS[@]} ]; then
            _app_store_action $selected_idx
        fi
    done
}

_refresh_store_index() {
    ui_print info "正在连接云端列表..."
    sleep 0.5
    ui_print success "列表已更新"
}

_app_store_action() {
    local idx=$1
    local id="${STORE_IDS[$idx]}"
    
    if [ -z "$id" ]; then
        ui_print error "内部错误: 无效的应用 ID (Index: $idx)"
        return
    fi
    
    local name="${STORE_NAMES[$idx]}"
    local desc="${STORE_DESCS[$idx]}"
    local url="${STORE_URLS[$idx]}"
    local branch="${STORE_BRANCHES[$idx]}"
    local mod_path="$TAVX_DIR/modules/$id"
    local app_path=$(get_app_path "$id")
    
    local state="remote"
    if [ -d "$mod_path" ] && [ -f "$mod_path/main.sh" ]; then
        if [ -d "$app_path" ] && [ -n "$(ls -A "$app_path" 2>/dev/null)" ]; then
            state="installed"
        else
            state="pending"
        fi
    fi
    
    ui_header "应用详情: $name"
    echo -e "📝 描述: $desc"
    echo -e "🔗 仓库: $url"
    echo "----------------------------------------"
    
    case "$state" in
        "remote")
            echo -e "状态: ${BLUE}☁️ 云端${NC}"
            if ui_menu "选择操作" "📥 获取模块脚本" "🔙 返回" | grep -q "获取"; then
                prepare_network_strategy "Module Fetch"
                local final_url=$(get_dynamic_repo_url "$url")
                
                local CMD="mkdir -p '$mod_path'; git clone -b $branch '$final_url' '$mod_path'"
                if ui_stream_task "正在获取脚本..." "$CMD"; then
                    chmod +x "$mod_path"/*.sh 2>/dev/null
                    ui_print success "脚本获取成功！"
                    source "$TAVX_DIR/core/loader.sh"
                    scan_and_load_modules
                    if ui_confirm "是否立即安装应用本体？"; then
                        _trigger_app_install "$id"
                    fi
                else
                    ui_print error "获取失败。"
                    safe_rm "$mod_path"
                fi
            fi
            ;;
            
        "pending")
            echo -e "状态: ${YELLOW}🟡 待部署${NC}"
            local ACT=$(ui_menu "选择操作" "📦 安装应用本体" "🗑️ 删除模块脚本" "🔙 返回")
            case "$ACT" in
                *"安装"*) _trigger_app_install "$id" ;;
                *"删除"*) 
                    if ui_confirm "删除模块脚本？"; then
                        safe_rm "$mod_path"
                        source "$TAVX_DIR/core/loader.sh"
                        scan_and_load_modules
                        ui_print success "已删除。"
                    fi 
                    ;;
            esac
            ;;
            
        "installed")
            echo -e "状态: ${GREEN}🟢 已就绪${NC}"
            local ACT=$(ui_menu "选择操作" "🚀 管理/启动" "🔄 更新模块脚本" "🔙 返回")
            case "$ACT" in
                *"管理"*)
                    if [ -f "$mod_path/main.sh" ]; then
                        local entry=$(grep "MODULE_ENTRY:" "$mod_path/main.sh" | cut -d: -f2 | xargs)
                        if [ -n "$entry" ]; then
                            source "$mod_path/main.sh"
                            $entry
                        else
                            ui_print error "无法识别入口函数。"
                        fi
                    fi
                    ;;
                *"更新"*)
                    ui_stream_task "更新脚本..." "cd '$mod_path' && git pull"
                    ui_print success "脚本已更新。"
                    ;;
            esac
            ;;
    esac
}

_trigger_app_install() {
    local id=$1
    local mod_path="$TAVX_DIR/modules/$id"
    local install_func="${id}_install"
    
    ui_header "安装应用: $id"
    if [ -f "$mod_path/main.sh" ]; then
        (
            source "$mod_path/main.sh"
            if command -v "$install_func" &>/dev/null; then
                "$install_func"
            else
                if command -v app_install &>/dev/null; then
                    app_install
                else
                    ui_print error "模块未提供安装接口 ($install_func)。"
                fi
            fi
        )
        source "$TAVX_DIR/core/loader.sh"
        scan_and_load_modules
    else
        ui_print error "模块脚本丢失。"
    fi
    ui_pause
}
