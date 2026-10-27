from __future__ import annotations

import json
from pathlib import Path

from opc_service_monitor.app import _shutdown_log_panels, _shutdown_runtime, run_smoke_test
from opc_service_monitor.paths import ProjectLayout
from opc_service_monitor.processes import SubprocessProcessAdapter


def test_smoke_mode_builds_real_window_without_service_mutation(
    opc_root: Path,
    tmp_path: Path,
    monkeypatch,
) -> None:
    unrelated = tmp_path / "unrelated-cwd"
    unrelated.mkdir()
    report_path = tmp_path / "smoke-report.json"
    monkeypatch.chdir(unrelated)
    monkeypatch.setenv("UNRELATED_SECRET", "TOKEN_SHOULD_NOT_APPEAR")

    def forbidden(*_args, **_kwargs):
        raise AssertionError("smoke mode must not start or stop a service")

    monkeypatch.setattr(SubprocessProcessAdapter, "spawn", forbidden)
    monkeypatch.setattr(SubprocessProcessAdapter, "request_stop", forbidden)
    monkeypatch.setattr(SubprocessProcessAdapter, "force_stop", forbidden)

    exit_code = run_smoke_test(report_path, ProjectLayout.validate(opc_root))

    assert exit_code == 0
    report = json.loads(report_path.read_text(encoding="utf-8"))
    assert report["ok"] is True
    assert report["application"] == "OPC Service Monitor"
    assert report["python"]["major_minor"] == "3.12"
    assert report["qt"]["binding"] == "PySide6"
    assert report["platform"]["system"]
    assert report["resources"]["theme"] is True
    assert report["ui"]["service_cards"] == 3
    assert report["ui"]["themes"] == ["light", "dark"]
    assert report["ui"]["components"] == "Material / HUD"
    assert report["ui"]["log_details"] is True
    assert report["ui"]["power_controls"] is True
    assert report["ui"]["tabs"] == ["全部日志", "前端", "后端", "PostgreSQL", "业务审计"]
    serialized = report_path.read_text(encoding="utf-8")
    assert "TOKEN_SHOULD_NOT_APPEAR" not in serialized
    assert "environment" not in serialized.casefold()
    assert "access_token" not in serialized.casefold()


def test_log_panel_shutdown_attempts_every_panel_when_one_times_out() -> None:
    calls: list[str] = []

    class Panel:
        def __init__(self, name: str, result: bool) -> None:
            self.name = name
            self.result = result

        def shutdown(self, _timeout_ms: int = 5_000) -> bool:
            calls.append(self.name)
            return self.result

    panels = {
        "first": Panel("first", False),
        "second": Panel("second", True),
        "third": Panel("third", True),
    }

    assert _shutdown_log_panels(panels, timeout_ms=25) is False
    assert calls == ["first", "second", "third"]


def test_runtime_shutdown_closes_clients_and_store_only_after_workers_drain() -> None:
    calls: list[str] = []

    class RuntimeLogs:
        def stop(self, timeout_ms: int) -> bool:
            calls.append(f"runtime:{timeout_ms}")
            return True

    class Panel:
        def shutdown(self, timeout_ms: int) -> bool:
            calls.append(f"panel:{timeout_ms}")
            return True

    class Audit:
        def shutdown(self) -> None:
            calls.append("audit")

    class Controller:
        def shutdown(self, timeout_ms: int) -> bool:
            calls.append(f"global:{timeout_ms}")
            return True

    class Health:
        def close(self) -> None:
            calls.append("health-close")

    class Store:
        def close(self) -> None:
            calls.append("store-close")

    class Logger:
        def error(self, *_args) -> None:
            calls.append("error")

    assert _shutdown_runtime(
        RuntimeLogs(),
        {"all": Panel()},
        Audit(),
        Controller(),
        Health(),
        Store(),
        Logger(),
        timeout_ms=2_500,
    ) is True
    assert calls == [
        "runtime:2500",
        "panel:2500",
        "audit",
        "global:2500",
        "health-close",
        "store-close",
    ]


def test_runtime_shutdown_keeps_clients_and_store_open_when_global_workers_timeout() -> None:
    calls: list[str] = []

    class RuntimeLogs:
        def stop(self, _timeout_ms: int) -> bool:
            return True

    class Controller:
        def shutdown(self, _timeout_ms: int) -> bool:
            calls.append("global-timeout")
            return False

    class Resource:
        def close(self) -> None:
            calls.append("unsafe-close")

    class Logger:
        def error(self, *_args) -> None:
            calls.append("error")

    assert _shutdown_runtime(
        RuntimeLogs(),
        {},
        None,
        Controller(),
        Resource(),
        Resource(),
        Logger(),
        timeout_ms=100,
    ) is False
    assert calls == ["global-timeout", "error"]

