param([ValidateSet('Server','Admin')][string]$Kind='Server')
$ErrorActionPreference='Stop'
$taskRoot=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$taskLocal=Join-Path $taskRoot '.local/deployment'
Add-Type -AssemblyName System.Security
function Convert-HexBytes([string]$Value) {
    [byte[]]$taskResult=for($taskIndex=0;$taskIndex -lt $Value.Length;$taskIndex+=2) {
        [Convert]::ToByte($Value.Substring($taskIndex,2),16)
    }
    return ,$taskResult
}
if($Kind -eq 'Server') {
    $taskRecord=Get-Content -Raw -LiteralPath (Join-Path $taskLocal 'server-credentials.json') | ConvertFrom-Json
    $taskBytes=Convert-HexBytes $taskRecord.password_dpapi
    $taskScope=if($taskRecord.encryption_scope -eq 'LocalMachine'){[Security.Cryptography.DataProtectionScope]::LocalMachine}else{[Security.Cryptography.DataProtectionScope]::CurrentUser}
    $taskPlain=[Security.Cryptography.ProtectedData]::Unprotect($taskBytes,$null,$taskScope)
    $taskPassword=ConvertTo-SecureString ([Text.Encoding]::Unicode.GetString($taskPlain)) -AsPlainText -Force
    [PSCredential]::new($taskRecord.user,$taskPassword)
    [Array]::Clear($taskPlain,0,$taskPlain.Length)
} else {
    $taskRecord=Get-Content -Raw -LiteralPath (Join-Path $taskLocal 'admin-credentials.json') | ConvertFrom-Json
    $taskBytes=Convert-HexBytes $taskRecord.payload_dpapi
    $taskScope=if($taskRecord.encryption_scope -eq 'LocalMachine'){[Security.Cryptography.DataProtectionScope]::LocalMachine}else{[Security.Cryptography.DataProtectionScope]::CurrentUser}
    $taskPlain=[Security.Cryptography.ProtectedData]::Unprotect($taskBytes,$null,$taskScope)
    $taskValue=[Text.Encoding]::UTF8.GetString($taskPlain) | ConvertFrom-Json
    $taskPassword=ConvertTo-SecureString $taskValue.password -AsPlainText -Force
    [PSCredential]::new($taskValue.email,$taskPassword)
    [Array]::Clear($taskPlain,0,$taskPlain.Length)
    $taskValue=$null
}
