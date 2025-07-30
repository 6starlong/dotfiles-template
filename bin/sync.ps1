# sync.ps1
# 将系统中的配置文件同步回 dotfiles 仓库
# 只对使用 Copy 方法部署的配置文件有效

$dotfilesDir = Split-Path $PSScriptRoot -Parent

# 加载配置文件
$configFile = Join-Path $dotfilesDir "config.psd1"
if (-not (Test-Path $configFile)) {
    Write-Error "配置文件未找到: $configFile"
    return
}
$config = Import-PowerShellDataFile -Path $configFile

Write-Host "    🔄 同步Copy方法的配置文件到仓库..." -ForegroundColor Yellow
Write-Host ""

$syncedCount = 0
$skippedCount = 0

foreach ($link in $config.Links) {
    # 获取部署方法
    $method = if ($link.Method) { $link.Method } else { $config.DefaultMethod }
    if (-not $method) { $method = "SymLink" }
    
    # 只处理Copy方法的配置
    if ($method -eq "Copy") {
        $targetPath = $link.Target -replace '\{USERPROFILE\}', $env:USERPROFILE
        
        # 构建源文件路径
        $sourcePath = Join-Path $dotfilesDir $link.Source
        
        if (Test-Path $targetPath) {
            # 确保源文件目录存在
            $sourceDir = Split-Path $sourcePath -Parent
            if (-not (Test-Path $sourceDir)) {
                New-Item -Path $sourceDir -ItemType Directory -Force | Out-Null
            }
            
            # 复制文件到仓库
            Copy-Item $targetPath $sourcePath -Force
            Write-Host "    ✅ 同步: $($link.Comment)" -ForegroundColor Green
            Write-Host ""
            Write-Host "    $targetPath -> $sourcePath" -ForegroundColor Gray
            $syncedCount++
        } else {
            Write-Host "    ⚠️  文件不存在: $($link.Comment)" -ForegroundColor Yellow
            $skippedCount++
        }
    } else {
        Write-Host "    ➡️  跳过SymLink: $($link.Comment) (自动同步)" -ForegroundColor Cyan
        $skippedCount++
    }
}

Write-Host ""
Write-Host "    🎉 同步完成!" -ForegroundColor Green
Write-Host "    📊 同步了 $syncedCount 个配置文件，跳过 $skippedCount 个" -ForegroundColor Green

if ($syncedCount -gt 0) {
    Write-Host ""
    Write-Host "    💡 提示: 记得提交更改到Git仓库" -ForegroundColor Yellow
    Write-Host "       git add ." -ForegroundColor Gray
    Write-Host "       git commit -m `"Update configurations`"" -ForegroundColor Gray
}
Write-Host ""