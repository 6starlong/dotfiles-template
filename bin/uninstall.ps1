# uninstall.ps1
# 移除 install.ps1 部署的配置文件

$ErrorActionPreference = 'Stop'

#region 初始化
$script:DotfilesDir = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $PSScriptRoot "utils.psm1") -Force
$script:Config = Get-DotfilesConfig
#endregion

#region 主卸载逻辑
# 清理空的父目录
function Remove-EmptyDirectories {
    param([string]$FilePath)
    
    $parentDir = Split-Path $FilePath -Parent
    
    # 递归向上清理空目录，直到遇到非空目录或到达根目录
    while ($parentDir -and (Test-Path $parentDir)) {
        try {
            # 检查目录是否为空
            $items = Get-ChildItem $parentDir -Force -ErrorAction SilentlyContinue
            if ($items.Count -eq 0) {
                Remove-Item $parentDir -Force -ErrorAction Stop
                $parentDir = Split-Path $parentDir -Parent
            } else {
                # 目录不为空，停止清理
                break
            }
        } catch {
            # 无法删除目录（可能是权限问题或系统目录），停止清理
            break
        }
    }
}

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
        Remove-Item $targetPath -Force -ErrorAction Stop
        Write-Host "    🔥 已移除: $($Link.Comment)" -ForegroundColor Green
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
    Write-Host "    🗑️ 开始卸载 dotfiles 配置..." -ForegroundColor Yellow
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

    # 显示最终统计
    Write-Host ""
    Write-Host "    📊 卸载完成!" -ForegroundColor Green
    Write-Host "    🔥 已移除: $removedCount 个文件" -ForegroundColor Green
    if ($skippedCount -gt 0) {
        Write-Host "    ⏩ 已跳过: $skippedCount 个文件" -ForegroundColor Cyan
    }
}
#endregion

# 启动卸载过程
Start-UninstallProcess
