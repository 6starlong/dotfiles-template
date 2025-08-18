# PowerShell Dotfiles 管理工具

一个功能强大的跨平台 dotfiles 管理工具，基于 PowerShell 构建，提供智能配置部署、模板转换、自动备份和分层配置管理，实时同步你的开发环境配置。

## ✨ 主要功能

- **✅ 配置状态检查**: 实时检查每个配置的同步状态 (已同步、未同步、未部署等)
- **⚙️ 灵活部署方式**: 支持文件复制 `Copy` 及文件/目录符号链接 `SymLink` 多种部署模式
- **🛡️ 自动备份**: 安装前自动备份现有配置，并支持交互式地创建、恢复和清理备份
- **🚀 智能 JSON 转换**: 支持 JSONC、深度合并及字段映射实现高级配置管理
- **💻 跨平台分层配置**: 兼容 Windows/macOS/Linux，通过叠加文件管理差异
- **🚫 灵活忽略机制**: 使用类似 `.gitignore` 的语法控制部署
- **🔒 Windows 自动提权**: 自动请求管理员权限简化符号链接创建

## 🚀 快速开始

1. **克隆项目**:

    ```shell
    git clone https://github.com/6starlong/dotfiles-template.git dotfiles
    cd dotfiles
    ```

2. **自定义配置**:
    - 将你的配置文件放入 `configs/` 目录。
    - 在 `config.psd1` 中为你添加的文件或目录创建链接。

3. **运行安装**:

    ```shell
    .\setup.cmd
    # or run
    # ./setup.sh
    ```

## 📁 项目结构

```text
dotfiles/
├── backups/              # 自动备份 (被 git 忽略)
├── bin/                  # 核心管理脚本
├── configs/              # 配置文件目录
│   ├── git/              # Git 配置
│   ├── vscode/           # VS Code 配置
│   └── ...
├── lib/                  # 共享模块
├── scripts/              # 辅助脚本
│   └── transform.ps1     # 转换工具
├── templates/            # 配置生成模板
│   ├── editors/          # 编辑器模板
│   └── ...
├── config.psd1           # 主配置文件
├── README.md             # 说明文档
├── setup.cmd             # Windows 启动脚本
└── setup.sh              # macOS/Linux 启动脚本
```

## ⚙️ 核心工作流

你有两种核心方式来管理你的配置文件。

### 方式一：添加配置文件 (最常用)

适用于大多数独立的配置文件或配置目录。只需文件或目录放入 `configs/`，然后在 `config.psd1` 中为其创建条目即可。

**注意**：目录类型的链接仅支持 `SymLink` 方式。请确保目标路径是一个不存在或为空的目录，且不要将其指向已有重要文件或非独立的配置目录，以避免数据丢失或覆盖。

```powershell
# 链接单个文件 (Method: "SymLink" 或 "Copy")
@{
    Source    = "configs\git\.gitconfig"
    Target    = "{USERPROFILE}\.gitconfig"
    Comment   = "Git 全局配置"
    Method    = "SymLink"
}

# 链接整个目录 (Method 仅支持 "SymLink")
@{
    Source    = "configs\oh-my-posh\themes"
    Target    = "{USERPROFILE}\AppData\Local\Programs\oh-my-posh\themes"
    Comment   = "Oh My Posh 主题目录"
    Method    = "SymLink"
}
```

**安装**: 双击启动 `setup.cmd` 或运行 `./setup.sh`。

### 方式二：使用模板生成

适用于需要为不同应用或平台生成变体的复杂 JSON 配置。

#### 1. 字段映射 (FieldMapping)

当多个应用共享相同的值，但键名不同时使用。

- **场景**: 你的通用服务器列表使用 `mcpServers` 作为键名，但是 VS Code 使用 `servers`。
- **配置**:

  ```powershell
  # 在 config.psd1 中
  TransformSettings = @{
      "mcp" = @{
          SourceFile   = "templates\mcp\servers.json"
          DefaultField = "mcpServers"
          Platforms    = @{ vscode = "servers" }
      }
  }
  Links = @(
      @{
          Source    = "configs\mcp\servers.json"
          Target    = "{USERPROFILE}\AppData\Roaming\Code\User\mcp.json"
          Method    = "Copy"
          Transform = "mcp:vscode"
      }
  )
  ```

- **使用**: 运行 `.\scripts\transform.ps1 -Type "mcp:vscode"` 即可生成配置文件。

#### 2. 分层配置 (Layered)

当需要为不同应用（如 VS Code vs Cursor）或平台提供不同配置时使用。

- **场景**: VS Code 和 Cursor 共享一套基础配置，但各自有少量特殊设置。
- **配置**:

  ```powershell
  # 在 config.psd1 中
  TransformSettings = @{
      "editor" = @{
          SourceFile = "templates\editors\settings.base.json"
          Layered    = @{
              "vscode" = @("templates\editors\settings.vscode.json")
              "cursor" = @("templates\editors\settings.cursor.json")
          }
      }
  }
  Links = @(
      @{
          Source    = "configs\vscode\settings.json"
          Target    = "{USERPROFILE}\AppData\Roaming\Code\User\settings.json"
          Method    = "Copy"
          Transform = "editor:vscode"
      }
  )
  ```

- **使用**: 运行 `.\scripts\transform.ps1 -Type "editor:vscode"` 来生成 VS Code 的配置。
- **提示**: 你还可以在任何层级的文件中使用 `$excludeFields` 数组来移除顶层字段。

## 📋 使用方法

### 交互式管理

```shell
.\setup.cmd
# or run
# ./setup.sh
```

### 命令行使用

```shell
# 安装所有配置
.\bin\install.ps1

# 同步配置
.\bin\sync.ps1

# 检查状态
.\bin\status.ps1

# 创建备份
.\bin\backup.ps1

# 卸载所有配置
.\bin\uninstall.ps1

# 生成配置文件
.\scripts\transform.ps1
```

## 🔧 包含的配置示例

本模板默认包含以下常用配置，你可以直接修改使用：

- **Git**:
  - `.gitconfig`: 全局 Git 配置。
  - `.gitignore_global`: Git 全局忽略文件。
- **PowerShell**:
  - `Microsoft.PowerShell_profile.ps1`: PowerShell 核心配置文件。
- **NPM**:
  - `.npmrc`: NPM 配置文件。
- **SSH**:
  - `config`: SSH 客户端配置，用于简化远程连接。
- **VS Code (通过模板生成)**:
  - `settings.json`: 编辑器设置。
  - `mcp.json`: MCP 服务器列表。
- **Zsh**:
  - `.zshrc`: Zsh 核心配置文件。

## 🔒 处理敏感数据与特殊文件

原则：为了保证仓库的安全和通用性，请**不要**直接向 Git 仓库提交任何**密钥**、**令牌**或**私有信息**。

推荐使用以下方法来管理这些文件：

1. **使用模板**: 对于包含敏感信息的配置文件，在仓库中只保存一个带有占位符的 `.template` 版本。

    ```json
    // configs/app/config.template.json
    {
        "API_KEY": "YOUR_API_KEY"
    }
    ```

    然后在本地创建真实的配置文件，并将其路径添加到 `.gitignore` 中。

2. **使用环境变量**: 在脚本或配置中通过 `$env:API_KEY` 引用系统环境变量，而不是硬编码值。

3. **使用 `IgnoreList`**: 在 `config.psd1` 中添加不需要部署的配置路径，实现差异化管理配置文件。

## 🔍 常见问题

**配置未生效**：

- 确保目标应用已关闭
- 检查 `config.psd1` 中的文件路径
- 使用 `.\bin\status.ps1` 检查状态

## 📄 许可证

MIT License
