# Dotfiles Manager
# 提供图形化菜单界面来管理 dotfiles 配置

$Host.UI.RawUI.WindowTitle = "Dotfiles Manager"

function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "    ================================================================" -ForegroundColor Green
    Write-Host "                          Dotfiles Manager" -ForegroundColor Green
    Write-Host "    ================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "     [1] 安装 Dotfiles         [2] 卸载 Dotfiles" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "     [3] 备份管理              [4] 同步配置到仓库" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "     [5] 检查配置状态" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "     [0] 退出程序" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    ================================================================" -ForegroundColor Green
    Write-Host ""
}

function Show-BackupMenu {
    Clear-Host
    Write-Host ""
    Write-Host "    ================================================================" -ForegroundColor Green
    Write-Host "                        备份管理菜单" -ForegroundColor Green
    Write-Host "    ================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "     [1] 创建新备份            [2] 列出所有备份" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "     [3] 从备份恢复            [4] 清理旧备份" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "     [0] 返回主菜单" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    ================================================================" -ForegroundColor Green
    Write-Host ""
    
    $choice = Read-Host "    请选择一个选项 (0-4)"
    Write-Host ""

    switch ($choice) {
        "1" { & (Join-Path $PSScriptRoot "backup.ps1") -Action create; Pause-Continue }
        "2" { & (Join-Path $PSScriptRoot "backup.ps1") -Action list; Pause-Continue }
        "3" { & (Join-Path $PSScriptRoot "backup.ps1") -Action restore; Pause-Continue }
        "4" { & (Join-Path $PSScriptRoot "backup.ps1") -Action clean; Pause-Continue }
        "0" { return }
        default {
            Write-Host "    [错误] 无效选择，请重试！" -ForegroundColor Red
            Start-Sleep -Seconds 2
            Show-BackupMenu
        }
    }
}

function Execute-Action {
    param(
        [string]$ActionName,
        [string]$ScriptName
    )

    Clear-Host
    Write-Host ""
    Write-Host "    ================================================================" -ForegroundColor Green
    Write-Host "      正在执行: $ActionName" -ForegroundColor Yellow
    Write-Host "    ================================================================" -ForegroundColor Green
    Write-Host ""

    $scriptPath = Join-Path $PSScriptRoot $ScriptName

    if (-not (Test-Path $scriptPath)) {
        Write-Host "    [错误] 脚本文件未找到: $ScriptName" -ForegroundColor Red
        Pause-Continue
        return
    }

    try {
        & powershell -ExecutionPolicy Bypass -File $scriptPath
        Write-Host ""
        Write-Host "    [成功] 操作完成！" -ForegroundColor Green
    }
    catch {
        Write-Host ""
        Write-Host "    [错误] 执行过程中发生错误！" -ForegroundColor Red
        Write-Host "    错误详情: $($_.Exception.Message)" -ForegroundColor Red
    }

    Pause-Continue
}

function Show-Status {
    Clear-Host
    & (Join-Path $PSScriptRoot "status.ps1")
    Pause-Continue
}

function Pause-Continue {
    Write-Host ""
    Write-Host "    ================================================================" -ForegroundColor Green
    Write-Host "      按任意键返回主菜单..." -ForegroundColor Yellow
    Write-Host "    ================================================================" -ForegroundColor Green
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# 主程序循环
do {
    Show-Menu
    $choice = Read-Host "    请选择一个选项 (0-5)"
    Write-Host ""

    switch ($choice) {
        "1" { Execute-Action "安装 Dotfiles" "install.ps1" }
        "2" { Execute-Action "卸载 Dotfiles" "uninstall.ps1" }
        "3" { Show-BackupMenu }
        "4" { Execute-Action "同步配置到仓库" "sync.ps1" }
        "5" { Show-Status }
        "0" {
            Clear-Host
            Write-Host ""
            Write-Host ""
            Write-Host "    ================================================================" -ForegroundColor Green
            Write-Host "                     感谢使用！Dotfiles 管理器" -ForegroundColor Cyan
            Write-Host "    ================================================================" -ForegroundColor Green
            Write-Host ""
            Write-Host "    程序将在 3 秒后自动关闭..." -ForegroundColor Yellow
            Start-Sleep -Seconds 3
            break
        }
        default {
            Write-Host "    [错误] 无效选择，请重试！" -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
} while ($true)