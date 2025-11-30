#!/bin/bash
# TAV-X v2.0 Local Bootstrapper (Startup Only)

SOURCE=${BASH_SOURCE[0]}
while [ -L "$SOURCE" ]; do
  DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
  SOURCE=$(readlink "$SOURCE")
  [[ $SOURCE != /* ]] && SOURCE=$DIR/$SOURCE
done
export TAVX_DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )

CURRENT_ALIAS=$(grep "alias st=" "$HOME/.bashrc" 2>/dev/null)
TARGET_CMD="bash $TAVX_DIR/st.sh"
EXPECTED_ALIAS="alias st='$TARGET_CMD'"

if echo "$CURRENT_ALIAS" | grep -q "$TAVX_DIR/st.sh"; then
    : 
else
    sed -i '/alias st=/d' "$HOME/.bashrc"
    echo "$EXPECTED_ALIAS" >> "$HOME/.bashrc"
fi

CORE_FILE="$TAVX_DIR/core/main.sh"

if [ -f "$CORE_FILE" ]; then
    chmod +x "$CORE_FILE"
    exec bash "$CORE_FILE"
else
    echo -e "\033[0;31m❌ 致命错误：核心文件丢失 ($CORE_FILE)\033[0m"
    echo "请尝试重新安装: curl -s https://tav-x.future404.qzz.io | bash"
    exit 1
fi
