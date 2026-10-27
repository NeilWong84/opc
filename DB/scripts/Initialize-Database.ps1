#requires -Version 5.1
<##
.SYNOPSIS
Creates or migrates the OPC-owned local development database.
.DESCRIPTION
Connects only to PostgreSQL at 127.0.0.1:5432 as postgres. An existing
database must carry the exact OPC marker; this script never adopts or drops
an unmarked database. Set PGPASSWORD in the current process, or enter a
password at the SecureString prompt. Passwords are never command arguments.
Each numbered migration is SHA-256 checked and committed independently.
.EXAMPLE
.\DB\scripts\Initialize-Database.ps1 -Verify
##>
[CmdletBinding()]
param(
    [ValidatePattern('^[a-z][a-z0-9_]{0,62}$')]
    [string]$DatabaseName = 'opc_dev',

    [string]$PsqlPath = 'C:\Program Files\PostgreSQL\18\bin\psql.exe',

    [switch]$Verify
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($DatabaseName -in @('postgres', 'template0', 'template1', 'accounts')) {
    throw 'System databases and Accounts are outside this script scope.'
}

$dbRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$bootstrapPath = Join-Path $dbRoot 'bootstrap.sql'
$migrationWrapperPath = Join-Path $dbRoot 'migrate.sql'
$migrationDirectory = Join-Path $dbRoot 'migrations'
$verificationPaths = @(
    (Join-Path $dbRoot 'tests\verify.sql'),
    (Join-Path $dbRoot 'tests\verify_metadata.sql')
)
$databaseMarker = 'opc.local-development.v1'

foreach ($requiredFile in @($PsqlPath, $bootstrapPath, $migrationWrapperPath)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required file does not exist: $requiredFile"
    }
}
if ($Verify) {
    foreach ($verificationPath in $verificationPaths) {
        if (-not (Test-Path -LiteralPath $verificationPath -PathType Leaf)) {
            throw "Verification script does not exist: $verificationPath"
        }
    }
}

$migrationFiles = @(Get-ChildItem -LiteralPath $migrationDirectory -Filter '*.sql' -File | Sort-Object Name)
if ($migrationFiles.Count -eq 0) {
    throw 'No SQL migrations found.'
}
for ($index = 0; $index -lt $migrationFiles.Count; $index++) {
    $migrationFile = $migrationFiles[$index]
    if ($migrationFile.Name -cnotmatch '^([0-9]{3})_[a-z][a-z0-9_]*\.sql$') {
        throw "Unexpected migration filename: $($migrationFile.Name)"
    }
    if ([int]$Matches[1] -ne ($index + 1)) {
        throw 'Migration numbers must start at 001 and be consecutive, without duplicates.'
    }
}

function Invoke-OpcPsql {
    param(
        [Parameter(Mandatory = $true)][string]$TargetDatabase,
        [Parameter(Mandatory = $true)][string]$SqlFile,
        [string[]]$Variables = @()
    )

    $psqlArguments = @(
        '-X', '-w', '--no-psqlrc', '--host=127.0.0.1', '--port=5432',
        '--username=postgres',
        "--dbname=host=127.0.0.1 hostaddr=127.0.0.1 port=5432 user=postgres dbname=$TargetDatabase",
        '--set=ON_ERROR_STOP=1',
        '--set=VERBOSITY=default', "--set=database_name=$DatabaseName",
        "--set=database_marker=$databaseMarker"
    )
    foreach ($variable in $Variables) {
        $psqlArguments += "--set=$variable"
    }
    $psqlArguments += "--file=$SqlFile"

    # File input avoids the Windows PowerShell 5.1 pipeline's legacy encoding.
    & $PsqlPath @psqlArguments
    if ($LASTEXITCODE -ne 0) {
        throw "psql failed with exit code $LASTEXITCODE while running $([IO.Path]::GetFileName($SqlFile))."
    }
}

$previousPassword = [Environment]::GetEnvironmentVariable('PGPASSWORD', 'Process')
$previousEncoding = [Environment]::GetEnvironmentVariable('PGCLIENTENCODING', 'Process')
$previousTimeout = [Environment]::GetEnvironmentVariable('PGCONNECT_TIMEOUT', 'Process')
$previousOptions = [Environment]::GetEnvironmentVariable('PGOPTIONS', 'Process')
$lockedMigrations = New-Object 'System.Collections.Generic.List[object]'
$passwordInput = $null

try {
    # Keep a shared-read lock from hashing until psql has finished. Writers and
    # renames cannot change the bytes whose checksum is entered in the ledger.
    foreach ($migrationFile in $migrationFiles) {
        $migrationStream = [IO.File]::Open($migrationFile.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $entry = [PSCustomObject]@{
            Version = $migrationFile.BaseName
            File = $migrationFile.FullName.Replace('\', '/')
            Stream = $migrationStream
            Checksum = $null
        }
        $lockedMigrations.Add($entry)
        $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
        $reader = New-Object System.IO.StreamReader($migrationStream, $strictUtf8, $false, 4096, $true)
        try {
            $null = $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
        $migrationStream.Position = 0
        $sha256 = [Security.Cryptography.SHA256]::Create()
        try {
            $entry.Checksum = ([BitConverter]::ToString($sha256.ComputeHash($migrationStream))).Replace('-', '').ToLowerInvariant()
        }
        finally {
            $sha256.Dispose()
        }
    }

    if ([string]::IsNullOrEmpty($previousPassword)) {
        $passwordInput = Read-Host 'Password for local PostgreSQL user postgres' -AsSecureString
        $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($passwordInput)
        try {
            $env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
        }
        if ([string]::IsNullOrEmpty($env:PGPASSWORD)) {
            throw 'A non-empty password is required through PGPASSWORD or the secure prompt.'
        }
    }

    $env:PGCLIENTENCODING = 'UTF8'
    $env:PGCONNECT_TIMEOUT = '10'
    # Override inherited session options; this does not alter server settings.
    $env:PGOPTIONS = '-c search_path=pg_catalog -c timezone=UTC'

    Write-Host "Checking OPC database $DatabaseName at 127.0.0.1:5432."
    Invoke-OpcPsql -TargetDatabase 'postgres' -SqlFile $bootstrapPath

    $migrationManifest = ($lockedMigrations | ForEach-Object { $_.Version }) -join ','
    # Check all existing hashes before applying any new migration. The wrapper
    # repeats these checks under its transaction lock when applying each file.
    foreach ($checkOnly in @('true', 'false')) {
        foreach ($entry in $lockedMigrations) {
            $variables = @(
                "migration_version=$($entry.Version)",
                "migration_checksum=$($entry.Checksum)",
                "migration_file=$($entry.File)",
                "migration_manifest=$migrationManifest",
                "check_only=$checkOnly"
            )
            Invoke-OpcPsql -TargetDatabase $DatabaseName -SqlFile $migrationWrapperPath -Variables $variables
        }
    }

    if ($Verify) {
        Write-Host 'Running rollback-only database verification.'
        foreach ($verificationPath in $verificationPaths) {
            Invoke-OpcPsql -TargetDatabase $DatabaseName -SqlFile $verificationPath
        }
    }
    Write-Host "OPC database $DatabaseName is initialized. Applied migrations are unchanged on repeat runs."
}
finally {
    foreach ($entry in $lockedMigrations) {
        $entry.Stream.Dispose()
    }
    if ($null -ne $passwordInput) {
        $passwordInput.Dispose()
    }
    $originalEnvironment = @{
        PGPASSWORD = $previousPassword
        PGCLIENTENCODING = $previousEncoding
        PGCONNECT_TIMEOUT = $previousTimeout
        PGOPTIONS = $previousOptions
    }
    foreach ($variableName in $originalEnvironment.Keys) {
        # PowerShell's string conversion can turn a null method argument into
        # an empty environment value. libpq rejects an empty connect_timeout.
        # Remove originally absent variables through the environment provider.
        if ($null -eq $originalEnvironment[$variableName]) {
            Remove-Item -LiteralPath "Env:$variableName" -ErrorAction SilentlyContinue
        }
        else {
            [Environment]::SetEnvironmentVariable($variableName, $originalEnvironment[$variableName], 'Process')
        }
    }
}
