# uninstall.ps1
# 移除 install.ps1 部署的配置文件

# 初始化
Import-Module (Join-Path $PSScriptRoot "..\lib\utils.psm1") -Force
$script:DotfilesDir = Split-Path $PSScriptRoot -Parent
$script:Config = Get-DotfilesConfig

$ErrorActionPreference = 'Stop'

# 处理单个配置链接的卸载
function Process-ConfigUninstall {
    param(
        [hashtable]$Link,
        [ref]$RemovedCount,
        [ref]$SkippedCount
    )

    $targetPath = Resolve-ConfigPath -Path $Link.Target -DotfilesDir $script:DotfilesDir
    $method = Get-Method -Link $Link

    if (-not (Test-Path $targetPath)) {
        Write-Host "    ⏩ 跳过: $($Link.Comment) (文件不存在)" -ForegroundColor Cyan
        $SkippedCount.Value++
        return
    }

    try {
        $item = Get-Item -Path $targetPath -Force -ErrorAction SilentlyContinue
        $isDir = $item.Attributes -band [System.IO.FileAttributes]::Directory

        Remove-Item $targetPath -Force -Recurse -ErrorAction Stop

        if ($isDir) {
            Write-Host "    ➖ 已移除目录: $($Link.Comment)" -ForegroundColor Green
        } else {
            Write-Host "    ➖ 已移除文件: $($Link.Comment)" -ForegroundColor Green
        }
        Write-Host "       $targetPath" -ForegroundColor Gray

        # 清理空的父目录
        Remove-EmptyDirectories -FilePath $targetPath

        $RemovedCount.Value++
    } catch {
        Write-Host "    ❌ 移除失败: $($Link.Comment)" -ForegroundColor Red
        Write-Host "       错误: $($_.Exception.Message)" -ForegroundColor Gray
        $SkippedCount.Value++
    }
}

# 启动卸载过程
function Start-UninstallProcess {
    Write-Host "    🚀 开始卸载 dotfiles 配置..." -ForegroundColor Yellow
    Write-Host ""

    $removedCount = 0
    $skippedCount = 0

    # 处理所有配置链接
    foreach ($link in $script:Config.Links) {
        # 检查是否应该忽略此配置项
        if (Test-ConfigIgnored -Link $link) {
            Write-Host "    ⏩ 忽略: $($link.Comment)" -ForegroundColor Gray
            $skippedCount++
            continue
        }

        Process-ConfigUninstall -Link $link -RemovedCount ([ref]$removedCount) -SkippedCount ([ref]$skippedCount)
    }

    # 清理生成的配置文件
    Write-Host ""
    Write-Host "    🧹 正在清理生成的配置文件..." -ForegroundColor Yellow
    $transformScript = Join-Path $PSScriptRoot "..\scripts\transform.ps1"
    if (Test-Path $transformScript) {
        try {
            & $transformScript -Remove -Silent 2>&1 | Out-Null
            Write-Host "    ✅ 清理完成" -ForegroundColor Green
        } catch {
            Write-Host "    ❌ 清理失败: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # 显示最终统计
    Write-Host ""
    Write-Host "    ✨ 卸载完成!" -ForegroundColor Green
    Write-Host "    🔥 已移除: $removedCount 个配置" -ForegroundColor Green
    if ($skippedCount -gt 0) {
        Write-Host "    ⏩ 已跳过: $skippedCount 个配置" -ForegroundColor Cyan
    }
    Write-Host ""
}

# 启动卸载过程
Start-UninstallProcess
