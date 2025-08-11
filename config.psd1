# config.psd1
# Dotfiles 管理脚本的核心配置文件
#
# 添加新配置的步骤：
# 1. 将源文件添加到相应目录
# 2. 在下面的 Links 数组中添加新条目
#
# 配置项说明：
# - Source: 源文件路径（相对于仓库根目录）
# - Target: 目标路径（使用 {USERPROFILE} 占位符）
# - Comment: 配置描述
# - Method: 部署方法 "SymLink"（默认）或 "Copy"

@{
    # 默认部署方法
    # "SymLink"   - 创建符号链接（推荐，节省空间且保持同步）
    # "Copy"      - 直接复制文件（适用于会被应用修改的配置）
    DefaultMethod = "SymLink"

    # 备份配置
    BackupSettings = @{
        # 备份存储位置（相对于 dotfiles 根目录）
        BackupDir = "backups"
        # 是否创建带时间戳的备份文件夹
        UseTimestamp = $true
        # 保留的备份文件夹数量上限（0 = 无限制）
        MaxBackups = 10
        # 备份时间戳格式（Windows 文件名兼容）
        TimestampFormat = "yyyy-MM-dd_HH-mm-ss"
    }

    # 忽略列表配置
    # 用于在部署时，跳过那些在 Links 中已定义、但当前不希望同步的配置项。
    # 支持 .gitignore 语法。
    IgnoreList = @(
        # 按完整路径忽略单个文件
        # "configs/local.settings.json"

        # 按目录忽略
        # "configs/linux/**"

        # 按通配符模式忽略
        "**/*secret*"

        # 否定模式 (即使上层目录被忽略，也强制部署此文件)
        # "!configs/linux/important.conf"
    )

    # 转换配置 - 定义不同类型配置文件的转换规则
    TransformSettings = @{
        # 编辑器分层配置
        "editor" = @{
            SourceFile = "templates\editors\settings.base.json"
            Layered = @{
                "vscode" = @("templates\editors\settings.vscode.json")
                "cursor" = @("templates\editors\settings.cursor.json")
            }
        }
        # MCP 服务器列表字段映射
        "mcp" = @{
            SourceFile   = "templates\mcp\servers.json"
            DefaultField = "mcpServers"
            Platforms    = @{
                vscode = "servers" # 将 mcpServers 映射为 VS Code MCP 所需的 servers
            }
        }
    }

    # 配置链接 - 定义源文件到目标位置的映射关系
    Links = @(
        # ---- 版本控制 ----
        @{
            Source    = "configs\git\.gitconfig"
            Target    = "{USERPROFILE}\.gitconfig"
            Comment   = "Git 全局配置"
            Method    = "SymLink"
        },
        @{
            Source    = "configs\git\.gitignore_global"
            Target    = "{USERPROFILE}\.gitignore_global"
            Comment   = "Git 全局忽略文件"
            Method    = "SymLink"
        },

        # ---- Shell 与终端 ----
        @{
            Source    = "configs\powershell\Microsoft.PowerShell_profile.ps1"
            Target    = "{USERPROFILE}\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
            Comment   = "PowerShell 7+ 配置文件"
            Method    = "SymLink"
        },
        @{
            Source    = "configs\powershell\Microsoft.PowerShell_profile.ps1"
            Target    = "{USERPROFILE}\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
            Comment   = "Windows PowerShell 5.x 配置文件"
            Method    = "SymLink"
        },
        @{
            Source    = "configs\oh-my-posh\my-theme.omp.json"
            Target    = "{USERPROFILE}\my-theme.omp.json"
            Comment   = "Oh My Posh 主题文件"
            Method    = "SymLink"
        },

        # ---- 编辑器 (使用 transform.ps1 生成) ----
        @{
            Source    = "configs\vscode\settings.json"
            Target    = "{USERPROFILE}\AppData\Roaming\Code\User\settings.json"
            Comment   = "VS Code 用户设置 (Generated)"
            Method    = "Copy"
            Transform = "editor:vscode"
        },
        @{
            Source    = "configs\vscode\mcp.json"
            Target    = "{USERPROFILE}\AppData\Roaming\Code\User\mcp.json"
            Comment   = "MCP 服务器列表 (Generated)"
            Method    = "Copy"
            Transform = "mcp:vscode"
        },

        # ---- 开发工具 ----
        @{
            Source    = "configs\npm\.npmrc"
            Target    = "{USERPROFILE}\.npmrc"
            Comment   = "NPM 配置文件"
            Method    = "SymLink"
        },
        @{
            Source    = "configs\ssh\config"
            Target    = "{USERPROFILE}\.ssh\config"
            Comment   = "SSH 客户端配置"
            Method    = "Copy"  # 使用复制以保护权限
        }
    )
}
