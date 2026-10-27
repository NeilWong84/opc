from __future__ import annotations

import ctypes
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

import pytest

from opc_service_monitor import frozen_runtime, postgres, processes
from opc_service_monitor.models import CommandSpec
from opc_service_monitor.processes import ProcessIdentity, SubprocessProcessAdapter


@pytest.mark.parametrize(
    ("platform", "frozen"), [("win32", False), ("linux", True), ("darwin", True)]
)
def test_unfrozen_or_nonwindows_runtime_never_changes_dll_lookup(monkeypatch, platform, frozen):
    monkeypatch.setattr(frozen_runtime, "sys", SimpleNamespace(platform=platform, frozen=frozen))
    win_api = Mock(side_effect=AssertionError("Win32 API must not be loaded"))
    monkeypatch.setattr(ctypes, "WinDLL", win_api, raising=False)

    assert frozen_runtime.configure_external_process_runtime() is False
    win_api.assert_not_called()


def test_frozen_windows_runtime_restores_default_dll_lookup(monkeypatch):
    monkeypatch.setattr(frozen_runtime, "sys", SimpleNamespace(platform="win32", frozen=True))
    reset = Mock(return_value=1)
    win_api = Mock(return_value=SimpleNamespace(SetDllDirectoryW=reset))
    monkeypatch.setattr(ctypes, "WinDLL", win_api, raising=False)

    assert frozen_runtime.configure_external_process_runtime() is True
    win_api.assert_called_once_with("kernel32", use_last_error=True)
    reset.assert_called_once_with(None)
    assert reset.argtypes == [ctypes.c_wchar_p]


def test_runtime_reports_failure_to_restore_dll_lookup(monkeypatch):
    monkeypatch.setattr(frozen_runtime, "sys", SimpleNamespace(platform="win32", frozen=True))
    kernel = SimpleNamespace(SetDllDirectoryW=Mock(return_value=0))
    monkeypatch.setattr(ctypes, "WinDLL", Mock(return_value=kernel), raising=False)
    monkeypatch.setattr(ctypes, "get_last_error", lambda: 5, raising=False)
    monkeypatch.setattr(ctypes, "WinError", lambda code: OSError(code, "reset failed"), raising=False)

    with pytest.raises(OSError, match="reset failed"):
        frozen_runtime.configure_external_process_runtime()


def test_child_path_removes_only_bundle_anchored_directories(monkeypatch):
    monkeypatch.setattr(frozen_runtime, "sys", SimpleNamespace(
        platform="win32", frozen=True, _MEIPASS=r"D:\Monitor\_internal",
    ))
    removed = [
        r"D:\Monitor\_internal",
        r"d:/MONITOR/_internal/PySide6/Qt/bin",
        r'"D:\Monitor\_internal\qt"',
        r"D:\Monitor\_internal\child\..\plugins",
    ]
    retained = [
        r"C:\Windows\System32",
        r"C:\Program Files\nodejs",
        r"C:\Program Files\PostgreSQL\18\bin",
        r"D:\Monitor\_internal-copy",
        r"D:\Monitor\_internal\..\external",
        r"\\server\share\tools",
        "relative-tools",
        "",
    ]
    original = {"Path": ";".join([*removed, *retained]), "PYTHONUTF8": "1"}
    snapshot = original.copy()

    result = frozen_runtime.sanitized_external_environment(original)

    assert result == {"Path": ";".join(retained), "PYTHONUTF8": "1"}
    assert original == snapshot


@pytest.mark.parametrize(
    "runtime",
    [
        SimpleNamespace(platform="win32", frozen=False, _MEIPASS=r"D:\Monitor\_internal"),
        SimpleNamespace(platform="linux", frozen=True, _MEIPASS=r"D:\Monitor\_internal"),
        SimpleNamespace(platform="win32", frozen=True),
        SimpleNamespace(platform="win32", frozen=True, _MEIPASS="relative-bundle"),
    ],
)
def test_child_environment_is_copied_unchanged_without_windows_bundle(monkeypatch, runtime):
    monkeypatch.setattr(frozen_runtime, "sys", runtime)
    original = {"PATH": r"D:\Monitor\_internal;C:\Windows\System32"}

    copied = frozen_runtime.sanitized_external_environment(original)

    assert copied == original
    assert copied is not original


def test_spawn_sanitizes_after_command_environment_overrides(monkeypatch, tmp_path: Path):
    monkeypatch.setattr(frozen_runtime, "sys", SimpleNamespace(
        platform="win32", frozen=True, _MEIPASS=r"D:\Monitor\_internal",
    ))
    environment = {"PATH": r"C:\Windows\System32", "KEEP": "yes"}
    monkeypatch.setattr(processes.os, "environ", environment)
    popen = Mock(return_value=SimpleNamespace(pid=912, stdout=None, stderr=None))
    monkeypatch.setattr(processes.subprocess, "Popen", popen)
    identity = ProcessIdentity(912, 123, "python.exe", ("python.exe",))
    adapter = SubprocessProcessAdapter(inspector=lambda _pid: identity)
    command = CommandSpec("python.exe", (), tmp_path, environment=((
        "PATH", r"D:\Monitor\_internal\PySide6;C:\Program Files\nodejs",
    ),))

    adapter.spawn(command, lambda _stream, _line: None)

    assert popen.call_args.kwargs["env"] == {"PATH": r"C:\Program Files\nodejs", "KEEP": "yes"}
    assert environment["PATH"] == r"C:\Windows\System32"


def test_postgres_helper_sanitizes_its_child_environment(monkeypatch, tmp_path: Path):
    monkeypatch.setattr(frozen_runtime, "sys", SimpleNamespace(
        platform="win32", frozen=True, _MEIPASS=r"D:\Monitor\_internal",
    ))
    environment = {"PATH": r"D:\Monitor\_internal;C:\Windows\System32"}
    monkeypatch.setattr(postgres.os, "environ", environment)
    run = Mock(return_value=SimpleNamespace(returncode=0, stdout=b""))
    monkeypatch.setattr(postgres.subprocess, "run", run)
    command = CommandSpec("python.exe", ("helper.py", "status"), tmp_path)

    assert postgres._run_helper(command, 5, lambda _stream, _line: None) == 0

    assert run.call_args.kwargs["env"] == {"PATH": r"C:\Windows\System32"}
    assert environment["PATH"].startswith(r"D:\Monitor\_internal;")
