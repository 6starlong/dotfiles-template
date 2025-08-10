# status.ps1
# 检查 dotfiles 配置的部署状态

#region 初始化
$script:DotfilesDir = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $PSScriptRoot "utils.psm1") -Force
$script:Config = Get-DotfilesConfig
#endregion

#region 状态检查逻辑
# 检查单个配置的状态
function Get-ConfigStatus {
    param([hashtable]$Link)
    
    $targetPath = Resolve-ConfigPath -Path $Link.Target -DotfilesDir $script:DotfilesDir
    $sourcePath = Join-Path $script:DotfilesDir $Link.Source
    $method = Get-Method -Link $Link
    
    # 检查目标文件是否存在
    if (-not (Test-Path $targetPath)) {
        return @{
            Status = "NotDeployed"
            Message = "未部署"
            Color = "Red"
            Icon = "❌"
        }
    }
    
    # 检查源文件是否存在
    if (-not (Test-Path $sourcePath)) {
        return @{
            Status = "SourceMissing"
            Message = "源文件缺失"
            Color = "Yellow"
            Icon = "⚠️"
        }
    }
    
    $item = Get-Item $targetPath -Force
    
    # 检查是否为符号链接
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        $target = $item.Target
        if ($target -and $target[0] -eq $sourcePath) {
            return @{
                Status = "Synced"
                Message = "已同步"
                Color = "Green"
                Icon = "✅"
            }
        } elseif ($target) {
            return @{
                Status = "LinkError"
                Message = "链接错误"
                Color = "Yellow"
                Icon = "⚠️"
            }
        } else {
            return @{
                Status = "LinkBroken"
                Message = "链接损坏"
                Color = "Red"
                Icon = "❌"
            }
        }
    } else {
        # 普通文件，比较内容
        if (Test-FileContentEqual -File1 $sourcePath -File2 $targetPath) {
            return @{
                Status = "Synced"
                Message = "已同步"
                Color = "Cyan"
                Icon = "✅"
            }
        } else {
            return @{
                Status = "OutOfSync"
                Message = "未同步"
                Color = "Yellow"
                Icon = "⚠️"
            }
        }
    }
}

# 显示状态报告
function Show-StatusReport {
    Write-Host ""
    Write-Host "    ================================================================" -ForegroundColor Green
    Write-Host "                        配置状态检查" -ForegroundColor Green
    Write-Host "    ================================================================" -ForegroundColor Green
    Write-Host ""

    # 计算最长的配置名称长度，用于动态对齐
    $maxCommentLength = ($script:Config.Links | ForEach-Object { $_.Comment.Length } | Measure-Object -Maximum).Maximum
    $commentPadding = [Math]::Max($maxCommentLength + 2, 35)

    $statusCounts = @{
        Synced = 0
        NotDeployed = 0
        OutOfSync = 0
        Error = 0
    }

    foreach ($link in $script:Config.Links) {
        $status = Get-ConfigStatus -Link $link
        $method = Get-Method -Link $link
        
        $configName = $link.Comment.PadRight($commentPadding)
        $methodTag = "[$method]".PadRight(13)
        
        Write-Host "    $($status.Icon) $configName $methodTag $($status.Message)" -ForegroundColor $status.Color
        
        # 统计状态
        switch ($status.Status) {
            "Synced" { $statusCounts.Synced++ }
            "NotDeployed" { $statusCounts.NotDeployed++ }
            "OutOfSync" { $statusCounts.OutOfSync++ }
            default { $statusCounts.Error++ }
        }
    }

    # 显示统计信息
    Write-Host ""
    Write-Host "    📊 状态统计:" -ForegroundColor Cyan
    Write-Host "    ✅ 已同步: $($statusCounts.Synced) 个" -ForegroundColor Green
    if ($statusCounts.NotDeployed -gt 0) {
        Write-Host "    ❌ 未部署: $($statusCounts.NotDeployed) 个" -ForegroundColor Red
    }
    if ($statusCounts.OutOfSync -gt 0) {
        Write-Host "    ⚠️ 未同步: $($statusCounts.OutOfSync) 个" -ForegroundColor Yellow
    }
    if ($statusCounts.Error -gt 0) {
        Write-Host "    🔥 有问题: $($statusCounts.Error) 个" -ForegroundColor Red
    }
    Write-Host ""
}
#endregion

# 显示状态报告
Show-StatusReport
