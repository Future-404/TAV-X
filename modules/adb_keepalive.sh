#!/data/data/com.termux/files/usr/bin/bash
# TAV-X Module: ADB Keep-Alive System (v1.2.1)

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PKG="com.termux"
LOG_FILE="$TMPDIR/adb_connect_log.txt"

# --- 基础检测 ---
check_dependency() {
    if ! command -v adb &> /dev/null; then
        echo -e "${YELLOW}>>> 检测到缺失 android-tools，正在安装...${NC}"
        pkg update -y && pkg install android-tools termux-tools -y
    fi
}

check_adb_connection() {
    local count=$(adb devices | grep -v 'List' | grep -c 'device')
    [[ "$count" -gt 0 ]]
}

exec_adb_cmd() {
    "$@"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}❌ 命令执行失败： $* ${NC}"
        return 1
    fi
    return 0
}

confirm() {
    read -p "$1 (y/n): " answer
    [[ "$answer" == "y" || "$answer" == "Y" ]]
}

# --- 核心功能 ---

reset_adb_server() {
    echo -e "${YELLOW}正在重置 ADB 服务以修复协议错误...${NC}"
    adb kill-server
    adb start-server > /dev/null 2>&1
    sleep 1
}

pair_device() {
    echo -e "${CYAN}=== ADB 配对向导 ===${NC}"
    echo -e "${YELLOW}提示：建议使用 IP 127.0.0.1 以提高稳定性！${NC}"
    echo "1. 开发者选项 -> 无线调试 -> 使用配对码配对设备"
    echo "2. 输入弹窗中的 IP:端口 和 配对码"
    echo "-------------------------------------"
    
    adb start-server > /dev/null 2>&1

    read -p "请输入 IP:端口 (推荐 127.0.0.1:端口): " HOST
    [[ -z "$HOST" ]] && return
    
    read -p "请输入 6位配对码: " CODE
    [[ -z "$CODE" ]] && return
    
    echo -e "${CYAN}正在配对...${NC}"
    OUTPUT=$(adb pair "$HOST" "$CODE" 2>&1)
    echo "$OUTPUT"

    if [[ "$OUTPUT" == *"protocol fault"* ]]; then
        echo -e "${RED}❌ 检测到协议错误，正在自动修复...${NC}"
        reset_adb_server
        echo -e "${YELLOW}>>> 请重新尝试配对操作！${NC}"
    elif [[ "$OUTPUT" == *"Successfully paired"* ]]; then
        echo -e "${GREEN}✅ 配对成功！请继续进行连接。${NC}"
        read -n1 -r -p "按任意键继续..."
    else
        echo -e "${RED}配对未成功，请检查配对码是否过期。${NC}"
        read -n1 -r -p "按任意键继续..."
    fi
}

connect_adb_interactive() {
    if check_adb_connection; then
        echo -e "${GREEN}✔ 已连接到 ADB。${NC}"
        return 0
    fi

    echo -e "${CYAN}=== ADB 连接助手 ===${NC}"
    echo "请开启无线调试，查看【IP地址和端口】"
    echo -e "${YELLOW}注意：连接端口 与 配对端口 不同！${NC}"

    while true; do
        read -p "请输入端口（0返回，p配对，r重置ADB）： " PORT
        
        if [[ "$PORT" == "0" ]]; then return 1; fi
        
        if [[ "$PORT" == "p" || "$PORT" == "P" ]]; then 
            pair_device
            echo -e "${CYAN}=== 回到连接界面 ===${NC}"
            continue
        fi

        if [[ "$PORT" == "r" || "$PORT" == "R" ]]; then 
            reset_adb_server
            echo -e "${GREEN}ADB 服务已重启。${NC}"
            continue
        fi

        if [[ "$PORT" =~ ^[0-9]+$ ]]; then
            echo -e "${CYAN}尝试连接 127.0.0.1:$PORT ...${NC}"
            adb connect "127.0.0.1:$PORT" | tee "$LOG_FILE"

            if grep -q "connected" "$LOG_FILE" || check_adb_connection; then
                echo -e "${GREEN}✔ ADB 连接成功${NC}"
                rm -f "$LOG_FILE"
                return 0
            else
                echo -e "${RED}❌ 连接失败。${NC}"
                if grep -q "protocol fault" "$LOG_FILE"; then
                     echo -e "${YELLOW}检测到协议错误，自动重置 ADB...${NC}"
                     reset_adb_server
                     echo -e "${YELLOW}>>> 请重新输入端口尝试连接。${NC}"
                else
                     echo -e "${YELLOW}提示：输入 'p' 可进入配对模式，输入 'r' 重置服务。${NC}"
                fi
            fi
        else
            echo -e "${RED}❌ 格式错误${NC}"
        fi
    done
}

apply_keepalive() {
    if ! check_adb_connection; then
        echo -e "${RED}❌ ADB 未连接，无法执行保活。${NC}"
        return 1
    fi

    echo -e "${CYAN}>>> 下发保活策略...${NC}"

    if confirm "确定禁用幽灵进程杀手？(推荐)"; then
        exec_adb_cmd adb shell device_config put activity_manager max_phantom_processes 2147483647
        exec_adb_cmd adb shell settings put global settings_enable_monitor_phantom_procs false
    else
        echo "跳过。"
    fi

    if confirm "加入电池优化白名单？(推荐)"; then
        exec_adb_cmd adb shell dumpsys deviceidle whitelist +$PKG
    fi

    if confirm "赋予后台运行权限？(推荐)"; then
        exec_adb_cmd adb shell cmd appops set $PKG RUN_IN_BACKGROUND allow
        exec_adb_cmd adb shell cmd appops set $PKG RUN_ANY_IN_BACKGROUND allow
        exec_adb_cmd adb shell cmd appops set $PKG START_FOREGROUND allow
    fi

    echo "设置应用活跃优先级..."
    exec_adb_cmd adb shell am set-standby-bucket $PKG active

    if confirm "尝试关闭 MIUI 优化？(慎选)"; then
         exec_adb_cmd adb shell settings put secure miui_optimization 0 2>/dev/null
    fi
    
    echo "应用厂商通用优化..."
    exec_adb_cmd adb shell settings put system bg_power_permission_list +$PKG 2>/dev/null || true

    echo "申请 Termux CPU 唤醒锁 (WakeLock)..."
    if command -v termux-wake-lock &> /dev/null; then
        termux-wake-lock
        echo -e "${GREEN}✔ 锁已申请${NC}"
    else
        echo -e "${RED}❌ 失败: 未找到 termux-wake-lock 命令${NC}"
    fi

    echo -e "${GREEN}✅ 保活策略应用完成！${NC}"
    echo "提示：重启手机后部分设置会失效。"
    read -n1 -r -p "按任意键返回..."
}

stop_keepalive() {
    echo -e "${YELLOW}释放 WakeLock...${NC}"
    termux-wake-unlock || echo -e "${RED}释放失败 (可能未申请)${NC}"
    echo -e "${GREEN}✔ 已停止 CPU 唤醒锁${NC}"
    read -n1 -r -p "按任意键返回..."
}

# --- 菜单循环 ---
check_dependency

while true; do
    clear
    echo -e "${CYAN}=== TAV-X ADB 保活模块 ===${NC}"

    if check_adb_connection; then
        echo -e "ADB 状态：${GREEN}● 已连接${NC}"
    else
        echo -e "ADB 状态：${RED}● 未连接${NC}"
    fi

    echo "-------------------------------------"
    echo "1) 连接 ADB"
    echo "2) 执行系统级保活"
    echo "3) 停止保活"
    echo "0) 返回主菜单"
    echo ""

    read -p "选择： " c
    case $c in
        1) connect_adb_interactive ;;
        2) 
           if check_adb_connection; then
               apply_keepalive
           else
               echo -e "${YELLOW}请先连接 ADB！${NC}"; sleep 1
               connect_adb_interactive
               if check_adb_connection; then apply_keepalive; fi
           fi 
           ;;
        3) stop_keepalive ;;
        0) exit 0 ;;
        *) echo "无效选择"; sleep 0.5 ;;
    esac
done
