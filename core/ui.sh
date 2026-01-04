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
    
    # === [增强日志记录] ===
    # 将临时日志的完整内容追加到主日志，确保不遗漏任何细节
    if [ -n "$TAVX_LOG_FILE" ] && [ -f "$tmp_log" ]; then
        echo "--- [Task Log Dump: $title] ---" >> "$TAVX_LOG_FILE"
        cat "$tmp_log" >> "$TAVX_LOG_FILE"
        echo "-------------------------------" >> "$TAVX_LOG_FILE"
    fi
    
    if [ $result -eq 0 ]; then
        write_log "TASK_END" "Success: $title"
        # 成功后删除临时文件，因为内容已归档到主日志
        rm -f "$tmp_log"
        return 0
    else
        write_log "TASK_END" "FAILED (Code $result): $title"
        # 失败时不在控制台重复打印 Last 20 lines，因为主日志里已经有了全量。
        # 但为了终端用户体验，如果不是在排查模式，还是可以显示一点。
        # 鉴于当前是排查阶段，我们让用户直接去看主日志。
        return 1
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