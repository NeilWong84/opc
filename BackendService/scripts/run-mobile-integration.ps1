# Run from any directory. Requires the marked durable integration PG and seed.
[CmdletBinding()]
param(
    [string]$Device = 'emulator-5554',
    [int]$Port = 8002,
    [string]$Target = 'integration_test/real_api_smoke_test.dart'
)
$ErrorActionPreference = 'Stop'
$backendRoot = Split-Path -Parent $PSScriptRoot
$appRoot = Join-Path (Split-Path -Parent $backendRoot) 'APPClient'
$pythonPath = Join-Path $backendRoot '.venv\Scripts\python.exe'
$definePath = Join-Path $backendRoot '.local\mobile-e2e.json'
$artifactRoot = Join-Path $appRoot 'test_artifacts\real-api'
New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null
if (Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue) {
    throw "Port $Port is already in use; choose a separate test port."
}
$previousMode = [Environment]::GetEnvironmentVariable('OPC_ASSIGNMENT_MODE', 'Process')
$service = $null
$ready = $false
$revokeFailed = $false
try {
    # Test only: record the synthetic already-confirmed relationship.
    $env:OPC_ASSIGNMENT_MODE = 'record_confirmed'
    $service = Start-Process -FilePath $pythonPath -ArgumentList '-m','uvicorn','app.main:app','--host','127.0.0.1','--port',"$Port" -WorkingDirectory $backendRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $artifactRoot 'backend-stdout.log') -RedirectStandardError (Join-Path $artifactRoot 'backend-stderr.log') -PassThru
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try {
            $status = Invoke-RestMethod "http://127.0.0.1:$Port/health/ready" -TimeoutSec 2
            if ($status.status -eq 'ready') { $ready = $true; break }
        } catch { Start-Sleep -Milliseconds 500 }
    }
    if (-not $ready) { throw 'Integration API did not become ready; see backend-stderr.log.' }
    & $pythonPath (Join-Path $PSScriptRoot 'prepare-mobile-e2e.py') prepare --base-url "http://127.0.0.1:$Port"
    if ($LASTEXITCODE -ne 0) { throw 'Test account preparation failed.' }
    & adb -s $Device reverse "tcp:$Port" "tcp:$Port"
    if ($LASTEXITCODE -ne 0) { throw 'ADB reverse failed; start/connect an Android device first.' }
    Push-Location -LiteralPath $appRoot
    try {
        & flutter drive --driver=test_driver/real_api.dart "--target=$Target" -d $Device "--dart-define-from-file=$definePath" 2>&1 | Tee-Object -FilePath (Join-Path $artifactRoot 'android-e2e.log')
        if ($LASTEXITCODE -ne 0) { throw 'Android integration test failed; see android-e2e.log.' }
        Copy-Item -LiteralPath (Join-Path $appRoot 'build\integration_response_data.json') -Destination (Join-Path $artifactRoot 'integration_response_data.json')
    } finally { Pop-Location }
} finally {
    if ($ready -and (Test-Path -LiteralPath $definePath)) {
        try {
            & $pythonPath (Join-Path $PSScriptRoot 'prepare-mobile-e2e.py') revoke --base-url "http://127.0.0.1:$Port"
            if ($LASTEXITCODE -ne 0) { $revokeFailed = $true }
        } catch { $revokeFailed = $true }
    }
    if ($null -ne $service) {
        # Windows venv python.exe starts the actual interpreter as its child.
        Get-CimInstance Win32_Process -Filter "ParentProcessId=$($service.Id)" -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
        Stop-Process -Id $service.Id -ErrorAction SilentlyContinue
    }
    if ($null -eq $previousMode) {
        Remove-Item Env:OPC_ASSIGNMENT_MODE -ErrorAction SilentlyContinue
    } else {
        $env:OPC_ASSIGNMENT_MODE = $previousMode
    }
    if ($revokeFailed) {
        throw 'Test session revocation failed. The test service was stopped; restart a service against the same local database and run prepare-mobile-e2e.py revoke before distributing any package.'
    }
}
Write-Host 'Android integration passed. Data remains in PostgreSQL. Rebuild lib/main.dart before delivering the ordinary APP.'
