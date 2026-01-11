#!/bin/bash
# SillyTavern Tunnel Wait Link Helper
# 此脚本用于在子 Shell 中运行

if [ -f "$HOME/.tav_x/core/env.sh" ]; then
    source "$HOME/.tav_x/core/env.sh"
    source "$HOME/.tav_x/core/utils.sh"
    source "$HOME/.tav_x/modules/sillytavern/main.sh"
elif [ -f "/data/data/com.termux/files/home/TAV-X/core/env.sh" ]; then
    source "/data/data/com.termux/files/home/TAV-X/core/env.sh"
    source "/data/data/com.termux/files/home/TAV-X/core/utils.sh"
    source "/data/data/com.termux/files/home/TAV-X/modules/sillytavern/main.sh"
fi

link=$(_st_wait_link)
if [ -n "$link" ]; then
    echo "$link" > "$TAVX_DIR/.temp_link"
    exit 0
else
    exit 1
fi