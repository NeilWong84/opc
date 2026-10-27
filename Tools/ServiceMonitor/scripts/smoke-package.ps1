param(
    [string]$ProjectRoot = 'D:\OPC',
    [string]$Executable
)

$ErrorActionPreference = 'Stop'
$toolRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $Executable) {
    $Executable = Join-Path $toolRoot 'dist\OPCServiceMonitor\OPCServiceMonitor.exe'
}
$resolvedExecutable = (Resolve-Path -LiteralPath $Executable).Path
$resolvedProject = (Resolve-Path -LiteralPath $ProjectRoot).Path
$packageRoot = Split-Path -Parent $resolvedExecutable
$platformPlugin = Join-Path $packageRoot '_internal\PySide6\plugins\platforms\qwindows.dll'
if (-not (Test-Path -LiteralPath $platformPlugin -PathType Leaf)) {
    throw "打包目录缺少 Qt Windows 平台插件: $platformPlugin"
}
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$smokeRoot = Join-Path $tempBase ("opc-service-monitor-smoke-" + [guid]::NewGuid().ToString('N'))
$resolvedSmokeRoot = [IO.Path]::GetFullPath($smokeRoot)
if (-not $resolvedSmokeRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
    throw '冒烟目录未落在系统临时目录内。'
}
New-Item -ItemType Directory -Path $resolvedSmokeRoot | Out-Null
$report = Join-Path $resolvedSmokeRoot 'report.json'

try {
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $resolvedExecutable
    $startInfo.WorkingDirectory = $resolvedSmokeRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    [void]$startInfo.ArgumentList.Add('--smoke-test')
    [void]$startInfo.ArgumentList.Add('--report')
    [void]$startInfo.ArgumentList.Add($report)
    [void]$startInfo.ArgumentList.Add('--project-root')
    [void]$startInfo.ArgumentList.Add($resolvedProject)
    [void]$startInfo.Environment.Remove('QT_QPA_PLATFORM')
    [void]$startInfo.Environment.Remove('QT_PLUGIN_PATH')
    $process = [Diagnostics.Process]::Start($startInfo)
    if (-not $process.WaitForExit(30000)) {
        $process.Kill($true)
        throw '打包程序冒烟检查超过 30 秒。'
    }
    if ($process.ExitCode -ne 0) {
        throw "打包程序冒烟检查失败，退出码 $($process.ExitCode)。"
    }
    if (-not (Test-Path -LiteralPath $report -PathType Leaf)) {
        throw '打包程序未生成冒烟报告。'
    }
    $payload = Get-Content -LiteralPath $report -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $payload.ok) { throw '打包程序报告界面初始化失败。' }
    if (-not $payload.resources.theme) { throw '打包程序未加载主题资源。' }
    if (-not $payload.external_processes.system_dll_search) { throw '打包程序未恢复外部服务的系统 DLL 搜索路径。' }
    if ($payload.ui.service_cards -ne 3) { throw '打包程序服务卡数量不正确。' }
    if (-not $payload.ui.log_details) { throw '打包程序日志详情窗口检查失败。' }
    if (-not $payload.ui.power_controls) { throw '打包程序启停开关状态检查失败。' }
    if ((Compare-Object -ReferenceObject @('light', 'dark') -DifferenceObject @($payload.ui.themes) -SyncWindow 0)) {
        throw '打包程序未成功切换明亮和暗黑主题。'
    }
    $expectedTabs = @('全部日志', '前端', '后端', 'PostgreSQL', '业务审计')
    if ((Compare-Object -ReferenceObject $expectedTabs -DifferenceObject @($payload.ui.tabs) -SyncWindow 0)) {
        throw '打包程序日志 Tab 与固定契约不一致。'
    }
    if ($payload.qt.platform_plugin -ne 'windows') { throw '打包程序未使用 Qt Windows 平台插件。' }
    Get-Content -LiteralPath $report -Raw -Encoding UTF8
} finally {
    if (Test-Path -LiteralPath $resolvedSmokeRoot) {
        Remove-Item -LiteralPath $resolvedSmokeRoot -Recurse -Force
    }
}

