#!/bin/bash
# TAV-X Core: Unified Module Updater
[ -n "$_TAVX_MODULE_UPDATER_LOADED" ] && return
_TAVX_MODULE_UPDATER_LOADED=true

source "$TAVX_DIR/core/env.sh"
source "$TAVX_DIR/core/ui.sh"
source "$TAVX_DIR/core/utils.sh"
source "$TAVX_DIR/core/net_utils.sh"

MODULE_UPDATE_CACHE_DIR="$TMP_DIR/.mod_updates_cache"
MODULE_UPDATE_CACHE_TTL=600 # 10 分钟缓存

_ensure_update_cache_dir() {
    mkdir -p "$MODULE_UPDATE_CACHE_DIR" 2>/dev/null
}

# 获取模块本地当前版本号
# 参数 1: 模块 ID
# 参数 2: compare_mode ("true" 时对 Git 仓库强制返回短 commit hash 以便与远端对称比对)
module_get_local_version() {
    local id="$1"
    local compare_mode="${2:-false}"
    local app_path
    app_path=$(get_app_path "$id")

    # 若处于 Git 对称比对模式且目录是 Git 仓库，直接返回短 commit hash
    if [ "$compare_mode" == "true" ] && [ -d "$app_path/.git" ]; then
        local short_sha
        short_sha=$(git -C "$app_path" rev-parse --short=7 HEAD 2>/dev/null)
        [ -n "$short_sha" ] && echo "$short_sha" && return 0
    fi

    # 1. 优先读取 .version 文件
    if [ -f "$app_path/.version" ]; then
        local v
        v=$(cat "$app_path/.version" 2>/dev/null | tr -d '\r\n ')
        [ -n "$v" ] && echo "$v" && return 0
    fi

    # 2. 如果模块有自定义版本获取函数
    if command -v "${id}_get_version" &>/dev/null; then
        local v
        v=$("${id}_get_version" 2>/dev/null | tr -d '\r\n ')
        [ -n "$v" ] && echo "$v" && return 0
    fi

    # 3. 检查是否为 Git 仓库
    if [ -d "$app_path/.git" ]; then
        local git_ver
        git_ver=$(git -C "$app_path" describe --tags --exact-match 2>/dev/null || git -C "$app_path" rev-parse --short=7 HEAD 2>/dev/null)
        [ -n "$git_ver" ] && echo "$git_ver" && return 0
    fi

    # 4. 二进制可执行文件版本推断 (-v / --version)
    local bin_file="$app_path/$id"
    if [ -x "$bin_file" ]; then
        local bin_ver
        bin_ver=$("$bin_file" -v 2>/dev/null || "$bin_file" --version 2>/dev/null | head -n 1)
        bin_ver=$(echo "$bin_ver" | grep -oE 'v?[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)
        [ -n "$bin_ver" ] && echo "$bin_ver" && return 0
    fi

    echo "未知"
}
export -f module_get_local_version

# 获取模块配置的更新仓库 (格式: owner/repo)
_module_get_repo() {
    local id="$1"
    local idx=-1
    for i in "${!REGISTERED_MODULE_IDS[@]}"; do
        if [ "${REGISTERED_MODULE_IDS[$i]}" == "$id" ]; then
            idx=$i; break
        fi
    done

    if [ "$idx" -ge 0 ] && [ -n "${REGISTERED_MODULE_UPDATE_REPOS[$idx]}" ]; then
        echo "${REGISTERED_MODULE_UPDATE_REPOS[$idx]}"
        return
    fi

    # 从模块 main.sh 解析 UPDATE_REPO 或 APP_PROJECT_URL 作为后备
    local mod_file="$TAVX_DIR/modules/$id/main.sh"
    if [ -f "$mod_file" ]; then
        local p_url
        p_url=$(grep -E "^# UPDATE_REPO:" "$mod_file" | head -n 1 | cut -d: -f2- | xargs)
        if [ -z "$p_url" ]; then
            p_url=$(grep -E "^# APP_PROJECT_URL:" "$mod_file" | head -n 1 | cut -d: -f2- | xargs)
        fi
        if [[ "$p_url" == *"github.com/"* ]]; then
            p_url=${p_url#*github.com/}
            p_url=${p_url%.git}
            p_url=${p_url%/}
            echo "$p_url"
            return
        elif [[ "$p_url" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
            echo "$p_url"
            return
        fi
    fi
    echo ""
}

# 获取模块配置的资产匹配模式 (UPDATE_ASSET)
_module_get_update_asset() {
    local id="$1"
    local idx=-1
    for i in "${!REGISTERED_MODULE_IDS[@]}"; do
        if [ "${REGISTERED_MODULE_IDS[$i]}" == "$id" ]; then
            idx=$i; break
        fi
    done

    if [ "$idx" -ge 0 ] && [ -n "${REGISTERED_MODULE_UPDATE_ASSETS[$idx]}" ]; then
        echo "${REGISTERED_MODULE_UPDATE_ASSETS[$idx]}"
        return
    fi

    local mod_file="$TAVX_DIR/modules/$id/main.sh"
    if [ -f "$mod_file" ]; then
        local asset
        asset=$(grep -E "^# UPDATE_ASSET:" "$mod_file" | head -n 1 | cut -d: -f2- | xargs)
        [ -n "$asset" ] && echo "$asset" && return
    fi
    echo ""
}

# 获取模块更新类型: github_release | git | custom | none
_module_get_update_type() {
    local id="$1"
    local idx=-1
    for i in "${!REGISTERED_MODULE_IDS[@]}"; do
        if [ "${REGISTERED_MODULE_IDS[$i]}" == "$id" ]; then
            idx=$i; break
        fi
    done

    if [ "$idx" -ge 0 ] && [ -n "${REGISTERED_MODULE_UPDATE_TYPES[$idx]}" ]; then
        echo "${REGISTERED_MODULE_UPDATE_TYPES[$idx]}"
        return
    fi

    local mod_file="$TAVX_DIR/modules/$id/main.sh"
    if [ -f "$mod_file" ]; then
        if grep -q "MODULE_DEPRECATED: true" "$mod_file" 2>/dev/null; then
            echo "none"
            return
        fi
        local ut
        ut=$(grep -E "^# UPDATE_TYPE:" "$mod_file" | head -n 1 | cut -d: -f2- | xargs)
        [ -n "$ut" ] && echo "$ut" && return
    fi

    local app_path
    app_path=$(get_app_path "$id")
    if [ -d "$app_path/.git" ]; then
        echo "git"
        return
    fi

    if command -v "${id}_update" &>/dev/null; then
        echo "custom"
        return
    fi

    local repo
    repo=$(_module_get_repo "$id")
    if [ -n "$repo" ]; then
        echo "github_release"
        return
    fi

    echo "none"
}

# 查询模块远端最新版本（带 TTL 缓存机制）
module_check_remote_version() {
    local id="$1"
    local force="${2:-false}"
    _ensure_update_cache_dir

    local up_type
    up_type=$(_module_get_update_type "$id")
    if [ "$up_type" == "none" ]; then
        echo ""
        return 1
    fi

    local repo
    repo=$(_module_get_repo "$id")
    [ -z "$repo" ] && echo "" && return 1

    local cache_file="$MODULE_UPDATE_CACHE_DIR/${id}.cache"
    local now
    now=$(date +%s)

    if [ "$force" != "true" ] && [ -f "$cache_file" ]; then
        local cache_time cache_val
        cache_time=$(head -n 1 "$cache_file" 2>/dev/null)
        cache_val=$(tail -n 1 "$cache_file" 2>/dev/null)
        if [ -n "$cache_time" ] && [ -n "$cache_val" ]; then
            if [ $(( now - cache_time )) -lt "$MODULE_UPDATE_CACHE_TTL" ]; then
                echo "$cache_val"
                return 0
            fi
        fi
    fi

    local remote_ver=""

    if [ "$up_type" == "git" ]; then
        prepare_network_strategy
        local check_url
        check_url=$(get_dynamic_repo_url "$repo")
        local app_path cur_branch="HEAD"
        app_path=$(get_app_path "$id")
        if [ -d "$app_path/.git" ]; then
            local br
            br=$(git -C "$app_path" rev-parse --abbrev-ref HEAD 2>/dev/null)
            [ -n "$br" ] && [ "$br" != "HEAD" ] && cur_branch="refs/heads/$br"
        fi
        remote_ver=$(git ls-remote "$check_url" "$cur_branch" 2>/dev/null | head -n 1 | awk '{print $1}' | cut -c1-7)
        if [ -z "$remote_ver" ] && [ "$cur_branch" != "HEAD" ]; then
            remote_ver=$(git ls-remote "$check_url" HEAD 2>/dev/null | head -n 1 | awk '{print $1}' | cut -c1-7)
        fi
    else
        # 默认尝试从 GitHub Release 获取最新 tag
        auto_load_proxy_env
        remote_ver=$(python3 - "$repo" << 'PY_EOF' 2>/dev/null
import sys, urllib.request, json, os

repo = sys.argv[1]
api_url = f"https://api.github.com/repos/{repo}/releases/latest"
proxy = os.environ.get("https_proxy") or os.environ.get("http_proxy") or os.environ.get("ALL_PROXY")

def fetch(url, p=None):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({'http': p, 'https': p})) if p else urllib.request.build_opener()
    req = urllib.request.Request(url, headers={"User-Agent": "TAV-X/ModuleUpdater"})
    with opener.open(req, timeout=6) as resp:
        return json.loads(resp.read().decode())

data = None
if proxy:
    try:
        data = fetch(api_url, proxy)
    except Exception:
        pass

if not data:
    try:
        data = fetch(api_url, None)
    except Exception:
        pass

if data:
    tag = data.get("tag_name", "").strip()
    if tag:
        print(tag)
        sys.exit(0)
sys.exit(1)
PY_EOF
)
        # 如果 Python 请求失败且有 curl，尝试 curl 兜底
        if [ -z "$remote_ver" ]; then
            local raw_json
            raw_json=$(curl -s -m 8 "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null)
            [ -z "$raw_json" ] && raw_json=$(curl --noproxy "*" -s -m 8 "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null)
            if [ -n "$raw_json" ] && [[ "$raw_json" != *"rate limit"* ]]; then
                remote_ver=$(echo "$raw_json" | grep -o '"tag_name": *"[^"]*"' | head -n 1 | cut -d'"' -f4)
            fi
        fi
    fi

    if [ -n "$remote_ver" ]; then
        echo -e "${now}\n${remote_ver}" > "$cache_file" 2>/dev/null
        echo "$remote_ver"
        return 0
    fi

    echo ""
    return 1
}
export -f module_check_remote_version

# 检查单个模块更新状态: 返回 0 表示有更新，1 表示已是最新，2 表示检查失败，3 表示未安装或不支持
module_check_update_status() {
    local id="$1"
    local app_path
    app_path=$(get_app_path "$id")
    if [ ! -d "$app_path" ] || ! is_dir_nonempty "$app_path"; then
        return 3
    fi

    local up_type
    up_type=$(_module_get_update_type "$id")
    [ "$up_type" == "none" ] && return 3

    local compare_flag="false"
    [ "$up_type" == "git" ] && compare_flag="true"

    local local_v
    local_v=$(module_get_local_version "$id" "$compare_flag")
    local remote_v
    remote_v=$(module_check_remote_version "$id")

    if [ -z "$remote_v" ]; then
        return 2
    fi

    local clean_local="${local_v#v}"
    local clean_remote="${remote_v#v}"

    if [ "$clean_local" != "$clean_remote" ] && [ "$local_v" != "$remote_v" ]; then
        return 0
    else
        return 1
    fi
}
export -f module_check_update_status

# 清除指定模块的更新缓存
module_clear_update_cache() {
    local id="$1"
    _ensure_update_cache_dir
    rm -f "$MODULE_UPDATE_CACHE_DIR/${id}.cache" 2>/dev/null
}
export -f module_clear_update_cache

# 通用 Git 仓库更新驱动
driver_update_git_repo() {
    local id="$1"
    local target_dir="$2"
    local repo="$3"

    [ -z "$target_dir" ] && target_dir=$(get_app_path "$id")
    if [ ! -d "$target_dir/.git" ]; then
        ui_print error "目录并非 Git 仓库: $target_dir"
        return 1
    fi

    prepare_network_strategy
    local dyn_url
    dyn_url=$(get_dynamic_repo_url "$repo")

    local pull_cmd="cd '$target_dir' && git fetch '$dyn_url' && git merge --autostash FETCH_HEAD"
    if ui_stream_task "同步最新代码..." "$pull_cmd"; then
        if [ -f "$target_dir/package.json" ]; then
            ui_print info "检测到 package.json，正在检查依赖更新..."
            npm_install_smart "$target_dir"
        fi
        local new_ver
        new_ver=$(git -C "$target_dir" describe --tags --exact-match 2>/dev/null || git -C "$target_dir" rev-parse --short=7 HEAD 2>/dev/null)
        [ -n "$new_ver" ] && echo "$new_ver" > "$target_dir/.version"
        ui_print success "代码同步成功！当前版本: ${new_ver}"
        return 0
    else
        ui_print error "Git 同步更新失败，请检查网络。"
        return 1
    fi
}
export -f driver_update_git_repo

# 通用 GitHub Release 二进制更新驱动
driver_update_github_release() {
    local id="$1"
    local repo="$2"
    local asset_pattern="$3"
    local bin_name="${4:-$id}"
    local app_dir
    app_dir=$(get_app_path "$id")

    prepare_network_strategy
    auto_load_proxy_env

    ui_print info "正在获取最新 Release 资产链接..."
    local arch
    arch=$(uname -m)
    local match_arch="linux-amd64"
    local match_uarch="linux_amd64"
    case "$arch" in
        aarch64|arm64)
            match_arch="linux-arm64"
            match_uarch="linux_aarch64"
            ;;
        x86_64|amd64)
            match_arch="linux-amd64"
            match_uarch="linux_amd64"
            ;;
    esac

    [ -z "$asset_pattern" ] && asset_pattern=$(_module_get_update_asset "$id")

    local pattern="${asset_pattern//\{arch\}/$match_arch}"
    pattern="${pattern//\{uarch\}/$match_uarch}"
    [ -z "$pattern" ] && pattern="$match_arch"

    local release_info
    release_info=$(python3 - "$repo" "$pattern" << 'PY_EOF' 2>/dev/null
import sys, urllib.request, json, os

repo = sys.argv[1]
pattern = sys.argv[2]
api_url = f"https://api.github.com/repos/{repo}/releases/latest"
proxy = os.environ.get("https_proxy") or os.environ.get("http_proxy") or os.environ.get("ALL_PROXY")

def fetch(url, p=None):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({'http': p, 'https': p})) if p else urllib.request.build_opener()
    req = urllib.request.Request(url, headers={"User-Agent": "TAV-X/ModuleUpdater"})
    with opener.open(req, timeout=8) as resp:
        return json.loads(resp.read().decode())

data = None
if proxy:
    try:
        data = fetch(api_url, proxy)
    except Exception:
        pass

if not data:
    try:
        data = fetch(api_url, None)
    except Exception:
        pass

if data:
    tag = data.get("tag_name", "").strip()
    for a in data.get("assets", []):
        name = a.get("name", "")
        if pattern in name:
            print(f"{tag}|{a.get('browser_download_url', '')}")
            sys.exit(0)
sys.exit(1)
PY_EOF
)

    if [ -z "$release_info" ]; then
        ui_print error "未能解析到匹配的 Release 资产 ($pattern)。"
        return 1
    fi

    local tag dl_url
    tag="${release_info%%|*}"
    dl_url="${release_info##*|}"

    ui_print info "目标版本: ${tag}"

    local tmp_archive="$TMP_DIR/${id}_new_asset"
    local tmp_extract="$TMP_DIR/${id}_new_extract"
    safe_rm "$tmp_archive"
    safe_rm "$tmp_extract"
    mkdir -p "$tmp_extract"

    local dl_cmd="source \"$TAVX_DIR/core/net_utils.sh\"; download_file_smart '$dl_url' '$tmp_archive' 'true'"
    if ! ui_stream_task "下载新版组件..." "$dl_cmd"; then
        ui_print error "下载失败，请检查网络或代理设置。"
        safe_rm "$tmp_archive"; safe_rm "$tmp_extract"
        return 1
    fi

    # 解压或解包
    if [[ "$dl_url" == *".tar.gz" || "$dl_url" == *".tgz" ]]; then
        tar -xzf "$tmp_archive" -C "$tmp_extract" 2>/dev/null
    elif [[ "$dl_url" == *".zip" ]]; then
        unzip -q -o "$tmp_archive" -d "$tmp_extract" 2>/dev/null
    else
        mv "$tmp_archive" "$tmp_extract/$bin_name"
    fi

    local extracted_bin
    extracted_bin=$(find "$tmp_extract" -type f -name "$bin_name" | head -n 1)
    if [ -z "$extracted_bin" ] || [ ! -f "$extracted_bin" ]; then
        extracted_bin=$(find "$tmp_extract" -type f -executable | head -n 1)
    fi

    if [ -z "$extracted_bin" ] || [ ! -f "$extracted_bin" ]; then
        ui_print error "在下载的归档包中未找到可执行文件。"
        safe_rm "$tmp_archive"; safe_rm "$tmp_extract"
        return 1
    fi

    # 替换目标二进制：先 unlink 再复制，防止 ETXTBSY 错误
    mkdir -p "$app_dir"
    local target_bin="$app_dir/$bin_name"
    rm -f "$target_bin" 2>/dev/null
    cp -f "$extracted_bin" "$target_bin"
    chmod +x "$target_bin"
    echo "$tag" > "$app_dir/.version"

    safe_rm "$tmp_archive"; safe_rm "$tmp_extract"
    ui_print success "二进制更新成功！当前版本: ${tag}"
    return 0
}
export -f driver_update_github_release

# 执行模块更新流程（含完整生命周期保护）
# 参数 1: 模块 ID
# 参数 2: skip_confirm ("true" 时跳过确认弹窗与末尾暂停，用于一键批量更新)
module_perform_update() {
    local id="$1"
    local skip_confirm="${2:-false}"
    local app_path
    app_path=$(get_app_path "$id")

    if [ ! -d "$app_path" ] || ! is_dir_nonempty "$app_path"; then
        ui_print error "应用尚未安装，无法更新。"
        [ "$skip_confirm" != "true" ] && ui_pause
        return 1
    fi

    local up_type
    up_type=$(_module_get_update_type "$id")
    local compare_flag="false"
    [ "$up_type" == "git" ] && compare_flag="true"

    local display_v local_cmp_v
    display_v=$(module_get_local_version "$id" "false")
    local_cmp_v=$(module_get_local_version "$id" "$compare_flag")

    ui_header "模块更新: $id"
    echo -e "当前本地版本: \033[1;33m${display_v}\033[0m"

    if [ "$skip_confirm" != "true" ]; then
        ui_print info "正在检测远端最新版本..."
        local remote_v
        remote_v=$(module_check_remote_version "$id" "true")
        if [ -n "$remote_v" ]; then
            echo -e "发现远端版本: \033[1;32m${remote_v}\033[0m"
            if [ "$local_cmp_v" == "$remote_v" ] || [ "${local_cmp_v#v}" == "${remote_v#v}" ]; then
                ui_print info "当前已是最新版本。"
                if ! ui_confirm "当前已是最新，是否仍要强制重新覆盖安装？"; then
                    return 0
                fi
            else
                if ! ui_confirm "确认立即更新到 ${remote_v} 吗？"; then
                    return 0
                fi
            fi
        else
            ui_print warn "无法获取远端最新版本信息，可能网络受限。"
            if ! ui_confirm "是否尝试强制执行更新流程？"; then
                return 0
            fi
        fi
    fi

    # 1. 运行态安全守卫（优雅停服，杜绝 ETXTBSY 文件忙错误）
    local was_running=false
    if is_app_running "$id"; then
        was_running=true
        ui_print info "检测到服务正在运行中，正在安全停止以释放文件锁..."
        if command -v "${id}_stop" &>/dev/null; then
            "${id}_stop"
        elif [ "$OS_TYPE" == "TERMUX" ] && [ -d "$PREFIX/var/service/$id" ]; then
            tavx_service_control "down" "$id"
        else
            kill_process_safe "$TAVX_DIR/run/${id}.pid" "$id"
        fi
        sleep 1
    fi

    # 2. 调用模块专属更新钩子或通用更新驱动
    local success=false
    if command -v "${id}_update" &>/dev/null; then
        ui_print info "执行模块专用更新程序 (${id}_update)..."
        if "${id}_update"; then success=true; fi
    else
        local repo asset_pattern
        repo=$(_module_get_repo "$id")
        asset_pattern=$(_module_get_update_asset "$id")

        if [ "$up_type" == "git" ] && [ -n "$repo" ]; then
            driver_update_git_repo "$id" "$app_path" "$repo" && success=true
        elif [ "$up_type" == "github_release" ] && [ -n "$repo" ] && [ -n "$asset_pattern" ]; then
            driver_update_github_release "$id" "$repo" "$asset_pattern" "$id" && success=true
        elif command -v "${id}_install" &>/dev/null; then
            "${id}_install" && success=true
        fi
    fi

    # 3. 清理缓存
    module_clear_update_cache "$id"

    # 4. 运行态自动恢复
    if [ "$success" = true ]; then
        local new_local_v
        new_local_v=$(module_get_local_version "$id" "false")
        ui_print success "🎉 模块 [$id] 更新完成！当前版本: ${new_local_v}"

        if [ "$was_running" = true ]; then
            ui_print info "正在自动恢复后台服务..."
            if command -v "${id}_start" &>/dev/null; then
                "${id}_start"
            elif [ "$OS_TYPE" == "TERMUX" ] && [ -d "$PREFIX/var/service/$id" ]; then
                tavx_service_control "up" "$id"
            fi
        fi
    else
        ui_print error "更新流程异常退出，请检查上方日志。"
    fi

    [ "$skip_confirm" != "true" ] && ui_pause
    return 0
}
export -f module_perform_update

# 批量检查并更新所有已安装模块
module_check_all_updates() {
    ui_header "应用批量更新检查"
    ui_print info "正在扫描所有已安装模块的版本状态..."

    local updates_available=()
    local up_to_date=()
    local failed=()

    for i in "${!REGISTERED_MODULE_IDS[@]}"; do
        local id="${REGISTERED_MODULE_IDS[$i]}"
        local name="${REGISTERED_MODULE_NAMES[$i]}"
        local app_path
        app_path=$(get_app_path "$id")

        [ ! -d "$app_path" ] || ! is_dir_nonempty "$app_path" && continue

        local up_type
        up_type=$(_module_get_update_type "$id")
        [ "$up_type" == "none" ] && continue

        local compare_flag="false"
        [ "$up_type" == "git" ] && compare_flag="true"

        local display_v local_cmp_v remote_v
        display_v=$(module_get_local_version "$id" "false")
        local_cmp_v=$(module_get_local_version "$id" "$compare_flag")
        remote_v=$(module_check_remote_version "$id" "true")

        if [ -z "$remote_v" ]; then
            failed+=("$name ($id)")
        elif [ "$local_cmp_v" != "$remote_v" ] && [ "${local_cmp_v#v}" != "${remote_v#v}" ]; then
            updates_available+=("$id|$name|$display_v|$remote_v")
        else
            up_to_date+=("$name: $display_v")
        fi
    done

    echo ""
    if [ ${#updates_available[@]} -eq 0 ]; then
        ui_print success "恭喜！所有已安装模块均已是最新版本。"
        if [ ${#failed[@]} -gt 0 ]; then
            echo -e "\033[1;33m⚠️ 以下应用检查超时或暂无更新源：${failed[*]}\033[0m"
        fi
        ui_pause; return
    fi

    echo -e "\033[1;36m发现以下应用有可用更新：\033[0m"
    local menu_items=()
    for item in "${updates_available[@]}"; do
        IFS='|' read -r mid mname mcur mnew <<< "$item"
        echo -e "  🌟 \033[1m$mname\033[0m: $mcur -> \033[1;32m$mnew\033[0m"
        menu_items+=("🔄 更新 $mname ($mcur -> $mnew)")
    done

    menu_items+=("🚀 一键全部更新")
    menu_items+=("🔙 返回")

    echo ""
    local CHOICE
    CHOICE=$(ui_menu "请选择更新操作" "${menu_items[@]}")

    if [[ "$CHOICE" == *"返回"* ]]; then return; fi

    if [[ "$CHOICE" == *"一键全部更新"* ]]; then
        for item in "${updates_available[@]}"; do
            IFS='|' read -r mid mname mcur mnew <<< "$item"
            module_perform_update "$mid" "true"
        done
        ui_pause
        return
    fi

    for item in "${updates_available[@]}"; do
        IFS='|' read -r mid mname mcur mnew <<< "$item"
        if [[ "$CHOICE" == *"$mname"* ]]; then
            module_perform_update "$mid" "true"
            ui_pause
            break
        fi
    done
}
export -f module_check_all_updates
