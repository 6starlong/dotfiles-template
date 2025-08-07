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
    [switch]$Overwrite
)

$TransformType = $TransformType.Trim("'", '"')
$ErrorActionPreference = 'Stop'

# 引入共享函数
Import-Module (Join-Path $PSScriptRoot "utils.psm1")

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
    # 优先处理分层合并
    if ($config.Layered -and $config.Layered.$platform) {
        $sourceObject = Invoke-LayeredTransform -Config $config -Platform $platform -SourceFile $SourceFile -TargetFile $TargetFile -Overwrite:$Overwrite
    }
    # 如果没有分层合并，则正常读取源文件
    else {
        if (-not (Test-Path $SourceFile)) {
            throw "源文件未找到: $SourceFile"
        }
        $sourceContent = Get-Content $SourceFile -Raw -Encoding UTF8
        $sourceObject = ConvertFrom-Jsonc -Content $sourceContent
    }
    
    # 可选的字段映射转换
    $defaultField = $config.DefaultField
    $platformField = $config.DefaultField  # 默认值
    if ($config.Platforms -and $config.Platforms.ContainsKey($platform)) {
        $platformField = $config.Platforms[$platform]
    }

    # 仅当字段映射有效且需要转换时才执行
    if ($defaultField -and $platformField -and $defaultField -ne $platformField) {
        $sourceKey = $defaultField
        $targetKey = $platformField
        
        # 如果源对象包含需要转换的键
        if ($sourceObject.psobject.Properties.Name -contains $sourceKey) {
            $dataToTransform = $sourceObject.$sourceKey
            
            # 创建新的结果对象，严格按源对象的字段顺序构建
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

    # 将最终处理过的对象与目标文件中的现有数据进行智能合并
    $resultObject = Merge-JsonObjects -Base $resultObject -Override $sourceObject

    # 写入最终文件
    Write-OutputFile -Content $resultObject -TargetFile $TargetFile

}
catch {
    Write-Error "    转换失败: $($_.Exception.Message)"
    exit 1
}
