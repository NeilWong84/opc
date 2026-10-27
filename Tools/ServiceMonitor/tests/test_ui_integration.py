from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path

from PySide6.QtCore import QObject, Signal
from PySide6.QtWidgets import QTabWidget

from opc_service_monitor.catalog import build_catalog
from opc_service_monitor.log_pipeline import make_log_entry
from opc_service_monitor.log_store import LogStore
from opc_service_monitor.models import LogSource
from opc_service_monitor.paths import ProjectLayout
from opc_service_monitor.ui.audit_panel import AuditPanel
from opc_service_monitor.ui.log_panel import LogPanel
from opc_service_monitor.ui.main_window import MainWindow


class IntegrationController(QObject):
    observation_changed = Signal(object)
    operation_started = Signal(str)
    operation_finished = Signal(object)
    operation_error = Signal(str)
    refresh_finished = Signal(object)
    busy = False
    owned_services = ()

    def refresh(self):
        return True

    def start_all(self):
        return True

    def stop_all(self):
        return True

    def start(self, _service):
        return True

    def stop(self, _service):
        return True


class EmptyAuditClient:
    session = None

    def close(self):
        self.session = None


def test_main_window_uses_real_log_and_audit_panels_and_routes_live_entry(opc_root: Path, tmp_path: Path, qtbot) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    window = MainWindow(
        IntegrationController(),
        build_catalog(ProjectLayout.validate(opc_root)),
        log_store=store,
        audit_client=EmptyAuditClient(),
        audit_task_runner=lambda *_args: None,
        confirm_close=lambda: False,
    )
    qtbot.addWidget(window)
    try:
        tabs = window.findChild(QTabWidget, "logTabs")
        assert tabs is not None
        assert all(isinstance(tabs.widget(index), LogPanel) for index in range(4))
        assert isinstance(tabs.widget(4), AuditPanel)

        entry = make_log_entry(
            source=LogSource.BACKEND,
            stream="stdout",
            text="password=live-secret",
            occurred_at=datetime.now(UTC),
        )
        store.append([entry])
        frontend = make_log_entry(
            source=LogSource.FRONTEND,
            stream="stdout",
            text="frontend batch entry",
            occurred_at=datetime.now(UTC),
        )
        window.append_log_entry((entry, frontend))

        assert "live-secret" not in window.log_panels["all"].visible_entries[-1].message
        assert len(window.log_panels["all"].visible_entries) == 2
        assert len(window.log_panels["frontend"].visible_entries) == 1
        assert len(window.log_panels["backend"].visible_entries) == 1
    finally:
        for panel in window.log_panels.values():
            panel.shutdown()
        store.close()


def test_main_window_routes_each_live_batch_with_one_panel_call(
    opc_root: Path,
    tmp_path: Path,
    qtbot,
    monkeypatch,
) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    window = MainWindow(
        IntegrationController(),
        build_catalog(ProjectLayout.validate(opc_root)),
        log_store=store,
        audit_client=EmptyAuditClient(),
        audit_task_runner=lambda *_args: None,
        confirm_close=lambda: False,
    )
    qtbot.addWidget(window)
    calls: list[tuple[str, tuple]] = []
    try:
        for name, panel in window.log_panels.items():
            monkeypatch.setattr(
                panel,
                "append_live",
                lambda entries, name=name: calls.append((name, tuple(entries))),
            )
        backend = make_log_entry(source=LogSource.BACKEND, stream="stdout", text="backend")
        frontend = make_log_entry(source=LogSource.FRONTEND, stream="stdout", text="frontend")

        window.append_log_entry((backend, frontend))

        assert calls == [
            ("all", (backend, frontend)),
            ("frontend", (frontend,)),
            ("backend", (backend,)),
        ]
    finally:
        for panel in window.log_panels.values():
            panel.shutdown()
        store.close()

