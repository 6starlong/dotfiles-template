# utils.psm1 - Dotfiles 管理工具模块

# ==================== 模块级变量 ====================
$script:DotfilesDir = Split-Path $PSScriptRoot -Parent

# ==================== 基础工具函数 ====================

# 获取部署方式
function Get-Method {
    [CmdletBinding()]
    param([hashtable]$Link)
    
    # 如果需要配置文件，先加载
    if (-not $script:Config) {
        $script:Config = Get-DotfilesConfig
    }
    
    $method = if ($Link.Method) { $Link.Method } else { $script:Config.DefaultMethod }
    if ($method) { return $method } else { return "SymLink" }
}

# 加载 dotfiles 配置文件
function Get-DotfilesConfig {
    [CmdletBinding()]
    param()
    
    $configFile = Join-Path $script:DotfilesDir "config.psd1"
    if (-not (Test-Path $configFile)) {
        throw "配置文件未找到: $configFile"
    }
    
    return Import-PowerShellDataFile $configFile
}

# 检查路径是否匹配ignore模式（类似 .gitignore 语法）
function Test-IgnorePattern {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [string]$Pattern
    )
    
    if ([string]::IsNullOrWhiteSpace($Pattern)) { return $false }
    
    # 标准化路径分隔符
    $path = $Path -replace '\\', '/'
    $pattern = $Pattern -replace '\\', '/'
    
    # 构建正则表达式
    $regex = $pattern
    
    # 转义正则表达式特殊字符（保留 * 和 ?）
    $regex = $regex -replace '\.', '\.'
    $regex = $regex -replace '\+', '\+'
    $regex = $regex -replace '\[', '\['
    $regex = $regex -replace '\]', '\]'
    $regex = $regex -replace '\(', '\('
    $regex = $regex -replace '\)', '\)'
    $regex = $regex -replace '\{', '\{'
    $regex = $regex -replace '\}', '\}'
    $regex = $regex -replace '\^', '\^'
    $regex = $regex -replace '\$', '\$'
    $regex = $regex -replace '\|', '\|'
    
    # 处理通配符：先处理 **，再处理 *
    $regex = $regex -replace '\*\*', '§GLOBSTAR§'
    $regex = $regex -replace '\*', '[^/]*'
    $regex = $regex -replace '\?', '[^/]'
    $regex = $regex -replace '§GLOBSTAR§/', '(?:.*/)?'
    $regex = $regex -replace '§GLOBSTAR§', '.*'
    
    # 处理目录匹配和路径锚定
    if ($pattern.EndsWith('/')) {
        $regex = $regex.TrimEnd('/') + '(/.*)?'
    } else {
        $regex = $regex + '(/.*)?'
    }
    
    if ($pattern.StartsWith('/')) {
        $regex = '^' + $regex.Substring(1) + '$'
    } elseif ($pattern.StartsWith('**/') -or -not $pattern.Contains('/')) {
        $regex = if ($pattern.StartsWith('**/')) { '^' + $regex + '$' } else { '(^|/)' + $regex + '$' }
    } else {
        $regex = '^' + $regex + '$'
    }
    
    $result = $path -match $regex
    Write-Verbose "匹配检查: '$Path' vs '$Pattern' -> $result"
    return $result
}

# 检查配置项是否应该被忽略
function Test-ConfigIgnored {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Link
    )
    
    if (-not $script:Config) { $script:Config = Get-DotfilesConfig }
    if (-not $script:Config.IgnoreList) { return $false }
    
    $shouldIgnore = $false
    
    # 按顺序处理所有模式，后面的规则覆盖前面的规则
    foreach ($pattern in $script:Config.IgnoreList) {
        if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
        
        $isNegation = $pattern.StartsWith('!')
        $actualPattern = if ($isNegation) { $pattern.Substring(1) } else { $pattern }
        
        if (Test-IgnorePattern -Path $Link.Source -Pattern $actualPattern) {
            $shouldIgnore = -not $isNegation
            Write-Verbose "配置项 '$($Link.Comment)' 匹配$(if ($isNegation) { '否定' } else { '忽略' })模式 '$pattern'"
        }
    }
    
    return $shouldIgnore
}

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
    
    # 清理多余空格和空行
    $cleanJson = $JsonString -replace '\s*:\s*\[\s*\]', ': []' `
                              -replace '\s*:\s*\{\s*\}', ': {}' `
                              -replace ':\s+(["\d\[\{tfn])', ': $1' `
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
    
    # 处理Unicode转义字符（直接替换常用字符）
    $result = $JsonString
    foreach ($pair in @(
        ('\\u0027', "'"), ('\\u0026', '&'), ('\\u003c', '<'), ('\\u003e', '>'),
        ('\\u002f', '/'), ('\\u005c', '\'), ('\\u0022', '"'), ('\\u0020', ' '),
        ('\\u0021', '!'), ('\\u0023', '#'), ('\\u0024', '$'), ('\\u0025', '%'),
        ('\\u0028', '('), ('\\u0029', ')'), ('\\u002a', '*'), ('\\u002b', '+'),
        ('\\u002c', ','), ('\\u002d', '-'), ('\\u002e', '.'), ('\\u003a', ':'),
        ('\\u003b', ';'), ('\\u003d', '='), ('\\u003f', '?'), ('\\u0040', '@'),
        ('\\u005b', '['), ('\\u005d', ']'), ('\\u005e', '^'), ('\\u005f', '_'),
        ('\\u0060', '`'), ('\\u007b', '{'), ('\\u007c', '|'), ('\\u007d', '}'), ('\\u007e', '~')
    )) {
        $result = $result -replace $pair[0], $pair[1]
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

# ==================== 配置移除函数 ====================

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
    
    # 步骤 1: 收集所有源文件的字段名
    $allSourceFields = @()

    # 添加基础配置文件的字段
    if (Test-Path $SourceFile) {
        $sourceContent = Get-Content $SourceFile -Raw -Encoding UTF8
        $sourceObject = ConvertFrom-Jsonc -Content $sourceContent
        $allSourceFields += $sourceObject.psobject.Properties.Name
    }

    # 如果是分层模式，添加所有层的字段
    if ($Config.Layered -and $Config.Layered.$Platform) {
        $platformConfig = $Config.Layered.$Platform
        if ($platformConfig) {
            $dotfilesDir = Split-Path $PSScriptRoot -Parent
            foreach ($layerPath in $platformConfig) {
                $fullLayerPath = Join-Path $dotfilesDir $layerPath
                if (Test-Path $fullLayerPath) {
                    $layerContent = Get-Content $fullLayerPath -Raw -Encoding UTF8
                    $layerObject = ConvertFrom-Jsonc -Content $layerContent
                    $allSourceFields += $layerObject.psobject.Properties.Name
                }
            }
        }
    }

    # 步骤 2: 对收集到的所有字段应用字段映射规则
    $defaultField = $Config.DefaultField
    $platformField = if ($Config.Platforms -and $Config.Platforms.ContainsKey($Platform)) {
        $Config.Platforms[$Platform]
    } else {
        $Config.DefaultField
    }
    
    # 如果没有定义有效的映射规则，直接返回源字段
    if (-not $defaultField -or -not $platformField -or $defaultField -eq $platformField) {
        return $allSourceFields | Select-Object -Unique
    }

    # 步骤 3: 遍历所有源字段，生成最终的目标字段列表
    $allTargetFields = @()
    foreach ($sourceFieldName in $allSourceFields) {
        if ($sourceFieldName -eq $defaultField) {
            # 如果字段匹配，则替换为平台特定字段
            $allTargetFields += $platformField
        } else {
            # 其他字段保持原名
            $allTargetFields += $sourceFieldName
        }
    }
    
    return $allTargetFields | Select-Object -Unique
}

# 从目标文件中移除指定的配置字段
function Remove-ConfigFields {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TargetFile,
        
        [Parameter(Mandatory)]
        [array]$FieldsToRemove
    )
    
    # 如果没有要移除的字段，直接返回
    if (-not $FieldsToRemove -or $FieldsToRemove.Count -eq 0) {
        Write-Verbose "没有要移除的字段，跳过操作"
        return
    }
    
    # 读取目标文件
    if (-not (Test-Path $TargetFile)) {
        Write-Warning "目标文件不存在: $TargetFile"
        return
    }
    
    try {
        $targetContent = Get-Content $TargetFile -Raw -Encoding UTF8
        if (-not $targetContent -or -not $targetContent.Trim()) {
            Write-Warning "目标文件为空: $TargetFile"
            return
        }
        
        $targetObject = ConvertFrom-Jsonc -Content $targetContent
        if (-not $targetObject) {
            Write-Warning "无法解析目标文件: $TargetFile"
            return
        }
        
        # 记录移除的字段
        $removedFields = @()
        
        # 移除指定的字段
        foreach ($fieldName in $FieldsToRemove) {
            if ($targetObject.PSObject.Properties[$fieldName]) {
                $targetObject.PSObject.Properties.Remove($fieldName)
                $removedFields += $fieldName
                Write-Verbose "已移除字段: $fieldName"
            }
        }
        
        # 如果没有移除任何字段，提示用户
        if ($removedFields.Count -eq 0) {
            Write-Warning "未找到要移除的字段: $($FieldsToRemove -join ', ')"
            return
        }
        
        # 检查移除字段后对象是否为空
        $remainingProperties = @($targetObject.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' })
        
        if ($remainingProperties.Count -eq 0) {
            # 如果对象为空，直接删除文件
            Remove-Item -Path $TargetFile -Force
            Write-Verbose "对象为空，已删除文件: $TargetFile"
            Write-Verbose "成功移除 $($removedFields.Count) 个字段: $($removedFields -join ', ')"
        } else {
            # 写回文件
            Write-OutputFile -Content $targetObject -TargetFile $TargetFile
            Write-Verbose "成功移除 $($removedFields.Count) 个字段: $($removedFields -join ', ')"
        }
        
    } catch {
        throw "移除配置字段失败: $($_.Exception.Message)"
    }
}

# ==================== 模块导出 ====================
Export-ModuleMember -Function *-*
