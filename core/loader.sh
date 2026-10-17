#!/bin/bash
# TAV-X Core: Dynamic Module Loader
# 负责扫描 modules/ 目录，解析元数据，动态注册应用。

export REGISTERED_MODULE_NAMES=()
export REGISTERED_MODULE_ENTRIES=()
export REGISTERED_MODULE_IDS=()

_reset_registry() {
    REGISTERED_MODULE_NAMES=()
    REGISTERED_MODULE_ENTRIES=()
    REGISTERED_MODULE_IDS=()
}

_parse_metadata() {
    local file="$1"
    [ ! -r "$file" ] && return 1
    
    _META_NAME=""
    _META_ENTRY=""
    _META_ID=""

    local line val
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "# MODULE_NAME:"*|"# MODULE_NAME="*)
                val="${line#*MODULE_NAME[=:]}"
                val="${val# }"
                val="${val%\"}"
                val="${val#\"}"
                _META_NAME="${val%"${val##*[![:space:]]}"}"
                ;;
            "# MODULE_ENTRY:"*|"# MODULE_ENTRY="*)
                val="${line#*MODULE_ENTRY[=:]}"
                val="${val# }"
                val="${val%\"}"
                val="${val#\"}"
                _META_ENTRY="${val%"${val##*[![:space:]]}"}"
                ;;
            "# MODULE_ID:"*|"# MODULE_ID="*)
                val="${line#*MODULE_ID[=:]}"
                val="${val# }"
                val="${val%\"}"
                val="${val#\"}"
                _META_ID="${val%"${val##*[![:space:]]}"}"
                ;;
            "#!/bin/bash"|"#!"*|"#"*|"")
                ;;
            *)
                break
                ;;
        esac
    done < "$file"

    if [ -z "$_META_ID" ]; then
        local parent="${file%/*}"
        local dir_name="${parent##*/}"
        if [ "$dir_name" != "modules" ]; then
            _META_ID="$dir_name"
        else
            local fname="${file##*/}"
            _META_ID="${fname%.sh}"
        fi
    fi

    [ -n "$_META_NAME" ] && [ -n "$_META_ENTRY" ] && return 0 || return 1
}

scan_and_load_modules() {
    _reset_registry
    shopt -s nullglob
    local bundles=("$TAVX_DIR/modules/"*/main.sh)
    local singles=("$TAVX_DIR/modules/"*.sh)
    shopt -u nullglob

    for file in "${bundles[@]}" "${singles[@]}"; do
        if _parse_metadata "$file"; then
            unset APP_DIR ST_DIR CLEWD_DIR MIHOMO_DIR GEMINI_DIR GCLI_DIR
            unset PID_FILE LOG_FILE BINARY
            # shellcheck disable=SC1090
            source "$file"
            REGISTERED_MODULE_NAMES+=("$_META_NAME")
            REGISTERED_MODULE_ENTRIES+=("$_META_ENTRY")
            REGISTERED_MODULE_IDS+=("$_META_ID")
        fi
    done
}