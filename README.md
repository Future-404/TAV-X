# TAV-X 开发者文档

TAV-X(Termux Automated Venture-X)是一个可扩展、模块化的 Shell 脚本框架，专为在Android Termux环境下部署和管理AI应用而设计，同时兼容debian和Ubuntu。

## 🏗️ 架构概览

TAV-X 采用核心框架与功能模块分离的架构。核心框架负责生命周期管理、UI交互、网络策略和依赖处理；具体的功能应用则封装在独立的“模块”中。

### 目录结构

```text
TAV-X/
├── core/               # 核心框架库
│   ├── env.sh          # 全局环境变量
│   ├── ui.sh           # UI 组件 (Text/Gum 适配器)
│   ├── utils.sh        # 通用工具函数 (网络、Git、文件操作)
│   ├── loader.sh       # 模块动态加载逻辑
│   └── ...
├── modules/            # 功能模块目录
│   ├── sillytavern/    # 示例模块：酒馆
│   │   ├── main.sh     # 模块入口与元数据
│   │   └── ...
│   └── ...
├── config/             # 用户配置文件 (自动生成)
├── bin/                # 外部二进制工具 (由 deps.sh 管理)
└── st.sh               # 项目启动入口脚本
```

## 🧩 模块系统

模块是 TAV-X 的核心。任何位于 `modules/` 目录下且包含 `main.sh` 的文件夹都会被识别为一个模块。

### 元数据格式
每个模块的 `main.sh` 必须以元数据块开头，供 `core/loader.sh` 解析：

```bash
# [METADATA]
# MODULE_ID: my_module
# MODULE_NAME: 模块名称
# MODULE_ENTRY: my_module_menu
# APP_AUTHOR: 作者名称
# APP_PROJECT_URL: https://github.com/example/project
# APP_DESC: 模块的功能简述。
# [END_METADATA]
```

### 生命周期函数
标准模块应实现以下函数（建议以 `MODULE_ID` 作为前缀以防冲突）：

*   `${MODULE_ID}_install`: 负责安装依赖、克隆仓库及初始化环境。
*   `${MODULE_ID}_start`: 启动应用程序的逻辑（支持后台运行）。
*   `${MODULE_ID}_stop`: 停止应用程序。
*   `${MODULE_ID}_menu`: 模块的主菜单入口（对应元数据中的 `MODULE_ENTRY`）。

## 🛠️ 核心 API

TAV-X 提供了一套丰富的 Shell 函数库，旨在简化开发流程。

### UI 组件 (`core/ui.sh`)
自动适配图形化与纯文本模式。

*   `ui_print <type> <message>`: 打印信息 (info)、成功 (success)、警告 (warn) 或错误 (error)。
*   `ui_menu <title> <option1> <option2> ...`: 渲染交互式选择菜单。
*   `ui_input <prompt> [default]`: 获取用户输入。
*   `ui_confirm <prompt>`: 布尔值 (Yes/No) 确认框。
*   `ui_stream_task <title> <command>`: 执行耗时任务，并显示进度视图或旋转进度条。

### 通用工具 (`core/utils.sh`)
*   `get_app_path <id>`: 获取应用的标准化安装路径。
*   `prepare_network_strategy [type]`: 自动配置代理或国内镜像源。
*   `git_clone_smart <args> <repo> <dir>`: 支持自动镜像加速的 Git 克隆。
*   `check_process_smart <pid_file> <pattern>`: 鲁棒的进程状态检查。

## 💻 参与贡献与发布

TAV-X 支持加载本地模块和云端商店模块。您可以根据需求选择开发方式。

### 方式一：开发本地调试
1.  **Fork** 本仓库到您的账户。
2.  在 `modules/` 目录下创建一个新文件夹（以模块ID命名）。
3.  在其中编写 `main.sh`，务必包含标准的元数据块。
4.  运行 `st` 脚本，系统会自动扫描并加载您的本地模块进行测试。

### 方式二：发布到应用商城
如果您希望将模块分享给所有 TAV-X 用户：

1.  **建立独立仓库**：将您的模块代码托管在一个独立的Git仓库中（推荐 GitHub）。
    *   *注意：`main.sh` 必须位于仓库根目录。*
2.  **提交收录申请**：编辑本仓库的 `config/store.csv` 文件，在末尾追加一行配置：
    ```csv
    模块ID,模块显示名称,一句话描述,Git仓库地址,分支名称
    ```
    > 示例：`super_tool,超级工具箱,这是一个强大的辅助工具,https://github.com/user/super-tool.git,main`
3.  **提交 PR**：向我们提交 Pull Request。审核合并后，您的模块将实时出现在所有用户的“应用中心”列表中。

## 📄 许可证
本项目采用 AGPL-3.0 许可证。