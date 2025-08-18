# status.ps1
# 检查 dotfiles 配置的部署状态

#region 初始化
$script:DotfilesDir = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $PSScriptRoot "..\lib\utils.psm1") -Force
$script:Config = Get-DotfilesConfig
#endregion

#region 状态检查逻辑
# 检查单个配置的状态
function Get-ConfigStatus {
    param([hashtable]$Link)

    $targetPath = Resolve-ConfigPath -Path $Link.Target -DotfilesDir $script:DotfilesDir
    $sourcePath = Join-Path $script:DotfilesDir $Link.Source
    $method = Get-Method -Link $Link

    # 检查源文件是否存在
    if (-not (Test-Path $sourcePath)) {
        return @{
            Status = "SourceMissing"
            Message = "源文件缺失"
            Color = "Yellow"
            Icon = "🔔"
        }
    }

    # 检查目标文件是否存在
    if (-not (Test-Path $targetPath)) {
        return @{
            Status = "NotDeployed"
            Message = "未部署"
            Color = "Red"
            Icon = "❌"
        }
    }

    $isSourceDir = Test-Path -Path $sourcePath -PathType Container
    $item = Get-Item $targetPath -Force

    # 检查是否为符号链接或Junction
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        $rawTarget = $item.Target
        $resolvedLinkTarget = try {
            Resolve-Path -LiteralPath $rawTarget -ErrorAction Stop
        } catch { $null }

        if ($resolvedLinkTarget -and ($resolvedLinkTarget.Path -eq $sourcePath)) {
            $message = if ($isSourceDir) { "已链接 (目录)" } else { "已链接 (文件)" }
            return @{
                Status = "Synced"
                Message = $message
                Color = "Green"
                Icon = "✅"
            }
        } else {
            return @{
                Status = "InvalidLink"
                Message = "链接无效"
                Color = "Red"
                Icon = "❌"
            }
        }
    } else {
        # 目标不是链接
        if ($isSourceDir) {
            # 源是目录，但目标不是链接，这是一个错误状态
            return @{
                Status = "InvalidLink"
                Message = "链接无效"
                Color = "Red"
                Icon = "❌"
            }
        }

        # 普通文件，比较内容
        if (Test-FileContentEqual -File1 $sourcePath -File2 $targetPath) {
            return @{
                Status = "Synced"
                Message = "已同步 (文件)"
                Color = "Cyan"
                Icon = "✅"
            }
        } else {
            return @{
                Status = "OutOfSync"
                Message = "未同步 (文件)"
                Color = "Yellow"
                Icon = "🔔"
            }
        }
    }
}

# 计算字符串显示宽度（中文字符占2个位置）
function Get-DisplayWidth {
    param([string]$Text)
    $width = 0
    foreach ($char in $Text.ToCharArray()) {
        if ([int]$char -gt 127) { $width += 2 } else { $width += 1 }
    }
    return $width
}

# 格式化状态行
function Format-StatusLine {
    param(
        [hashtable]$Status,
        [hashtable]$Link,
        [string]$Method
    )

    $fixedWidth = 32
    $comment = $Link.Comment
    $width = Get-DisplayWidth $comment

    # 截断过长的注释
    if ($width -gt $fixedWidth) {
        $truncated = ""
        $currentWidth = 0
        foreach ($char in $comment.ToCharArray()) {
            $charWidth = if ([int]$char -gt 127) { 2 } else { 1 }
            if ($currentWidth + $charWidth + 3 -le $fixedWidth) {
                $truncated += $char
                $currentWidth += $charWidth
            } else { break }
        }
        $comment = $truncated + "..."
        $width = Get-DisplayWidth $comment
    }

    # 对齐到固定位置
    $commentPadding = " " * ($fixedWidth - $width + 2)
    $methodFormatted = "[$Method]"
    $methodPadding = " " * (10 - $methodFormatted.Length)

    return "$($Status.Icon) $comment$commentPadding$methodFormatted$methodPadding$($Status.Message)"
}

# 显示状态报告
function Show-StatusReport {
    Write-Host ""
    Write-Host "    ================================================================" -ForegroundColor Green
    Write-Host "                        配置状态检查" -ForegroundColor Green
    Write-Host "    ================================================================" -ForegroundColor Green
    Write-Host ""

    $statusCounts = @{
        Synced = 0
        NotDeployed = 0
        OutOfSync = 0
        Error = 0
    }

    foreach ($link in $script:Config.Links) {
        # 检查是否应该忽略此配置项
        if (Test-ConfigIgnored -Link $link) {
            $line = Format-StatusLine -Status @{Icon="⏩"; Message="已忽略"; Color="Gray"} -Link $link -Method "N/A"
            Write-Host "    $line" -ForegroundColor Gray
            continue
        }

        $status = Get-ConfigStatus -Link $link
        $method = Get-Method -Link $link

        # 使用格式化函数生成状态行
        $line = Format-StatusLine -Status $status -Link $link -Method $method
        Write-Host "    $line" -ForegroundColor $status.Color

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
    Write-Host "    🤖 状态统计:" -ForegroundColor Cyan
    Write-Host "    ✅ 已同步: $($statusCounts.Synced) 个" -ForegroundColor Green
    if ($statusCounts.NotDeployed -gt 0) {
        Write-Host "    ❌ 未部署: $($statusCounts.NotDeployed) 个" -ForegroundColor Red
    }
    if ($statusCounts.OutOfSync -gt 0) {
        Write-Host "    🔔 未同步: $($statusCounts.OutOfSync) 个" -ForegroundColor Yellow
    }
    if ($statusCounts.Error -gt 0) {
        Write-Host "    🔥 有问题: $($statusCounts.Error) 个" -ForegroundColor Red
    }
    Write-Host ""
}
#endregion

# 显示状态报告
Show-StatusReport
