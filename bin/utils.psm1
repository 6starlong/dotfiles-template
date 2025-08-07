# utils.psm1 - Dotfiles 管理工具模块

# ==================== 模块级变量 ====================
$script:DotfilesDir = Split-Path $PSScriptRoot -Parent

# ==================== 基础工具函数 ====================

# 将JSONC内容转换为JSON对象
function ConvertFrom-Jsonc {
    [CmdletBinding()]
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

# 清理和标准化JSON格式
function Format-JsonClean {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JsonString,
        [int]$Indent = 2
    )
    
    # 移除PowerShell的多余空格和奇怪格式
    $cleanJson = $JsonString -replace '\s*:\s*\[\s*\]', ': []' `
                              -replace '\s*:\s*\{\s*\}', ': {}' `
                              -replace ':\s+\[', ': [' `
                              -replace ':\s+\{', ': {' `
                              -replace ':\s+(["\d\[\{])', ': $1' `
                              -replace '(?m)^\s*$\n', ''
    
    # 重新格式化缩进
    $lines = $cleanJson -split "`r?`n"
    $result = [System.Collections.Generic.List[string]]::new()
    $currentIndent = 0
    
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        
        # 调整缩进级别
        if ($trimmed.StartsWith('}') -or $trimmed.StartsWith(']')) {
            $currentIndent = [Math]::Max(0, $currentIndent - 1)
        }
        
        # 添加正确缩进的行
        $result.Add((' ' * ($currentIndent * $Indent)) + $trimmed)
        
        # 为下一行调整缩进
        if ($trimmed.EndsWith('{') -or $trimmed.EndsWith('[')) {
            $currentIndent++
        }
    }
    
    return $result -join [System.Environment]::NewLine
}

# 路径处理工具函数
function Resolve-ConfigPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [string]$DotfilesDir,
        
        [switch]$ToRelative
    )
    
    if ($ToRelative) {
        # 转换为相对路径模式
        $baseConfigRelPath = $Path
        
        # 如果是绝对路径，转换为相对路径
        if ([System.IO.Path]::IsPathRooted($Path)) {
            $sourceFullPath = [System.IO.Path]::GetFullPath($Path)
            $dotfilesFullPath = [System.IO.Path]::GetFullPath($DotfilesDir)
            
            if ($sourceFullPath.StartsWith($dotfilesFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                $baseConfigRelPath = $sourceFullPath.Substring($dotfilesFullPath.Length).TrimStart('\', '/')
            } else {
                $baseConfigRelPath = $sourceFullPath
            }
        }
        
        return $baseConfigRelPath
    } else {
        # 转换为绝对路径模式（默认）
        # 展开环境变量
        $resolvedPath = $Path -replace '\{USERPROFILE\}', $env:USERPROFILE
        
        # 如果是相对路径，则相对于 dotfiles 根目录
        if (-not [System.IO.Path]::IsPathRooted($resolvedPath)) {
            $resolvedPath = Join-Path $DotfilesDir $resolvedPath
        }
        
        return $resolvedPath
    }
}

# ==================== 配置文件操作函数 ====================

# 获取转换配置
function Get-TransformConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Format
    )
    
    # 加载配置文件
    $configFile = Join-Path $script:DotfilesDir "config.psd1"
    if (-not (Test-Path $configFile)) {
        throw "配置文件未找到: $configFile"
    }
    
    $config = Import-PowerShellDataFile $configFile
    if (-not $config.TransformSettings.ContainsKey($Format)) {
        throw "转换配置未找到: $Format"
    }
    
    return $config.TransformSettings[$Format]
}

# 读取JSON配置文件（支持JSONC格式）
function Read-JsonConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    if (-not (Test-Path $Path)) {
        return [psobject]@{}
    }
    
    try {
        $content = Get-Content $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($content)) {
            return [psobject]@{}
        }
        return ConvertFrom-Jsonc -Content $content
    } catch {
        Write-Warning "无法读取配置文件 $Path : $($_.Exception.Message)"
        return [psobject]@{}
    }
}

# 获取现有配置
function Get-ExistingConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TargetFile
    )
    
    try {
        $existingContent = Get-Content $TargetFile -Raw -Encoding UTF8
        if ($existingContent -and $existingContent.Trim()) {
            return ConvertFrom-Jsonc -Content $existingContent
        }
    } catch {
        Write-Verbose "无法读取现有配置文件，将创建新文件: $($_.Exception.Message)"
    }
    
    return $null
}

# 反转义Unicode字符
function Restore-UnicodeCharacters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JsonString
    )
    
    # 常见的Unicode转义字符映射（只处理常见的可打印ASCII字符）
    $unicodeReplacements = @{
        '\\u0027' = "'"      # 单引号
        '\\u0026' = '&'      # &符号
        '\\u003c' = '<'      # 小于号
        '\\u003e' = '>'      # 大于号
        '\\u002f' = '/'      # 斜杠
        '\\u005c' = '\'      # 反斜杠
        '\\u0022' = '"'      # 双引号
        '\\u0020' = ' '      # 空格
        '\\u0021' = '!'      # 感叹号
        '\\u0023' = '#'      # 井号
        '\\u0024' = '$'      # 美元符号
        '\\u0025' = '%'      # 百分号
        '\\u0028' = '('      # 左括号
        '\\u0029' = ')'      # 右括号
        '\\u002a' = '*'      # 星号
        '\\u002b' = '+'      # 加号
        '\\u002c' = ','      # 逗号
        '\\u002d' = '-'      # 减号
        '\\u002e' = '.'      # 句号
        '\\u003a' = ':'      # 冒号
        '\\u003b' = ';'      # 分号
        '\\u003d' = '='      # 等号
        '\\u003f' = '?'      # 问号
        '\\u0040' = '@'      # @符号
        '\\u005b' = '['      # 左方括号
        '\\u005d' = ']'      # 右方括号
        '\\u005e' = '^'      # 脱字符
        '\\u005f' = '_'      # 下划线
        '\\u0060' = '`'      # 反引号
        '\\u007b' = '{'      # 左大括号
        '\\u007c' = '|'      # 竖线
        '\\u007d' = '}'      # 右大括号
        '\\u007e' = '~'      # 波浪号
    }
    
    $result = $JsonString
    
    # 处理Unicode转义字符
    foreach ($unicode in $unicodeReplacements.Keys) {
        $result = $result -replace $unicode, $unicodeReplacements[$unicode]
    }
    
    return $result
}

# 写入输出文件
function Write-OutputFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Content,
        
        [Parameter(Mandatory)]
        [string]$TargetFile
    )
    
    # 生成最终JSON
    $rawJson = $Content | ConvertTo-Json -Depth 100 -Compress:$false
    
    # 反转义Unicode字符
    $unescapedJson = Restore-UnicodeCharacters -JsonString $rawJson
    
    # 清理格式
    $finalJson = Format-JsonClean -JsonString $unescapedJson -Indent 2
    
    # 确保输出目录存在
    $outputDir = Split-Path $TargetFile -Parent
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    }
    
    # 写入文件
    [System.IO.File]::WriteAllText($TargetFile, ($finalJson + [System.Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
}

# ==================== 文件比较函数 ====================

# 比较两个文件的原始内容是否相等
function Test-FileContentEqual {
    [CmdletBinding()]
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
    [CmdletBinding()]
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

# ==================== JSON对象操作函数 ====================

# 深度合并JSON对象
function Merge-JsonObjects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Base,
        
        [Parameter(Mandatory)]
        [psobject]$Override
    )
    
    # 创建一个新的PSCustomObject作为结果
    $result = [pscustomobject]@{}
    
    # 复制基础对象的属性
    foreach ($property in $Base.PSObject.Properties) {
        if ($property.MemberType -eq 'NoteProperty') {
            $result | Add-Member -MemberType NoteProperty -Name $property.Name -Value $property.Value
        }
    }
    
    foreach ($property in $Override.PSObject.Properties) {
        $key = $property.Name
        $value = $property.Value
        
        if ($result.PSObject.Properties[$key] -and 
            $result.$key -is [psobject] -and 
            $value -is [psobject] -and
            $result.$key.GetType().Name -eq 'PSCustomObject' -and
            $value.GetType().Name -eq 'PSCustomObject') {
            # 递归合并嵌套对象
            $result.$key = Merge-JsonObjects -Base $result.$key -Override $value
        } else {
            # 直接覆盖或添加新属性
            if ($result.PSObject.Properties[$key]) {
                $result.$key = $value
            } else {
                $result | Add-Member -MemberType NoteProperty -Name $key -Value $value
            }
        }
    }
    
    return $result
}

# ==================== 分层配置处理函数 ====================

# 通用的分层配置合并函数
function Get-LayeredConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BaseConfigPath,
        
        [Parameter()]
        [array]$Layers = @()
    )
    
    # 1. 从基础配置开始
    $baseFullPath = Join-Path $script:DotfilesDir $BaseConfigPath
    if (Test-Path $baseFullPath) {
        $mergedConfig = Read-JsonConfig -Path $baseFullPath
        Write-Verbose "已加载基础配置: $baseFullPath"
    } else {
        Write-Verbose "基础配置不存在: $baseFullPath"
        $mergedConfig = [psobject]@{}
    }
    
    # 2. 按顺序合并额外配置层
    foreach ($layerPath in $Layers) {
        $fullPath = Join-Path $script:DotfilesDir $layerPath
        
        if (Test-Path $fullPath) {
            $layerConfig = Read-JsonConfig -Path $fullPath
            $mergedConfig = Merge-JsonObjects -Base $mergedConfig -Override $layerConfig
            Write-Verbose "已合并额外配置层: $fullPath"
        } else {
            Write-Verbose "额外配置层不存在，跳过: $fullPath"
        }
    }
    
    return $mergedConfig
}

# 处理分层配置转换
function Invoke-LayeredTransform {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Config,
        
        [Parameter(Mandatory)]
        [string]$Platform,
        
        [Parameter(Mandatory)]
        [string]$SourceFile,
        
        [Parameter(Mandatory)]
        [string]$TargetFile,
        
        [switch]$Overwrite
    )
    
    $platformConfig = $Config.Layered.$Platform
    if (-not $platformConfig) {
        throw "分层配置未找到平台 '$Platform' 的配置层定义"
    }
    
    # 计算相对路径
    $baseConfigRelPath = Resolve-ConfigPath -Path $SourceFile -DotfilesDir (Split-Path $PSScriptRoot -Parent) -ToRelative
    
    # 获取分层合并配置
    $mergedConfig = Get-LayeredConfig -BaseConfigPath $baseConfigRelPath -Layers $platformConfig
    
    # 如果不是强制覆盖模式，合并现有用户配置
    if (-not $Overwrite -and (Test-Path $TargetFile)) {
        $existingConfig = Get-ExistingConfig -TargetFile $TargetFile
        if ($existingConfig) {
            $mergedConfig = Merge-JsonObjects -Base $existingConfig -Override $mergedConfig
        }
    }
    
    return $mergedConfig
}

# ==================== 卸载相关函数 ====================

# 获取源文件字段列表（用于卸载）
function Get-SourceFields {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Config,
        
        [Parameter(Mandatory)]
        [string]$Platform,
        
        [Parameter(Mandatory)]
        [string]$SourceFile
    )
    
    # 检查是否支持分层合并
    if ($Config.Layered -and $Config.Layered.$Platform) {
        $platformConfig = $Config.Layered.$Platform
        if (-not $platformConfig) {
            throw "分层配置未找到平台 '$Platform' 的配置层定义"
        }
        
        # 收集所有配置层的字段
        $allSourceFields = @()
        
        # 添加基础配置文件的字段
        if (Test-Path $SourceFile) {
            $sourceContent = Get-Content $SourceFile -Raw -Encoding UTF8
            $sourceObject = ConvertFrom-Jsonc -Content $sourceContent
            $allSourceFields += $sourceObject.psobject.Properties.Name
        }
        
        # 添加各层配置文件的字段
        $dotfilesDir = Split-Path $PSScriptRoot -Parent
        foreach ($layerPath in $platformConfig) {
            $fullLayerPath = Join-Path $dotfilesDir $layerPath
            if (Test-Path $fullLayerPath) {
                $layerContent = Get-Content $fullLayerPath -Raw -Encoding UTF8
                $layerObject = ConvertFrom-Jsonc -Content $layerContent
                $allSourceFields += $layerObject.psobject.Properties.Name
            }
        }
        return $allSourceFields | Select-Object -Unique
    } else {
        # 传统的字段映射处理 - 返回源文件中所有字段的目标映射
        $defaultField = $Config.DefaultField
        $platformField = if ($Config.Platforms.ContainsKey($Platform)) {
            $Config.Platforms[$Platform]
        } else {
            $Config.DefaultField
        }

        if (-not $defaultField -or -not $platformField) {
            throw "无法确定默认字段或平台字段。"
        }

        # 读取源文件，获取所有字段
        if (-not (Test-Path $SourceFile)) {
            throw "源文件未找到: $SourceFile"
        }
        
        $sourceContent = Get-Content $SourceFile -Raw -Encoding UTF8
        $sourceObject = ConvertFrom-Jsonc -Content $sourceContent
        $allTargetFields = @()
        
        # 遍历源文件中的所有字段，确定它们在目标文件中的字段名
        foreach ($sourceFieldName in $sourceObject.psobject.Properties.Name) {
            if ($sourceFieldName -eq $defaultField) {
                # 默认字段需要转换为平台特定字段
                $allTargetFields += $platformField
            } else {
                # 其他字段保持原名
                $allTargetFields += $sourceFieldName
            }
        }
        
        return $allTargetFields | Select-Object -Unique
    }
}

# ==================== 模块导出 ====================
Export-ModuleMember -Function *-*