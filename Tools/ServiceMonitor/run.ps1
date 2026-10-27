$ErrorActionPreference = 'Stop'

$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$python = Join-Path $toolRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    throw '缺少 Tools/ServiceMonitor/.venv；请先按 README 安装锁定依赖。'
}

Push-Location -LiteralPath $toolRoot
try {
    & $python -m opc_service_monitor @args
    exit $LASTEXITCODE
} finally {
    Pop-Location
}

