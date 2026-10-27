"""The launch script must parse without running the API or loading local credentials."""

import base64
import json
from pathlib import Path
import shutil
import subprocess
import sys

import pytest


@pytest.mark.skipif(sys.platform != "win32", reason="Windows PowerShell launcher compatibility")
@pytest.mark.parametrize("host", ["powershell.exe", "pwsh.exe"])
def test_start_script_preserves_unicode_literals_in_both_powershell_hosts(host):
    executable = shutil.which(host)
    if executable is None:
        pytest.skip(f"{host} is not installed")
    path = Path(__file__).resolve().parents[1] / "scripts" / "start.ps1"
    # ParseFile uses the host's actual file-encoding rules; ParseInput with Python's
    # already decoded text would hide the Windows PowerShell 5.1 ANSI fallback.
    script = """
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            '%s', [ref]$tokens, [ref]$parseErrors)
        $literals = @($ast.FindAll({param($node)
            $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
        }, $true) | ForEach-Object { $_.Value })
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
        [pscustomobject]@{
            Errors = @($parseErrors | ForEach-Object { $_.ErrorId })
            Literals = $literals
        } | ConvertTo-Json -Compress
    """ % str(path).replace("'", "''")
    command = base64.b64encode(script.encode("utf-16-le")).decode("ascii")
    result = subprocess.run(
        [executable, "-NoProfile", "-NonInteractive", "-EncodedCommand", command],
        capture_output=True,
        timeout=15,
        check=True,
    )
    parsed = json.loads(result.stdout.decode("utf-8-sig"))
    assert parsed["Errors"] == []
    assert "请先按 README 创建 .venv 并安装 requirements.lock.txt。" in parsed["Literals"]
    assert "后端启动失败。" in parsed["Literals"]
