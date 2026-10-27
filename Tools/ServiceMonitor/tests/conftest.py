from __future__ import annotations

import os
from pathlib import Path

import pytest


os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")


@pytest.fixture
def opc_root(tmp_path: Path) -> Path:
    root = tmp_path / "OPC"
    (root / "BackendService" / "scripts").mkdir(parents=True)
    (root / "BackendService" / ".venv" / "Scripts").mkdir(parents=True)
    (root / "BackendService" / ".local" / "integration").mkdir(parents=True)
    (root / "FrontendAdmin").mkdir()
    (root / "DB").mkdir()
    (root / "README.md").write_text("# OPC\n", encoding="utf-8")
    (root / "BackendService" / "scripts" / "start.ps1").write_text("", encoding="utf-8")
    (root / "BackendService" / "scripts" / "provision-local-integration.py").write_text("", encoding="utf-8")
    (root / "BackendService" / ".venv" / "Scripts" / "python.exe").write_bytes(b"")
    (root / "FrontendAdmin" / "package.json").write_text("{}\n", encoding="utf-8")
    (root / "DB" / "README.md").write_text("# DB\n", encoding="utf-8")
    return root

