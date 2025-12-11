#!/bin/bash
# TAV-X Core: Update Center

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"
source "$TAVX_DIR/core/install.sh"

check_for_updates() {
    [ ! -d "$TAVX_DIR/.git" ] && return
    (
        cd "$TAVX_DIR" || exit
        if git fetch origin --quiet --timeout=10; then
            LOCAL=$(git rev-parse HEAD)
            REMOTE=$(git rev-parse @{u})
            [ "$LOCAL" != "$REMOTE" ] && echo "true" > "$TAVX_DIR/.update_available" || rm -f "$TAVX_DIR/.update_available"
        fi
    ) >/dev/null 2>&1 &
}

update_sillytavern() {
    ui_header "SillyTavern 智能更新"
    
    if [ ! -d "$INSTALL_DIR/.git" ]; then
        ui_print error "未检测到有效的 Git 仓库。"
        ui_pause; return
    fi

    cd "$INSTALL_DIR" || return
    if ! git symbolic-ref -q HEAD >/dev/null; then
        local current_tag=$(git describe --tags --exact-match 2>/dev/null || git rev-parse --short HEAD)
        ui_print warn "当前处于版本锁定状态 ($current_tag)"
        echo -e "${YELLOW}请先 [解除锁定] 后再尝试更新。${NC}"
        ui_pause; return
    fi

    prepare_network_strategy "SillyTavern/SillyTavern"

    local UPDATE_CMD="source \"$TAVX_DIR/core/utils.sh\"; fix_git_remote \"$INSTALL_DIR\" \"SillyTavern/SillyTavern\"; cd \"$INSTALL_DIR\"; git pull --autostash"
    
    if ui_spinner "正在同步最新代码..." "$UPDATE_CMD"; then
        ui_print success "代码同步完成。"
        echo ""
        if npm_install_smart "$INSTALL_DIR"; then
            ui_print success "依赖更新完成！"
        else
            ui_print warn "依赖更新遇到问题。"
        fi
    else
        ui_print error "更新失败！可能存在冲突或网络问题。"
    fi
    ui_pause
}

rollback_sillytavern() {
    while true; do
        ui_header "版本时光机"
        cd "$INSTALL_DIR" || return
        
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
        
        local TAG_CACHE="$TAVX_DIR/.tag_cache"
        local CACHE_STATUS=""
        if [ -f "$TAG_CACHE" ]; then CACHE_STATUS="(Cached)"; fi
        
        echo -e "当前状态: $CURRENT_DESC"
        echo "----------------------------------------"
        
        local MENU_ITEMS=()
        [ "$IS_DETACHED" = true ] && MENU_ITEMS+=("🔓 解除锁定 (恢复最新版)")
        MENU_ITEMS+=("⏳ 回退至历史版本 $CACHE_STATUS")
        MENU_ITEMS+=("🔄 强制刷新版本列表")
        MENU_ITEMS+=("🔀 切换通道: Release")
        MENU_ITEMS+=("🔀 切换通道: Staging")
        MENU_ITEMS+=("🔙 返回")
        
        CHOICE=$(ui_menu "请选择操作" "${MENU_ITEMS[@]}")
        
        case "$CHOICE" in
            *"解除锁定"*)
                if ui_confirm "确定恢复到最新 Release 版？"; then
                    prepare_network_strategy "SillyTavern/SillyTavern"
                    local RESTORE="source \"$TAVX_DIR/core/utils.sh\"; fix_git_remote \"$INSTALL_DIR\" \"SillyTavern/SillyTavern\"; git config remote.origin.fetch \"+refs/heads/*:refs/remotes/origin/*\"; git fetch origin release --depth=1; git reset --hard origin/release; git checkout release"
                    if ui_spinner "正在归队..." "$RESTORE"; then
                        echo ""; npm_install_smart "$INSTALL_DIR"
                        ui_print success "已恢复！"
                    else ui_print error "恢复失败"; fi
                fi
                ui_pause ;;
            *"强制刷新"*)
                rm -f "$TAG_CACHE"
                ui_print info "缓存已清除。"
                sleep 0.5 ;;
            *"回退至历史版本"*)
                prepare_network_strategy "SillyTavern/SillyTavern"
                if [ ! -f "$TAG_CACHE" ]; then
                    local FETCH="source \"$TAVX_DIR/core/utils.sh\"; fix_git_remote \"$INSTALL_DIR\" \"SillyTavern/SillyTavern\"; git fetch --tags"
                    if ! ui_spinner "云端获取中..." "$FETCH"; then
                        ui_print error "获取失败"; ui_pause; continue
                    fi
                    git tag --sort=-v:refname | head -n 10 > "$TAG_CACHE"
                fi
                mapfile -t TAG_LIST < "$TAG_CACHE"
                if [ ${#TAG_LIST[@]} -eq 0 ]; then ui_print warn "列表为空"; rm -f "$TAG_CACHE"; ui_pause; continue; fi
                TAG_LIST+=("🔙 取消")
                TAG_CHOICE=$(ui_menu "选择版本" "${TAG_LIST[@]}")
                if [[ "$TAG_CHOICE" != *"取消"* ]]; then
                    echo -e "${RED}警告：即将重置核心文件以解决冲突。${NC}"
                    if ui_confirm "确认回退到 $TAG_CHOICE ？"; then
                        local ROLLBACK_CMD="source \"$TAVX_DIR/core/utils.sh\"; fix_git_remote \"$INSTALL_DIR\" \"SillyTavern/SillyTavern\"; git fetch origin tag \"$TAG_CHOICE\" --depth=1; git reset --hard; git checkout \"$TAG_CHOICE\""
                        if ui_spinner "时光倒流..." "$ROLLBACK_CMD"; then
                            echo ""; npm_install_smart "$INSTALL_DIR"
                            ui_print success "已锁定在 $TAG_CHOICE"
                        else ui_print error "切换失败"; fi
                    fi
                fi
                ui_pause ;;
            *"切换通道"*)
                local TARGET=""; [[ "$CHOICE" == *"Release"* ]] && TARGET="release"; [[ "$CHOICE" == *"Staging"* ]] && TARGET="staging"
                prepare_network_strategy "SillyTavern/SillyTavern"
                local SW_CMD="source \"$TAVX_DIR/core/utils.sh\"; fix_git_remote \"$INSTALL_DIR\" \"SillyTavern/SillyTavern\"; git config remote.origin.fetch \"+refs/heads/*:refs/remotes/origin/*\"; git fetch origin $TARGET --depth=1; git reset --hard origin/$TARGET; git checkout $TARGET"
                if ui_spinner "切换至 $TARGET..." "$SW_CMD"; then
                    echo ""; npm_install_smart "$INSTALL_DIR"
                    ui_print success "切换成功！"
                else ui_print error "切换失败"; fi
                ui_pause ;;
            *"返回"*) return ;;
        esac
    done
}

perform_self_update() {
    prepare_network_strategy "Future-404/TAV-X.git"
    local UPD_CMD="source \"$TAVX_DIR/core/utils.sh\"; fix_git_remote \"$TAVX_DIR\" \"Future-404/TAV-X.git\"; cd \"$TAVX_DIR\"; CURr=\$(git rev-parse --abbrev-ref HEAD); git fetch --all && git reset --hard origin/\$CURr"
    if ui_spinner "更新脚本..." "$UPD_CMD"; then
        rm -f "$TAVX_DIR/.update_available"; chmod +x st.sh core/*.sh modules/*.sh scripts/*.js 2>/dev/null
        ui_print success "完成！重启中..."; sleep 1; exec bash "$TAVX_DIR/st.sh"
    else ui_print error "失败"; ui_pause; fi
}

update_center_menu() {
    while true; do
        ui_header "安装与更新管理"
        cd "$TAVX_DIR" || return
        TAV_VER_DISP="${CURRENT_VERSION:-Unknown} ($(git rev-parse --short HEAD))"
        ST_VER_DISP="未安装"; local st_installed=false
        if [ -d "$INSTALL_DIR/.git" ]; then
            cd "$INSTALL_DIR"
            if ! git symbolic-ref -q HEAD >/dev/null; then
                ST_VER_DISP="${YELLOW}🔒 $(git describe --tags --exact-match 2>/dev/null || git rev-parse --short HEAD)${NC}"
            else
                ST_VER_DISP="$(git rev-parse --abbrev-ref HEAD) ($(git rev-parse --short HEAD))"
            fi
            st_installed=true
        fi
        
        echo "脚本: $TAV_VER_DISP"; echo -e "酒馆: $ST_VER_DISP"; echo "----------------------------------------"
        [ -f "$TAVX_DIR/.update_available" ] && ui_print warn "🔔 脚本有新版本可用！"
        
        MENU_ITEMS=()
        [ "$st_installed" = true ] && MENU_ITEMS+=("🍷 更新 SillyTavern") && MENU_ITEMS+=("🔙 版本回退/切换") || MENU_ITEMS+=("📥 安装 SillyTavern")
        MENU_ITEMS+=("📜 更新 TAV-X 脚本")
        MENU_ITEMS+=("🔙 返回主菜单")
        
        CHOICE=$(ui_menu "请选择操作" "${MENU_ITEMS[@]}")
        case "$CHOICE" in
            *"更新 SillyTavern"*) update_sillytavern ;;
            *"安装 SillyTavern"*) install_sillytavern ;;
            *"版本回退"*) rollback_sillytavern ;;
            *"更新 TAV-X"*) perform_self_update ;;
            *"返回"*) return ;;
        esac
    done
}