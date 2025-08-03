# transform.ps1
# 通用 JSON 配置文件格式转换工具
# 支持智能合并，保持源文件格式和字段顺序

param(
    [Parameter(Mandatory = $true)]
    [string]$SourceFile,
    [Parameter(Mandatory = $true)]
    [string]$TargetFile,
    [Parameter(Mandatory = $true)]
    [string]$TransformType,
    [switch]$Reverse
)

$TransformType = $TransformType.Trim("'", '"')
$ErrorActionPreference = 'Stop'
$script:DotfilesDir = Split-Path $PSScriptRoot -Parent

# 将JSONC内容转换为JSON对象
function ConvertFrom-Jsonc {
    param ([string]$Content)
    # 移除块注释和行注释
    $cleanContent = $Content -replace '(?s)/\*.*?\*/' -replace '(?m)//.*$'
    return $cleanContent | ConvertFrom-Json
}

# 智能合并对象，保持原有结构
function Merge-Objects {
    param ($Destination, $Source)
    
    # 确保参数不为null
    if (-not $Destination) { $Destination = [pscustomobject]@{} }
    if (-not $Source) { return $Destination }
    
    foreach ($prop in $Source.psobject.Properties) {
        $key = $prop.Name
        $sourceValue = $prop.Value
        $destinationProperty = $Destination.psobject.Properties[$key]
        
        # 如果目标已存在此键且都是复杂对象，递归合并
        if ($destinationProperty -and 
            $destinationProperty.Value -is [psobject] -and 
            $sourceValue -is [psobject] -and
            $destinationProperty.Value.GetType().Name -eq 'PSCustomObject' -and
            $sourceValue.GetType().Name -eq 'PSCustomObject') {
            Merge-Objects -Destination $destinationProperty.Value -Source $sourceValue
        }
        else {
            # 直接替换或添加新属性
            if ($destinationProperty) { 
                $destinationProperty.Value = $sourceValue 
            }
            else { 
                Add-Member -InputObject $Destination -MemberType NoteProperty -Name $key -Value $sourceValue 
            }
        }
    }
    return $Destination
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

try {
    # 解析转换类型参数
    $parts = $TransformType -split ":"
    if ($parts.Length -ne 2) { 
        throw "无效的转换类型格式。预期格式为'format:platform'。" 
    }
    $format = $parts[0]
    $platform = $parts[1]

    # 获取配置并确定字段映射
    $config = Get-TransformConfig -Format $format
    $defaultField = $config.defaultField
    $platformField = if ($config.platforms.psobject.Properties[$platform]) { 
        $config.platforms.$platform 
    } else { 
        $config.defaultField 
    }

    if (-not $defaultField -or -not $platformField) { 
        throw "无法确定默认字段或平台字段。" 
    }

    # 检查并读取源文件
    if (-not (Test-Path $SourceFile)) { 
        throw "源文件未找到: $SourceFile" 
    }
    $sourceContent = Get-Content $SourceFile -Raw -Encoding UTF8
    $sourceObject = ConvertFrom-Jsonc -Content $sourceContent

    # 确定转换方向的键名
    $sourceKey, $targetKey = if ($Reverse) { 
        $platformField, $defaultField 
    } else { 
        $defaultField, $platformField 
    }
    
    # 验证源文件包含所需的键
    if (-not $sourceObject.psobject.Properties[$sourceKey]) {
        Write-Warning "源文件'$SourceFile'不包含键'$sourceKey'。"
        exit 0
    }
    $dataToTransform = $sourceObject.$sourceKey

    # 准备目标对象（安全处理空文件和无效JSON）
    $resultObject = [pscustomobject]@{}
    if (Test-Path $TargetFile) {
        try {
            $targetContent = Get-Content $TargetFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($targetContent -and $targetContent.Trim()) { 
                $targetObject = ConvertFrom-Jsonc -Content $targetContent
                if ($targetObject) {
                    $resultObject = $targetObject
                }
            }
        }
        catch {
            Write-Warning "目标文件'$TargetFile'格式无效，将创建新文件"
        }
    }

    # 合并数据
    $objectToMerge = [pscustomobject]@{ ($targetKey) = $dataToTransform }
    $resultObject = Merge-Objects -Destination $resultObject -Source $objectToMerge

    # 生成最终JSON（统一使用ConvertTo-Json确保格式一致性）
    $rawJson = $resultObject | ConvertTo-Json -Depth 100 -Compress:$false
    $finalJson = Format-JsonClean -JsonString $rawJson -Indent 2

    # 确保输出目录存在并写入文件
    $outputDir = Split-Path $TargetFile -Parent
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    }
    Set-Content -Path $TargetFile -Value ($finalJson + [System.Environment]::NewLine) -Encoding UTF8 -NoNewline

    Write-Host "转换成功: '$SourceFile' -> '$TargetFile'" -ForegroundColor Green
}
catch {
    Write-Error "转换失败: $($_.Exception.Message)"
    exit 1
}