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
# - Method: 部署方法 "SymLink"（默认）或 "Copy" 或 "Transform"
# - MappingId: 映射标识符，用于区分多个目标指向同一源的情况，也用于临时文件命名

@{
    # 默认部署方法
    # "SymLink" - 创建符号链接
    # "Copy" - 直接复制文件（适用于会被应用修改的配置）
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

    # 配置链接
    Links = @(
        # 示例格式：
        # @{
        #     Source    = "path\to\source.ext"                # 源文件路径
        #     Target    = "{USERPROFILE}\path\to\target.ext"  # 目标路径
        #     Comment   = "Config description"                # 配置描述
        #     Method    = "SymLink"                           # 部署方法（可选）
        #     MappingId = "mapping:id"                        # 映射ID（可选）
        # }


        # Test 配置
        @{
            Source    = "test\demo.txt"
            Target    = "D:\Projects\dotfiles\test\demo1.txt"
            Comment   = "Test 1"
            Method    = "Copy"
        }

        @{
            Source    = "test\demo.txt"
            Target    = "D:\Projects\dotfiles\test\demo2.txt"
            Comment   = "Test 2"
            Method    = "Copy"
        }

        # MCP 配置文件
        @{
            Source    = "mcp\base.json"
            Target    = "D:\Projects\dotfiles\test\demo.json"
            Comment   = "MCP Config for Demo"
            Method    = "Transform"
            MappingId = "mcp:demo"
        }

        @{
            Source    = "mcp\base.json"
            Target    = "D:\Projects\dotfiles\test\vscode-mcp.json"
            Comment   = "MCP Config for VSCode"
            Method    = "Transform"
            MappingId = "mcp:vscode"
        }

        # @{
        #     Source    = "mcp\base.json"
        #     Target    = "{USERPROFILE}\AppData\Roaming\Code\User\mcp.json"
        #     Comment   = "MCP Config for VSCode"
        #     Method    = "Transform"
        #     MappingId = "mcp:vscode"
        # }

        # @{
        #     Source    = "mcp\base.json"
        #     Target    = "{USERPROFILE}\.cursor\mcp.json"
        #     Comment   = "MCP Config for Cursor"
        #     Method    = "Transform"
        #     MappingId = "mcp:cursor"
        # }
    )
}
