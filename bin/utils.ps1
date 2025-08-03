# utils.ps1
# transform.ps1 和 uninstall.ps1 的共享函数

# 将JSONC内容转换为JSON对象
function ConvertFrom-Jsonc {
    param ([string]$Content)
    # 移除块注释和行注释
    $cleanContent = $Content -replace '(?s)/\*.*?\*/' -replace '(?m)//.*$'
    return $cleanContent | ConvertFrom-Json
}

# 获取转换配置
function Get-TransformConfig {
    param([string]$Format)
    $configPath = Join-Path $script:DotfilesDir "$Format\platforms.json"
    if (-not (Test-Path $configPath)) { 
        throw "配置文件未找到: $configPath" 
    }
    $configContent = Get-Content $configPath -Raw -Encoding UTF8
    return ConvertFrom-Jsonc -Content $configContent
}

# 清理和标准化JSON格式
function Format-JsonClean {
    param([string]$JsonString, [int]$Indent = 2)
    
    # 移除PowerShell的多余空格和奇怪格式
    $cleanJson = $JsonString -replace '\s*:\s*\[\s*\]', ': []'
    $cleanJson = $cleanJson -replace '\s*:\s*\{\s*\}', ': {}'
    $cleanJson = $cleanJson -replace ':\s+\[', ': ['
    $cleanJson = $cleanJson -replace ':\s+\{', ': {'
    $cleanJson = $cleanJson -replace ':\s+(["\d\[\{])', ': $1'
    $cleanJson = $cleanJson -replace '(?m)^\s*$\n', ''
    
    # 重新格式化缩进
    $lines = $cleanJson -split "`r?`n"
    $result = @()
    $currentIndent = 0
    
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if (-not $trimmed) { continue }
        
        # 调整缩进级别
        if ($trimmed -match '^[\}\]]') {
            $currentIndent = [Math]::Max(0, $currentIndent - 1)
        }
        
        # 添加正确缩进的行
        $result += (' ' * ($currentIndent * $Indent)) + $trimmed
        
        # 为下一行调整缩进
        if ($trimmed -match '[\{\[]$') {
            $currentIndent++
        }
    }
    
    return $result -join [System.Environment]::NewLine
}