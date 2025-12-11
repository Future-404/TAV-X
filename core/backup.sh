v#!/bin/bash
# TAV-X Core: Backup & Restore

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
    ui_header "数据备份 (优化版)"
    if [ ! -d "$INSTALL_DIR" ]; then ui_print error "请先安装酒馆！"; ui_pause; return; fi
    check_storage_permission || { ui_pause; return; }

    cd "$INSTALL_DIR" || return
    
    local TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
    [ -z "$TIMESTAMP" ] && TIMESTAMP=$(date +%s)

    local BACKUP_FILE="$EXTERNAL_DIR/ST_Data_${TIMESTAMP}.tar.gz"
    
    local TARGETS="data"
    [ -f "secrets.json" ] && TARGETS="$TARGETS secrets.json"
    [ -d "plugins" ] && TARGETS="$TARGETS plugins"
    if [ -d "public/scripts/extensions/third-party" ]; then
        TARGETS="$TARGETS public/scripts/extensions/third-party"
    fi
    
    echo -e "${CYAN}正在备份以下内容:${NC}"
    echo -e "$TARGETS" | tr ' ' '\n' | sed 's/^/  - /'
    echo ""

    if ui_spinner "正在打包数据..." "tar -czf '$BACKUP_FILE' $TARGETS 2>/dev/null"; then
        ui_print success "备份成功！"
        echo -e "位置: ${GREEN}Download/ST_Backup/$(basename "$BACKUP_FILE")${NC}"
        echo -e "${YELLOW}提示: 此备份不含 config.yaml，恢复后将重置系统设置。${NC}"
    else
        ui_print error "备份失败。"
    fi
    ui_pause
}

perform_restore() {
    ui_header "数据恢复 (智能覆盖)"
    if [ ! -d "$INSTALL_DIR" ]; then ui_print error "请先安装酒馆！"; ui_pause; return; fi
    check_storage_permission || { ui_pause; return; }
    
    local files=("$EXTERNAL_DIR"/ST_*.tar.gz)
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
    ui_print warn "警告: 这将覆盖现有的聊天记录和角色卡！"
    if ui_confirm "确定要继续吗？"; then
        local TEMP_DIR="$TAVX_DIR/temp_restore"
        local LOCAL_COPY="$TEMP_DIR/restore_target.tar.gz"
        
        safe_rm "$TEMP_DIR"; mkdir -p "$TEMP_DIR"
        
        if ! cp "$selected_file" "$LOCAL_COPY"; then
            ui_print error "无法读取备份文件，请检查存储权限！"
            ui_pause; return
        fi
        
        if ui_spinner "正在解压校验..." "tar -xzf '$LOCAL_COPY' -C '$TEMP_DIR'"; then
            cd "$INSTALL_DIR" || return
            
            ui_print info "开始导入数据..."
            
            if [ -d "$TEMP_DIR/data" ]; then 
                if [ -d "data" ]; then mv data data_old_bak; fi
                
                if cp -r "$TEMP_DIR/data" .; then
                    safe_rm "data_old_bak"
                    ui_print success "核心数据 (Data) 恢复成功"
                else
                    ui_print error "Data 恢复失败！正在回滚..."
                    safe_rm "data"
                    mv data_old_bak data
                    ui_pause; return
                fi
            fi

            if [ -f "$TEMP_DIR/secrets.json" ]; then 
                cp "$TEMP_DIR/secrets.json" .
                ui_print success "API 密钥 (Root) 已恢复"
            fi
            
            if [ -d "$TEMP_DIR/plugins" ]; then
                ui_print info "正在恢复服务端插件..."
                cp -r "$TEMP_DIR/plugins" .
            fi
            
            if [ -d "$TEMP_DIR/public/scripts/extensions/third-party" ]; then
                ui_print info "正在恢复前端扩展..."
                mkdir -p "public/scripts/extensions/third-party"
                cp -r "$TEMP_DIR/public/scripts/extensions/third-party/." "public/scripts/extensions/third-party/"
            fi
            
            if [ -f "$TEMP_DIR/config.yaml" ]; then 
                 echo ""
                 if ui_confirm "检测到备份含旧版配置文件，是否恢复？(推荐否)"; then
                    cp "$TEMP_DIR/config.yaml" .
                    ui_print success "旧版 Config 已恢复"
                 else
                    ui_print info "已跳过旧版配置，保持当前系统设置。"
                 fi
            fi
            
            safe_rm "$TEMP_DIR"
            echo ""
            ui_print success "🎉 恢复完成！建议重启酒馆服务。"
        else
            ui_print error "解压失败！文件可能已损坏。"
            safe_rm "$TEMP_DIR"
        fi
    else
        ui_print info "已取消。"
    fi
    ui_pause
}

backup_menu() {
    while true; do
        ui_header "备份与恢复 (Data Only)"
        CHOICE=$(ui_menu "请选择功能" "📤 备份核心数据+插件" "📥 恢复数据" "🔙 返回主菜单")
        case "$CHOICE" in
            *"备份"*) perform_backup ;;
            *"恢复"*) perform_restore ;;
            *"返回"*) return ;;
        esac
    done
}