# backup.ps1
# 配置文件备份管理工具

param(
    [Parameter(Position=0, Mandatory=$false)]
    [ValidateSet("create", "list", "restore", "clean", "help")]
    [string]$Action = "create"
)

#region 初始化
$script:DotfilesDir = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $PSScriptRoot "..\lib\utils.psm1") -Force
$script:Config = Get-DotfilesConfig

$script:BackupSettings = $script:Config.BackupSettings
$script:BackupBaseDir = Join-Path $script:DotfilesDir $script:BackupSettings.BackupDir
#endregion

#region 帮助信息
function Show-Help {
    Write-Host ""
    Write-Host "📋 备份工具使用说明" -ForegroundColor Green
    Write-Host ""
    Write-Host "用法: .\backup.ps1 [action]" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "可用操作:" -ForegroundColor Yellow
    Write-Host "  create   - 创建新备份 (默认)" -ForegroundColor White
    Write-Host "  list     - 列出所有备份" -ForegroundColor White
    Write-Host "  restore  - 从备份恢复配置" -ForegroundColor White
    Write-Host "  clean    - 清理旧备份" -ForegroundColor White
    Write-Host "  help     - 显示此帮助信息" -ForegroundColor White
    Write-Host ""
    Write-Host "示例:" -ForegroundColor Yellow
    Write-Host "  .\backup.ps1                # 创建备份" -ForegroundColor Gray
    Write-Host "  .\backup.ps1 list           # 列出备份" -ForegroundColor Gray
    Write-Host "  .\backup.ps1 restore        # 恢复备份" -ForegroundColor Gray
    Write-Host ""
}
#endregion

#region 备份操作
function Create-Backup {
    Write-Host "    🔄 检查需要备份的配置文件..." -ForegroundColor Yellow

    # 收集需要备份的文件
    $filesToBackup = @()
    foreach ($link in $script:Config.Links) {
        $targetPath = Resolve-ConfigPath -Path $link.Target -DotfilesDir $script:DotfilesDir
        if (Test-Path $targetPath) {
            $filesToBackup += @{
                Link = $link
                TargetPath = $targetPath
            }
        }
    }

    if ($filesToBackup.Count -eq 0) {
        Write-Host "    📭 没有找到需要备份的配置文件" -ForegroundColor Yellow
        Write-Host ""
        return
    }

    # 确定备份路径
    if ($script:BackupSettings.UseTimestamp) {
        $timestamp = Get-Date -Format $script:BackupSettings.TimestampFormat
        $backupPath = Join-Path $script:BackupBaseDir "backup_$timestamp"
    } else {
        $backupPath = $script:BackupBaseDir
    }

    Write-Host "    📁 创建备份目录: $backupPath" -ForegroundColor Cyan
    Write-Host ""

    # 创建备份目录
    try {
        New-Item -Path $backupPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "无法创建备份目录: $backupPath. 错误: $($_.Exception.Message)"
        return
    }

    # 备份文件
    $backedUpCount = 0
    foreach ($fileInfo in $filesToBackup) {
        $link = $fileInfo.Link
        $targetPath = $fileInfo.TargetPath

        $backupFilePath = Join-Path $backupPath $link.Source
        $backupDir = Split-Path $backupFilePath -Parent

        # 确保备份目录存在
        if (-not (Test-Path $backupDir)) {
            try {
                New-Item -Path $backupDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
            } catch {
                Write-Warning "无法创建备份子目录: $backupDir. 跳过 $($link.Comment)"
                continue
            }
        }

        # 复制文件
        try {
            Copy-Item $targetPath $backupFilePath -Force -ErrorAction Stop
            Write-Host "    ✅ 备份: $($link.Comment)" -ForegroundColor Green
            Write-Host "       $targetPath -> $backupFilePath" -ForegroundColor Gray
            $backedUpCount++
        } catch {
            Write-Host "    ⚠️ 备份失败: $($link.Comment). 错误: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # 清理旧备份
    if ($script:BackupSettings.MaxBackups -gt 0 -and $script:BackupSettings.UseTimestamp) {
        Clean-OldBackupsAuto
    }

    Write-Host ""
    Write-Host "    🎉 备份了 $backedUpCount 个配置文件" -ForegroundColor Green
    Write-Host "    📁 备份位置: $backupPath" -ForegroundColor Green
    Write-Host ""
}

function List-Backups {
    Write-Host "    📁 备份目录: $script:BackupBaseDir" -ForegroundColor Gray
    Write-Host ""

    if (-not (Test-Path $script:BackupBaseDir)) {
        Write-Host "    ❌ 备份目录不存在" -ForegroundColor Red
        Write-Host ""
        return @()
    }

    $backups = Get-ChildItem -Path $script:BackupBaseDir -Directory -ErrorAction SilentlyContinue | Sort-Object CreationTime -Descending

    if ($backups.Count -eq 0) {
        Write-Host "    📭 没有找到备份文件" -ForegroundColor Yellow
        Write-Host ""
        return @()
    }

    for ($i = 0; $i -lt $backups.Count; $i++) {
        $backup = $backups[$i]
        $size = (Get-ChildItem -Path $backup.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum
        $sizeStr = if ($size -gt 1MB) { "{0:N2} MB" -f ($size / 1MB) } else { "{0:N2} KB" -f ($size / 1KB) }

        Write-Host "    [$($i + 1)] $($backup.Name)" -ForegroundColor Cyan
        Write-Host "        创建时间: $($backup.CreationTime.ToString('yyyy-MM-dd HH:mm:ss'))    大小: $sizeStr" -ForegroundColor Gray
        Write-Host ""
    }

    return $backups
}

function Restore-FromBackup {
    $backups = List-Backups
    if ($backups.Count -eq 0) {
        return
    }

    Write-Host "    请选择要恢复的备份 (1-$($backups.Count)):" -ForegroundColor Yellow
    Write-Host ""
    Write-Host -NoNewline "    选择: "
    $choice = Read-Host

    if (-not ($choice -match '^\d+$') -or [int]$choice -lt 1 -or [int]$choice -gt $backups.Count) {
        Write-Host ""
        Write-Host "    ❌ 无效选择" -ForegroundColor Red
        Write-Host ""
        return
    }

    $selectedBackup = $backups[[int]$choice - 1]
    Write-Host ""
    Write-Host "    🔄 从备份恢复: $($selectedBackup.Name)" -ForegroundColor Yellow
    Write-Host ""

    # 恢复文件
    $restoredCount = 0
    foreach ($link in $script:Config.Links) {
        $backupFilePath = Join-Path $selectedBackup.FullName $link.Source

        if (Test-Path $backupFilePath) {
            $targetPath = Resolve-ConfigPath -Path $link.Target -DotfilesDir $script:DotfilesDir

            # 确保目标目录存在
            $targetDir = Split-Path $targetPath -Parent
            if (-not (Test-Path $targetDir)) {
                New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
            }

            # 恢复文件
            Copy-Item $backupFilePath $targetPath -Force
            Write-Host "    ✅ 恢复: $($link.Comment)" -ForegroundColor Green
            $restoredCount++
        }
    }

    Write-Host ""
    Write-Host "    🎉 恢复完成! 恢复了 $restoredCount 个配置文件" -ForegroundColor Green
    Write-Host ""
}

function Clean-OldBackups {
    Write-Host "    📁 备份目录: $script:BackupBaseDir" -ForegroundColor Gray
    Write-Host ""

    if (-not (Test-Path $script:BackupBaseDir)) {
        Write-Host "    ❌ 备份目录不存在" -ForegroundColor Red
        Write-Host ""
        return
    }

    $backups = Get-ChildItem -Path $script:BackupBaseDir -Directory -ErrorAction SilentlyContinue | Sort-Object CreationTime -Descending

    if ($backups.Count -eq 0) {
        Write-Host "    📭 没有找到备份文件" -ForegroundColor Yellow
        Write-Host ""
        return
    }

    Write-Host "    📊 当前备份数量: $($backups.Count)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    🗑️ 将删除所有备份文件:" -ForegroundColor Yellow
    Write-Host ""

    foreach ($backup in $backups) {
        Write-Host "        - $($backup.Name)" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host -NoNewline "    确认删除所有备份? (y/N): "
    $confirm = Read-Host

    if ($confirm -eq 'y' -or $confirm -eq 'Y') {
        Write-Host ""
        foreach ($backup in $backups) {
            Remove-Item $backup.FullName -Recurse -Force
            Write-Host "    🗑️ 已删除: $($backup.Name)" -ForegroundColor DarkGray
        }
        Write-Host ""
        Write-Host "    ✅ 清理完成! 已删除所有 $($backups.Count) 个备份" -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host ""
        Write-Host "    ❌ 取消清理" -ForegroundColor Red
        Write-Host ""
    }
}

# 自动清理旧备份（内部使用）
function Clean-OldBackupsAuto {
    $allBackups = Get-ChildItem -Path $script:BackupBaseDir -Directory |
                  Where-Object { $_.Name -match "^backup_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$" } |
                  Sort-Object CreationTime -Descending

    if ($allBackups.Count -gt $script:BackupSettings.MaxBackups) {
        $toDelete = $allBackups | Select-Object -Skip $script:BackupSettings.MaxBackups
        foreach ($oldBackup in $toDelete) {
            Write-Host "    🗑️ 删除旧备份: $($oldBackup.Name)" -ForegroundColor DarkGray
            Remove-Item $oldBackup.FullName -Recurse -Force
        }
    }
}
#endregion

# 执行操作
switch ($Action) {
    "create" { Create-Backup }
    "list" { List-Backups | Out-Null }
    "restore" { Restore-FromBackup }
    "clean" { Clean-OldBackups }
    "help" { Show-Help }
    default { Show-Help }
}
