# install.ps1
# 根据 config.psd1 配置文件安装 dotfiles
# 需要管理员权限来创建符号链接

param(
    [string]$LogFile,
    [switch]$Overwrite
)

$dotfilesDir = Split-Path $PSScriptRoot -Parent
$ErrorActionPreference = 'Stop'

# 检查管理员权限
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 输出函数：同时支持控制台显示和文件记录
function Write-InstallResult {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    
    # 显示到控制台
    if ($Message -eq "") {
        Write-Host ""
    } else {
        Write-Host "    $Message" -ForegroundColor $Color
    }
    
    # 写入日志文件（仅提权模式）
    if ($LogFile) {
        try {
            if ($Message -eq "") {
                "" | Out-File -FilePath $LogFile -Append -Encoding UTF8 -ErrorAction Stop
            } else {
                "$Color|$Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8 -ErrorAction Stop
            }
        } catch {
            Write-Host "    [警告] 写入日志文件失败: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# 非管理员模式：自动提权并显示结果
if (-not (Test-Administrator)) {
    Write-Host "    ⚠️ 需要管理员权限创建符号链接" -ForegroundColor Yellow
    Write-Host "    🔄 正在自动提权..." -ForegroundColor Cyan
    
    try {
        # 加载配置以获取项目前缀
        $configFile = Join-Path $dotfilesDir "config.psd1"
        $projectPrefix = "dotfiles" # 默认值
        $config = Import-PowerShellDataFile -Path $configFile
        if ($config.ProjectSettings -and $config.ProjectSettings.ProjectPrefix) {
            $projectPrefix = $config.ProjectSettings.ProjectPrefix
        }

        # 创建临时日志文件
        $logFile = Join-Path $env:TEMP "$($projectPrefix)_install_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        
        # 启动提权进程
        $argumentList = @(
            "-NoProfile", "-ExecutionPolicy", "Bypass"
            "-File", "`"$($MyInvocation.MyCommand.Path)`""
            "-LogFile", "`"$logFile`""
        )
        if ($Overwrite) {
            $argumentList += "-Overwrite"
        }
        $process = Start-Process "PowerShell" -ArgumentList $argumentList -Verb RunAs -WindowStyle Hidden -PassThru
        $process.WaitForExit()
        
        # 等待并读取结果
        $maxWait = 10
        $waited = 0
        while (-not (Test-Path $logFile) -and $waited -lt $maxWait) {
            Start-Sleep -Milliseconds 500
            $waited += 0.5
        }
        
        if (Test-Path $logFile) {
            $results = Get-Content $logFile -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($results -and $results.Count -gt 0) {
                foreach ($result in $results) {
                    if ($result -eq "") {
                        Write-Host ""
                    } elseif ($result -match "^([^|]+)\|(.+)$") {
                        $color = $matches[1]
                        $message = $matches[2]
                        Write-Host "    $message" -ForegroundColor $color
                    } else {
                        Write-Host "    $result" -ForegroundColor White
                    }
                }
            } else {
                Write-Host "    ⚠️ 安装过程未生成输出，请检查是否成功" -ForegroundColor Yellow
            }
            Remove-Item $logFile -Force -ErrorAction SilentlyContinue
        } else {
            Write-Host "    ❌ 安装过程中出现问题，未生成日志文件" -ForegroundColor Red
            Write-Host "    请手动以管理员身份运行: .\bin\install.ps1" -ForegroundColor Yellow
        }
        
        Write-Host ""
        return
    } catch {
        Write-Host "    ❌ 自动提权失败：$($_.Exception.Message)" -ForegroundColor Red
        Write-Host "    请手动以管理员身份运行：.\bin\install.ps1" -ForegroundColor Yellow
        Write-Host ""
        return
    }
}

# 加载配置文件
$configFile = Join-Path $dotfilesDir "config.psd1"
if (-not (Test-Path $configFile)) {
    Write-Error "配置文件未找到: $configFile"
    return
}
$config = Import-PowerShellDataFile -Path $configFile

Write-InstallResult ""
Write-InstallResult "🚀 开始安装 dotfiles..." "Yellow"
Write-InstallResult ""

# 创建备份
Write-InstallResult "📦 正在创建现有配置的备份..." "Cyan"
$backupScript = Join-Path $PSScriptRoot "backup.ps1"
if (Test-Path $backupScript) {
    try {
        $backupOutput = & $backupScript 2>&1
        if ($LASTEXITCODE -eq 0 -or $? -eq $true) {
            Write-InstallResult "✅ 备份完成" "Green"
        } else {
            Write-InstallResult "⚠️ 备份失败，但继续安装" "Yellow"
        }
    } catch {
        Write-InstallResult "⚠️ 备份失败，但继续安装: $($_.Exception.Message)" "Yellow"
    }
}

Write-InstallResult ""
Write-InstallResult "🔗 正在安装 dotfiles 配置..." "Cyan"
Write-InstallResult ""

# 处理配置链接
$successCount = 0
$failureCount = 0

foreach ($link in $config.Links) {
    $sourcePath = Join-Path $dotfilesDir $link.Source
    $targetPath = $link.Target -replace '\{USERPROFILE\}', $env:USERPROFILE

    if (-not (Test-Path $sourcePath)) {
        Write-InstallResult "⚠️ 跳过: 源文件未找到 '$sourcePath'" "Yellow"
        continue
    }

    # 创建目标目录
    $targetDir = Split-Path -Path $targetPath -Parent
    if (-not (Test-Path $targetDir)) {
        Write-InstallResult "📁 创建目标目录: $targetDir" "Gray"
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    # 确定部署方法
    $method = if ($link.Method) { $link.Method } else { $config.DefaultMethod }
    if (-not $method) { $method = "SymLink" }

    try {
        switch ($method) {
            "Copy" {
                Copy-Item -Path $sourcePath -Destination $targetPath -Force -ErrorAction Stop
                Write-InstallResult "✅ 已复制 $($link.Comment)" "Green"
            }
            "Transform" {
                if (-not $link.MappingId) {
                    Write-InstallResult "❌ Transform配置缺少MappingId参数: $($link.Comment)" "Red"
                    $failureCount++
                    continue
                }
                
                $transformScript = Join-Path $PSScriptRoot "transform.ps1"
                if (-not (Test-Path $transformScript)) {
                    Write-InstallResult "❌ 转换脚本未找到: $transformScript" "Red"
                    $failureCount++
                    continue
                }

                if ($Overwrite) {
                    # 强制覆盖模式：先转换到临时文件，再覆盖目标
                    $tempFile = [System.IO.Path]::GetTempFileName()
                    try {
                        & $transformScript -SourceFile $sourcePath -TargetFile $tempFile -TransformType $link.MappingId -ErrorAction Stop | Out-Null
                        Copy-Item $tempFile $targetPath -Force
                        Write-InstallResult "✅ 已覆盖 $($link.Comment)" "Green"
                    } finally {
                        if (Test-Path $tempFile) {
                            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                        }
                    }
                } else {
                    # 目标文件不存在，直接转换
                    & $transformScript -SourceFile $sourcePath -TargetFile $targetPath -TransformType $link.MappingId -ErrorAction Stop | Out-Null
                    Write-InstallResult "✅ 已转换 $($link.Comment)" "Green"
                }
            }
            default {
                New-Item -ItemType SymbolicLink -Path $targetPath -Target $sourcePath -Force -ErrorAction Stop | Out-Null
                Write-InstallResult "✅ 已链接 $($link.Comment)" "Green"
            }
        }
        $successCount++
    } catch {
        Write-InstallResult "❌ 部署失败 $($link.Comment): $($_.Exception.Message)" "Red"
        if ($method -eq "SymLink") {
            Write-InstallResult "💡 提示: 创建符号链接需要管理员权限" "Yellow"
        }
        $failureCount++
    }
}

# 显示结果
Write-InstallResult ""
if ($failureCount -eq 0) {
    Write-InstallResult "✨ Dotfiles 安装完成！" "Green"
} elseif ($successCount -gt 0) {
    Write-InstallResult "⚠️ Dotfiles 安装部分完成（$successCount 成功，$failureCount 失败）" "Yellow"
} else {
    Write-InstallResult "❌ Dotfiles 安装失败！" "Red"
}
Write-InstallResult "📊 处理了 $($successCount + $failureCount) 个配置项" "Green"
Write-host ""