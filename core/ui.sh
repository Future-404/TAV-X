#!/bin/bash
# TAV-X Core: UI Adapter (V5.8 Minimalist Fix)

HAS_GUM=false
if command -v gum &> /dev/null; then HAS_GUM=true; fi

# --- 🎨 配色方案 ---
C_PINK=212    
C_PURPLE=99   
C_DIM=240     
C_GREEN=82    
C_RED=196     
C_BLUE=39     
C_YELLOW=220  

# --- 🖼️ ASCII LOGO ---
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

# --- 🖼️ 顶部 Logo ---
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

# --- 📊 仪表盘  ---
ui_dashboard() {
    local st=$1; local cf=$2; local adb=$3
    local net_dl="$4"; local net_api="$5"

    if [ "$HAS_GUM" = true ]; then
        make_dot() {
            local label="$1"; local state="$2"
            if [ "$state" == "1" ]; then
                echo "$(gum style --foreground $C_GREEN "●") $label"
            else
                echo "$(gum style --foreground $C_RED "●") $label"
            fi
        }

        local spacer="       " 
        
        local line1=$(gum join --horizontal --align center \
            "$(make_dot "ST" $st)" \
            "$spacer" \
            "$(make_dot "CF" $cf)" \
            "$spacer" \
            "$(make_dot "ADB" $adb)" \
        )
        
        local line2=$(gum join --vertical --align center \
            "$(gum style --foreground $C_BLUE "下载网络: $net_dl")" \
            "$(gum style --foreground $C_PURPLE "API 网络: $net_api")" \
        )

        gum style --border normal --border-foreground $C_DIM --padding "0 1" --margin "0 0 1 0" --align center "$line1" "" "$line2"
    else
        echo "状态: ST[$st] CF[$cf] ADB[$adb]"
        echo "下载: $net_dl"
        echo "API : $net_api"
        echo "----------------------------------------"
    fi
}

# --- 通用组件 ---

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
