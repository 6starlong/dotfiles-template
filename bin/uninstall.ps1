# uninstall.ps1
# 移除 install.ps1 部署的配置文件

$dotfilesDir = Split-Path $PSScriptRoot -Parent

# 加载配置文件
$configFile = Join-Path $dotfilesDir "config.psd1"
if (-not (Test-Path $configFile)) {
    Write-Error "配置文件未找到: $configFile"
    return
}
$config = Import-PowerShellDataFile -Path $configFile

Write-Host "    🗑️  开始卸载 dotfiles 配置..." -ForegroundColor Yellow
Write-Host ""

$removedCount = 0
$skippedCount = 0

# 处理配置移除
foreach ($link in $config.Links) {
    $targetPath = $link.Target -replace '\{USERPROFILE\}', $env:USERPROFILE

    if (Test-Path $targetPath) {
        try {
            Remove-Item $targetPath -Force -ErrorAction Stop
            Write-Host "    🔥 已移除 ($($link.Comment)): $targetPath" -ForegroundColor Green
            $removedCount++
        } catch {
            Write-Host "    ❌ 移除失败 ($($link.Comment)): $($_.Exception.Message)" -ForegroundColor Red
            $skippedCount++
        }
    } else {
        Write-Host "    ➡️  跳过 ($($link.Comment)): 文件不存在" -ForegroundColor Cyan
        $skippedCount++
    }
}

Write-Host ""
Write-Host "    ✅ 卸载完成！" -ForegroundColor Green
Write-Host "    📊 移除了 $removedCount 个配置，跳过 $skippedCount 个" -ForegroundColor Green
Write-Host ""
