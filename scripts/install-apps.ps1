# =========================================================================
#
#   安装应用 (install-apps.ps1)
#
#   使用 Winget 自动化安装常用软件
#
# =========================================================================

# ---- 使用说明 ----
#
#   1. 如何使用:
#      - 推荐: 逐个复制想安装的命令到 PowerShell 终端中执行。
#      - 批量: 删除命令前的 '#' 注释符，然后直接运行本脚本。
#
#   2. 前提条件:
#      - 确保 winget 可用。建议以管理员身份运行 PowerShell。
#
#   3. 高级选项 (可选):
#      - --source: 指定来源 (msstore 或 winget)
#      - --scope:  指定范围 (user 或 machine)
#      - 示例: winget install <ID> --source msstore --scope user
#
# ---- Winget 命令速查 ----
#
#   search, install, uninstall, upgrade, upgrade --all, list
#
# =========================================================================
#   应用列表
# =========================================================================

# ---- 终端与 Shell ----

# PowerShell 7 (开发主力)
# winget install Microsoft.PowerShell

# Oh My Posh (终端美化)
# winget install JanDeDobbeleer.OhMyPosh --source msstore --scope user

# Git (版本控制)
# winget install Git.Git


# ---- 开发工具 ----

# Visual Studio Code
# winget install Microsoft.VisualStudioCode

# Python 3
# winget install Python.Python.3

# Node.js (LTS)
# winget install OpenJS.NodeJS.LTS

# nvm-for-windows (Node.js 版本管理器)
# winget install CoreyButler.NVMforWindows

# Docker Desktop
# winget install Docker.DockerDesktop


# ---- 浏览器 ----

# Google Chrome
# winget install Google.Chrome

# Microsoft Edge
# winget install Microsoft.Edge


# ---- 效率工具 ----

# Everything (文件秒搜)
# winget install voidtools.Everything

# 7-Zip (压缩软件)
# winget install 7zip.7zip

# PowerToys (微软官方工具集)
# winget install Microsoft.PowerToys

# Notion (笔记与协作)
# winget install Notion.Notion

# Obsidian (知识管理)
# winget install Obsidian.Obsidian


# ---- 娱乐与社交 ----

# QQ
# winget install Tencent.QQ

# WeChat
# winget install Tencent.WeChat

# Steam
# winget install Valve.Steam
