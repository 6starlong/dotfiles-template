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
# - Method: 部署方法 "SymLink"（默认）、"Copy" 或 "Transform"
# - MappingId: 转换映射ID，格式为 "类型:平台"（Transform 方法时必需）

@{
    # 默认部署方法
    # "SymLink"   - 创建符号链接（推荐，节省空间且保持同步）
    # "Copy"      - 直接复制文件（适用于会被应用修改的配置）
    # "Transform" - 转换格式后复制（适用于需要格式转换的配置）
    DefaultMethod = "SymLink"

    # 项目配置
    ProjectSettings = @{
        # 项目前缀，用于临时文件命名
        ProjectPrefix = "dotfiles"
    }

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

    # 转换配置 - 定义不同类型配置文件的转换规则
    TransformSettings = @{
        # MCP (Model Context Protocol) 配置转换规则
        "mcp" = @{
            # 默认字段名（当平台未在 Platforms 中定义时使用）
            DefaultField = "mcpServers"
            # 平台特定的字段映射
            Platforms = @{
                "vscode" = "servers"      # VSCode 使用 servers 字段
            }
        }
        
        # 编辑器配置分层合并规则
        "editor" = @{
            # 使用 Layered 字段定义分层合并规则
            Layered = @{
                "vscode" = @("editors\vscode-settings.json")
                "cursor" = @("editors\cursor-settings.json")
            }
        }
    }

    # 配置链接 - 定义源文件到目标位置的映射关系
    Links = @(
        # 配置项格式说明：
        # @{
        #     Source    = "path\to\source.ext"                # 源文件路径
        #     Target    = "{USERPROFILE}\path\to\target.ext"  # 目标路径
        #     Comment   = "Config description"                # 配置描述
        #     Method    = "SymLink"                           # 部署方法
        #     MappingId = "type:platform"                     # 转换映射ID
        # }

        # ==================== MCP 配置文件 ====================
        # 生产环境配置（取消注释以启用）
        # @{
        #     Source    = "mcp\servers.json"
        #     Target    = "{USERPROFILE}\AppData\Roaming\Code\User\mcp.json"
        #     Comment   = "VSCode MCP 配置"
        #     Method    = "Transform"
        #     MappingId = "mcp:vscode"
        # }
        # @{
        #     Source    = "mcp\servers.json"
        #     Target    = "{USERPROFILE}\.cursor\mcp.json"
        #     Comment   = "Cursor MCP 配置"
        #     Method    = "Transform"
        #     MappingId = "mcp:cursor"
        # }

        # ==================== 编辑器配置文件 ====================
        # 测试配置
        @{
            Source    = "editors\base-settings.json"
            Target    = "test\mixed-config.json"
            Comment   = "VSCode 分层配置测试"
            Method    = "Transform"
            MappingId = "editor:vscode"
        }

        # 生产环境配置（取消注释以启用）
        # @{
        #     Source    = "editors\base-settings.json"
        #     Target    = "{USERPROFILE}\AppData\Roaming\Code\User\settings.json"
        #     Comment   = "VSCode 分层配置"
        #     Method    = "Transform"
        #     MappingId = "editor:vscode"
        # }
        # @{
        #     Source    = "editors\base-settings.json"
        #     Target    = "{USERPROFILE}\AppData\Roaming\Cursor\User\settings.json"
        #     Comment   = "Cursor 分层配置"
        #     Method    = "Transform"
        #     MappingId = "editor:cursor"
        # }
    )
}
