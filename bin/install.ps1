# install.ps1
# 根据 config.psd1 配置文件安装 dotfiles
# 需要管理员权限来创建符号链接

$dotfilesDir = Split-Path $PSScriptRoot -Parent

# 检查管理员权限
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host ""
    Write-Host "    ❌ 此脚本需要管理员权限才能创建符号链接" -ForegroundColor Red
    Write-Host ""
    Write-Host "    请复制以下命令并执行，它会在当前目录打开管理员权限的 PowerShell 窗口：" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    Start-Process PowerShell -ArgumentList '-NoExit -Command Set-Location `"$PWD`"' -Verb RunAs" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    然后在新窗口中执行：.\bin\install.ps1" -ForegroundColor Green
    Write-Host ""
    return
}

# 加载配置文件
$configFile = Join-Path $dotfilesDir "config.psd1"
if (-not (Test-Path $configFile)) {
    Write-Error "配置文件未找到: $configFile"
    return
}
$config = Import-PowerShellDataFile -Path $configFile

Write-Host "    🚀 开始安装 dotfiles..." -ForegroundColor Yellow
Write-Host ""

# 安装前创建备份
Write-Host "    📦 正在创建现有配置的备份..." -ForegroundColor Cyan
$backupScript = Join-Path $PSScriptRoot "backup.ps1"
if (Test-Path $backupScript) {
    try {
        & $backupScript
        Write-Host "    ✅ 备份完成" -ForegroundColor Green
    } catch {
        Write-Host "    ⚠️  备份失败，但继续安装: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "    ⚠️  未找到备份脚本，跳过备份" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "    🔗 正在安装 dotfiles 配置..." -ForegroundColor Cyan
Write-Host ""

# 处理配置链接
foreach ($link in $config.Links) {
    $sourcePath = Join-Path $dotfilesDir $link.Source
    $targetPath = $link.Target -replace '\{USERPROFILE\}', $env:USERPROFILE

    if (-not (Test-Path $sourcePath)) {
        Write-Host "    ⚠️  跳过: 源文件未找到 '$sourcePath'" -ForegroundColor Yellow
        continue
    }

    $targetDir = Split-Path -Path $targetPath -Parent
    if (-not (Test-Path $targetDir)) {
        Write-Host "    📁 正在创建目标目录: $targetDir" -ForegroundColor Gray
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    # 确定部署方法
    $method = if ($link.Method) { $link.Method } else { $config.DefaultMethod }
    if (-not $method) { $method = "SymLink" }

    try {
        if ($method -eq "Copy") {
            Copy-Item -Path $sourcePath -Destination $targetPath -Force -ErrorAction Stop
            Write-Host "    ✅ 已复制 ($($link.Comment)): $sourcePath -> $targetPath" -ForegroundColor Green
        } elseif ($method -eq "Transform") {
            # 使用转换脚本处理
            if (-not $link.Transform) {
                Write-Host "    ❌ Transform配置缺少Transform参数: $($link.Comment)" -ForegroundColor Red
                continue
            }
            
            $transformScript = Join-Path $PSScriptRoot "transform.ps1"
            if (-not (Test-Path $transformScript)) {
                Write-Host "    ❌ 转换脚本未找到: $transformScript" -ForegroundColor Red
                continue
            }
            
            & $transformScript -SourceFile $sourcePath -TargetFile $targetPath -TransformType $link.Transform -ErrorAction Stop
            Write-Host "    ✅ 已转换 ($($link.Comment)): $sourcePath -> $targetPath" -ForegroundColor Green
        } else {
            New-Item -ItemType SymbolicLink -Path $targetPath -Target $sourcePath -Force -ErrorAction Stop | Out-Null
            Write-Host "    ✅ 已链接 ($($link.Comment)): $targetPath -> $sourcePath" -ForegroundColor Green
        }
    } catch {
        Write-Host "    ❌ 部署失败 $($link.Comment)，方法 '$method'。错误: $($_.Exception.Message)" -ForegroundColor Red
        if ($method -eq "SymLink") {
            Write-Host "    💡 提示: 创建符号链接需要管理员权限" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "    ✨ Dotfiles 安装完成！" -ForegroundColor Green
Write-Host ""