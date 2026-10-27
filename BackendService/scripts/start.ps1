param([int]$Port = 8000)
$ErrorActionPreference = 'Stop'
$backendRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $backendRoot
try {
    $pythonPath = Join-Path $backendRoot '.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $pythonPath)) { throw '请先按 README 创建 .venv 并安装 requirements.lock.txt。' }
    & $pythonPath -m uvicorn app.main:app --host 127.0.0.1 --port $Port
    if ($LASTEXITCODE -ne 0) { throw '后端启动失败。' }
} finally { Pop-Location }
