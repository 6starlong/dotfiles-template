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

#region 文件比较和差异显示
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

# 获取 Git diff 输出
function Get-GitDiffOutput {
    param(
        [Parameter(Mandatory)][string]$File1,
        [Parameter(Mandatory)][string]$File2
    )

    $originalEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    try {
        $rawOutput = & git diff --no-index --no-prefix -- $File1 $File2 2>$null
        $coloredOutput = & git diff --no-index --color=always --no-prefix -- $File1 $File2 2>$null

        return @{
            ExitCode = $LASTEXITCODE
            RawLines = if ($rawOutput) { $rawOutput -split "`n" } else { @() }
            ColoredLines = if ($coloredOutput) { $coloredOutput -split "`n" } else { @() }
        }
    }
    finally {
        [Console]::OutputEncoding = $originalEncoding
    }
}

# 过滤 Git diff 输出
function Filter-GitDiffOutput {
    param(
        [Parameter(Mandatory)][string[]]$RawLines,
        [Parameter(Mandatory)][string[]]$ColoredLines
    )

    $processedLines = @()
    $filterPatterns = @('^diff --git\s', '^index\s+[a-f0-9]+\.\.[a-f0-9]+', '^---\s', '^\+\+\+\s')

    for ($i = 0; $i -lt [Math]::Min($RawLines.Length, $ColoredLines.Length); $i++) {
        $rawLine = $RawLines[$i]
        $coloredLine = $ColoredLines[$i]

        # 检查是否需要过滤
        $shouldFilter = $filterPatterns | Where-Object { $rawLine -match $_ }
        if ($shouldFilter) {
            continue
        }

        # 清理并保留行
        if ($coloredLine.Trim() -ne "") {
            $processedLines += $coloredLine
        }
    }

    return $processedLines
}

# 显示文件差异
function Show-DiffView {
    param(
        [Parameter(Mandatory)][string]$File1,
        [Parameter(Mandatory)][string]$File2,
        [string]$Description1 = "文件1",
        [string]$Description2 = "文件2"
    )

    try {
        $diffResult = Get-GitDiffOutput -File1 $File1 -File2 $File2

        switch ($diffResult.ExitCode) {
            0 { Write-Host "    📄 文件内容相同" -ForegroundColor Gray }
            1 {
                if ($diffResult.RawLines -and $diffResult.ColoredLines) {
                    $processedLines = Filter-GitDiffOutput -RawLines $diffResult.RawLines -ColoredLines $diffResult.ColoredLines
                    $processedLines | ForEach-Object {
                        if ($_.Trim() -ne "") { Write-Host "    $_" }
                    }
                } else {
                    Write-Host "    📄 文件内容相同" -ForegroundColor Gray
                }
            }
            default {
                Write-Host "    ❌ git diff 执行失败（退出代码: $($diffResult.ExitCode)）" -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "    ❌ 无法调用 git diff: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 比较文件内容并显示差异
function Compare-FileContent {
    param(
        [Parameter(Mandatory)][string]$File1,
        [Parameter(Mandatory)][string]$File2,
        [string]$Description1 = "文件1",
        [string]$Description2 = "文件2"
    )

    if (Test-FileContentEqual $File1 $File2) {
        return $true
    }

    Write-Host ""
    Write-Host "    📋 文件差异 (git diff):" -ForegroundColor Cyan
    Write-Host ""
    Show-DiffView $File1 $File2 $Description1 $Description2
    return $false
}
#endregion

#region 同步处理函数
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
            if (-not $Link.Transform) {
                Write-Host "    ❌ Transform配置缺少Transform参数: $($Link.Comment)" -ForegroundColor Red
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
                    & $transformScript -SourceFile $TargetPath -TargetFile $tempFile -TransformType $Link.Transform -Reverse -ErrorAction Stop | Out-Null
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
                Write-Host "    ✅ 同步: $($ConflictItem.Link.Comment)" -ForegroundColor Green
                Write-Host "    $($ConflictItem.TargetPath) -> $($ConflictItem.SourcePath)" -ForegroundColor Gray
            }
            "Transform" {
                Invoke-WithTempFiles -Count 1 -ScriptBlock {
                    param($tempFile)
                    & $ConflictItem.TransformScript -SourceFile $ConflictItem.TargetPath -TargetFile $tempFile -TransformType $ConflictItem.Link.Transform -Reverse -ErrorAction Stop | Out-Null
                    Copy-Item $tempFile $ConflictItem.SourcePath -Force
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

    $originalContent = if (Test-Path $SourcePath) { Get-Content $SourcePath -Raw } else { "" }

    return @{
        Link = $Link
        Method = $Method
        TargetPath = $TargetPath
        SourcePath = $SourcePath
        OriginalDotfilesContent = $originalContent
        TransformScript = if ($Method -eq "Transform") { Join-Path $PSScriptRoot "transform.ps1" } else { $null }
    }
}
#endregion

#region 用户界面函数
# 显示冲突概览选项
function Show-ConflictOverviewOptions {
    param([array]$ConflictItems)

    $sourceGroups = $ConflictItems | Group-Object { $_.SourcePath }
    $hasSourceConflicts = ($sourceGroups | Where-Object { $_.Count -gt 1 }).Count -gt 0

    Write-Host ""
    Write-Host "    冲突解决选项:" -ForegroundColor Yellow
    Write-Host "    [d] 逐个查看差异并选择" -ForegroundColor White

    if ($hasSourceConflicts) {
        Write-Host "    [s] 对所有冲突跳过同步" -ForegroundColor White
        Write-Host ""
        Write-Host "    ⚠️ 注意: 检测到多个配置指向相同源文件，不提供批量同步选项" -ForegroundColor Yellow
        Write-Host "    💡 建议使用 [d] 选项逐个处理以避免数据覆盖" -ForegroundColor Cyan
    } else {
        Write-Host "    [a] 对所有冲突使用 UserProfile" -ForegroundColor White
        Write-Host "    [s] 对所有冲突跳过同步" -ForegroundColor White
    }
    Write-Host ""
}

# 显示单个文件的差异选项
function Show-DiffEditOptions {
    Write-Host ""
    Write-Host "    - 旧内容 (Dotfiles)" -ForegroundColor Red
    Write-Host "    + 新内容 (UserProfile)" -ForegroundColor Green
    Write-Host ""
    Write-Host "    选择操作:" -ForegroundColor Yellow
    Write-Host "    [1] 使用 UserProfile (覆盖 Dotfiles)" -ForegroundColor White
    Write-Host "    [2] 跳过此文件 (保留 Dotfiles)" -ForegroundColor White
    Write-Host ""
}

# 显示冲突差异
function Show-ConflictDiff {
    param([hashtable]$ConflictItem)

    Write-Host ""
    Write-Host "    📄 处理冲突: $($ConflictItem.Link.Comment)" -ForegroundColor Yellow

    switch ($ConflictItem.Method) {
        "Copy" {
            Invoke-WithTempFiles -Count 1 -ScriptBlock {
                param($tempDotfilesFile)
                [System.IO.File]::WriteAllText($tempDotfilesFile, $ConflictItem.OriginalDotfilesContent, [System.Text.UTF8Encoding]::new($false))
                Compare-FileContent $tempDotfilesFile $ConflictItem.TargetPath "Dotfiles (仓库中的配置)" "UserProfile (你的当前配置)" | Out-Null
            }
        }
        "Transform" {
            Invoke-WithTempFiles -Count 2 -ScriptBlock {
                param($tempUserFile, $tempDotfilesFile)
                & $ConflictItem.TransformScript -SourceFile $ConflictItem.TargetPath -TargetFile $tempUserFile -TransformType $ConflictItem.Link.Transform -Reverse -ErrorAction Stop | Out-Null
                [System.IO.File]::WriteAllText($tempDotfilesFile, $ConflictItem.OriginalDotfilesContent, [System.Text.UTF8Encoding]::new($false))
                Compare-FileContent $tempDotfilesFile $tempUserFile "Dotfiles (仓库中的配置)" "UserProfile (转换后)" | Out-Null
            }
        }
    }
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

    Write-Host ""
    Write-Host "    ⚠️ 检测到 $($ConflictItems.Count) 个冲突:" -ForegroundColor Yellow

    # 显示所有冲突项
    for ($i = 0; $i -lt $ConflictItems.Count; $i++) {
        Write-Host "    $($i + 1). $($ConflictItems[$i].Link.Comment)" -ForegroundColor White
    }

    # 显示冲突概览选项
    Show-ConflictOverviewOptions -ConflictItems $ConflictItems

    # 检查是否有源文件冲突来决定可用选项
    $sourceGroups = $ConflictItems | Group-Object { $_.SourcePath }
    $hasSourceConflicts = ($sourceGroups | Where-Object { $_.Count -gt 1 }).Count -gt 0

    # 获取用户选择
    if ($hasSourceConflicts) {
        Write-Host -NoNewline "    选择 (d/s): "
    } else {
        Write-Host -NoNewline "    选择 (d/a/s): "
    }
    $overviewChoice = Read-Host

    switch ($overviewChoice.ToLower()) {
        "d" {
            Process-IndividualConflicts -ConflictItems $ConflictItems -SyncedCount $SyncedCount -SkippedCount $SkippedCount
        }
        "a" {
            if (-not $hasSourceConflicts) {
                Process-BatchConflictResolution -ConflictItems $ConflictItems -Action "SyncAll" -SyncedCount $SyncedCount -SkippedCount $SkippedCount
            }
        }
        "s" {
            Process-BatchConflictResolution -ConflictItems $ConflictItems -Action "SkipAll" -SyncedCount $SyncedCount -SkippedCount $SkippedCount
        }
        default {
            Write-Host "    ❌ 无效选择，跳过所有冲突" -ForegroundColor Red
            Process-BatchConflictResolution -ConflictItems $ConflictItems -Action "SkipAll" -SyncedCount $SyncedCount -SkippedCount $SkippedCount
        }
    }
}

# 处理逐个冲突解决
function Process-IndividualConflicts {
    param(
        [array]$ConflictItems,
        [ref]$SyncedCount,
        [ref]$SkippedCount
    )

    Write-Host ""
    Write-Host "    🔍 进入差异编辑模式..." -ForegroundColor Cyan

    foreach ($conflictItem in $ConflictItems) {
        Show-ConflictDiff -ConflictItem $conflictItem
        Show-DiffEditOptions

        Write-Host -NoNewline "    选择 (1/2): "
        $choice = Read-Host

        switch ($choice) {
            "1" {
                if (Sync-SingleFile -ConflictItem $conflictItem) {
                    $SyncedCount.Value++
                } else {
                    $SkippedCount.Value++
                }
            }
            "2" {
                Write-Host "    ⏩ 跳过: $($conflictItem.Link.Comment)" -ForegroundColor Cyan
                $SkippedCount.Value++
            }
            default {
                Write-Host "    ❌ 无效选择，跳过此文件" -ForegroundColor Red
                $SkippedCount.Value++
            }
        }
    }
}

# 处理批量冲突解决
function Process-BatchConflictResolution {
    param(
        [array]$ConflictItems,
        [ValidateSet("SyncAll", "SkipAll")][string]$Action,
        [ref]$SyncedCount,
        [ref]$SkippedCount
    )

    switch ($Action) {
        "SyncAll" {
            Write-Host ""
            Write-Host "    🔄 同步所有冲突文件..." -ForegroundColor Cyan
            foreach ($conflictItem in $ConflictItems) {
                if (Sync-SingleFile -ConflictItem $conflictItem) {
                    $SyncedCount.Value++
                } else {
                    $SkippedCount.Value++
                }
            }
        }
        "SkipAll" {
            Write-Host ""
            Write-Host "    ⏩ 跳过所有冲突文件..." -ForegroundColor Cyan
            foreach ($conflictItem in $ConflictItems) {
                Write-Host "    ⏩ 跳过: $($conflictItem.Link.Comment)" -ForegroundColor Cyan
                $SkippedCount.Value++
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
    Write-Host ""
}
#endregion

# 启动同步过程
Start-SyncProcess
