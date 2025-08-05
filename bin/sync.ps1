# sync.ps1
# 将系统中的配置文件同步回 dotfiles 仓库
# 支持 Copy 和 Transform 方法的配置文件

param(
    [Parameter(Position=0, Mandatory=$false)]
    [ValidateSet("sync", "force", "silent", "help")]
    [string]$Action = "sync"
)

#region 辅助函数
# 显示帮助信息
function Show-HelpMessage {
    Write-Host ""
    Write-Host "📋 同步工具使用说明" -ForegroundColor Green
    Write-Host ""
    Write-Host "用法: .\sync.ps1 [action]" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "可用操作:" -ForegroundColor Yellow
    Write-Host "  sync     - 交互式同步 (默认)" -ForegroundColor White
    Write-Host "  force    - 强制同步(覆盖所有冲突)" -ForegroundColor White
    Write-Host "  silent   - 静默模式(跳过所有冲突)" -ForegroundColor White
    Write-Host "  help     - 显示此帮助信息" -ForegroundColor White
    Write-Host ""
    Write-Host "示例:" -ForegroundColor Yellow
    Write-Host "  .\sync.ps1                  # 交互式同步" -ForegroundColor Gray
    Write-Host "  .\sync.ps1 force            # 强制同步" -ForegroundColor Gray
    Write-Host "  .\sync.ps1 silent           # 静默同步" -ForegroundColor Gray
    Write-Host ""
}

# 加载配置数据
function Get-ConfigData {
    $configFile = Join-Path $script:DotfilesDir "config.psd1"
    if (-not (Test-Path $configFile)) {
        Write-Error "配置文件未找到: $configFile"
        exit 1
    }
    return Import-PowerShellDataFile -Path $configFile
}

# 展开路径变量
function Expand-Path {
    param([string]$Path)
    return $Path -replace '\{USERPROFILE\}', $env:USERPROFILE
}

# 获取部署方法
function Get-Method {
    param([hashtable]$Link)
    $method = if ($Link.Method) { $Link.Method } else { $script:Config.DefaultMethod }
    if ($method) { return $method } else { return "SymLink" }
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
# 处理帮助信息
if ($Action -eq "help") {
    Show-HelpMessage
    return
}

# 设置全局变量
$script:Force = ($Action -eq "force")
$script:Silent = ($Action -eq "silent")
$script:DotfilesDir = Split-Path $PSScriptRoot -Parent
$script:Config = Get-ConfigData
#endregion

#region 文件比较
# 比较文件内容
function Test-FileContentEqual {
    param(
        [Parameter(Mandatory)][string]$File1,
        [Parameter(Mandatory)][string]$File2
    )

    try {
        $content1 = Get-Content $File1 -Raw -ErrorAction Stop
        $content2 = Get-Content $File2 -Raw -ErrorAction Stop
        return $content1 -eq $content2
    } catch {
        return $false
    }
}
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
        $originalContent = if (Test-Path $sourcePath) {
            # 使用 .NET 方法正确读取 UTF-8 with BOM 文件
            [System.IO.File]::ReadAllText($sourcePath, [System.Text.UTF8Encoding]::new($true))
        } else { 
            "" 
        }
        
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
    if (Test-Path $SourcePath) { 
        # 使用 .NET 方法正确读取 UTF-8 with BOM 文件
        return [System.IO.File]::ReadAllText($SourcePath, [System.Text.UTF8Encoding]::new($true))
    } else { 
        return "" 
    }
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
            return -not (Test-FileContentEqual $TargetPath $SourcePath)
        }
        "Transform" {
            if (-not $Link.MappingId) {
                Write-Host "    ❌ Transform配置缺少MappingId参数: $($Link.Comment)" -ForegroundColor Red
                return $false
            }

            $transformScript = Join-Path $PSScriptRoot "transform.ps1"
            if (-not (Test-Path $transformScript)) {
                Write-Host "    ❌ 转换脚本未找到: $transformScript" -ForegroundColor Red
                return $false
            }

            try {
                return Invoke-WithTempFiles -Count 1 -ScriptBlock {
                    param($tempFile)
                    & $transformScript -SourceFile $TargetPath -TargetFile $tempFile -TransformType $Link.MappingId -Reverse -ErrorAction Stop | Out-Null
                    return -not (Test-FileContentEqual $tempFile $SourcePath)
                }
            } catch {
                Write-Host "    ❌ 转换失败: $($Link.Comment). 错误: $($_.Exception.Message)" -ForegroundColor Red
                return $false
            }
        }
        default {
            return $false
        }
    }
}

# 同步单个文件
function Sync-SingleFile {
    param([Parameter(Mandatory)][hashtable]$ConflictItem)

    try {
        switch ($ConflictItem.Method) {
            "Copy" {
                Copy-Item $ConflictItem.TargetPath $ConflictItem.SourcePath -Force
                
                # 更新源文件跟踪器
                $newContent = Get-Content $ConflictItem.SourcePath -Raw
                Update-SourceFileCurrentContent -SourcePath $ConflictItem.SourcePath -NewContent $newContent
                
                Write-Host "    ✅ 同步: $($ConflictItem.Link.Comment)" -ForegroundColor Green
                Write-Host "    $($ConflictItem.TargetPath) -> $($ConflictItem.SourcePath)" -ForegroundColor Gray
            }
            "Transform" {
                Invoke-WithTempFiles -Count 1 -ScriptBlock {
                    param($tempFile)
                    & $ConflictItem.TransformScript -SourceFile $ConflictItem.TargetPath -TargetFile $tempFile -TransformType $ConflictItem.Link.MappingId -Reverse -ErrorAction Stop | Out-Null
                    Copy-Item $tempFile $ConflictItem.SourcePath -Force
                    
                    # 更新源文件跟踪器
                    $newContent = Get-Content $ConflictItem.SourcePath -Raw
                    Update-SourceFileCurrentContent -SourcePath $ConflictItem.SourcePath -NewContent $newContent
                    
                    Write-Host "    ✅ 同步(转换): $($ConflictItem.Link.Comment)" -ForegroundColor Green
                    Write-Host "    $($ConflictItem.TargetPath) -> $($ConflictItem.SourcePath) (反向转换)" -ForegroundColor Gray
                }
            }
            default {
                throw "不支持的同步方法: $($ConflictItem.Method)"
            }
        }
        return $true
    } catch {
        Write-Host "    ❌ 同步失败: $($ConflictItem.Link.Comment). 错误: $($_.Exception.Message)" -ForegroundColor Red
        return $false
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
# VS Code 交互式差异处理
function Invoke-VSCodeDiff {
    param([Parameter(Mandatory)][hashtable]$ConflictItem)

    Write-Host ""
    Write-Host "    📝 启动 VS Code 差异视图..." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    操作说明:" -ForegroundColor Yellow
    Write-Host "    • 左侧: 当前配置 (系统版本)" -ForegroundColor Gray
    Write-Host "    • 右侧: Dotfiles (仓库版本)" -ForegroundColor Gray
    Write-Host "    • 点击差异块旁的箭头选择保留哪一侧的修改" -ForegroundColor Gray
    Write-Host "    • 或直接编辑右侧文件进行自定义合并" -ForegroundColor Gray
    Write-Host "    • 完成后请保存右侧文件并关闭 VS Code 标签页" -ForegroundColor Gray
    Write-Host ""

    # 创建基于映射ID的临时文件名
    $tempDir = [System.IO.Path]::GetTempPath()
    $projectPrefix = if ($script:Config.ProjectSettings -and $script:Config.ProjectSettings.ProjectPrefix) {
        $script:Config.ProjectSettings.ProjectPrefix
    } else {
        "dotfiles"
    }
    
    # 构建目标文件名：[项目前缀]_[映射ID]_current.[扩展名]
    $targetExtension = [System.IO.Path]::GetExtension($ConflictItem.TargetPath)
    if ($ConflictItem.Link.MappingId) {
        # 有映射ID的情况，使用映射ID（替换 : 为 -）
        $cleanMappingId = $ConflictItem.Link.MappingId -replace ":", "-"
        $tempUserFile = Join-Path $tempDir "$projectPrefix`_$cleanMappingId`_current$targetExtension"
    } else {
        # 没有映射ID的情况，使用目标文件名
        $targetBaseName = [System.IO.Path]::GetFileNameWithoutExtension($ConflictItem.TargetPath)
        $tempUserFile = Join-Path $tempDir  "$projectPrefix`_$targetBaseName`_current$targetExtension"
    }
    
    # 构建源文件名：[项目前缀]_[文件路径]_target.[扩展名]
    $sourceExtension = [System.IO.Path]::GetExtension($ConflictItem.SourcePath)
    $sourceRelativePath = $ConflictItem.Link.Source -replace "[\\/]", "-"
    # 移除扩展名以避免重复（更精确的移除方式）
    if ($sourceRelativePath.EndsWith($sourceExtension)) {
        $sourceRelativePath = $sourceRelativePath.Substring(0, $sourceRelativePath.Length - $sourceExtension.Length)
    }
    $tempDotfilesFile = Join-Path $tempDir "$projectPrefix`_$sourceRelativePath`_target$sourceExtension"

    try {
        
        # 准备文件内容用于比较，确保编码一致性
        # 读取目标文件内容并以 UTF-8 with BOM 写入临时文件
        $targetContent = Get-Content $ConflictItem.TargetPath -Raw
        [System.IO.File]::WriteAllText($tempUserFile, $targetContent, [System.Text.UTF8Encoding]::new($true))
        
        # # 使用 UTF-8 with BOM 确保中文在 VS Code 中正常显示
        [System.IO.File]::WriteAllText($tempDotfilesFile, $ConflictItem.OriginalDotfilesContent, [System.Text.UTF8Encoding]::new($true))

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
        & code --diff $tempUserFile $tempDotfilesFile --wait

        # 用户完成后，检查右侧文件是否有修改
        if (-not (Test-FileContentEqual $tempDotfilesFile $ConflictItem.OriginalDotfilesContent)) {
            # 应用合并结果
            Copy-Item $tempDotfilesFile $ConflictItem.SourcePath -Force
            
            # 更新源文件跟踪器
            $newContent = Get-Content $ConflictItem.SourcePath -Raw
            Update-SourceFileCurrentContent -SourcePath $ConflictItem.SourcePath -NewContent $newContent
            
            Write-Host "    ✅ 合并完成: $($ConflictItem.Link.Comment)" -ForegroundColor Green
            Write-Host "    合并结果 -> $($ConflictItem.SourcePath)" -ForegroundColor Gray
            return $true
        } else {
            Write-Host "    ⏩ 未修改，跳过: $($ConflictItem.Link.Comment)" -ForegroundColor Cyan
            return $false
        }
    }
    catch {
        Write-Host "    ❌ VS Code 处理失败: $($ConflictItem.Link.Comment). 错误: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    finally {
        # 清理临时文件
        if (Test-Path $tempUserFile) { Remove-Item $tempUserFile -Force -ErrorAction SilentlyContinue }
        if (Test-Path $tempDotfilesFile) { Remove-Item $tempDotfilesFile -Force -ErrorAction SilentlyContinue }
    }
}
#endregion

#region 用户界面函数

# 显示单个文件的处理选项
function Show-FileProcessOptions {
    param(
        [int]$CurrentIndex, 
        [int]$TotalCount,
        [bool]$HasMultipleTargetsToSameSource = $false
    )
    
    Write-Host ""
    Write-Host "    选择操作:" -ForegroundColor Yellow
    Write-Host "    [Enter] VS Code 差异合并 (默认)" -ForegroundColor Cyan
    Write-Host "    [1] 使用当前配置覆盖 Dotfiles" -ForegroundColor White
    Write-Host "    [2] 跳过此文件" -ForegroundColor White
    
    if ($HasMultipleTargetsToSameSource) {
        Write-Host "    [A] 全部覆盖 (已禁用 - 检测到同源冲突)" -ForegroundColor DarkGray
    } else {
        Write-Host "    [A] 全部覆盖" -ForegroundColor Yellow
    }
    
    Write-Host "    [S] 全部跳过" -ForegroundColor Yellow
    Write-Host ""
}

#endregion

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

    # 只处理 Copy 和 Transform 方法
    if ($method -ne "Copy" -and $method -ne "Transform") {
        Write-Host "    ⏩ 跳过SymLink: $($Link.Comment) (自动同步)" -ForegroundColor Cyan
        $SkippedCount.Value++
        return
    }

    $targetPath = Expand-Path -Path $Link.Target
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

    if ($hasConflict -and -not $script:Force) {
        # 收集冲突项
        $ConflictItems.Value += New-ConflictItem -Link $Link -Method $method -TargetPath $targetPath -SourcePath $sourcePath
    } else {
        # 处理无冲突或强制模式
        $shouldSync = $true

        if ($script:Silent -and $hasConflict) {
            Write-Host "    ⏩ 静默模式，跳过冲突: $($Link.Comment)" -ForegroundColor Cyan
            $shouldSync = $false
        }

        if ($shouldSync) {
            $conflictItem = New-ConflictItem -Link $Link -Method $method -TargetPath $targetPath -SourcePath $sourcePath
            if (Sync-SingleFile -ConflictItem $conflictItem) {
                $SyncedCount.Value++
            } else {
                $SkippedCount.Value++
            }
        } else {
            $SkippedCount.Value++
        }
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

    if ($ConflictItems.Count -eq 0 -or $script:Silent) {
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

# 检查是否存在多个目标指向同一源文件的情况
function Test-MultipleTargetsToSameSource {
    param([array]$ConflictItems)
    
    $sourceGroups = $ConflictItems | Group-Object -Property SourcePath
    return ($sourceGroups | Where-Object { $_.Count -gt 1 }).Count -gt 0
}

# 处理逐个冲突解决
function Process-IndividualConflicts {
    param(
        [array]$ConflictItems,
        [ref]$SyncedCount,
        [ref]$SkippedCount
    )

    # 检查是否存在多目标同源的情况
    $hasMultipleTargetsToSameSource = Test-MultipleTargetsToSameSource -ConflictItems $ConflictItems

    $batchAction = $null  # 用于批量操作: "SyncAll" 或 "SkipAll"
    
    for ($i = 0; $i -lt $ConflictItems.Count; $i++) {
        $conflictItem = $ConflictItems[$i]
        $currentIndex = $i + 1
        
        # 如果设置了批量操作，直接执行
        if ($batchAction) {
            if ($batchAction -eq "SyncAll") {
                # 重新创建冲突项以获取最新的源文件内容
                $updatedConflictItem = New-ConflictItem -Link $conflictItem.Link -Method $conflictItem.Method -TargetPath $conflictItem.TargetPath -SourcePath $conflictItem.SourcePath
                if (Sync-SingleFile -ConflictItem $updatedConflictItem) {
                    Write-Host "    ✅ 批量覆盖: $($conflictItem.Link.Comment)" -ForegroundColor Green
                    $SyncedCount.Value++
                } else {
                    $SkippedCount.Value++
                }
            } elseif ($batchAction -eq "SkipAll") {
                Write-Host "    ⏩ 批量跳过: $($conflictItem.Link.Comment)" -ForegroundColor Cyan
                $SkippedCount.Value++
            }
            continue
        }
        
        Write-Host ""
        Write-Host "    📄 处理冲突: $($conflictItem.Link.Comment) ($currentIndex/$($ConflictItems.Count))" -ForegroundColor Yellow
        Write-Host "    $($conflictItem.TargetPath) → $($conflictItem.SourcePath)" -ForegroundColor Gray
        
        Show-FileProcessOptions -CurrentIndex $currentIndex -TotalCount $ConflictItems.Count -HasMultipleTargetsToSameSource $hasMultipleTargetsToSameSource

        Write-Host -NoNewline "    选择 ([Enter]/1/2/A/S) : "
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
            "1" {
                # 使用当前配置覆盖
                # 重新创建冲突项以获取最新的源文件内容
                $updatedConflictItem = New-ConflictItem -Link $conflictItem.Link -Method $conflictItem.Method -TargetPath $conflictItem.TargetPath -SourcePath $conflictItem.SourcePath
                if (Sync-SingleFile -ConflictItem $updatedConflictItem) {
                    $SyncedCount.Value++
                } else {
                    $SkippedCount.Value++
                }
            }
            "2" {
                # 跳过此文件
                Write-Host "    ⏩ 跳过: $($conflictItem.Link.Comment)" -ForegroundColor Cyan
                $SkippedCount.Value++
            }
            "A" {
                if ($hasMultipleTargetsToSameSource) {
                    Write-Host "    ❌ 批量覆盖已禁用 - 存在多目标指向同源的情况" -ForegroundColor Red
                    Write-Host "    💡 请逐个处理或使用批量跳过 (S)" -ForegroundColor Yellow
                    # 重新处理当前项
                    $i--
                    continue
                }
                # 剩余全部覆盖
                Write-Host "    🔄 剩余文件全部覆盖..." -ForegroundColor Cyan
                $batchAction = "SyncAll"
                # 重新创建冲突项以获取最新的源文件内容
                $updatedConflictItem = New-ConflictItem -Link $conflictItem.Link -Method $conflictItem.Method -TargetPath $conflictItem.TargetPath -SourcePath $conflictItem.SourcePath
                if (Sync-SingleFile -ConflictItem $updatedConflictItem) {
                    Write-Host "    ✅ 覆盖: $($conflictItem.Link.Comment)" -ForegroundColor Green
                    $SyncedCount.Value++
                } else {
                    $SkippedCount.Value++
                }
            }
            "S" {
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
