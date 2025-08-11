# PowerShell 核心配置文件

# ---- 模块与配置 ----

# 导入常用模块
Import-Module posh-git -ErrorAction SilentlyContinue
Import-Module PSReadLine -ErrorAction SilentlyContinue

# 配置 PSReadLine，提供更好的命令行编辑体验
Set-PSReadLineOption -EditMode Windows
Set-PSReadLineOption -HistorySearchCursorMovesToEnd

# 设置默认编辑器 (例如 VS Code)
$env:EDITOR = 'code'

# ---- 常用别名与函数 ----

# 导航
Set-Alias -Name ll -Value Get-ChildItem -Option AllScope
function Set-LocationUp { Set-Location .. }
Set-Alias -Name .. -Value Set-LocationUp -Option AllScope

# Git (依赖 posh-git)
Set-Alias -Name gs -Value Get-GitStatus -Option AllScope

# ---- 终端主题 ----

# 加载 Oh My Posh 主题
# 主题文件路径 '{USERPROFILE}\my-theme.omp.json' 将由 dotfiles 管理
oh-my-posh init pwsh --config '{USERPROFILE}\my-theme.omp.json' | Invoke-Expression
