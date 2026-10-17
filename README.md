<div align="center">

# 🚀 TAV-X (Termux Automated Venture-X)

> **“别让虚拟的温柔，偷走了你在现实里本该拥有的温暖。”**

[![Version](https://img.shields.io/badge/version-v3.5.0-blue.svg)](https://github.com/Future-404/TAV-X)
[![License](https://img.shields.io/badge/license-AGPL--3.0-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android%20Termux%20%7C%20Linux-orange.svg)](#)
[![Shell](https://img.shields.io/badge/shell-Bash-yellow.svg)](#)

**TAV-X** 是专为 **Android Termux** 打造的可扩展、模块化 AI 应用部署与全生命周期管理框架，同时全面兼容 **Debian** 与 **Ubuntu**。  
集成了系统级服务守护、后台保活、内网穿透、网络镜像加速与丰富的 AI 逆向及交互应用。

</div>

---

## ⚡ 快速安装与启动

### 📥 一键安装（推荐）

打开 Termux 终端，复制并执行以下命令即可全自动完成依赖安装与环境初始化：

```bash
curl -s -L https://tav-x.rka.qzz.io | bash
```

> **备用加速节点**（若上方链接不可达可使用）：
> ```bash
> curl -s -L https://tav-x.future404.qzz.io | bash
> ```

### 🛠️ Git 源码手动安装

```bash
git clone https://github.com/Future-404/TAV-X.git ~/.tav_x && bash ~/.tav_x/st.sh
```

### 🎯 启动面板

安装完成后，在终端任意位置直接输入快捷指令即可打开交互式主控制台：

```bash
st
```

---

## ⌨️ 终端快捷指令

无需每次都进入交互菜单，直接在终端执行即可快速控制与排错：

| 快捷指令 | 说明 |
| :--- | :--- |
| `st` | 打开 TAV-X 交互式图形/文本主菜单 |
| `st ps` | 查看当前所有运行中的服务状态与 PID |
| `st re` | 一键重启所有后台运行中的应用服务 |
| `st stop` | 一键平滑停止所有运行中的服务 |
| `st hb` | 快捷开关无声音频后台保活守护 (`audio_keeper`) |
| `st update` | 强制检查并同步最新的 TAV-X 脚本核心代码 |
| `st log` | 查看当前有可用日志的应用 ID 列表 |
| `st log <ID>` | 实时监控指定应用日志（例如 `st log aistudio2api`，按 `q` 退出） |

---

## ✨ 核心特性亮点

### 📱 原生 Android / Termux 深度融合
- **系统服务守护**：基于 `termux-services` (runit) 架构，应用后台持续运行、故障自动重启、开机自启。
- **锁屏防休眠**：联动 `termux-wake-lock` 与静音音频流双重保活机制，彻底规避锁屏 CPU 降频或休眠。
- **ADB 系统级保活**：无需 Root，通过无线调试一键解除 Android 12+ 幽灵进程杀手（Phantom Process Killer）及系统电池优化白名单。

### ⚡ 极致性能与现代交互
- **纯原生性能重构**：v3.5.0 彻底消除循环中的外部子进程调用（`basename`/`dirname`/`cat`/`awk`/`xargs`），菜单打开与列表切换零延迟秒开。
- **自适应 UI 引擎**：支持 Gum 现代富文本交互卡片，并自动无缝回退至纯 ANSI 高度优化的终端界面。

### 🌐 智能全自动网络优化
- **国内镜像测速直连**：内置多组主流 GitHub 镜像源，自动并发测速并选择延迟最低的通道加速下载与克隆。
- **本地代理穿透**：智能识别本地常见代理端口（Clash / V2Ray / Sing-box 等），一键配置终端环境变量。

### 🤖 丰富的模块化应用生态
- **🚀 AIStudio2API (v3.5.0 新增)**：Google AI Studio 逆向 API 网关，集成纯 Go 进程内 WAA 算法，免浏览器、极低内存，支持多账号凭据导入与 Web 控制台，完美规避 Android seccomp 限制。
- **🎭 SillyTavern (酒馆)**：移动端一键部署酒馆前端与 Node.js 运行时，支持官方/第三方插件拓展与安全备份恢复。
- **🧠 Grok2API**：支持网页双模逆向的 Grok API 网关服务。
- **💎 Gemini CLI / GCLI2API**：Google 官方 Gemini 命令行及 API 转换网关。
- **☁️ Cloudflare Tunnel**：无需公网 IP 与云服务器，免费一键穿透手机本地服务至公网 HTTPS。
- **🛡️ Mihomo (Clash Meta)**：轻量级网络代理分流内核。
- **💻 CodeXMobile / Koishi**：代码移动工作区与多协议机器人框架。

---

## 🏗️ 架构概览与目录结构

TAV-X 采用核心框架与应用模块解耦的架构：

```text
TAV-X/
├── core/               # 核心框架库
│   ├── env.sh          # 全局环境变量与版本配置
│   ├── ui.sh           # 自适应 UI 渲染引擎
│   ├── utils.sh        # 通用系统工具与服务注册逻辑
│   ├── loader.sh       # 模块动态扫描与加载引擎
│   ├── store.sh        # 云端应用中心与本地模块管理
│   ├── net_utils.sh    # 智能网络策略与镜像加速
│   └── updater.sh      # 脚本自更新逻辑
├── modules/            # 功能模块目录
│   ├── aistudio2api/   # Google AI Studio 逆向模块
│   ├── sillytavern/    # SillyTavern 酒馆模块
│   ├── grok/           # Grok2API 模块
│   └── ...
├── config/             # 用户自定义配置文件
├── bin/                # 外部预编译工具
└── st.sh               # 统一启动与安装入口
```

---

## 🧩 模块开发与贡献

每个模块均拥有独立且完整的生命周期，位于 `modules/<MODULE_ID>/main.sh`。

### 1. 规范元数据头
模块的 `main.sh` 需以标准元数据块开头：

```bash
# [METADATA]
# MODULE_ID: my_module
# MODULE_NAME: 我的应用
# MODULE_ENTRY: my_module_menu
# APP_CATEGORY: AI 工具
# APP_AUTHOR: 作者名
# APP_PROJECT_URL: https://github.com/example/my_module
# APP_DESC: 模块的功能简要介绍。
# [END_METADATA]
```

### 2. 标准生命周期函数
模块应实现以下标准函数：
- `${MODULE_ID}_install`：依赖安装与初始化配置。
- `${MODULE_ID}_start`：启动服务（支持 Termux `tavx_service_register` 或后台 nohup）。
- `${MODULE_ID}_stop`：平滑停止服务。
- `${MODULE_ID}_menu`：模块的主管理界面入口。

### 3. 发布到应用商店
1. 将模块托管在独立的 Git 仓库（确保 `main.sh` 位于仓库根目录）。
2. 编辑本仓库的 `config/store.csv` 追加收录行：
   ```csv
   模块ID,模块显示名称,分类,一句话描述,Git仓库地址,分支名称
   ```
3. 提交 Pull Request，审核合并后将自动对所有 TAV-X 用户生效。

---

## 💬 交流与支持

- 💬 **官方反馈 QQ 群**：`616353694`
- 👤 **作者 QQ**：`317032529`
- 📮 **反馈邮箱**：`future_404@outlook.com`
- 🐙 **GitHub 项目主页**：[https://github.com/Future-404/TAV-X](https://github.com/Future-404/TAV-X)

---

## 📄 许可证与使用限制

本项目基于 **AGPL-3.0** 许可证发布。

- 本项目 **仅限个人学习、技术研究与非商业用途**。
- **严禁任何形式的商业用途**，包括但不限于收费部署、商业托管、转售、或作为任何盈利性产品与服务的一部分。
- 依据 AGPL-3.0 协议要求，若修改本项目代码并向公众提供服务，必须开源对应修改后的全部源代码。