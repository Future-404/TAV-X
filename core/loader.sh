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

    local meta_block=$(grep -E "^# MODULE_(NAME|ENTRY|ID)[:=]" "$file")
    [ -z "$meta_block" ] && return 1

    _META_NAME=$(echo "$meta_block" | grep "NAME" | head -n 1 | sed 's/^# MODULE_NAME[:=] *//;s/"//g' | xargs)
    _META_ENTRY=$(echo "$meta_block" | grep "ENTRY" | head -n 1 | sed 's/^# MODULE_ENTRY[:=] *//;s/"//g' | xargs)
    _META_ID=$(echo "$meta_block" | grep "ID" | head -n 1 | sed 's/^# MODULE_ID[:=] *//;s/"//g' | xargs)

    if [ -z "$_META_ID" ]; then
        local dir_name=$(basename "$(dirname "$file")")
        [ "$dir_name" != "modules" ] && _META_ID="$dir_name" || _META_ID=$(basename "$file" .sh)
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
            source "$file"
            REGISTERED_MODULE_NAMES+=("$_META_NAME")
            REGISTERED_MODULE_ENTRIES+=("$_META_ENTRY")
            REGISTERED_MODULE_IDS+=("$_META_ID")
        fi
    done
}