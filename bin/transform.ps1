# transform.ps1
# 通用配置文件格式转换工具
# 支持多种格式和平台的配置文件转换
#
# 功能特性：
# - 支持多种配置格式（通过配置文件扩展）
# - 保持原有文件格式（缩进、换行等）
# - 支持正向和反向转换
# - 可配置的字段映射和格式选项

param(
    [Parameter(Mandatory = $true)]
    [string]$SourceFile,

    [Parameter(Mandatory = $true)]
    [string]$TargetFile,

    [Parameter(Mandatory = $true)]
    [string]$TransformType,

    [switch]$Reverse
)

# 全局变量
$script:DotfilesDir = Split-Path $PSScriptRoot -Parent
$script:ConfigCache = @{}

# 通用配置加载函数
function Get-TransformConfig {
    param(
        [string]$Format
    )

    if ($script:ConfigCache.ContainsKey($Format)) {
        return $script:ConfigCache[$Format]
    }

    $configPath = Join-Path $script:DotfilesDir "$Format\platforms.json"
    if (-not (Test-Path $configPath)) {
        throw "格式配置文件未找到: $configPath"
    }

    $config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:ConfigCache[$Format] = $config
    return $config
}

# 通用字段映射函数
function Get-FieldMapping {
    param(
        [string]$Format,
        [string]$Platform,
        [bool]$IsReverse = $false
    )

    $config = Get-TransformConfig -Format $Format

    # 获取平台的字段映射，如果没有则使用默认映射
    $platformMapping = if ($config.mappings.$Platform) {
        $config.mappings.$Platform
    } else {
        $config.default
    }

    # 合并默认映射和平台特定映射
    $finalMapping = @{}

    # 先添加默认映射
    if ($config.default) {
        $config.default.PSObject.Properties | ForEach-Object {
            $finalMapping[$_.Name] = $_.Value
        }
    }

    # 再添加平台特定映射（会覆盖默认值）
    # 注意：如果平台映射不存在，则使用默认映射
    if ($platformMapping -and $platformMapping -ne $config.default) {
        $platformMapping.PSObject.Properties | ForEach-Object {
            $finalMapping[$_.Name] = $_.Value
        }
    }

    return $finalMapping
}

# 通用内容转换函数
function Convert-ConfigContent {
    param(
        [object]$Content,
        [string]$Format,
        [string]$Platform,
        [bool]$IsReverse = $false
    )

    $mapping = Get-FieldMapping -Format $Format -Platform $Platform -IsReverse $IsReverse
    $result = @{}

    if ($IsReverse) {
        # 反向转换：从平台格式转换回基础格式
        foreach ($baseField in $mapping.Keys) {
            $platformField = $mapping[$baseField]
            if ($Content.$platformField) {
                $result.$baseField = $Content.$platformField
            }
        }
    } else {
        # 正向转换：从基础格式转换到平台格式
        foreach ($baseField in $mapping.Keys) {
            $platformField = $mapping[$baseField]
            if ($Content.$baseField) {
                $result.$platformField = $Content.$baseField
            }
        }
    }

    return $result
}

# 通用格式保持转换函数
function Convert-WithFormatPreservation {
    param(
        [string]$SourceContent,
        [string]$Format,
        [string]$Platform,
        [bool]$IsReverse = $false
    )

    $mapping = Get-FieldMapping -Format $Format -Platform $Platform -IsReverse $IsReverse
    $result = $SourceContent

    if ($IsReverse) {
        # 反向转换：将平台字段名替换为基础字段名
        foreach ($baseField in $mapping.Keys) {
            $platformField = $mapping[$baseField]
            if ($platformField -ne $baseField) {
                $searchPattern = '"' + $platformField + '":'
                $replacePattern = '"' + $baseField + '":'
                $result = $result.Replace($searchPattern, $replacePattern)
            }
        }
    } else {
        # 正向转换：将基础字段名替换为平台字段名
        foreach ($baseField in $mapping.Keys) {
            $platformField = $mapping[$baseField]
            if ($baseField -ne $platformField) {
                $searchPattern = '"' + $baseField + '":'
                $replacePattern = '"' + $platformField + '":'
                $result = $result.Replace($searchPattern, $replacePattern)
            }
        }
    }

    return $result
}

# 通用JSON格式化函数
function Format-JsonOutput {
    param(
        [object]$Content,
        [string]$Format
    )

    $config = Get-TransformConfig -Format $Format

    # 使用配置中的格式设置，如果没有则使用默认值
    $indent = if ($config.formatting -and $config.formatting.indent) {
        $config.formatting.indent
    } else {
        2  # 默认2个空格缩进
    }

    $jsonOutput = $Content | ConvertTo-Json -Depth 10

    # 转换缩进
    if ($indent -ne 4) {
        $indentString = ' ' * $indent
        $jsonOutput = $jsonOutput -replace '    ', $indentString
    }

    return $jsonOutput
}

try {
    if (-not (Test-Path $SourceFile)) {
        throw "输入文件不存在: $SourceFile"
    }

    # 解析转换类型 (format:platform)
    $parts = $TransformType -split ":"
    if ($parts.Length -ne 2) {
        throw "转换类型格式错误。应为 'format:platform'，如 'mcp:vscode'"
    }

    $format = $parts[0]
    $platform = $parts[1]

    # 验证格式配置是否存在
    $formatConfigPath = Join-Path $script:DotfilesDir "$format\platforms.json"
    if (-not (Test-Path $formatConfigPath)) {
        throw "不支持的转换格式: $format (配置文件不存在: $formatConfigPath)"
    }

    # 读取源文件内容
    $sourceContent = Get-Content $SourceFile -Raw -Encoding UTF8
    $content = $sourceContent | ConvertFrom-Json

    # 获取格式配置
    $config = Get-TransformConfig -Format $format

    # 确保输出目录存在
    $outputDir = Split-Path $TargetFile -Parent
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    }

    # 根据配置决定转换方式
    $preserveFormat = if ($config.preserveFormat -ne $null) {
        $config.preserveFormat
    } else {
        $true  # 默认保持格式
    }

    if ($preserveFormat) {
        # 保持原有格式，使用字符串替换
        $finalOutput = Convert-WithFormatPreservation -SourceContent $sourceContent -Format $format -Platform $platform -IsReverse:$Reverse
    } else {
        # 使用JSON重新格式化
        $convertedContent = Convert-ConfigContent -Content $content -Format $format -Platform $platform -IsReverse:$Reverse
        $finalOutput = Format-JsonOutput -Content $convertedContent -Format $format
    }

    # 写入文件，保持UTF8编码
    $finalOutput | Set-Content $TargetFile -Encoding UTF8 -NoNewline
} catch {
    Write-Error "转换失败: $($_.Exception.Message)"
    exit 1
}