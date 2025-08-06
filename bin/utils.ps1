# utils.ps1
# transform.ps1 和 uninstall.ps1 的共享函数

# 将JSONC内容转换为JSON对象
function ConvertFrom-Jsonc {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Content
    )
    
    process {
        # 移除块注释和行注释
        $cleanContent = $Content -replace '(?s)/\*.*?\*/' -replace '(?m)//.*$'
        return $cleanContent | ConvertFrom-Json
    }
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

# 比较两个文件的原始内容是否相等
function Test-FileContentEqual {
    param(
        [Parameter(Mandatory)][string]$File1,
        [Parameter(Mandatory)][string]$File2
    )

    try {
        # 如果任一文件不存在，则认为不相等
        if (-not (Test-Path $File1) -or -not (Test-Path $File2)) {
            return $false
        }
        $content1 = Get-Content $File1 -Raw -ErrorAction Stop
        $content2 = Get-Content $File2 -Raw -ErrorAction Stop
        return $content1 -eq $content2
    } catch {
        return $false
    }
}

# 比较两个JSON/JSONC文件的语义内容是否相等（忽略注释和格式）
function Test-JsonContentEqual {
    param(
        [Parameter(Mandatory)][string]$File1,
        [Parameter(Mandatory)][string]$File2
    )

    try {
        # 如果任一文件不存在，则认为不相等
        if (-not (Test-Path $File1) -or -not (Test-Path $File2)) {
            return $false
        }
        
        # 读取并解析为对象
        $obj1 = Get-Content $File1 -Raw | ConvertFrom-Jsonc
        $obj2 = Get-Content $File2 -Raw | ConvertFrom-Jsonc
        
        # 转换为规范的、压缩的JSON字符串进行比较
        $canonical1 = $obj1 | ConvertTo-Json -Depth 100 -Compress
        $canonical2 = $obj2 | ConvertTo-Json -Depth 100 -Compress
        
        return $canonical1 -eq $canonical2
    }
    catch {
        # 解析失败或任何其他错误都意味着不相等
        return $false
    }
}