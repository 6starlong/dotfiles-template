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
    [switch]$Reverse,
    [switch]$Overwrite
)

$TransformType = $TransformType.Trim("'", '"')
$ErrorActionPreference = 'Stop'

# 引入共享函数
Import-Module (Join-Path $PSScriptRoot "utils.psm1")

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

try {
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
        $mergedConfig = Invoke-LayeredTransform -Config $config -Platform $platform -SourceFile $SourceFile -TargetFile $TargetFile -Overwrite:$Overwrite
        Write-OutputFile -Content $mergedConfig -TargetFile $TargetFile
        return
    }
    
    # 处理其他类型的转换（如 MCP 配置）
    $defaultField = $config.DefaultField
    
    # 获取平台特定字段
    $platformField = $config.DefaultField  # 默认值
    $platformValue = $config.Platforms.$platform
    if ($platformValue) {
        $platformField = $platformValue
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
        # 如果源文件不包含所需字段，静默退出，让冲突检测处理
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

    # 创建新的结果对象，严格按源对象的字段顺序构建
    $orderedResult = [pscustomobject]@{}
    
    # 遍历源对象的所有属性，保持原始顺序
    foreach ($prop in $sourceObject.psobject.Properties) {
        if ($prop.Name -eq $sourceKey) {
            # 当前属性是需要转换的字段，添加转换后的键值对
            Add-Member -InputObject $orderedResult -MemberType NoteProperty -Name $targetKey -Value $dataToTransform
        } else {
            # 当前属性是其他字段，原封不动地复制
            Add-Member -InputObject $orderedResult -MemberType NoteProperty -Name $prop.Name -Value $prop.Value
        }
    }
    
    # 将有序结果与目标文件中的现有数据进行智能合并
    $resultObject = Merge-Objects -Destination $resultObject -Source $orderedResult

    # 生成最终JSON（统一使用ConvertTo-Json确保格式一致性）
    $rawJson = $resultObject | ConvertTo-Json -Depth 100 -Compress:$false
    $finalJson = Format-JsonClean -JsonString $rawJson -Indent 2

    # 写入最终文件
    Write-OutputFile -Content $resultObject -TargetFile $TargetFile

}
catch {
    Write-Error "    转换失败: $($_.Exception.Message)"
    exit 1
}
