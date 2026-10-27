param([string]$PackageName = 'OPCServiceMonitor')

$ErrorActionPreference = 'Stop'

if ($PackageName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$') {
    throw '构建输出目录名称无效。'
}

$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$python = Join-Path $toolRoot '.venv\Scripts\python.exe'
$spec = Join-Path $toolRoot 'packaging\OPCServiceMonitor.spec'
$packageRoot = [IO.Path]::GetFullPath((Join-Path (Join-Path $toolRoot 'dist') $PackageName))
$executable = Join-Path $packageRoot 'OPCServiceMonitor.exe'
$packageBoundary = $packageRoot.TrimEnd('\') + '\'
$stagingRoot = Join-Path $toolRoot ('build\package-staging-' + [guid]::NewGuid().ToString('N'))
$stagedPackage = Join-Path $stagingRoot 'OPCServiceMonitor'

if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    throw '缺少 Tools/ServiceMonitor/.venv；请先按 README 安装锁定依赖。'
}

$runningMonitor = Get-CimInstance Win32_Process -Filter "Name = 'OPCServiceMonitor.exe'" |
    Where-Object { $_.ExecutablePath -eq $executable }
if ($runningMonitor) {
    throw '请先退出 OPCServiceMonitor，再构建更新包。'
}

Push-Location -LiteralPath $toolRoot
try {
    # Build separately: a service launched by an older frozen monitor may still
    # have an unchanged runtime DLL loaded from the destination package.
    & $python -m PyInstaller --noconfirm --clean --distpath $stagingRoot --workpath build $spec
    if ($LASTEXITCODE -ne 0) { throw 'PyInstaller 构建失败。' }
    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath $stagedPackage -Recurse -File) {
        $relative = $file.FullName.Substring($stagedPackage.TrimEnd('\').Length + 1)
        $destination = [IO.Path]::GetFullPath((Join-Path $packageRoot $relative))
        if (-not $destination.StartsWith($packageBoundary, [StringComparison]::OrdinalIgnoreCase)) {
            throw '构建文件超出指定程序目录。'
        }
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            $existingHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
            $stagedHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            if ($existingHash -eq $stagedHash) { continue }
        }
        $destinationParent = Split-Path -Parent $destination
        New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
        try {
            Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
        } catch {
            throw "无法更新 $relative；完整新包已保存在 $stagedPackage。$($_.Exception.Message)"
        }
    }
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw '构建结束但未找到 OPCServiceMonitor.exe。'
    }
    Write-Host "Windows onedir 已生成：$executable"
} finally {
    Pop-Location
}

