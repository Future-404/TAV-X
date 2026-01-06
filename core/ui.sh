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
    local st=$1; local adb=$2
    local net_dl="$3"; local net_api="$4"
    local modules_line="$5"

    if [ "$HAS_GUM" = true ]; then
        make_dynamic_badge() {
            local label="$1"; local state="$2"
            if [ "$state" == "1" ]; then
                echo "$(gum style --foreground $C_GREEN "●") $label"
            fi
        }

        local spacer="      "
        local active_items=()
        
        # 1. 核心服务状态
        [ "$st" == "1" ]  && active_items+=("$(make_dynamic_badge "酒馆" $st)")
        [ "$adb" == "1" ] && active_items+=("$(make_dynamic_badge "ADB" $adb)")
        
        # 2. 动态模块状态 (纯文本列表，遍历渲染)
        if [ -n "$modules_line" ]; then
             for mod in $modules_line; do
                 # 过滤无效字符 (可选)
                 [ -z "$mod" ] && continue
                 active_items+=("$(make_dynamic_badge "$mod" "1")")
             done
        fi

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
        echo "核心: ST[$st] ADB[$adb]"
        echo "模块: $modules_line"
        echo "下载: $net_dl"
        echo "API : $net_api"
        echo "----------------------------------------"
    fi
}

write_log() {
    local level="$1"
    local msg="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    local clean_msg=$(echo "$msg" | sed 's/\x1b\[[0-9;]*m//g')
    
    if [ -n "$TAVX_LOG_FILE" ]; then
        echo "[$timestamp] [$level] $clean_msg" >> "$TAVX_LOG_FILE"
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
    local tmp_log=""
    if command -v mktemp &> /dev/null; then
        tmp_log=$(mktemp "$TMP_DIR/task_XXXXXX.log")
    else
        tmp_log="$TMP_DIR/task_${BASHPID}_$(date +%s%N).log"
    fi

    write_log "TASK_START" "$title (Log: $tmp_log)"
    
    local wrapped_cmd="{ $cmd ; } > \"$tmp_log\" 2>&1"

    local result=0
    if [ "$HAS_GUM" = true ]; then
        gum spin --spinner dot --title "$title" --title.foreground $C_PURPLE -- bash -c "$wrapped_cmd"
        result=$?
    else
        echo ">>> $title"
        eval "$wrapped_cmd"
        result=$?
    fi
    
    if [ -n "$TAVX_LOG_FILE" ] && [ -f "$tmp_log" ]; then
        echo "--- [Task Log Dump: $title] ---" >> "$TAVX_LOG_FILE"
        cat "$tmp_log" >> "$TAVX_LOG_FILE"
        echo "-------------------------------" >> "$TAVX_LOG_FILE"
    fi
    
    if [ $result -eq 0 ]; then
        write_log "TASK_END" "Success: $title"
        rm -f "$tmp_log"
        return 0
    else
        write_log "TASK_END" "FAILED (Code $result): $title"
        return 1
    fi
}

ui_status_card() {
    local type="$1"
    local main_text="$2"
    shift 2
    local infos=("$@")

    local color_code=""
    local gum_color=""
    local icon=""
    
    case "$type" in
        running|success) 
            color_code="$GREEN"
            gum_color="$C_GREEN"
            icon="●" 
            ;;
        stopped|error|failure) 
            color_code="$RED"
            gum_color="$C_RED"
            icon="●" 
            ;;
        warn|working) 
            color_code="$YELLOW"
            gum_color="$C_YELLOW"
            icon="●" 
            ;;
        *) 
            color_code="$BLUE"
            gum_color="$C_BLUE"
            icon="●" 
            ;;
    esac

    if [ "$HAS_GUM" = true ]; then
        local content=""
        content+=$(gum style --foreground "$gum_color" --bold "$icon $main_text")
        content+=$'\n'
        if [ ${#infos[@]} -gt 0 ]; then
            content+=$'\n'
            for line in "${infos[@]}"; do
                if [[ "$line" == *": "* ]]; then
                    local k="${line%%: *}"
                    local v="${line#*: }"
                    content+="$(gum style --foreground $C_PURPLE "$k"): $v"
                else
                    content+="$line"
                fi
                content+=$'\n'
            done
        fi
        
        gum style --border normal --border-foreground $C_DIM --padding "0 1" --margin "0 0 1 0" --align left "$content"
    else
        echo -e "状态: ${color_code}${icon} ${main_text}${NC}"
        for line in "${infos[@]}"; do
            if [[ "$line" == *": "* ]]; then
                local k="${line%%: *}"
                local v="${line#*: }"
                echo -e "${CYAN}${k}${NC}: ${v}"
            else
                echo -e "$line"
            fi
        done
        echo "----------------------------------------"
    fi
}

ui_print() {
    local type="$1"; local msg="$2"
    
    local log_level=$(echo "$type" | tr '[:lower:]' '[:upper:]')
    write_log "$log_level" "$msg"

    if [ "$HAS_GUM" = true ]; then
        case $type in
            success) gum style --foreground $C_GREEN "✔ $msg" ;;
            error)   gum style --foreground $C_RED   "✘ $msg" ;;
            warn)    gum style --foreground $C_YELLOW "⚠ $msg" ;;
            *)       gum style --foreground $C_PURPLE "ℹ $msg" ;;
        esac
    else 
        case $type in
            success) echo -e "\033[1;32m[DONE]\033[0m $msg" ;;
            error)   echo -e "\033[1;31m[ERROR]\033[0m $msg" ;;
            warn)    echo -e "\033[1;33m[WARN]\033[0m $msg" ;;
            *)       echo -e "\033[1;34m[INFO]\033[0m $msg" ;;
        esac
    fi
}

ui_pause() {
    if [ "$HAS_GUM" = true ]; then
        echo ""; gum style --foreground $C_DIM "按任意键继续..."; read -n 1 -s -r
    else
        echo ""; read -n 1 -s -r -p "按任意键继续..."
    fi
}