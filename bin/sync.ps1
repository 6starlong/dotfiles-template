# sync.ps1
# 将系统中的配置文件同步回 dotfiles 仓库
# 支持 Copy 和 Transform 方法的配置文件

#region 辅助函数

# 加载配置数据
function Get-ConfigData {
    $configFile = Join-Path $script:DotfilesDir "config.psd1"
    if (-not (Test-Path $configFile)) {
        Write-Error "配置文件未找到: $configFile"
        exit 1
    }
    return Import-PowerShellDataFile -Path $configFile
}

# 获取部署方法
function Get-Method {
    param([hashtable]$Link)
    $method = if ($Link.Method) { $Link.Method } else { $script:Config.DefaultMethod }
    if ($method) { return $method } else { return "SymLink" }
}

# 统一的UTF-8文件读取函数
function Read-Utf8File {
    param([string]$Path)
    if (Test-Path $Path) {
        return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($true))
    } else {
        return ""
    }
}

# 统一的UTF-8文件写入函数
function Write-Utf8File {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($true))
}

# 安全执行临时文件操作
function Invoke-WithTempFiles {
    param(
        [scriptblock]$ScriptBlock,
        [int]$Count = 1
    )

    $tempFiles = @()
    try {
        for ($i = 0; $i -lt $Count; $i++) {
            $tempFiles += [System.IO.Path]::GetTempFileName()
        }
        & $ScriptBlock @tempFiles
    }
    finally {
        $tempFiles | ForEach-Object {
            if (Test-Path $_) { Remove-Item $_ -Force -ErrorAction SilentlyContinue }
        }
    }
}
#endregion

#region 初始化
# 设置全局变量
$script:DotfilesDir = Split-Path $PSScriptRoot -Parent
$script:Config = Get-ConfigData
Import-Module (Join-Path $PSScriptRoot "utils.psm1")
#endregion

#region 同步处理函数
# 源文件状态管理器
$script:SourceFileTracker = @{}

# 初始化源文件跟踪
function Initialize-SourceFileTracker {
    param([array]$ConflictItems)
    
    $script:SourceFileTracker.Clear()
    
    # 按源文件分组
    $sourceGroups = $ConflictItems | Group-Object -Property SourcePath
    
    foreach ($group in $sourceGroups) {
        $sourcePath = $group.Name
        if ([string]::IsNullOrEmpty($sourcePath)) {
            continue
        }
        $originalContent = Read-Utf8File -Path $sourcePath
        
        $script:SourceFileTracker[$sourcePath] = @{
            OriginalContent = $originalContent
            CurrentContent = $originalContent
            ProcessedItems = @()
            TempFile = $null
        }
    }
}

# 获取源文件当前内容
function Get-SourceFileCurrentContent {
    param([string]$SourcePath)
    
    if ([string]::IsNullOrEmpty($SourcePath)) {
        return ""
    }
    
    if ($script:SourceFileTracker.ContainsKey($SourcePath)) {
        return $script:SourceFileTracker[$SourcePath].CurrentContent
    }
    
    # 如果没有跟踪，返回文件原始内容
    return Read-Utf8File -Path $SourcePath
}

# 更新源文件当前内容
function Update-SourceFileCurrentContent {
    param(
        [string]$SourcePath,
        [string]$NewContent
    )
    
    if ($script:SourceFileTracker.ContainsKey($SourcePath)) {
        $script:SourceFileTracker[$SourcePath].CurrentContent = $NewContent
        $script:SourceFileTracker[$SourcePath].ProcessedItems += @{ Timestamp = Get-Date }
    }
}

# 清理源文件跟踪器
function Clear-SourceFileTracker {
    foreach ($tracker in $script:SourceFileTracker.Values) {
        if ($tracker.TempFile -and (Test-Path $tracker.TempFile)) {
            Remove-Item $tracker.TempFile -Force -ErrorAction SilentlyContinue
        }
    }
    $script:SourceFileTracker.Clear()
}

# 检查文件冲突
function Test-FileConflict {
    param(
        [Parameter(Mandatory)][hashtable]$Link,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$Method
    )

    if (-not (Test-Path $SourcePath)) {
        return $false
    }

    switch ($Method) {
        "Copy" {
            return -not (Test-FileContentEqual -File1 $TargetPath -File2 $SourcePath)
        }
        "Transform" {
            if (-not $Link.MappingId) {
                Write-Host "    ❌ Transform配置缺少MappingId参数: $($Link.Comment)" -ForegroundColor Red
                return $false # 标记为无冲突，但记录错误
            }
            
            $transformScript = Join-Path $PSScriptRoot "transform.ps1"
            if (-not (Test-Path $transformScript)) {
                Write-Host "    ❌ 转换脚本未找到: $transformScript" -ForegroundColor Red
                return $false # 标记为无冲突
            }

            try {
                # 统一使用正向转换进行比较，与 status.ps1 逻辑一致
                return Invoke-WithTempFiles -Count 1 -ScriptBlock {
                    param($tempFile)
                    
                    # 将源文件（或分层合并结果）正向转换到临时文件
                    & $transformScript -SourceFile $SourcePath -TargetFile $tempFile -TransformType $Link.MappingId -ErrorAction Stop | Out-Null
                    
                    # 使用JSON语义比较函数，比较转换后的临时文件和当前的目标文件
                    # 如果不相等，则说明有冲突
                    return -not (Test-JsonContentEqual -File1 $tempFile -File2 $TargetPath)
                }
            } catch {
                Write-Host "    ❌ 转换检查失败: $($Link.Comment). 错误: $($_.Exception.Message)" -ForegroundColor Red
                return $false # 转换失败也标记为无冲突，避免误操作
            }
        }
        default {
            return $false
        }
    }
}

# 创建冲突项
function New-ConflictItem {
    param(
        [Parameter(Mandatory)][hashtable]$Link,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$SourcePath
    )

    # 使用源文件跟踪器获取当前内容，而不是原始文件内容
    $currentSourceContent = Get-SourceFileCurrentContent -SourcePath $SourcePath

    return @{
        Link = $Link
        Method = $Method
        TargetPath = $TargetPath
        SourcePath = $SourcePath
        OriginalDotfilesContent = $currentSourceContent  # 使用当前累积的内容
        TransformScript = if ($Method -eq "Transform") { Join-Path $PSScriptRoot "transform.ps1" } else { $null }
    }
}
#endregion

#region VS Code 差异处理
function Invoke-VSCodeDiff {
    param([Parameter(Mandatory)][hashtable]$ConflictItem)

    Write-Host ""
    Write-Host "    📝 启动 VS Code 差异视图..." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    操作说明:" -ForegroundColor Yellow
    Write-Host "    • 左侧: System (系统中的文件)。" -ForegroundColor Gray
    Write-Host "    • 右侧: Repo (仓库中的文件)。" -ForegroundColor Gray
    Write-Host "    • 请在右侧合并修改 (箭头选择或手动编辑)。" -ForegroundColor Gray
    Write-Host "    • 完成后保存并关闭 VS Code 标签页。" -ForegroundColor Gray
    Write-Host ""

    # 创建统一的临时文件名
    $tempDir = [System.IO.Path]::GetTempPath()
    $projectPrefix = if ($script:Config.ProjectSettings -and $script:Config.ProjectSettings.ProjectPrefix) {
        $script:Config.ProjectSettings.ProjectPrefix
    } else {
        "dotfiles"
    }

    # 确定统一的名称主干 (baseName)
    $identifier = if ($ConflictItem.Link.MappingId) {
        $ConflictItem.Link.MappingId -replace ":", "-"
    } else {
        # 使用 Source 路径作为备选，并清理特殊字符
        $sourceRelativePath = $ConflictItem.Link.Source -replace "[\\/]", "-"
        $sourceExtension = [System.IO.Path]::GetExtension($ConflictItem.SourcePath)
        if ($sourceRelativePath.EndsWith($sourceExtension)) {
            $sourceRelativePath.Substring(0, $sourceRelativePath.Length - $sourceExtension.Length)
        } else {
            $sourceRelativePath
        }
    }
    $baseName = "$projectPrefix-$identifier"

    # 构建最终的临时文件名
    $extension = [System.IO.Path]::GetExtension($ConflictItem.TargetPath)
    $tempSystemFile = Join-Path $tempDir "$baseName-system$extension"
    $tempRepoFile = Join-Path $tempDir "$baseName-repo$extension"

    try {
        # 准备文件内容用于比较，确保编码一致性
        # 读取系统文件内容并以 UTF-8 with BOM 写入临时文件
        $systemContent = Get-Content $ConflictItem.TargetPath -Raw
        Write-Utf8File -Path $tempSystemFile -Content $systemContent
        
        # 将仓库文件内容以 UTF-8 with BOM 写入临时文件
        Write-Utf8File -Path $tempRepoFile -Content $ConflictItem.OriginalDotfilesContent

        # 检查 VS Code 是否可用
        $codeExists = Get-Command "code" -ErrorAction SilentlyContinue
        if (-not $codeExists) {
            Write-Host "    ❌ VS Code 命令行工具未找到" -ForegroundColor Red
            Write-Host "    请确保已安装 VS Code 并将其添加到 PATH" -ForegroundColor Yellow
            return $false
        }

        # 打开 VS Code 差异视图
        Write-Host "    正在打开 VS Code... (请等待)" -ForegroundColor Gray
        Write-Host ""
        & code --diff $tempSystemFile $tempRepoFile --wait

        # 应用合并结果（可能是用户修改后的，也可能是用户确认的原始版本）
        Copy-Item $tempRepoFile $ConflictItem.SourcePath -Force
        
        # 更新源文件跟踪器
        $newContent = Get-Content $ConflictItem.SourcePath -Raw
        Update-SourceFileCurrentContent -SourcePath $ConflictItem.SourcePath -NewContent $newContent
        
        Write-Host "    ✅ 确认同步: $($ConflictItem.Link.Comment)" -ForegroundColor Green
        Write-Host "    合并结果 -> $($ConflictItem.SourcePath)" -ForegroundColor Gray
        return $true
    }
    catch {
        Write-Host "    ❌ VS Code 处理失败: $($ConflictItem.Link.Comment). 错误: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    finally {
        # 清理临时文件
        if (Test-Path $tempSystemFile) { Remove-Item $tempSystemFile -Force -ErrorAction SilentlyContinue }
        if (Test-Path $tempRepoFile) { Remove-Item $tempRepoFile -Force -ErrorAction SilentlyContinue }
    }
}
#endregion

# 显示单个文件的处理选项
function Show-FileProcessOptions {
    param(
        [int]$CurrentIndex, 
        [int]$TotalCount
    )
    
    Write-Host ""
    Write-Host "    选择操作:" -ForegroundColor Yellow
    Write-Host "    [Enter] VS Code 差异合并 (默认)" -ForegroundColor Cyan
    Write-Host "    [S] 跳过此文件" -ForegroundColor White
    Write-Host "    [A] 全部跳过" -ForegroundColor Yellow
    Write-Host ""
}

#region 主同步逻辑
# 处理单个配置链接
function Process-ConfigLink {
    param(
        [hashtable]$Link,
        [ref]$SyncedCount,
        [ref]$SkippedCount,
        [ref]$ConflictItems
    )

    $method = Get-Method -Link $Link

    if ($method -ne "Copy" -and $method -ne "Transform") {
        Write-Host "    ⏩ 跳过 SymLink: $($Link.Comment) (SymLink 自动同步)" -ForegroundColor Cyan
        $SkippedCount.Value++
        return
    }

    $targetPath = Resolve-ConfigPath -Path $Link.Target -DotfilesDir $script:DotfilesDir
    $sourcePath = Join-Path $script:DotfilesDir $Link.Source

    # 检查目标文件是否存在
    if (-not (Test-Path $targetPath)) {
        Write-Host "    ⚠️ 文件不存在: $($Link.Comment)" -ForegroundColor Yellow
        $SkippedCount.Value++
        return
    }

    # 确保源文件目录存在
    $sourceDir = Split-Path $sourcePath -Parent
    if (-not (Test-Path $sourceDir)) {
        New-Item -Path $sourceDir -ItemType Directory -Force | Out-Null
    }

    # 检查冲突
    $hasConflict = Test-FileConflict -Link $Link -TargetPath $targetPath -SourcePath $sourcePath -Method $method

    if ($hasConflict) {
        # 检测到冲突，收集冲突项以供后续交互处理
        $ConflictItems.Value += New-ConflictItem -Link $Link -Method $method -TargetPath $targetPath -SourcePath $sourcePath
    } else {
        # 没有冲突，报告已同步并跳过
        Write-Host "    ✅ 已同步: $($Link.Comment)" -ForegroundColor Green
        $SkippedCount.Value++
    }
}

# 启动同步过程
function Start-SyncProcess {
    Write-Host "    🔄 同步配置文件到仓库..." -ForegroundColor Yellow
    Write-Host ""

    $syncedCount = 0
    $skippedCount = 0
    $conflictItems = @()

    # 第一阶段：收集所有冲突和无冲突项
    foreach ($link in $script:Config.Links) {
        Process-ConfigLink -Link $link -SyncedCount ([ref]$syncedCount) -SkippedCount ([ref]$skippedCount) -ConflictItems ([ref]$conflictItems)
    }
    # 第二阶段：处理所有冲突
    Process-ConflictResolution -ConflictItems $conflictItems -SyncedCount ([ref]$syncedCount) -SkippedCount ([ref]$skippedCount)

    # 如果有文件被同步，自动运行安装脚本
    if ($syncedCount -gt 0) {
        Write-Host ""
        Write-Host "    ----------------------------------------------------------------" -ForegroundColor Gray
        Write-Host ""
        Write-Host "    🔄 自动同步更新的配置..." -ForegroundColor Cyan
        Write-Host ""
        
        $installScript = Join-Path $PSScriptRoot "install.ps1"
        if (Test-Path $installScript) {
            & $installScript -Overwrite
        }

        Write-Host "    ----------------------------------------------------------------" -ForegroundColor Gray
    }

    # 显示最终统计
    Show-SyncSummary -SyncedCount $syncedCount -SkippedCount $skippedCount -ConflictCount $conflictItems.Count
}

# 处理冲突解决
function Process-ConflictResolution {
    param(
        [array]$ConflictItems,
        [ref]$SyncedCount,
        [ref]$SkippedCount
    )

    if ($ConflictItems.Count -eq 0) {
        return
    }

    # 初始化源文件跟踪器
    Initialize-SourceFileTracker -ConflictItems $ConflictItems
    
    try {
        Write-Host ""
        Write-Host "    ⚠️ 检测到 $($ConflictItems.Count) 个冲突:" -ForegroundColor Yellow

        # 显示所有冲突项
        for ($i = 0; $i -lt $ConflictItems.Count; $i++) {
            Write-Host "    $($i + 1). $($ConflictItems[$i].Link.Comment)" -ForegroundColor White
        }

        Write-Host ""
        Write-Host "    ----------------------------------------------------------------" -ForegroundColor Gray

        # 按源文件分组处理
        Process-ConflictsBySourceGroup -ConflictItems $ConflictItems -SyncedCount $SyncedCount -SkippedCount $SkippedCount
    }
    finally {
        # 清理源文件跟踪器
        Clear-SourceFileTracker
    }
}

# 按源文件分组处理冲突
function Process-ConflictsBySourceGroup {
    param(
        [array]$ConflictItems,
        [ref]$SyncedCount,
        [ref]$SkippedCount
    )
    
    # 按源文件分组
    $sourceGroups = $ConflictItems | Group-Object -Property SourcePath
    
    foreach ($group in $sourceGroups) {
        $groupItems = $group.Group
        
        # 逐个处理组内项目，每次都基于更新后的源文件内容
        Process-IndividualConflicts -ConflictItems $groupItems -SyncedCount $SyncedCount -SkippedCount $SkippedCount
    }
}

# 处理逐个冲突解决
function Process-IndividualConflicts {
    param(
        [array]$ConflictItems,
        [ref]$SyncedCount,
        [ref]$SkippedCount
    )

    $batchAction = $null  # 用于批量操作: "SkipAll"
    
    for ($i = 0; $i -lt $ConflictItems.Count; $i++) {
        $conflictItem = $ConflictItems[$i]
        $currentIndex = $i + 1
        
        # 如果设置了批量操作，直接执行
        if ($batchAction) {
            if ($batchAction -eq "SkipAll") {
                Write-Host "    ⏩ 批量跳过: $($conflictItem.Link.Comment)" -ForegroundColor Cyan
                $SkippedCount.Value++
            }
            continue
        }
        
        Write-Host ""
        Write-Host "    📄 处理冲突: $($conflictItem.Link.Comment) ($currentIndex/$($ConflictItems.Count))" -ForegroundColor Yellow
        Write-Host "    $($conflictItem.TargetPath) → $($conflictItem.SourcePath)" -ForegroundColor Gray
        
        Show-FileProcessOptions -CurrentIndex $currentIndex -TotalCount $ConflictItems.Count

        Write-Host -NoNewline "    选择 ([Enter]/S/A) : "
        $choice = Read-Host

        switch ($choice.ToUpper()) {
            "" {
                # 默认选择：VS Code 合并
                # 重新创建冲突项以获取最新的源文件内容
                $updatedConflictItem = New-ConflictItem -Link $conflictItem.Link -Method $conflictItem.Method -TargetPath $conflictItem.TargetPath -SourcePath $conflictItem.SourcePath
                if (Invoke-VSCodeDiff -ConflictItem $updatedConflictItem) {
                    $SyncedCount.Value++
                } else {
                    $SkippedCount.Value++
                }
            }
            "S" {
                # 跳过此文件
                Write-Host "    ⏩ 跳过: $($conflictItem.Link.Comment)" -ForegroundColor Cyan
                $SkippedCount.Value++
            }
            "A" {
                # 剩余全部跳过
                Write-Host "    ⏩ 剩余文件全部跳过..." -ForegroundColor Cyan
                $batchAction = "SkipAll"
                Write-Host "    ⏩ 跳过: $($conflictItem.Link.Comment)" -ForegroundColor Cyan
                $SkippedCount.Value++
            }
            default {
                # 无效选择，默认VS Code处理
                Write-Host "    💡 无效选择，使用默认选项 (VS Code 合并)" -ForegroundColor Yellow
                # 重新创建冲突项以获取最新的源文件内容
                $updatedConflictItem = New-ConflictItem -Link $conflictItem.Link -Method $conflictItem.Method -TargetPath $conflictItem.TargetPath -SourcePath $conflictItem.SourcePath
                if (Invoke-VSCodeDiff -ConflictItem $updatedConflictItem) {
                    $SyncedCount.Value++
                } else {
                    $SkippedCount.Value++
                }
            }
        }
    }
}

# 显示同步摘要
function Show-SyncSummary {
    param(
        [int]$SyncedCount,
        [int]$SkippedCount,
        [int]$ConflictCount
    )

    Write-Host ""
    Write-Host "    📊 同步完成!" -ForegroundColor Green
    Write-Host "    ✅ 已同步: $SyncedCount 个文件" -ForegroundColor Green
    Write-Host "    ⏩ 已跳过: $SkippedCount 个文件" -ForegroundColor Cyan
    if ($ConflictCount -gt 0) {
        Write-Host "    ⚠️ 冲突数: $ConflictCount 个文件" -ForegroundColor Yellow
    }
}
#endregion

# 启动同步过程
Start-SyncProcess
