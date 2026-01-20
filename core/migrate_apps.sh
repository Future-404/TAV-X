#!/bin/bash
# TAV-X Application Migration Script

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"

migrate_legacy_apps() {
    ui_header "应用数据迁移"
    
    local standard_tavx=""
    if [ -n "$TERMUX_VERSION" ]; then
        standard_tavx="/data/data/com.termux/files/home/.tav_x"
    else
        standard_tavx="$HOME/.tav_x"
    fi

    local source_dirs=()
    source_dirs+=("$TAVX_DIR")
    [ "$TAVX_DIR" != "$standard_tavx" ] && [ -d "$standard_tavx" ] && source_dirs+=("$standard_tavx")

    echo "正在扫描旧版应用数据..."
    echo "目标目录: $APPS_DIR"
    echo ""

    mkdir -p "$APPS_DIR"
    local count=0
    local skipped=0

    for s_dir in "${source_dirs[@]}"; do
        local source_apps_dir="$s_dir/apps"
        if [ -d "$source_apps_dir" ]; then
            echo "🔎 扫描目录: $source_apps_dir"
            shopt -s nullglob
            for app in "$source_apps_dir"/*; do
                [ ! -d "$app" ] && continue
                local app_name
                app_name=$(basename "$app")
                
                if [ -d "$APPS_DIR/$app_name" ]; then
                    echo "⚠️  $app_name: 目标已存在，跳过迁移。"
                    ((skipped++))
                    continue
                fi

                echo "📦 正在迁移: $app_name ..."
                if mv "$app" "$APPS_DIR/"; then
                    success "迁移成功: $app_name"
                    ((count++))
                else
                    error "迁移失败: $app_name"
                fi
            done
            shopt -u nullglob
            rmdir "$source_apps_dir" 2>/dev/null
        fi

        local potential_roots=("clewdr" "gemini" "mihomo" "autoglm" "sillytavern_extras")
        for folder in "${potential_roots[@]}"; do
            local src="$s_dir/$folder"
            local dest_name="$folder"
            [ "$folder" == "clewdr" ] && dest_name="clewd"
            
            if [ -d "$src" ] && [ -n "$(ls -A "$src" 2>/dev/null)" ]; then
                 if [ -d "$APPS_DIR/$dest_name" ]; then
                    echo "⚠️  $dest_name (旧版): 目标已存在，跳过迁移。"
                    ((skipped++))
                    continue
                fi
                
                echo "📦 正在迁移旧版根目录: $folder -> $dest_name ..."
                if mv "$src" "$APPS_DIR/$dest_name"; then
                    success "迁移成功: $dest_name"
                    ((count++))
                else
                    error "迁移失败: $dest_name"
                fi
            fi
        done
    done

    echo ""
    if [ "$count" -gt 0 ]; then
        ui_print success "迁移完成: 成功 $count 个，跳过 $skipped 个 (已存在)。"
    elif [ "$skipped" -gt 0 ]; then
        ui_print warn "未执行迁移: $skipped 个应用在目标位置已存在。"
    else
        ui_print info "未发现需要迁移的应用。"
    fi
    
    ui_pause
}

export -f migrate_legacy_apps