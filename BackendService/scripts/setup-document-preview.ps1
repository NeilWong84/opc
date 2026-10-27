[CmdletBinding()]
param([string]$InstallerPath = '')
$ErrorActionPreference = 'Stop'
$backendRoot = Split-Path -Parent $PSScriptRoot
$toolsRoot = Join-Path $backendRoot '.local\preview-tools'
$target = Join-Path $toolsRoot 'LibreOffice'
$binary = Join-Path $target 'program\soffice.com'
if (Test-Path -LiteralPath $binary) {
    & $binary --version
    exit $LASTEXITCODE
}
New-Item -ItemType Directory -Path $toolsRoot -Force | Out-Null
$version = '26.8.1'
$expectedHash = 'c6298b10cfa1748bcbedad94c62ce771e240e5021bfd6d7a967cd571b04b5312'
if (-not $InstallerPath) {
    $InstallerPath = Join-Path $toolsRoot "LibreOffice_${version}_Win_x86-64.msi"
    if (-not (Test-Path -LiteralPath $InstallerPath)) {
        Invoke-WebRequest -Uri "https://download.documentfoundation.org/libreoffice/stable/$version/win/x86_64/LibreOffice_${version}_Win_x86-64.msi" -OutFile $InstallerPath
    }
}
$installer = (Resolve-Path -LiteralPath $InstallerPath).Path
if ((Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedHash) {
    throw 'LibreOffice installer SHA256 does not match the official release.'
}
$log = Join-Path $toolsRoot 'extract.log'
# /a 只建立工作区内的管理映像，不安装系统文件关联。
$arguments = "/a `"$installer`" /qn TARGETDIR=`"$target`" /L*v `"$log`""
$operation = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
if ($operation.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $binary)) {
    throw "Document preview extraction failed. See $log"
}
& $binary --version
exit $LASTEXITCODE
