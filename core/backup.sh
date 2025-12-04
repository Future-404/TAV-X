#!/bin/bash
# TAV-X Core: Backup & Restore (V2.2.3 Timestamp Fix)

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"

EXTERNAL_DIR="$HOME/storage/downloads/ST_Backup"

check_storage_permission() {
    if [ ! -d "$HOME/storage" ]; then
        ui_print warn "未检测到 storage 映射，尝试创建..."
        termux-setup-storage
        sleep 3
    fi

    if [ ! -d "$HOME/storage/downloads" ]; then
        ui_print error "无法访问存储目录 (Permission Denied)"
        ui_print info "请尝试手动运行: termux-setup-storage"
        return 1
    fi
    mkdir -p "$EXTERNAL_DIR"
    return 0
}

perform_backup() {
    ui_header "数据备份"
    if [ ! -d "$INSTALL_DIR" ]; then ui_print error "请先安装酒馆！"; ui_pause; return; fi
    check_storage_permission || { ui_pause; return; }

    cd "$INSTALL_DIR" || return
    
    local TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
    
    if [ -z "$TIMESTAMP" ]; then
        TIMESTAMP=$(date +%s)
    fi

    local BACKUP_FILE="$EXTERNAL_DIR/ST_Backup_$TIMESTAMP.tar.gz"
    local TARGETS="data config.yaml"
    [ -f "secrets.json" ] && TARGETS="$TARGETS secrets.json"
    
    if ui_spinner "正在打包数据..." "tar -czf '$BACKUP_FILE' $TARGETS 2>/dev/null"; then
        ui_print success "备份成功！"
        echo -e "位置: ${GREEN}Download/ST_Backup/$(basename "$BACKUP_FILE")${NC}"
    else
        ui_print error "备份失败。"
    fi
    ui_pause
}

perform_restore() {
    ui_header "数据恢复"
    if [ ! -d "$INSTALL_DIR" ]; then ui_print error "请先安装酒馆！"; ui_pause; return; fi
    check_storage_permission || { ui_pause; return; }
    
    local files=("$EXTERNAL_DIR"/ST_Backup_*.tar.gz)
    if [ ! -e "${files[0]}" ]; then ui_print warn "无备份文件。"; ui_pause; return; fi

    MENU_ITEMS=()
    for file in "${files[@]}"; do
        local fname=$(basename "$file")
        local fsize=$(du -h "$file" | awk '{print $1}')
        MENU_ITEMS+=("📦 $fname ($fsize)")
    done
    MENU_ITEMS+=("🔙 返回")

    CHOICE=$(ui_menu "请选择备份文件" "${MENU_ITEMS[@]}")
    if [[ "$CHOICE" == *"返回"* ]]; then return; fi
    
    local selected_name=$(echo "$CHOICE" | awk '{print $2}')
    local selected_file="$EXTERNAL_DIR/$selected_name"

    echo ""
    if ui_confirm "警告: 此操作将覆盖现有数据！确定吗？"; then
        local TEMP_DIR="$TAVX_DIR/temp_restore"
        local LOCAL_COPY="$TEMP_DIR/restore_target.tar.gz"
        
        safe_rm "$TEMP_DIR"; mkdir -p "$TEMP_DIR"
        
        if ! cp "$selected_file" "$LOCAL_COPY"; then
            ui_print error "无法读取备份文件，请检查存储权限！"
            ui_pause; return
        fi
        
        if ui_spinner "正在解压校验..." "tar -xzf '$LOCAL_COPY' -C '$TEMP_DIR'"; then
            cd "$INSTALL_DIR" || return
            
            ui_print info "校验通过，正在恢复..."
            
            if [ -d "$TEMP_DIR/data" ]; then 
                if [ -d "data" ]; then mv data data_old_tmp; fi
                
                if cp -r "$TEMP_DIR/data" .; then
                    safe_rm "data_old_tmp"
                    ui_print success "Data 恢复成功"
                else
                    ui_print error "Data 恢复失败！正在还原旧数据..."
                    safe_rm "data"
                    mv data_old_tmp data
                    ui_pause; return
                fi
            fi

            if [ -f "$TEMP_DIR/config.yaml" ]; then 
                cp "$TEMP_DIR/config.yaml" . 
                ui_print success "Config 恢复成功"
            fi
            if [ -f "$TEMP_DIR/secrets.json" ]; then 
                cp "$TEMP_DIR/secrets.json" .
            fi
            
            safe_rm "$TEMP_DIR"
            ui_print success "🎉 所有操作完成！请重启酒馆。"
        else
            ui_print error "解压失败！备份文件确实已损坏或格式错误。"
            safe_rm "$TEMP_DIR"
        fi
    else
        ui_print info "已取消。"
    fi
    ui_pause
}

backup_menu() {
    while true; do
        ui_header "备份与恢复"
        CHOICE=$(ui_menu "请选择功能" "📤 备份数据" "📥 恢复数据" "🔙 返回主菜单")
        case "$CHOICE" in
            *"备份"*) perform_backup ;;
            *"恢复"*) perform_restore ;;
            *"返回"*) return ;;
        esac
    done
}