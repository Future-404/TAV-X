#!/bin/bash
# TAV-X Core: UI Adapter
[ -n "$_TAVX_UI_LOADED" ] && return
_TAVX_UI_LOADED=true

HAS_GUM=false
GUM_BIN=""
if command -v gum &> /dev/null; then 
    if [[ "$TERMUX_VERSION" == *"googleplay"* ]] || gum --version 2>&1 | grep -q "unexpected argument"; then
        echo -e "\033[0;33m[警告] 环境不兼容，已自动降级至文本模式。\033[0m" >&2
        HAS_GUM=false
    elif gum style "test" &> /dev/null; then
        HAS_GUM=true
        GUM_BIN="gum"
    fi
fi
export HAS_GUM
export GUM_BIN
export HAS_GUM
export GUM_BIN

export NC='\033[0m'
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'

export C_PINK=212    
export C_PURPLE=99   
export C_DIM=240     
export C_GREEN=82    
export C_RED=196     
export C_BLUE=39     
export C_YELLOW=220  

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
export -f get_ascii_logo

ui_header() {
    local subtitle="$1"
    local ver="${CURRENT_VERSION:-3.0}"
    
    clear
    if [ "$HAS_GUM" = true ]; then
        local logo=$("$GUM_BIN" style --foreground $C_PINK "$(get_ascii_logo)")
        local v_tag=$("$GUM_BIN" style --foreground $C_DIM --align right "Ver: $ver | by Future 404  ")
        echo "$logo"
        echo "$v_tag"
        
        if [ -n "$subtitle" ]; then
            local prefix=$("$GUM_BIN" style --foreground $C_PURPLE --bold "  🚀 ")
            local divider=$("$GUM_BIN" style --foreground $C_DIM "  ───────────────────────────────────────")
            echo -e "${prefix}${subtitle}"
            echo "$divider"
        fi
    else
        # Fallback for text mode with colors
        local PINK='\033[38;5;212m'
        echo -e "${PINK}"
        get_ascii_logo
        echo -e "${NC}Ver: ${CYAN}$ver${NC} | by Future 404"
        echo "----------------------------------------"
        if [ -n "$subtitle" ]; then
            echo -e "${PURPLE}🚀 $subtitle${NC}"
            echo "----------------------------------------"
        fi
    fi
}
export -f ui_header

ui_dashboard() {
    local modules_line="$1"
    local net_info="$2"
    local mem_val="$3"
    
    local base_items=()
    [ -n "$mem_val" ] && base_items+=("${PURPLE}● ${NC}🧠 $mem_val")
    [ -n "$net_info" ] && base_items+=("${CYAN}● ${NC}$net_info")
    [ -f "$TAVX_DIR/config/.adb_optimized" ] && base_items+=("${RED}● ${NC}已保活")

    if [ ${#base_items[@]} -gt 0 ]; then
        echo -n "  "
        for i in "${!base_items[@]}"; do
            echo -n -e "${base_items[$i]}"
            [ $i -lt $((${#base_items[@]} - 1)) ] && echo -n "    "
        done
        echo -e "\n"
    fi

    if [ -n "$modules_line" ]; then
        echo -e "  $modules_line"
        echo ""
    fi
}
export -f ui_dashboard

write_log() {
    return 0
}
export -f write_log

ui_menu() {
    local header="$1"; shift
    if [ "$HAS_GUM" = true ]; then
        "$GUM_BIN" choose --header="" --cursor="👉 " --cursor.foreground "$C_PINK" --selected.foreground "$C_PINK" -- "$@"
    else
        echo -e "\n${CYAN}[ $header ]${NC}" >&2
        local i=1
        local options=("$@")
        for opt in "${options[@]}"; do
            echo -e "  ${YELLOW}$i.${NC} $opt" >&2
            ((i++))
        done
        
        local idx
        while true; do
            echo -n -e "\n  ${BLUE}➜${NC} 请输入编号: " >&2
            read -r idx
            if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le "${#options[@]}" ]; then
                 break
            fi
            echo -e "  ${RED}✘ 无效选择，请重试。${NC}" >&2
        done
        echo "${options[$((idx-1))]}"
    fi
}
export -f ui_menu

ui_input() {
    local prompt="${1:-请输入}"
    local default="$2"
    local is_pass="$3"
    
    if [ "$HAS_GUM" = true ]; then
        local args=(--placeholder "$prompt" --width 40 --cursor.foreground $C_PINK)
        [ -n "$default" ] && args+=(--value "$default")
        [ "$is_pass" = "true" ] && args+=(--password)
        "$GUM_BIN" input "${args[@]}"
    else
        local flag=""; [ "$is_pass" = "true" ] && flag="-s"
        echo -n -e "  ${CYAN}➜${NC} $prompt" >&2
        [ -n "$default" ] && echo -n -e " [${YELLOW}$default${NC}]" >&2
        echo -n ": " >&2
        local val; read $flag val; echo "${val:-$default}"
    fi
}
export -f ui_input

ui_input_validated() {
    local prompt="$1"
    local default="$2"
    local type="${3:-any}"
    local result=""
    
    while true; do
        result=$(ui_input "$prompt" "$default" "false")
        if [ -z "$result" ]; then
            if [ -n "$default" ]; then result="$default"; else continue; fi
        fi
        local danger_chars='[;\|&><\$\(\)\`]'
        if [[ "$result" =~ $danger_chars ]]; then
            ui_print error "检测到非法字符，请重新输入。" >&2
            continue
        fi

        local is_ok=false
        case "$type" in
            "numeric") [[ "$result" =~ ^[0-9]+$ ]] && is_ok=true ;;
            "url") [[ "$result" =~ ^https?:// ]] && is_ok=true ;;
            "ip") [[ "$result" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && is_ok=true ;;
            "host") [[ "$result" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(:[0-9]{1,5})?$ ]] && is_ok=true ;;
            "alphanumeric") [[ "$result" =~ ^[a-zA-Z0-9_-]+$ ]] && is_ok=true ;;
            "any"|*) is_ok=true ;;
        esac
        
        if [ "$is_ok" = true ]; then
            echo "$result"
            return 0
        else
            ui_print error "输入格式 ($type) 不符合要求，请重新输入。" >&2
            sleep 0.5
        fi
    done
}
export -f ui_input_validated

ui_confirm() {
    local prompt="${1:-确定要执行此操作吗？}"
    if [ "$HAS_GUM" = true ]; then
        "$GUM_BIN" confirm "$prompt" --affirmative "是" --negative "否" --selected.background $C_PINK
    else
        echo -e -n "${YELLOW}⚠ $prompt (y/n): ${NC}" >&2
        read -r c; [[ "$c" == "y" || "$c" == "Y" ]]
    fi
}
export -f ui_confirm

ui_spinner() {
    local title="$1"; shift
    ui_stream_task "$title" "$*"
}
export -f ui_spinner

ui_restore_terminal() {
    [ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc" 2>/dev/null
}

ui_stream_task() {
    local title="$1"; local cmd="$2"
    local exit_status_file="$TMP_DIR/status_$$"

    ui_print info "$title"

    local stdbuf_cmd=""
    command -v stdbuf &>/dev/null && stdbuf_cmd="stdbuf -oL -eL"
    local term_width=80
    [ -n "$COLUMNS" ] && [ "$COLUMNS" -gt 20 ] && term_width=$((COLUMNS - 8))

    (
        export TAVX_NON_INTERACTIVE=true
        export TAVX_DIR="$TAVX_DIR"
        [ -n "$TERMUX_VERSION" ] && export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
        
        $stdbuf_cmd bash -c "$cmd" 2>&1
        echo $? > "$exit_status_file"
    ) | while IFS= read -r line; do
        local clean_line=$(echo "$line" | tr -d '\r' | sed 's/^[[:space:]]*//')
        [ -z "$clean_line" ] && continue
        
        if [ "$HAS_GUM" = true ]; then
            local display_line="${clean_line:0:$term_width}"
            [ "${#clean_line}" -gt "$term_width" ] && display_line="${display_line}..."
            "$GUM_BIN" style --foreground "$C_DIM" "  │ $display_line"
        else
            echo -e "  \033[0;90m│\033[0m ${clean_line:0:$term_width}"
        fi
    done

    local result=1
    [ -f "$exit_status_file" ] && result=$(cat "$exit_status_file") && rm -f "$exit_status_file"

    if [ "$result" -eq 0 ]; then
        return 0
    else
        ui_print error "任务执行失败 [Code: $result]"
        return 1
    fi
}
export -f ui_stream_task

ui_status_card() {
    local type="$1"
    local main_text="$2"
    shift 2
    local infos=("$@")

    local gum_color=""
    local icon=""
    
    case "$type" in
        running|success) gum_color="$C_GREEN"; icon="●" ;; 
        stopped|error|failure) gum_color="$C_RED"; icon="●" ;; 
        warn|working) gum_color="$C_YELLOW"; icon="●" ;; 
        *) gum_color="$C_BLUE"; icon="●" ;; 
    esac

    if [ "$HAS_GUM" = true ]; then
        local parts=()
        parts+=("$("$GUM_BIN" style --foreground "$gum_color" --bold "$icon $main_text")")
        
        if [ ${#infos[@]} -gt 0 ]; then
            parts+=("")
            for line in "${infos[@]}"; do
                if [[ "$line" == *": "* ]]; then
                    local k="${line%%: *}"
                    local v="${line#*: }"
                    parts+=("$("$GUM_BIN" style --foreground $C_PURPLE "$k"): $v")
                else
                    parts+=("$line")
                fi
            done
        fi
        
        local joined=$("$GUM_BIN" join --vertical --align left "${parts[@]}")
        "$GUM_BIN" style --border normal --border-foreground $C_DIM --padding "0 1" --margin "0 0 1 0" --width 45 "$joined"
    else
        local color_code=""
        case "$type" in
            running|success) color_code="$GREEN" ;; 
            stopped|error|failure) color_code="$RED" ;; 
            warn|working) color_code="$YELLOW" ;; 
            *) color_code="$BLUE" ;; 
        esac
        
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
export -f ui_status_card

ui_print() {
    local type="${1:-info}"
    local msg="$2"
    
    local log_level=$(echo "$type" | tr '[:lower:]' '[:upper:]')
    write_log "$log_level" "$msg"

    if [ "$HAS_GUM" = true ]; then
        case $type in
            success) "$GUM_BIN" style --foreground $C_GREEN "  ✔ $msg" ;; 
            error)   "$GUM_BIN" style --foreground $C_RED   "  ✘ $msg" ;; 
            warn)    "$GUM_BIN" style --foreground $C_YELLOW "  ⚠ $msg" ;; 
            *)       "$GUM_BIN" style --foreground $C_PURPLE "  ℹ $msg" ;; 
        esac
    else 
        case $type in
            success) echo -e "  ${GREEN}✔${NC} $msg" ;; 
            error)   echo -e "  ${RED}✘${NC} $msg" ;; 
            warn)    echo -e "  ${YELLOW}⚠${NC} $msg" ;; 
            *)       echo -e "  ${BLUE}ℹ${NC} $msg" ;; 
        esac
    fi
}
export -f ui_print

ui_pause() {
    local prompt="${1:-按任意键继续...}"
    echo ""
    if [ "$HAS_GUM" = true ]; then
        "$GUM_BIN" style --foreground $C_DIM "  $prompt"
        read -n 1 -s -r
    else
        read -n 1 -s -r -p "  $prompt"
    fi
}
export -f ui_pause
