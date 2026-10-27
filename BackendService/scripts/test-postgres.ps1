[CmdletBinding()]
param(
    [string]$PostgresBin = 'C:\Program Files\PostgreSQL\18\bin',
    [int]$Port = 55439,
    [switch]$KeepCluster,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$PytestArgs
)
$ErrorActionPreference = 'Stop'
$backendRoot = Split-Path -Parent $PSScriptRoot
$pythonPath = Join-Path $backendRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $pythonPath)) {
    throw 'BackendService/.venv is missing. Follow BackendService/README.md to install dependencies first.'
}
$testScript = Join-Path $PSScriptRoot 'test_database.py'
$arguments = @($testScript, '--postgres-bin', $PostgresBin, '--port', [string]$Port)
if ($KeepCluster) { $arguments += '--keep-cluster' }
if ($PytestArgs) { $arguments += '--'; $arguments += $PytestArgs }
& $pythonPath @arguments
exit $LASTEXITCODE
