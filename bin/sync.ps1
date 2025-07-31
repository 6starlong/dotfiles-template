# sync.ps1
# 将系统中的配置文件同步回 dotfiles 仓库
# 支持 Copy 和 Transform 方法的配置文件

param(
    [switch]$Force,
    [switch]$Silent
)

$dotfilesDir = Split-Path $PSScriptRoot -Parent

# 加载配置文件
$configFile = Join-Path $dotfilesDir "config.psd1"
if (-not (Test-Path $configFile)) {
    Write-Error "配置文件未找到: $configFile"
    return
}
$config = Import-PowerShellDataFile -Path $configFile

# 显示冲突概览选项
function Show-ConflictOverviewOptions {
    param(
        [array]$ConflictItems
    )

    # 检查是否有多个配置指向同一个源文件
    $sourceGroups = $ConflictItems | Group-Object { $_.SourcePath }
    $hasSourceConflicts = ($sourceGroups | Where-Object { $_.Count -gt 1 }).Count -gt 0

    Write-Host ""
    Write-Host "    冲突解决选项:" -ForegroundColor Yellow
    Write-Host "    [d] 逐个查看差异并选择" -ForegroundColor White

    if ($hasSourceConflicts) {
        Write-Host "    [s] 对所有冲突跳过同步" -ForegroundColor White
        Write-Host ""
        Write-Host "    ⚠️  注意: 检测到多个配置指向相同源文件，不提供批量同步选项" -ForegroundColor Yellow
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
    Write-Host "    选择操作:" -ForegroundColor Yellow
    Write-Host "    [1] 使用 UserProfile (覆盖 Dotfiles)" -ForegroundColor White
    Write-Host "    [2] 跳过此文件 (保留 Dotfiles)" -ForegroundColor White
    Write-Host ""
}

# 静默比较文件内容
function Test-FileContentEqual {
    param(
        [string]$File1,
        [string]$File2
    )

    try {
        $content1 = Get-Content $File1 -Raw -ErrorAction Stop
        $content2 = Get-Content $File2 -Raw -ErrorAction Stop
        return $content1 -eq $content2
    } catch {
        return $false
    }
}

# 比较文件内容并显示差异
function Compare-FileContent {
    param(
        [string]$File1,
        [string]$File2,
        [string]$Description1 = "文件1",
        [string]$Description2 = "文件2"
    )

    try {
        $content1 = Get-Content $File1 -Raw -ErrorAction Stop
        $content2 = Get-Content $File2 -Raw -ErrorAction Stop

        if ($content1 -eq $content2) {
            return $true
        }

        Write-Host ""
        Write-Host "    📋 文件差异 (类似 git diff):" -ForegroundColor Cyan
        Write-Host ""

        # 分割为行数组
        $lines1 = $content1 -split "`n"
        $lines2 = $content2 -split "`n"

        # 生成差异视图
        Show-DiffView $lines1 $lines2 $Description1 $Description2

        Write-Host ""
        return $false
    } catch {
        Write-Host "    ❌ 无法比较文件: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 显示类似 git diff 的差异视图
function Show-DiffView {
    param(
        [string[]]$Lines1,
        [string[]]$Lines2,
        [string]$Description1,
        [string]$Description2
    )

    $maxLines = [Math]::Max($Lines1.Count, $Lines2.Count)
    $contextLines = 3  # 上下文行数
    $diffBlocks = @()  # 存储差异块

    # 找出所有差异行
    for ($i = 0; $i -lt $maxLines; $i++) {
        $line1 = if ($i -lt $Lines1.Count) { $Lines1[$i] } else { $null }
        $line2 = if ($i -lt $Lines2.Count) { $Lines2[$i] } else { $null }

        if ($line1 -ne $line2) {
            # 计算上下文范围
            $start = [Math]::Max(0, $i - $contextLines)
            $end = [Math]::Min($maxLines - 1, $i + $contextLines)

            # 检查是否与现有差异块重叠
            $merged = $false
            for ($j = 0; $j -lt $diffBlocks.Count; $j++) {
                if ($start -le $diffBlocks[$j].End + 1 -and $end -ge $diffBlocks[$j].Start - 1) {
                    # 合并差异块
                    $diffBlocks[$j].Start = [Math]::Min($diffBlocks[$j].Start, $start)
                    $diffBlocks[$j].End = [Math]::Max($diffBlocks[$j].End, $end)
                    $merged = $true
                    break
                }
            }

            if (-not $merged) {
                $diffBlocks += @{
                    Start = $start
                    End = $end
                }
            }
        }
    }

    # 显示差异块
    foreach ($block in $diffBlocks) {
        Write-Host "    @@ -$($block.Start + 1),$($block.End - $block.Start + 1) +$($block.Start + 1),$($block.End - $block.Start + 1) @@" -ForegroundColor Cyan

        for ($i = $block.Start; $i -le $block.End; $i++) {
            $line1 = if ($i -lt $Lines1.Count) { $Lines1[$i] } else { $null }
            $line2 = if ($i -lt $Lines2.Count) { $Lines2[$i] } else { $null }

            if ($line1 -eq $line2) {
                # 相同行 (上下文)
                Write-Host "    $($i + 1):  $line1" -ForegroundColor Gray
            } else {
                # 差异行
                if ($line1 -ne $null) {
                    Write-Host "    $($i + 1): -$line1" -ForegroundColor Red
                }
                if ($line2 -ne $null) {
                    Write-Host "    $($i + 1): +$line2" -ForegroundColor Green
                }
            }
        }
        Write-Host ""
    }

    # 显示文件信息
    Write-Host "    📄 $Description1 (红色 -)" -ForegroundColor Red
    Write-Host "    📄 $Description2 (绿色 +)" -ForegroundColor Green
}

# 同步单个文件
function Sync-SingleFile {
    param($ConflictItem)

    try {
        if ($ConflictItem.Method -eq "Copy") {
            # 直接复制文件
            Copy-Item $ConflictItem.TargetPath $ConflictItem.SourcePath -Force
            Write-Host "    ✅ 同步: $($ConflictItem.Link.Comment)" -ForegroundColor Green
            Write-Host "    $($ConflictItem.TargetPath) -> $($ConflictItem.SourcePath)" -ForegroundColor Gray
        } else {
            # Transform方法，需要反向转换
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                & $ConflictItem.TransformScript -SourceFile $ConflictItem.TargetPath -TargetFile $tempFile -TransformType $ConflictItem.Link.Transform -Reverse -ErrorAction Stop | Out-Null
                Copy-Item $tempFile $ConflictItem.SourcePath -Force
                Write-Host "    ✅ 同步(转换): $($ConflictItem.Link.Comment)" -ForegroundColor Green
                Write-Host "    $($ConflictItem.TargetPath) -> $($ConflictItem.SourcePath) (反向转换)" -ForegroundColor Gray
            } finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
            }
        }
        return $true
    } catch {
        Write-Host "    ❌ 同步失败: $($ConflictItem.Link.Comment). 错误: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

Write-Host "    🔄 同步配置文件到仓库..." -ForegroundColor Yellow
Write-Host ""

$syncedCount = 0
$skippedCount = 0
$conflictCount = 0
$globalChoice = $null
$conflictItems = @()  # 存储所有冲突项

# 第一阶段：收集所有冲突和无冲突项
foreach ($link in $config.Links) {
    # 获取部署方法
    $method = if ($link.Method) { $link.Method } else { $config.DefaultMethod }
    if (-not $method) { $method = "SymLink" }

    # 处理Copy和Transform方法的配置
    if ($method -eq "Copy" -or $method -eq "Transform") {
        $targetPath = $link.Target -replace '\{USERPROFILE\}', $env:USERPROFILE
        $sourcePath = Join-Path $dotfilesDir $link.Source

        if (-not (Test-Path $targetPath)) {
            Write-Host "    ⚠️  文件不存在: $($link.Comment)" -ForegroundColor Yellow
            $skippedCount++
            continue
        }

        # 确保源文件目录存在
        $sourceDir = Split-Path $sourcePath -Parent
        if (-not (Test-Path $sourceDir)) {
            New-Item -Path $sourceDir -ItemType Directory -Force | Out-Null
        }

        $hasConflict = $false
        $shouldSync = $true

        # 检查是否存在冲突
        if (Test-Path $sourcePath) {
            if ($method -eq "Copy") {
                # 直接比较文件内容
                $hasConflict = -not (Test-FileContentEqual $targetPath $sourcePath)
            } elseif ($method -eq "Transform") {
                # 对于Transform方法，需要反向转换后比较
                if (-not $link.Transform) {
                    Write-Host "    ❌ Transform配置缺少Transform参数: $($link.Comment)" -ForegroundColor Red
                    $skippedCount++
                    continue
                }

                $transformScript = Join-Path $PSScriptRoot "transform.ps1"
                if (-not (Test-Path $transformScript)) {
                    Write-Host "    ❌ 转换脚本未找到: $transformScript" -ForegroundColor Red
                    $skippedCount++
                    continue
                }

                # 创建临时文件进行反向转换
                $tempFile = [System.IO.Path]::GetTempFileName()
                try {
                    # 将 UserProfile 反向转换为基础格式
                    & $transformScript -SourceFile $targetPath -TargetFile $tempFile -TransformType $link.Transform -Reverse -ErrorAction Stop | Out-Null
                    $hasConflict = -not (Test-FileContentEqual $tempFile $sourcePath)
                } catch {
                    Write-Host "    ❌ 转换失败: $($link.Comment). 错误: $($_.Exception.Message)" -ForegroundColor Red
                    $skippedCount++
                    continue
                } finally {
                    if (Test-Path $tempFile) {
                        Remove-Item $tempFile -Force
                    }
                }
            }
        }

        # 收集冲突项或直接处理无冲突项
        if ($hasConflict -and -not $Force) {
            # 收集冲突项，稍后统一处理
            # 保存原始的 Dotfiles 内容，避免后续处理时被覆盖
            $originalDotfilesContent = Get-Content $sourcePath -Raw

            $conflictItems += @{
                Link = $link
                Method = $method
                TargetPath = $targetPath
                SourcePath = $sourcePath
                OriginalDotfilesContent = $originalDotfilesContent
                TransformScript = if ($method -eq "Transform") { $transformScript } else { $null }
            }
            $conflictCount++
            $shouldSync = $false  # 冲突文件不在第一阶段同步
        } else {
            # 无冲突或强制模式，直接同步
            if ($Silent -and $hasConflict) {
                # 静默模式，默认跳过冲突
                Write-Host "    ➡️  静默模式，跳过冲突: $($link.Comment)" -ForegroundColor Cyan
                $shouldSync = $false
            } else {
                $shouldSync = $true  # 无冲突，直接同步
            }
        }

        if ($shouldSync) {
            try {
                if ($method -eq "Copy") {
                    # 直接复制文件
                    Copy-Item $targetPath $sourcePath -Force
                    Write-Host "    ✅ 同步: $($link.Comment)" -ForegroundColor Green
                    Write-Host "    $targetPath -> $sourcePath" -ForegroundColor Gray
                } elseif ($method -eq "Transform") {
                    # 反向转换后保存
                    & $transformScript -SourceFile $targetPath -TargetFile $sourcePath -TransformType $link.Transform -Reverse -ErrorAction Stop | Out-Null
                    Write-Host "    ✅ 同步(转换): $($link.Comment)" -ForegroundColor Green
                    Write-Host "    $targetPath -> $sourcePath (反向转换)" -ForegroundColor Gray
                }
                $syncedCount++
            } catch {
                Write-Host "    ❌ 同步失败: $($link.Comment). 错误: $($_.Exception.Message)" -ForegroundColor Red
                $skippedCount++
            }
        } elseif (-not ($hasConflict -and -not $Force)) {
            # 只有非冲突的跳过才显示消息，冲突文件会在后面统一处理
            Write-Host "    ➡️  跳过: $($link.Comment)" -ForegroundColor Cyan
            $skippedCount++
        }
    } else {
        Write-Host "    ➡️  跳过SymLink: $($link.Comment) (自动同步)" -ForegroundColor Cyan
        $skippedCount++
    }
}

# 第二阶段：处理所有冲突
if ($conflictItems.Count -gt 0 -and -not $Silent) {
    Write-Host ""
    Write-Host "    ⚠️  检测到 $($conflictItems.Count) 个冲突:" -ForegroundColor Yellow

    # 显示所有冲突项
    for ($i = 0; $i -lt $conflictItems.Count; $i++) {
        Write-Host "    $($i + 1). $($conflictItems[$i].Link.Comment)" -ForegroundColor White
    }

    # 显示冲突概览选项
    Show-ConflictOverviewOptions -ConflictItems $conflictItems

    # 检查是否有源文件冲突来决定可用选项
    $sourceGroups = $conflictItems | Group-Object { $_.SourcePath }
    $hasSourceConflicts = ($sourceGroups | Where-Object { $_.Count -gt 1 }).Count -gt 0

    if ($hasSourceConflicts) {
        Write-Host -NoNewline "    选择 (d/s): "
    } else {
        Write-Host -NoNewline "    选择 (d/a/s): "
    }
    $overviewChoice = Read-Host

    switch ($overviewChoice.ToLower()) {
        "d" {
            # 逐个查看差异并选择
            Write-Host ""
            Write-Host "    🔍 进入差异编辑模式..." -ForegroundColor Cyan

            foreach ($conflictItem in $conflictItems) {
                Write-Host ""
                Write-Host "    📄 处理冲突: $($conflictItem.Link.Comment)" -ForegroundColor Yellow

                # 显示差异（使用保存的原始内容）
                if ($conflictItem.Method -eq "Copy") {
                    # 创建临时文件保存原始 Dotfiles 内容
                    $tempDotfilesFile = [System.IO.Path]::GetTempFileName()
                    try {
                        Set-Content $tempDotfilesFile $conflictItem.OriginalDotfilesContent -NoNewline
                        Compare-FileContent $conflictItem.TargetPath $tempDotfilesFile "UserProfile" "Dotfiles" | Out-Null
                    } finally {
                        if (Test-Path $tempDotfilesFile) { Remove-Item $tempDotfilesFile -Force }
                    }
                } else {
                    $tempUserFile = [System.IO.Path]::GetTempFileName()
                    $tempDotfilesFile = [System.IO.Path]::GetTempFileName()
                    try {
                        # 转换 UserProfile 内容
                        & $conflictItem.TransformScript -SourceFile $conflictItem.TargetPath -TargetFile $tempUserFile -TransformType $conflictItem.Link.Transform -Reverse -ErrorAction Stop | Out-Null
                        # 保存原始 Dotfiles 内容
                        Set-Content $tempDotfilesFile $conflictItem.OriginalDotfilesContent -NoNewline
                        Compare-FileContent $tempUserFile $tempDotfilesFile "UserProfile(转换后)" "Dotfiles" | Out-Null
                    } finally {
                        if (Test-Path $tempUserFile) { Remove-Item $tempUserFile -Force }
                        if (Test-Path $tempDotfilesFile) { Remove-Item $tempDotfilesFile -Force }
                    }
                }

                # 显示单个文件选项
                Show-DiffEditOptions
                Write-Host -NoNewline "    选择 (1/2): "
                $fileChoice = Read-Host

                switch ($fileChoice) {
                    "1" {
                        # 同步此文件
                        if (Sync-SingleFile $conflictItem) {
                            $syncedCount++
                        } else {
                            $skippedCount++
                        }
                    }
                    default {
                        # 跳过此文件
                        Write-Host "    ➡️  跳过: $($conflictItem.Link.Comment)" -ForegroundColor Cyan
                        $skippedCount++
                    }
                }
            }
        }
        "a" {
            # 对所有冲突使用 UserProfile（仅在无源文件冲突时可用）
            if ($hasSourceConflicts) {
                Write-Host ""
                Write-Host "    ❌ 无效选择: 存在多个配置指向相同源文件，无法批量同步" -ForegroundColor Red
                Write-Host "    💡 请使用 [d] 选项逐个处理冲突" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "    ➡️  自动跳过所有冲突文件" -ForegroundColor Cyan
                $skippedCount += $conflictItems.Count
            } else {
                Write-Host ""
                Write-Host "    🔄 同步所有冲突文件..." -ForegroundColor Green
                foreach ($conflictItem in $conflictItems) {
                    if (Sync-SingleFile $conflictItem) {
                        $syncedCount++
                    } else {
                        $skippedCount++
                    }
                }
            }
        }
        default {
            # 跳过所有冲突
            Write-Host ""
            Write-Host "    ➡️  跳过所有冲突文件" -ForegroundColor Cyan
            $skippedCount += $conflictItems.Count
        }
    }
}

Write-Host ""
Write-Host "    🎉 同步完成!" -ForegroundColor Green
Write-Host "    📊 同步了 $syncedCount 个配置文件，跳过 $skippedCount 个" -ForegroundColor Green

if ($conflictCount -gt 0) {
    Write-Host "    ⚠️  处理了 $conflictCount 个冲突" -ForegroundColor Yellow
}

if ($syncedCount -gt 0) {
    Write-Host ""
    Write-Host "    💡 提示: 记得提交更改到Git仓库" -ForegroundColor Yellow
    Write-Host "       git add ." -ForegroundColor Gray
    Write-Host "       git commit -m `"Update configurations`"" -ForegroundColor Gray
}

Write-Host ""
Write-Host "    📖 使用说明:" -ForegroundColor Cyan
Write-Host "       .\sync.ps1          # 交互式同步" -ForegroundColor Gray
Write-Host "       .\sync.ps1 -Force   # 强制同步(覆盖所有冲突)" -ForegroundColor Gray
Write-Host "       .\sync.ps1 -Silent  # 静默模式(跳过所有冲突)" -ForegroundColor Gray
Write-Host ""