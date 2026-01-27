#!/bin/bash
# Grok2API Utils: Configuration & Tutorials

grok_set_port() {
    _grok_vars
    if [ ! -f "$GROK_CONF" ]; then ui_print error "未找到配置文件，请先安装。"; return 1; fi
    
    local current
    current=$(grep "^PORT=" "$GROK_CONF" | cut -d'=' -f2)
    local new_port
    new_port=$(ui_input "请输入新端口号" "${current:-8001}")
    
    if [[ "$new_port" =~ ^[0-9]+$ ]]; then
        if grep -q "^PORT=" "$GROK_CONF"; then
            sed -i "s/^PORT=.*/PORT=$new_port/" "$GROK_CONF"
        else
            echo "PORT=$new_port" >> "$GROK_CONF"
        fi
        ui_print success "端口已修改为 $new_port (重启服务后生效)"
        if ui_confirm "立即重启服务？"; then
            grok_stop
            sleep 1
            grok_start
        fi
    else
        ui_print error "无效的端口号。"
    fi
}

grok_show_tutorial() {
    ui_header "如何获取 Grok Token"
    
    local md_content="
# 📚 Grok Token 获取指南

获取到的 
 sso 
 Token 是通用的，您可以在 PC 上获取后发送到手机使用。

---

## 💻 方案一：PC 浏览器 (推荐)

1. 使用电脑浏览器登录 [grok.com](https://grok.com)。
2. 按下键盘上的 **F12** 键（或右键 -> 检查）打开开发者工具。
3. 切换到顶部的 **Application** (应用) 选项卡。
4. 在左侧菜单找到 **Storage** -> **Cookies**，点击展开并选择 
 https://grok.com 
。
5. 在右侧列表中找到名为 
 sso 
 的条目。
6. 双击其 **Value** (值) 列，复制那段长长的字符串。

---

## 📱 方案二：安卓端浏览器

如果您身边没有电脑，可以使用支持插件的安卓浏览器。

### 1. 准备浏览器
下载支持 Chrome 插件的浏览器，推荐：
* **Kiwi Browser**
* **狐猴浏览器 (Lemur)**

### 2. 安装插件
在浏览器扩展商店搜索并安装 
 Cookie-Editor 
 插件。

### 3. 提取 Token
1. 登录 [grok.com](https://grok.com)。
2. 点击浏览器菜单中的 **Cookie-Editor** 图标。
3. 搜索 
 sso 
 并复制其值。

---

## 🚀 填入后台
拿到 Token 后，访问本服务的 **Web 面板** (默认 http://127.0.0.1:8001/login)，在账号管理中粘贴并保存。
"

    if [ "$HAS_GUM" = true ]; then
        echo "$md_content" | gum format
    else
        echo -e "${YELLOW}Grok Token 获取指南${NC}"
        echo -e "【PC端】F12 -> Application -> Cookies -> grok.com -> 复制 sso 值"
        echo -e "【安卓端】使用 Kiwi 浏览器安装 Cookie-Editor 插件提取 sso 值"
    fi
    ui_pause
}
