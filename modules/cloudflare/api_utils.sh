#!/bin/bash
# TAV-X Cloudflare API Utilities
# 负责处理 Cloudflare API 的交互逻辑

_cf_api_vars() {
    CF_API_TOKEN_FILE="$CONFIG_DIR/cf_api_token"
}

_cf_api_call() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    
    _cf_api_vars
    if [ ! -f "$CF_API_TOKEN_FILE" ]; then return 1; fi
    local token=$(cat "$CF_API_TOKEN_FILE")
    
    local args=("-s" "-X" "$method" "-H" "Authorization: Bearer $token" "-H" "Content-Type: application/json")
    [ -n "$data" ] && args+=("-d" "$data")
    
    local response=$(curl "${args[@]}" "https://api.cloudflare.com/client/v4$endpoint")
    
    if echo "$response" | grep -q '"success":true'; then
        echo "$response"
        return 0
    else
        echo "$response" >&2
        return 1
    fi
}
export -f _cf_api_vars
export -f _cf_api_call


cf_verify_token() {
    ui_spinner "验证 Token..." "_cf_api_call 'GET' '/user/tokens/verify' >/dev/null"
}

cf_configure_api_token() {
    _cf_api_vars
    ui_header "配置 API Token"
    echo -e "${YELLOW}高级功能：绑定 API Token 可实现 DNS 自动清理。${NC}"
    echo -e "请前往 Dashbord -> API Tokens 创建。"
    echo -e "所需权限: ${CYAN}Zone.DNS:Edit${NC}"
    echo ""
    
    local current=""
    [ -f "$CF_API_TOKEN_FILE" ] && current=$(cat "$CF_API_TOKEN_FILE")
    
    if [ -n "$current" ]; then
        echo -e "当前状态: ${GREEN}已配置${NC} (${current:0:6}...)"
        if ! ui_confirm "是否重新设置？"; then return; fi
    fi
    
    local token=$(ui_input "粘贴 API Token" "" "true")
    if [ -n "$token" ]; then
        echo "$token" > "$CF_API_TOKEN_FILE"
        if cf_verify_token; then
            ui_print success "验证通过！"
        else
            ui_print error "验证失败，Token 无效。"
            rm -f "$CF_API_TOKEN_FILE"
        fi
    fi
    ui_pause
}

cf_api_delete_dns() {
    local hostname="$1"
    [ -z "$hostname" ] && return 1
    
    _cf_api_vars
    if [ ! -f "$CF_API_TOKEN_FILE" ]; then return 2; fi
    
    ui_print info "正在通过 API 搜索 DNS 记录..."
    local zones_json
    if ! zones_json=$(_cf_api_call "GET" "/zones?per_page=50"); then
        ui_print error "获取域名列表失败。"
        return 1
    fi
    
    local zone_id=""
    local zone_name=""
    local best_len=0

    while read -r z_id z_name; do
        if [[ "$hostname" == "$z_name" || "$hostname" == *"$z_name" ]]; then
            local len=${#z_name}
            if (( len > best_len )); then
                best_len=$len
                zone_id="$z_id"
                zone_name="$z_name"
            fi
        fi
    done < <(
        echo "$zones_json" \
        | grep -oE '"id":"[a-f0-9]+","name":"[^"]+"' \
        | sed 's/"id":"//;s/","name":"/ /;s/"//'
    )

    if [ -z "$zone_id" ]; then
        ui_print warn "未找到匹配的 Zone (最长后缀匹配失败)。"
        return 1
    fi

    ui_print info "匹配 Zone: $zone_name"
    
    local dns_json
    if ! dns_json=$(_cf_api_call "GET" "/zones/$zone_id/dns_records?name=$hostname"); then
        ui_print error "查询 DNS 记录失败。"
        return 1
    fi
    
    local record_id=$(echo "$dns_json" | grep -oE '"id":"[a-f0-9]+"' | head -n 1 | cut -d'"' -f4)
    
    if [ -z "$record_id" ]; then
        ui_print warn "未找到该域名的 DNS 记录，可能已删除。"
        return 0
    fi
    
    if _cf_api_call "DELETE" "/zones/$zone_id/dns_records/$record_id" >/dev/null; then
        ui_print success "API: 成功删除 DNS 记录 ($hostname)"
        return 0
    else
        ui_print error "API: 删除 DNS 记录失败。"
        return 1
    fi
}

cf_scan_orphan_dns() {
    _cf_api_vars
    if [ ! -f "$CF_API_TOKEN_FILE" ]; then
        ui_print error "未配置 API Token，无法扫描 DNS。"
        ui_print info "请先在菜单中选择 [🔑 API Token 设置] 进行配置。"
        ui_pause
        return 2
    fi
    
    if [ ! -f "$CF_USER_DATA/cert.pem" ]; then
        ui_print error "未登录 Cloudflare Tunnel，无法比对 UUID。"
        ui_pause
        return 1
    fi

    ui_header "🧹 扫描孤儿 Tunnel DNS"

    local zones_json
    if ! zones_json=$(_cf_api_call "GET" "/zones?per_page=50"); then
        ui_print error "无法获取 Zone 列表。"
        return 1
    fi

    ui_print info "正在获取本地活跃 Tunnel 列表..."
    local alive_tunnels
alive_tunnels=$(cloudflared tunnel list 2>/dev/null | awk 'NR>1 {print $1}')

    local found_any=false

    while read -r zone_id zone_name; do

        ui_print info "扫描 Zone: $zone_name"

        local dns_json
        
        if ! dns_json=$(_cf_api_call "GET" "/zones/$zone_id/dns_records?per_page=100&type=CNAME" 2>/dev/null); then
            ui_print warn "跳过: 无法访问该 Zone (可能无权限)。"
            continue
        fi

        while read -r line; do
            [ -z "$line" ] && continue

            local record_id
            local hostname
            local target
            local uuid

            record_id=$(echo "$line" | grep -oE '"id":"[a-f0-9]+"' | cut -d'"' -f4)
            hostname=$(echo "$line" | grep -oE '"name":"[^"]+"' | cut -d'"' -f4)
            target=$(echo "$line" | grep -oE '"content":"[^"]+"' | cut -d'"' -f4)
            uuid=${target%%.*}

            if ! echo "$alive_tunnels" | grep -q "$uuid"; then
                found_any=true
                echo ""
                echo -e "${YELLOW}⚠️  发现孤儿 DNS:${NC}"
                echo "  Hostname : $hostname"
                echo "  Target   : $target"
                echo "  Zone     : $zone_name"

                if ui_confirm "是否删除该 DNS？"; then
                    if _cf_api_call "DELETE" "/zones/$zone_id/dns_records/$record_id" >/dev/null; then
                        ui_print success "已删除 $hostname"
                    else
                        ui_print error "删除失败：$hostname"
                    fi
                fi
            fi
        done < <(echo "$dns_json" | grep -oE '"id":"[a-f0-9]+".*"type":"CNAME".*"content":"[^ "]+cfargotunnel.com"')

    done < <(echo "$zones_json" | grep -oE '"id":"[a-f0-9]+","name":"[^"]+"' | sed 's/"id":"//;s/","name":"/ /;s/"//')

    echo ""
    if [ "$found_any" = false ]; then
        ui_print success "扫描完成，未发现孤儿 DNS 记录。"
    else
        ui_print success "清理工作已完成。"
    fi
    ui_pause
}