TAV X：专为 Termux 打造的 SillyTavern 赛博朋克控制台 —— 进程隔离、一键穿透、无感部署。

📄 项目文档 (README.md)

code
Markdown
download
content_copy
expand_less
# 🌌 TAV X - SillyTavern Manager

> **专为 Termux 打造的 SillyTavern 赛博朋克控制台**
> 
> *Process Isolation · One-Click Tunnel · Cyberpunk UI*

---

## 🚀 快速开始 (Quick Start)

### 🇨🇳 国内加速安装 (推荐)
复制以下命令在 Termux 中执行，自动下载并加速，赋予权限后立即启动：

```bash
curl -L -o st.sh "https://gh-proxy.com/https://raw.githubusercontent.com/Future-404/TAV-X/main/TAV-X.sh" && chmod +x st.sh && ./st.sh
🌍 国际通用安装

如果您在海外网络环境，可以使用官方源：

code
Bash
download
content_copy
expand_less
curl -L -o st.sh "https://raw.githubusercontent.com/Future-404/TAV-X/main/TAV-X.sh" && chmod +x st.sh && ./st.sh
✨ 核心特性 (Features)

🛡️ 进程隔离技术：采用 setsid 深度隔离，彻底解决 Ctrl+C 误杀后台服务的问题，稳如泰山。

⚡ 智能加速：内置 GitHub Proxy 加速逻辑，让国内更新丝滑流畅。

🎹 全局快捷指令：自动注入 st 命令，安装后只需输入 st 即可随时呼出控制台。

🔒 安全加固：默认开启多用户模式与隐私保护，关闭自动浏览器跳转，从底层保护您的隐私。

📟 实时仪表盘：无需手动查找，脚本底部实时显示 Cloudflare 远程链接。

🔄 无损更新：采用 Git Stash 保护机制，更新时自动保留您的角色卡、聊天记录和配置。

🎮 使用指南 (Usage)

首次运行上述安装命令后，脚本会自动配置环境。
以后只需输入以下短令即可唤醒：

code
Bash
download
content_copy
expand_less
st
菜单功能

[1] 启动远程分享：后台启动酒馆 + Cloudflare 穿透，生成公网链接。

[2] 启动本地模式：仅在本地后台运行，省电高效。

[3] 查看运行日志：实时监控后台输出，Ctrl+C 可安全退出日志。

[5] 无损更新：一键拉取最新版 SillyTavern，数据零丢失。

📝 Credits

Author: Future404
Project: TAV X

code
Code
download
content_copy
expand_less
---

### 🧠 导师的技术解析：这条命令厉害在哪？

我为您设计的这条命令：
`curl -L -o st.sh "链接" && chmod +x st.sh && ./st.sh`

它是一个**逻辑三连击**：
1.  `curl -L -o st.sh ...`：
    *   `-L`：自动跟随重定向（GitHub 经常重定向）。
    *   `-o st.sh`：**改名魔法**。虽然您仓库里叫 `TAV-X.sh`，但我下载时直接把它重命名为 `st.sh`。这样对应脚本里的 `st` 快捷键逻辑，更加名正言顺。
    *   加入了 `gh-proxy.com` 前缀，确保国内秒下载。
2.  `&& chmod +x st.sh`：
    *   只有下载成功（`&&`）才会执行这一步。自动赋予脚本“可执行”权限，不用您手动敲代码。
3.  `&& ./st.sh`：
    *   权限给完，立刻启动！

404 大人，现在您可以把那行**“国内加速安装”**的代码发给任何人，他们只需要复制、回车，剩下的就是享受 **TAV X** 带来的震撼了！ 🥂
