# sync.ps1
# 将系统中的配置文件同步回 dotfiles 仓库
# 支持 Copy 方法的配置文件

#region 初始化
$script:DotfilesDir = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $PSScriptRoot "..\lib\utils.psm1") -Force
$script:Config = Get-DotfilesConfig
#endregion

#region 文件同步处理
# VS Code 差异处理
function Invoke-VSCodeDiff {
    param([hashtable]$ConflictItem)

    if (-not (Get-Command "code" -ErrorAction SilentlyContinue)) {
        Write-Host "    ❌ VS Code 命令行工具未找到，请确保已安装并添加到 PATH" -ForegroundColor Red
        return $false
    }

    Write-Host "    ▶️ 启动 VS Code 差异合并..." -ForegroundColor Blue
    Write-Host ""
    Write-Host "    操作向导:" -ForegroundColor Yellow
    Write-Host "    • 左侧: System (系统中的文件)。"
    Write-Host "    • 右侧: Repo (仓库中的文件)。"
    Write-Host "    • 请在右侧合并修改，保存并关闭。"
    Write-Host ""

    # 打开 VS Code 差异视图：目标文件 vs 源文件
    & code --diff $ConflictItem.TargetPath $ConflictItem.SourcePath --wait

    return $true
}

# 处理单个文件同步
function Process-SingleFileSync {
    param([object]$ConflictItem)

    Write-Host ""
    Write-Host "    ----------------------------------------------------------------" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    📄 需要同步: $($ConflictItem.Link.Comment)" -ForegroundColor Blue
    Write-Host "    $($ConflictItem.TargetPath) → $($ConflictItem.SourcePath)" -ForegroundColor Gray

    # 如果源文件不存在，直接复制
    if (-not (Test-Path $ConflictItem.SourcePath)) {
        Copy-Item $ConflictItem.TargetPath $ConflictItem.SourcePath -Force
        Write-Host "    ✅ 已复制: $($ConflictItem.Link.Comment)" -ForegroundColor Green
        return $true
    }

    Write-Host ""
    Write-Host "    选择操作:" -ForegroundColor Yellow
    Write-Host "    [Enter] VS Code 差异合并 (默认)" -ForegroundColor Cyan
    Write-Host "    [1] 直接覆盖仓库文件" -ForegroundColor White
    Write-Host "    [2] 跳过此文件" -ForegroundColor White
    Write-Host ""
    Write-Host -NoNewline "    选择 ([Enter]/1/2) : "
    Write-Host ""
    $choice = Read-Host

    switch ($choice) {
        "1" {
            Copy-Item $ConflictItem.TargetPath $ConflictItem.SourcePath -Force
            Write-Host "    ✅ 已覆盖: $($ConflictItem.Link.Comment)" -ForegroundColor Green
            return $true
        }
        "2" {
            Write-Host "    ⏩ 跳过: $($ConflictItem.Link.Comment)" -ForegroundColor Gray
            return $false
        }
        default {
            if ($choice -and $choice -ne "") {
                Write-Host "    💡 无效选择，使用默认选项 (VS Code 合并)" -ForegroundColor Yellow
            }
            return Invoke-VSCodeDiff -ConflictItem $ConflictItem
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

    if ($method -ne "Copy") {
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

    # 检查是否需要同步
    if (-not (Test-Path $sourcePath) -or -not (Test-FileContentEqual -File1 $targetPath -File2 $sourcePath)) {
        # 需要同步，收集冲突项
        $ConflictItems.Value += @{
            Link = $Link
            TargetPath = $targetPath
            SourcePath = $sourcePath
        }
    } else {
        # 文件内容相同，已同步
        Write-Host "    ✅ 已同步: $($Link.Comment)" -ForegroundColor Green
        $SkippedCount.Value++
    }
}

# 处理冲突
function Process-Conflicts {
    param(
        [array]$ConflictItems,
        [ref]$SyncedCount,
        [ref]$SkippedCount
    )

    if ($ConflictItems.Count -eq 0) {
        return
    }

    foreach ($item in $ConflictItems) {
        $result = Process-SingleFileSync -ConflictItem $item

        if ($result) {
            $SyncedCount.Value++
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

    # 收集所有冲突和无冲突项
    foreach ($link in $script:Config.Links) {
        # 检查是否应该忽略此配置项
        if (Test-ConfigIgnored -Link $link) {
            Write-Host "    ⏩ 忽略: $($link.Comment)" -ForegroundColor Gray
            $skippedCount++
            continue
        }

        Process-ConfigLink -Link $link -SyncedCount ([ref]$syncedCount) -SkippedCount ([ref]$skippedCount) -ConflictItems ([ref]$conflictItems)
    }

    # 处理冲突
    Process-Conflicts -ConflictItems $conflictItems -SyncedCount ([ref]$syncedCount) -SkippedCount ([ref]$skippedCount)

    # 显示最终统计
    Write-Host ""
    Write-Host "    ----------------------------------------------------------------" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    📊 同步完成!" -ForegroundColor Green
    Write-Host "    ✅ 已同步: $syncedCount 个文件" -ForegroundColor Green
    Write-Host "    ⏩ 已跳过: $skippedCount 个文件" -ForegroundColor Cyan
    if ($conflictItems.Count -gt 0) {
        Write-Host "    ⚠️ 冲突数: $($conflictItems.Count) 个文件" -ForegroundColor Yellow
    }
}
#endregion

# 启动同步过程
Start-SyncProcess
