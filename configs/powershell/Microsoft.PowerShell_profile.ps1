# ======================================================================
# PowerShell 核心配置文件
# 美化终端、集成常用工具、提升命令行工作效率
# ======================================================================

# ----------------------------------------------------------------------
# 1. 安装必备模块
# ----------------------------------------------------------------------
# 首次配置或更新时，请在 PowerShell (Admin) 中执行以下命令：
#
# Install-Module posh-git -Scope CurrentUser -Force
# Install-Module PSReadLine -Scope CurrentUser -Force

# ----------------------------------------------------------------------
# 2. 导入核心模块
# ----------------------------------------------------------------------
# 加载导入的模块，增强终端功能。
Import-Module posh-git -ErrorAction SilentlyContinue
Import-Module PSReadLine -ErrorAction SilentlyContinue


# ----------------------------------------------------------------------
# 3. PSReadLine (命令行编辑)
# ----------------------------------------------------------------------
# 配置语法高亮、历史记录、自动补全等命令行编辑功能。
Set-PSReadLineOption -EditMode Windows               # 设置编辑模式为 Windows 风格 (快捷键同 cmd)
Set-PSReadLineOption -PredictionSource History       # 开启基于历史的命令预测 (输入命令时会灰色显示建议)
Set-PSReadLineOption -HistorySearchCursorMovesToEnd  # 搜索历史命令时，光标自动置于末尾
# Set-PSReadLineOption -ViModeIndicator Script       # (可选) 如果你习惯 Vi/Vim，可以开启 Vi 模式

# 补全增强配置
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete                 # 菜单式补全
Set-PSReadLineKeyHandler -Chord "Ctrl+RightArrow" -Function ForwardWord  # 逐字补全


# ----------------------------------------------------------------------
# 4. 环境变量
# ----------------------------------------------------------------------
# 默认编辑器
$env:EDITOR = "code"


# ----------------------------------------------------------------------
# 5. 命令别名
# ----------------------------------------------------------------------
# 为常用命令创建简短的别名以提升效率。
Set-Alias -Name pn -Value pnpm -Option AllScope         # pn -> pnpm


# ----------------------------------------------------------------------
# 6. Oh My Posh (主题)
# ----------------------------------------------------------------------
# 初始化 Oh My Posh，美化终端提示符。
# !! 重要: 请确保终端已配置 Nerd Font 字体以正常显示图标。
# !! 字体下载: https://www.nerdfonts.com/font-downloads
#
# 主题预览: https://ohmyposh.dev/docs/themes
oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH/catppuccin_mocha.omp.json" | Invoke-Expression
