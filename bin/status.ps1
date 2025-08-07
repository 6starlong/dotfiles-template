# status.ps1
# 检查 dotfiles 配置的部署状态

$dotfilesDir = Split-Path $PSScriptRoot -Parent

# 导入工具模块
Import-Module (Join-Path $PSScriptRoot "utils.psm1") -Force

# 加载配置文件和共享函数
Import-Module (Join-Path $PSScriptRoot "utils.psm1")
$configFile = Join-Path $dotfilesDir "config.psd1"
if (-not (Test-Path $configFile)) {
    Write-Error "配置文件未找到: $configFile"
    return
}
$config = Import-PowerShellDataFile -Path $configFile

Write-Host ""
Write-Host "    ================================================================" -ForegroundColor Green
Write-Host "                        配置状态检查" -ForegroundColor Green
Write-Host "    ================================================================" -ForegroundColor Green
Write-Host ""

# 计算最长的配置名称长度，用于动态对齐
$maxCommentLength = ($config.Links | ForEach-Object { $_.Comment.Length } | Measure-Object -Maximum).Maximum
$commentPadding = [Math]::Max($maxCommentLength + 2, 35)  # 至少35个字符，或者最长名称+2

foreach ($link in $config.Links) {
    $targetPath = Resolve-ConfigPath -Path $link.Target -DotfilesDir $dotfilesDir
    
    # 构建源文件路径
    $sourcePath = Join-Path $dotfilesDir $link.Source
    
    # 获取部署方法
    $method = if ($link.Method) { $link.Method } else { $config.DefaultMethod }
    if (-not $method) { $method = "SymLink" }
    
    # 使用动态计算的填充长度确保对齐
    $configName = $link.Comment.PadRight($commentPadding)
    $methodTag = "[$method]".PadRight(13)
    
    if (-not (Test-Path $targetPath)) {
        Write-Host "    ❌ $configName $methodTag 未部署" -ForegroundColor Red
    } elseif (-not (Test-Path $sourcePath)) {
        Write-Host "    ⚠️ $configName $methodTag 源文件缺失" -ForegroundColor Yellow
    } else {
        $item = Get-Item $targetPath -Force
        
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            # 是符号链接
            $target = $item.Target
            if ($target -and $target[0] -eq $sourcePath) {
                Write-Host "    ✅ $configName $methodTag 已同步" -ForegroundColor Green
            } elseif ($target) {
                Write-Host "    ⚠️ $configName $methodTag 链接错误" -ForegroundColor Yellow
            } else {
                Write-Host "    ❌ $configName $methodTag 链接损坏" -ForegroundColor Red
            }
        } else {
            # 是普通文件
            if ($method -eq "Copy") {
                # 使用文件内容比较函数
                if (Test-FileContentEqual -File1 $sourcePath -File2 $targetPath) {
                    Write-Host "    ✅ $configName $methodTag 已同步" -ForegroundColor Cyan
                } else {
                    Write-Host "    ⚠️ $configName $methodTag 未同步" -ForegroundColor Yellow
                }
            } elseif ($method -eq "Transform") {
                try {
                    # 对于Transform方法，需要比较转换后的内容
                    if (-not $link.MappingId) {
                        Write-Host "    ❌ $configName $methodTag MappingId参数缺失" -ForegroundColor Red
                        continue
                    }
                    
                    # 创建临时文件进行转换比较
                    $tempFile = [System.IO.Path]::GetTempFileName()
                    try {
                        $transformScript = Join-Path $PSScriptRoot "transform.ps1"
                        if (-not (Test-Path $transformScript)) {
                            Write-Host "    ❌ $configName $methodTag 转换脚本未找到" -ForegroundColor Red
                            continue
                        }
                        
                        # 转换基础配置到临时文件
                        & $transformScript -SourceFile $sourcePath -TargetFile $tempFile -TransformType $link.MappingId -ErrorAction Stop | Out-Null
                        
                        # 使用JSON语义比较函数
                        if (Test-JsonContentEqual -File1 $tempFile -File2 $targetPath) {
                            Write-Host "    ✅ $configName $methodTag 已同步" -ForegroundColor Cyan
                        } else {
                            Write-Host "    ⚠️ $configName $methodTag 未同步" -ForegroundColor Yellow
                        }
                    } finally {
                        if (Test-Path $tempFile) {
                            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                        }
                    }
                } catch {
                    Write-Host "    ❌ $configName $methodTag 检查失败: $($_.Exception.Message)" -ForegroundColor Red
                }
            } else {
                Write-Host "    ⚠️ $configName $methodTag 应为链接" -ForegroundColor Yellow
            }
        }
    }
}

Write-Host ""
