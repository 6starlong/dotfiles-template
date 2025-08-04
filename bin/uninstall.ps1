# uninstall.ps1
# 智能移除 install.ps1 部署的配置文件
# 对于 Transform 方法：只移除 dotfiles 管理的字段，保留用户自定义配置
# 对于其他方法：直接删除文件

$ErrorActionPreference = 'Stop'
$script:DotfilesDir = Split-Path $PSScriptRoot -Parent

# 引入共享函数
. (Join-Path $PSScriptRoot "utils.ps1")

# 智能移除 JSON 字段
function Remove-JsonField {
    param(
        [string]$FilePath,
        [string]$TransformType,
        [string]$SourceFile
    )
    
    try {
        # 解析转换类型参数
        $parts = $TransformType -split ":"
        if ($parts.Length -ne 2) { 
            throw "无效的转换类型格式。预期格式为'format:platform'。" 
        }
        $format = $parts[0]
        $platform = $parts[1]

        # 获取配置并确定字段映射
        $config = Get-TransformConfig -Format $format
        $defaultField = $config.defaultField
        $platformField = if ($config.platforms.psobject.Properties[$platform]) { 
            $config.platforms.$platform 
        } else { 
            $config.defaultField 
        }

        if (-not $defaultField -or -not $platformField) { 
            throw "无法确定默认字段或平台字段。" 
        }

        # 读取源文件，获取所有源文件的字段名
        if (-not (Test-Path $SourceFile)) {
            throw "源文件未找到: $SourceFile"
        }
        $sourceContent = Get-Content $SourceFile -Raw -Encoding UTF8
        $sourceObject = ConvertFrom-Jsonc -Content $sourceContent
        $sourceFields = $sourceObject.psobject.Properties.Name

        # 读取目标文件
        if (-not (Test-Path $FilePath)) {
            Write-Warning "文件不存在: $FilePath"
            return $false
        }

        $content = Get-Content $FilePath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if (-not $content -or -not $content.Trim()) {
            Write-Warning "文件为空或无效: $FilePath"
            Remove-Item $FilePath -Force
            return $true
        }

        # 解析目标 JSON
        $jsonObject = ConvertFrom-Jsonc -Content $content
        if (-not $jsonObject) {
            Write-Warning "无法解析 JSON 文件: $FilePath"
            return $false
        }

        # 移除所有来自源文件的字段
        $fieldsRemoved = @()
        
        # 移除源文件中的所有字段
        foreach ($sourceField in $sourceFields) {
            if ($jsonObject.psobject.Properties[$sourceField]) {
                $jsonObject.psobject.Properties.Remove($sourceField)
                $fieldsRemoved += $sourceField
            }
        }
        
        # 如果平台字段与源文件字段不同，也需要移除平台字段
        if ($platformField -notin $sourceFields -and $jsonObject.psobject.Properties[$platformField]) {
            $jsonObject.psobject.Properties.Remove($platformField)
            $fieldsRemoved += $platformField
        }

        # 如果没有移除任何字段，说明文件中不包含 dotfiles 管理的内容
        if ($fieldsRemoved.Count -eq 0) {
            Write-Warning "文件中未找到 dotfiles 管理的字段: $FilePath"
            return $false
        }

        # 检查是否还有其他字段
        $hasProperties = $false
        foreach ($prop in $jsonObject.psobject.Properties) {
            $hasProperties = $true
            break
        }
        
        if (-not $hasProperties) {
            # 如果对象为空，删除文件
            Remove-Item $FilePath -Force
            return $true
        }

        # 生成格式化的 JSON 并写回文件
        $rawJson = $jsonObject | ConvertTo-Json -Depth 100 -Compress:$false
        $finalJson = Format-JsonClean -JsonString $rawJson -Indent 2
        Set-Content -Path $FilePath -Value ($finalJson + [System.Environment]::NewLine) -Encoding UTF8 -NoNewline

        return $true
    }
    catch {
        Write-Error "处理 JSON 文件失败 ($FilePath): $($_.Exception.Message)"
        return $false
    }
}

# 主执行逻辑
try {
    # 加载配置文件
    $configFile = Join-Path $script:DotfilesDir "config.psd1"
    if (-not (Test-Path $configFile)) {
        Write-Error "配置文件未找到: $configFile"
        return
    }
    $config = Import-PowerShellDataFile -Path $configFile

    Write-Host "    🗑️ 开始卸载 dotfiles 配置..." -ForegroundColor Yellow
    Write-Host ""

    $removedCount = 0
    $skippedCount = 0
    $partialCount = 0

    # 处理配置移除
    foreach ($link in $config.Links) {
        $targetPath = $link.Target -replace '\{USERPROFILE\}', $env:USERPROFILE
        $method = if ($link.Method) { $link.Method } else { $config.DefaultMethod }

        if (-not (Test-Path $targetPath)) {
            Write-Host "    ⏩ 跳过 ($($link.Comment)): 文件不存在" -ForegroundColor Cyan
            $skippedCount++
            continue
        }

        try {
            if ($method -eq "Transform" -and $link.MappingId) {
                # 智能移除 JSON 字段
                $sourcePath = Join-Path $script:DotfilesDir $link.Source
                $result = Remove-JsonField -FilePath $targetPath -TransformType $link.MappingId -SourceFile $sourcePath
                if ($result) {
                    if (Test-Path $targetPath) {
                        Write-Host "    🧹 已清理字段 ($($link.Comment)): $targetPath" -ForegroundColor Yellow
                        $partialCount++
                    } else {
                        Write-Host "    🔥 已移除 ($($link.Comment)): $targetPath" -ForegroundColor Green
                        $removedCount++
                    }
                } else {
                    Write-Host "    ⏩ 跳过 ($($link.Comment)): 未找到管理的字段" -ForegroundColor Cyan
                    $skippedCount++
                }
            } else {
                # 直接删除文件（SymLink 和 Copy 方法）
                Remove-Item $targetPath -Force -ErrorAction Stop
                Write-Host "    🔥 已移除 ($($link.Comment)): $targetPath" -ForegroundColor Green
                $removedCount++
            }
        } catch {
            Write-Host "    ❌ 处理失败 ($($link.Comment)): $($_.Exception.Message)" -ForegroundColor Red
            $skippedCount++
        }
    }

    Write-Host ""
    Write-Host "    ✅ 卸载完成！" -ForegroundColor Green
    
    $statusParts = @()
    if ($removedCount -gt 0) { $statusParts += "移除了 $removedCount 个文件" }
    if ($partialCount -gt 0) { $statusParts += "清理了 $partialCount 个配置字段" }
    if ($skippedCount -gt 0) { $statusParts += "跳过 $skippedCount 个" }
    
    Write-Host "    📊 $($statusParts -join '，')" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Error "卸载过程中发生错误: $($_.Exception.Message)"
    exit 1
}
