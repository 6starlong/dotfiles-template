# ======================================================================
#  SIMPLIFIED ZSH CONFIGURATION TEMPLATE (.zshrc)
#  一个现代、快速且高效的 Zsh 配置模板。
# ======================================================================

# ----------------------------------------------------------------------
# 1. 环境变量 (Environment Variables)
# ----------------------------------------------------------------------
# 将 `~/.local/bin` 添加到你的 PATH
export PATH="$HOME/.local/bin:$PATH"

# 设置默认编辑器
export EDITOR='vim'

# ----------------------------------------------------------------------
# 2. 核心 Shell 选项 (Core Options)
# ----------------------------------------------------------------------
# 历史记录设置
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS    # 忽略连续重复的命令
setopt SHARE_HISTORY       # 在所有打开的终端间共享历史记录

# 导航
setopt AUTO_CD             # 如果输入的是目录名，直接 cd

# ----------------------------------------------------------------------
# 3. 自动补全 (Completion)
# ----------------------------------------------------------------------
# 启用 Zsh 强大的补全系统
autoload -U compinit
compinit

# ----------------------------------------------------------------------
# 4. 别名 (Aliases)
# ----------------------------------------------------------------------
# 为常用命令创建快捷方式
alias ls='ls --color=auto'
alias ll='ls -l'
alias la='ls -la'
alias grep='grep --color=auto'
alias c='clear'

# Git 常用别名
alias g='git'
alias gs='git status'
alias ga='git add'
alias gc='git commit -m'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'

# ----------------------------------------------------------------------
# 5. 函数 (Functions)
# ----------------------------------------------------------------------
# 创建目录并立即进入
mkcd() {
  mkdir -p "$1" && cd "$1"
}

# ----------------------------------------------------------------------
# 6. 插件 (Plugins) - 强烈推荐
# ----------------------------------------------------------------------
# 手动加载插件。请确保你已经按照插件的说明将它们下载到指定位置。
# 推荐存放位置: ~/.zsh/plugins/

# zsh-syntax-highlighting (提供命令语法高亮)
# 安装: git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.zsh/plugins/zsh-syntax-highlighting
if [ -f ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]; then
  source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

# zsh-autosuggestions (提供命令输入建议)
# 安装: git clone https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/plugins/zsh-autosuggestions
if [ -f ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]; then
  source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

# ----------------------------------------------------------------------
# 7. 加载本地/私有配置
# ----------------------------------------------------------------------
# 用于存放私有配置（如 API 密钥），此文件应被 .gitignore 忽略
if [ -f ~/.zshrc.local ]; then
  source ~/.zshrc.local
fi

echo "Simplified Zsh config loaded."
