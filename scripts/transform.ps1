# transform.ps1
# 基于 TransformSettings 进行配置文件转换和生成
# 支持命令行手动执行，可生成全部或指定配置

param(
    [string]$Type,      # 可选：指定配置类型 (mcp, editor) 或具体配置 (mcp:vscode)
    [switch]$Force,     # 强制重新生成文件
    [switch]$Remove,    # 反转操作：从目标文件中移除相关配置
    [switch]$Help       # 显示帮助信息
)

#region 帮助信息
function Show-Help {
    $scriptName = ".\scripts\transform.ps1"
    Write-Host ""
    Write-Host "📋 配置文件转换工具使用说明" -ForegroundColor Green
    Write-Host ""
    Write-Host "用法: $scriptName [参数]" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "参数:" -ForegroundColor Yellow
    Write-Host "  -Type            指定要生成的配置类型 (格式: 类型 或 类型:平台)" -ForegroundColor White
    Write-Host "  -Force           强制重新生成文件（默认会与现有配置合并）" -ForegroundColor White
    Write-Host "  -Remove          反转操作：从目标文件中移除指定配置" -ForegroundColor White
    Write-Host "  -Help            显示此帮助信息" -ForegroundColor White
    Write-Host ""
    Write-Host "示例:" -ForegroundColor Yellow
    Write-Host "  $scriptName                           # 生成所有配置" -ForegroundColor White
    Write-Host "  $scriptName -Type mcp                 # 只生成 MCP 配置" -ForegroundColor White
    Write-Host "  $scriptName -Type mcp:vscode -Force   # 强制生成 VSCode MCP" -ForegroundColor White
    Write-Host "  $scriptName -Type mcp:vscode -Remove  # 从 VSCode MCP 配置中移除相关配置" -ForegroundColor White
    Write-Host ""
}

if ($Help) {
    Show-Help
    return
}
#endregion

#region 初始化
$script:DotfilesDir = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $PSScriptRoot "..\lib\utils.psm1") -Force
$script:Config = Get-DotfilesConfig

$ErrorActionPreference = 'Stop'

# 输出信息
function Write-TransformResult {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}
#endregion

#region 转换逻辑
# 执行移除任务
function Invoke-RemoveTask {
    param($Task, [string]$SourceFile, [string]$TargetFile)

    # 检查目标文件是否存在
    if (-not (Test-Path $TargetFile)) {
        Write-TransformResult "🔔 目标文件不存在，跳过: $($Task.TargetFile)" "Yellow"
        return $false
    }

    try {
        Write-TransformResult "🔥 移除: $($Task.Comment)" "Cyan"
        Write-TransformResult "   从 $($Task.TargetFile) 移除相关配置" "Gray"

        # 执行移除操作
        Invoke-FileRemove -SourceFile $SourceFile -TargetFile $TargetFile -TransformType $Task.TransformType

        return $true
    }
    catch {
        Write-TransformResult "❌ 移除失败: $($Task.Comment)" "Red"
        Write-TransformResult "   错误: $($_.Exception.Message)" "Red"
        return $false
    }
}

# 执行单个转换任务
function Invoke-TransformTask {
    param($Task)

    $sourceFullPath = Join-Path $script:DotfilesDir $Task.SourceFile
    $targetFullPath = Join-Path $script:DotfilesDir $Task.TargetFile

    # 如果是移除模式
    if ($Remove) {
        return Invoke-RemoveTask -Task $Task -SourceFile $sourceFullPath -TargetFile $targetFullPath
    }

    # 检查源文件是否存在
    if (-not (Test-Path $sourceFullPath)) {
        Write-TransformResult "🔔 源文件不存在，跳过: $($Task.SourceFile)" "Yellow"
        return $false
    }

    # 检查是否需要覆盖
    if ((Test-Path $targetFullPath) -and -not $Force) {
        Write-TransformResult "⏩ 文件已存在，跳过: $($Task.TargetFile) (使用 -Force 强制覆盖)" "Yellow"
        return $false
    }

    try {
        Write-TransformResult "🔄 生成: $($Task.Comment)" "Cyan"
        Write-TransformResult "   $($Task.SourceFile) -> $($Task.TargetFile)" "Gray"

        # 确保目标目录存在
        $targetDir = Split-Path $targetFullPath -Parent
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        # 执行转换
        Invoke-FileTransform -SourceFile $sourceFullPath -TargetFile $targetFullPath -TransformType $Task.TransformType

        return $true
    }
    catch {
        Write-TransformResult "❌ 生成失败: $($Task.Comment)" "Red"
        Write-TransformResult "   错误: $($_.Exception.Message)" "Red"
        return $false
    }
}

# 核心移除逻辑
function Invoke-FileRemove {
    param([string]$SourceFile, [string]$TargetFile, [string]$TransformType)

    # 解析转换类型参数
    $parts = $TransformType -split ":"
    if ($parts.Length -ne 2) {
        throw "无效的转换类型格式。预期格式为'format:platform'。"
    }
    $format = $parts[0]
    $platform = $parts[1]

    # 获取配置
    $config = Get-TransformConfig -Format $format

    # 获取要移除的字段列表
    $fieldsToRemove = Get-SourceFields -Config $config -Platform $platform -SourceFile $SourceFile

    # 从目标文件移除字段
    Remove-ConfigFields -TargetFile $TargetFile -FieldsToRemove $fieldsToRemove
}

# 核心转换逻辑
function Invoke-FileTransform {
    param([string]$SourceFile, [string]$TargetFile, [string]$TransformType)

    # 解析转换类型参数
    $parts = $TransformType -split ":"
    if ($parts.Length -ne 2) {
        throw "无效的转换类型格式。预期格式为'format:platform'。"
    }
    $format = $parts[0]
    $platform = $parts[1]

    # 获取配置
    $config = Get-TransformConfig -Format $format

    # 检查是否支持分层合并
    if ($config.Layered -and $config.Layered.$platform) {
        $sourceObject = Invoke-LayeredTransform -Config $config -Platform $platform -SourceFile $SourceFile -TargetFile $TargetFile -Overwrite:$true
    }
    else {
        $sourceContent = Get-Content $SourceFile -Raw -Encoding UTF8
        $sourceObject = $sourceContent | ConvertFrom-Json
    }

    # 字段映射转换
    $defaultField = $config.DefaultField
    $platformField = $config.DefaultField
    if ($config.Platforms -and $config.Platforms.ContainsKey($platform)) {
        $platformField = $config.Platforms[$platform]
    }

    if ($defaultField -and $platformField -and $defaultField -ne $platformField) {
        $sourceKey = $defaultField
        $targetKey = $platformField

        if ($sourceObject.psobject.Properties.Name -contains $sourceKey) {
            $dataToTransform = $sourceObject.$sourceKey

            $orderedResult = [pscustomobject]@{}
            foreach ($prop in $sourceObject.psobject.Properties) {
                if ($prop.Name -eq $sourceKey) {
                    Add-Member -InputObject $orderedResult -MemberType NoteProperty -Name $targetKey -Value $dataToTransform -Force
                } else {
                    Add-Member -InputObject $orderedResult -MemberType NoteProperty -Name $prop.Name -Value $prop.Value -Force
                }
            }
            $sourceObject = $orderedResult
        }
    }

    # 准备目标对象
    $resultObject = [pscustomobject]@{}
    if (Test-Path $TargetFile) {
        try {
            $targetContent = Get-Content $TargetFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($targetContent -and $targetContent.Trim()) {
                $targetObject = $targetContent | ConvertFrom-Json
                if ($targetObject) {
                    $resultObject = $targetObject
                }
            }
        }
        catch {
            Write-Warning "目标文件'$TargetFile'格式无效，将创建新文件"
        }
    }

    # 智能合并并写入文件
    $resultObject = Merge-JsonObjects -Base $resultObject -Override $sourceObject
    Write-OutputFile -Content $resultObject -TargetFile $TargetFile
}

# 收集转换任务
function Get-TransformTasks {
    param([string]$FilterType)

    $tasks = @()

    # 检查 Transforms 配置节是否存在，如果不存在则直接返回
    if (-not $script:Config.psobject.Properties.Name -icontains 'Transforms') {
        return @()
    }

    # 统一循环处理所有转换任务
    foreach ($transform in $script:Config.Transforms) {
        # 关卡 1: 根据 -Type 过滤器进行匹配
        if ($FilterType) {
            if ($FilterType.Contains(":")) {
                # 精确匹配 (例如: mcp:vscode)
                if ($transform.Type -ne $FilterType) { continue }
            } else {
                # 类型匹配 (例如: mcp)，匹配所有 mcp:* 的任务
                $typePrefix = $FilterType + ":"
                if (-not $transform.Type.StartsWith($typePrefix)) { continue }
            }
        }

        # 关卡 2: 如果 Target 属性无效，则跳过
        if ([string]::IsNullOrWhiteSpace($transform.Target)) {
            continue
        }

        # 解析 Transform 字符串
        $transformParts = $transform.Type -split ":"
        if ($transformParts.Length -ne 2) {
            Write-TransformResult "🔔 配置格式无效: $($transform.Type) (应为 '类型:平台')，已跳过。" "Yellow"
            continue
        }
        $configType = $transformParts[0]
        $platform = $transformParts[1]

        # 关卡 3: 如果找不到对应的转换设置，则跳过
        $setting = $script:Config.TransformSettings[$configType]
        if ($null -eq $setting) {
            continue
        }

        # 关卡 4: 检查分层配置是否支持当前平台
        if ($setting.Layered -and $setting.Layered.Count -gt 0 -and -not $setting.Layered.ContainsKey($platform)) {
            Write-TransformResult "❌ 配置类型 '$configType' 不支持平台 '$platform' (在 layered 配置中未找到)" "Red"
            continue
        }

        $tasks += @{
            SourceFile    = $setting.SourceFile
            TargetFile    = $transform.Target
            TransformType = $transform.Type
            Comment       = $transform.Comment
        }
    }

    return $tasks
}
#endregion

#region 主执行逻辑
# 启动转换过程
Write-TransformResult ""
if ($Remove) {
    Write-TransformResult "🚀 开始移除配置..." "Green"
} else {
    Write-TransformResult "🚀 开始生成配置文件..." "Green"
}
Write-TransformResult ""

# 获取转换任务
$tasks = Get-TransformTasks -FilterType $Type

if ($tasks.Count -eq 0) {
    Write-TransformResult ""
    if ($Type) {
        Write-TransformResult "❌ 未找到匹配的配置: $Type" "Red"
        Write-TransformResult "💡 使用 -Help 查看支持的配置类型" "Yellow"
    } else {
        Write-TransformResult "❌ 未找到需要转换的配置" "Red"
    }
    Write-TransformResult ""
    return
}

$generated = 0
$skipped = 0

foreach ($task in $tasks) {
    if (Invoke-TransformTask -Task $task) {
        $generated++
    } else {
        $skipped++
    }
}

# 显示结果
Write-TransformResult ""
if ($Remove) {
    Write-TransformResult "✨ 移除完成!" "Green"
    Write-TransformResult "✅ 处理: $generated 个文件" "Green"
} else {
    Write-TransformResult "✨ 转换完成!" "Green"
    Write-TransformResult "✅ 生成: $generated 个文件" "Green"
}
if ($skipped -gt 0) {
    Write-TransformResult "⏩ 跳过: $skipped 个文件" "Yellow"
}
Write-TransformResult ""
#endregion
