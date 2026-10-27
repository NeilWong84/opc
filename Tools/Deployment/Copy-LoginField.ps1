param(
    [ValidateSet('Server','Admin')][string]$Kind='Admin',
    [ValidateSet('UserName','Password')][string]$Field='UserName'
)
$ErrorActionPreference='Stop'
$taskCredential=& (Join-Path $PSScriptRoot 'Get-Credential.ps1') -Kind $Kind
if($Field -eq 'Password') {
    Set-Clipboard -Value $taskCredential.GetNetworkCredential().Password
} else {
    Set-Clipboard -Value $taskCredential.UserName
}
Write-Output '选定登录字段已复制到本机剪贴板，未在终端显示内容。'
