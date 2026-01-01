#!/bin/bash
# TAV-X Core: UI Adapter
[ -n "$_TAVX_UI_LOADED" ] && return
_TAVX_UI_LOADED=true

HAS_GUM=false
if command -v gum &> /dev/null; then HAS_GUM=true; fi

C_PINK=212    
C_PURPLE=99   
C_DIM=240     
C_GREEN=82    
C_RED=196     
C_BLUE=39     
C_YELLOW=220  

get_ascii_logo() {
    cat << "LOGO_END"
████████╗░█████╗░██╗░░░██╗  ██╗░░██╗
╚══██╔══╝██╔══██╗██║░░░██║  ╚██╗██╔╝
░░░██║░░░███████║╚██╗░██╔╝  ░╚███╔╝░
░░░██║░░░██╔══██║░╚████╔╝░  ░██╔██╗░
░░░██║░░░██║░░██║░░╚██╔╝░░  ██╔╝╚██╗
░░░╚═╝░░░╚═╝░░╚═╝░░░╚═╝░░░  ╚═╝░░╚═╝
                T A V   X
LOGO_END
}

ui_header() {
    local subtitle="$1"
    local ver="${CURRENT_VERSION:-v2.0-beta}"
    
    clear
    if [ "$HAS_GUM" = true ]; then
        local logo=$(gum style --foreground $C_PINK "$(get_ascii_logo)")
        local v_tag=$(gum style --foreground $C_DIM --align right "Ver: $ver | by Future 404  ")
        echo "$logo"
        echo "$v_tag"
        
        if [ -n "$subtitle" ]; then
            local prefix=$(gum style --foreground $C_PURPLE --bold "  🚀 ")
            local divider=$(gum style --foreground $C_DIM "  ───────────────────────────────────────")
            echo -e "${prefix}${subtitle}"
            echo "$divider"
        fi
    else
        get_ascii_logo
        echo "Ver: $ver | by Future 404"
        echo "----------------------------------------"
        [ -n "$subtitle" ] && echo -e ">>> $subtitle\n----------------------------------------"
    fi
}

ui_dashboard() {
    local st=$1; local cf=$2; local adb=$3
    local net_dl="$4"; local net_api="$5"
    local clewd="${6:-0}"; local gemini="${7:-0}"; local audio="${8:-0}"

    if [ "$HAS_GUM" = true ]; then
        make_dynamic_badge() {
            local label="$1"; local state="$2"
            if [ "$state" == "1" ]; then
                echo "$(gum style --foreground $C_GREEN "●") $label"
            fi
        }

        local spacer="      "

        local active_items=()
        
        [ "$st" == "1" ]     && active_items+=("$(make_dynamic_badge "酒馆" $st)")
        [ "$cf" == "1" ]     && active_items+=("$(make_dynamic_badge "穿透" $cf)")
        [ "$adb" == "1" ]    && active_items+=("$(make_dynamic_badge "ADB" $adb)")
        [ "$audio" == "1" ]  && active_items+=("$(make_dynamic_badge "🎵保活" $audio)")
        [ "$clewd" == "1" ]  && active_items+=("$(make_dynamic_badge "ClewdR" $clewd)")
        [ "$gemini" == "1" ] && active_items+=("$(make_dynamic_badge "Gemini" $gemini)")

        local line1=""
        if [ ${#active_items[@]} -eq 0 ]; then
            line1=$(gum style --foreground $C_DIM "💤 等待服务启动...")
        else
            for item in "${active_items[@]}"; do
                line1="${line1}${item}${spacer}"
            done
        fi
        
        local line2=$(gum join --vertical --align center \
            "$(gum style --foreground $C_BLUE "网络: $net_dl")" \
            "$(gum style --foreground $C_PURPLE "API : $net_api")" \
        )

        gum style --border normal --border-foreground $C_DIM --padding "0 1" --margin "0 0 1 0" --align center "$line1" "" "$line2"
    else
        echo "运行中: ST[$st] CF[$cf] ADB[$adb] Audio[$audio] Clewd[$clewd] Gemini[$gemini]"
        echo "下载: $net_dl"
        echo "API : $net_api"
        echo "----------------------------------------"
    fi
}

ui_menu() {
    local header="$1"; shift; local options=("$@")
    if [ "$HAS_GUM" = true ]; then
        gum choose --header="" --cursor.foreground $C_PINK --selected.foreground $C_PINK "${options[@]}"
    else
        echo -e "\n[ $header ]"; local i=1
        for opt in "${options[@]}"; do echo "$i. $opt"; ((i++)); done
        read -p "请输入编号: " idx; echo "${options[$((idx-1))]}"
    fi
}

ui_input() {
    local prompt="$1"; local default="$2"; local is_pass="$3"
    if [ "$HAS_GUM" = true ]; then
        local args=(--placeholder "$prompt" --width 40 --cursor.foreground $C_PINK)
        [ -n "$default" ] && args+=(--value "$default")
        [ "$is_pass" = "true" ] && args+=(--password)
        gum input "${args[@]}"
    else
        local flag=""; [ "$is_pass" = "true" ] && flag="-s"
        read $flag -p "$prompt [$default]: " val; echo "${val:-$default}"
    fi
}

ui_confirm() {
    local prompt="$1"
    if [ "$HAS_GUM" = true ]; then
        gum confirm "$prompt" --affirmative "是" --negative "否" --selected.background $C_PINK
    else
        read -p "$prompt (y/n): " c; [[ "$c" == "y" || "$c" == "Y" ]]
    fi
}

ui_spinner() {
    local title="$1"; shift; local cmd="$@"
    if [ "$HAS_GUM" = true ]; then
        gum spin --spinner dot --title "$title" --title.foreground $C_PURPLE --show-output -- bash -c "$cmd"
    else
        echo ">>> $title"; eval "$cmd"
    fi
}

ui_print() {
    local type="$1"; local msg="$2"
    if [ "$HAS_GUM" = true ]; then
        case $type in
            success) gum style --foreground $C_GREEN "✔ $msg" ;;
            error)   gum style --foreground $C_RED   "✘ $msg" ;;
            warn)    gum style --foreground $C_YELLOW "⚠ $msg" ;;
            *)       gum style --foreground $C_PURPLE "ℹ $msg" ;;
        esac
    else echo "[$type] $msg"; fi
}

ui_pause() {
    if [ "$HAS_GUM" = true ]; then
        echo ""; gum style --foreground $C_DIM "按任意键继续..."; read -n 1 -s -r
    else
        echo ""; read -n 1 -s -r -p "按任意键继续..."
    fi
}