from __future__ import annotations

import argparse
import json
import os
import platform
import sqlite3
import sys
import tempfile
from dataclasses import replace
from collections.abc import Sequence
from datetime import UTC, datetime
from pathlib import Path

import PySide6
from PySide6.QtCore import QObject, Signal, qVersion
from PySide6.QtWidgets import QApplication, QFileDialog, QMessageBox

from opc_service_monitor import __version__
from opc_service_monitor.audit import AuditClient
from opc_service_monitor.catalog import build_catalog
from opc_service_monitor.diagnostics import configure_diagnostics
from opc_service_monitor.file_tail import AllowedFileTailer
from opc_service_monitor.frozen_runtime import configure_external_process_runtime
from opc_service_monitor.health import HealthProbe
from opc_service_monitor.log_store import LogStore
from opc_service_monitor.log_pipeline import make_log_entry
from opc_service_monitor.models import LogSource, ServiceId, ServiceState
from opc_service_monitor.paths import ProjectLayout, RuntimePaths, discover_project_root
from opc_service_monitor.postgres import PostgresController
from opc_service_monitor.processes import SubprocessProcessAdapter
from opc_service_monitor.runtime_logs import RuntimeLogCoordinator
from opc_service_monitor.settings import SettingsStore
from opc_service_monitor.supervisor import ServiceObservation, ServiceSupervisor
from opc_service_monitor.ui.main_window import MainWindow
from opc_service_monitor.ui.log_detail_dialog import LogDetailDialog
from opc_service_monitor.ui.theme import apply_theme
from opc_service_monitor.workers import MonitorController


def main(argv: Sequence[str] | None = None) -> int:
    arguments = list(argv) if argv is not None else sys.argv
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--smoke-test", action="store_true")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--project-root", type=Path)
    options, qt_arguments = parser.parse_known_args(arguments[1:])
    if options.smoke_test:
        if options.report is None:
            parser.error("--smoke-test requires --report")
        layout = _discover_for_cli(options.project_root)
        if layout is None:
            _write_json_report(options.report, {"ok": False, "error": "未找到有效的 OPC 项目根目录"})
            return 2
        return run_smoke_test(options.report, layout)

    application = QApplication.instance() or QApplication([arguments[0], *qt_arguments])
    application.setApplicationName("OPC Service Monitor")
    runtime = RuntimePaths.from_environment(os.environ)
    runtime.ensure_directories()
    logger = configure_diagnostics(runtime.diagnostics)
    settings_store = SettingsStore(runtime.settings)
    settings = settings_store.load()
    apply_theme(application, settings.theme)
    layout = _resolve_layout(settings.project_root, application)
    if layout is None:
        logger.warning("No valid OPC project root selected")
        return 2

    settings = replace(settings, project_root=layout.root)
    settings_store.save(settings)
    catalog = build_catalog(layout)
    log_store = LogStore.open(runtime.log_database)
    log_store.purge(datetime.now(UTC), retention_days=7)
    postgres_definition = catalog[ServiceId.POSTGRES]
    tailers = tuple(
        AllowedFileTailer(path, allowed_paths=postgres_definition.log_files, store=log_store)
        for path in postgres_definition.log_files
    )
    for tailer in tailers:
        try:
            repaired = tailer.repair_legacy_entries()
            if repaired:
                logger.info("已从白名单原日志恢复 %d 条历史乱码记录", repaired)
        except (OSError, sqlite3.Error, RuntimeError) as exc:
            logger.warning("历史日志编码恢复暂未完成，后续轮询将重试：%s", exc)
    runtime_logs = RuntimeLogCoordinator(log_store, tailers=tailers)
    processes = SubprocessProcessAdapter()
    health = HealthProbe()
    postgres = PostgresController(
        layout,
        postgres_definition,
        processes,
        output=lambda stream, line: runtime_logs.record(LogSource.POSTGRES, stream, line),
    )
    supervisor = ServiceSupervisor(
        catalog,
        processes,
        postgres,
        health,
        timeouts=settings.timeouts,
        log_callback=runtime_logs.record_service,
    )
    controller = MonitorController(supervisor)
    audit_client = AuditClient()
    window = MainWindow(
        controller,
        catalog,
        log_store=log_store,
        audit_client=audit_client,
        project_layout=layout,
        settings_store=settings_store,
        settings=settings,
    )
    runtime_logs.entry_received.connect(window.append_log_entry)
    runtime_logs.live_overflow.connect(
        lambda count: logger.warning("实时日志显示队列已丢弃较早的 %d 条；历史日志仍已保存", count)
    )
    runtime_logs.poll_error.connect(lambda message: logger.error("PostgreSQL log polling failed: %s", message))
    runtime_logs.ingestion_error.connect(lambda message: logger.error("Runtime log ingestion failed: %s", message))
    window.show()
    configure_external_process_runtime()
    runtime_logs.start()
    logger.info("OPC Service Monitor started")
    try:
        return application.exec()
    finally:
        _shutdown_runtime(
            runtime_logs,
            window.log_panels,
            window.audit_panel,
            controller,
            health,
            log_store,
            logger,
        )


class _SmokeController(QObject):
    observation_changed = Signal(object)
    operation_started = Signal(str)
    operation_finished = Signal(object)
    operation_error = Signal(str)
    refresh_finished = Signal(object)
    busy = False
    owned_services: tuple[ServiceId, ...] = ()

    def refresh(self) -> bool:
        return False

    def start_all(self) -> bool:
        return False

    def stop_all(self) -> bool:
        return False

    def start(self, _service_id: ServiceId) -> bool:
        return False

    def stop(self, _service_id: ServiceId) -> bool:
        return False


class _SmokeAuditClient:
    session = None

    def close(self) -> None:
        self.session = None


def run_smoke_test(report_path: Path, layout: ProjectLayout) -> int:
    """Build and briefly process the real window without probing or mutating services."""

    application = QApplication.instance() or QApplication(["OPCServiceMonitor", "--smoke-test"])
    application.setApplicationName("OPC Service Monitor")
    theme = resource_path("ui/theme.qss")
    store: LogStore | None = None
    window: MainWindow | None = None
    try:
        with tempfile.TemporaryDirectory(prefix="opc-monitor-smoke-") as temporary:
            store = LogStore.open(Path(temporary) / "smoke.sqlite3")
            window = MainWindow(
                _SmokeController(),
                build_catalog(layout),
                log_store=store,
                audit_client=_SmokeAuditClient(),
                audit_task_runner=lambda _function, _success, _error: None,
                project_layout=layout,
                confirm_close=lambda: False,
            )
            window.show()
            external_dll_reset = configure_external_process_runtime()
            application.processEvents()
            detail_text = "日志详情冒烟检查\n完整消息"
            detail = LogDetailDialog(
                make_log_entry(source=LogSource.POSTGRES, stream="file", text=detail_text),
                source_label="PostgreSQL", parent=window,
            )
            detail.open()
            application.processEvents()
            detail_ok = detail.message_edit.isReadOnly() and detail.message_edit.toPlainText() == detail_text
            detail.close()
            application.processEvents()
            themes = []
            for mode in ("light", "dark"):
                window.set_theme(mode, persist=False)
                application.processEvents()
                if application.property("opcTheme") == mode and window.theme_switch.buttons[mode].isChecked():
                    themes.append(mode)
            power_controls_ok = _smoke_power_controls(window)
            tabs = [window.tabs.tabText(index) for index in range(window.tabs.count())]
            expected_tabs = ["全部日志", "前端", "后端", "PostgreSQL", "业务审计"]
            smoke_ok = (
                theme.is_file() and len(window.cards) == 3 and tabs == expected_tabs
                and themes == ["light", "dark"] and detail_ok and power_controls_ok
            )
            report = {
                "ok": smoke_ok,
                "application": "OPC Service Monitor",
                "version": __version__,
                "python": {
                    "major_minor": f"{sys.version_info.major}.{sys.version_info.minor}",
                    "implementation": platform.python_implementation(),
                },
                "qt": {
                    "binding": "PySide6",
                    "binding_version": PySide6.__version__,
                    "qt_version": qVersion(),
                    "platform_plugin": application.platformName(),
                },
                "platform": {
                    "system": platform.system(),
                    "release": platform.release(),
                    "machine": platform.machine(),
                },
                "resources": {"theme": theme.is_file()},
                "external_processes": {"system_dll_search": external_dll_reset},
                "ui": {
                    "service_cards": len(window.cards), "tabs": tabs, "themes": themes,
                    "components": "Material / HUD", "log_details": detail_ok,
                    "power_controls": power_controls_ok,
                },
            }
            _write_json_report(report_path, report)
            window.close()
            application.processEvents()
            panels_drained = _shutdown_log_panels(window.log_panels, timeout_ms=3_000)
            from PySide6.QtCore import QThreadPool

            global_drained = QThreadPool.globalInstance().waitForDone(3_000)
            if not panels_drained or not global_drained:
                raise RuntimeError("桌面界面后台任务未能及时结束")
            store.close()
            store = None
            return 0
    except Exception:
        _write_json_report(report_path, {"ok": False, "error": "桌面界面冒烟检查失败"})
        return 1
    finally:
        if window is not None:
            window.deleteLater()
        if store is not None:
            panels_drained = window is None or _shutdown_log_panels(window.log_panels, timeout_ms=3_000)
            from PySide6.QtCore import QThreadPool

            global_drained = QThreadPool.globalInstance().waitForDone(3_000)
            if panels_drained and global_drained:
                store.close()


def _smoke_power_controls(window: MainWindow) -> bool:
    """Exercise packaged switches with synthetic observations, never real services."""
    initial_locked = not window.start_all_button.isEnabled() and not window.stop_all_button.isEnabled()
    stopped = {
        service_id: ServiceObservation(
            service_id, ServiceState.STOPPED, False, False, None, False, False, False,
            None, datetime.now(UTC), "合成开关冒烟检查：已停止",
        ) for service_id in ServiceId
    }
    window._refresh_finished(stopped)
    stopped_ok = window.start_all_button.isEnabled() and not window.stop_all_button.isEnabled()
    stopped_ok = stopped_ok and window.stop_all_button.isChecked() and all(
        card.start_button.isEnabled() and not card.stop_button.isEnabled() and card.stop_button.isChecked()
        for card in window.cards.values()
    )
    running = {
        service_id: replace(
            observation, state=ServiceState.EXTERNAL if service_id is ServiceId.POSTGRES else ServiceState.READY,
            process_running=True, port_open=True, ready=True, owned=service_id is not ServiceId.POSTGRES,
            external=service_id is ServiceId.POSTGRES, listener_identified=True,
        ) for service_id, observation in stopped.items()
    }
    window._set_busy(True)
    window._refresh_finished(running)
    busy_ok = not window.start_all_button.isEnabled() and not window.stop_all_button.isEnabled() and all(
        not card.start_button.isEnabled() and not card.stop_button.isEnabled() for card in window.cards.values()
    )
    window._set_busy(False)
    running_ok = not window.start_all_button.isEnabled() and window.stop_all_button.isEnabled()
    running_ok = running_ok and window.start_all_button.isChecked() and all(
        not card.start_button.isEnabled() and card.stop_button.isEnabled() == (service_id is not ServiceId.POSTGRES)
        and card.start_button.isChecked() for service_id, card in window.cards.items()
    )
    return initial_locked and stopped_ok and busy_ok and running_ok


def resource_path(relative: str) -> Path:
    source_candidate = Path(__file__).resolve().parent / relative
    if source_candidate.exists():
        return source_candidate
    bundle_root = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))
    return bundle_root / "opc_service_monitor" / relative


def _shutdown_log_panels(panels: dict[str, object], *, timeout_ms: int = 5_000) -> bool:
    results = [bool(panel.shutdown(timeout_ms)) for panel in panels.values()]
    return all(results)


def _shutdown_runtime(
    runtime_logs: object,
    log_panels: dict[str, object],
    audit_panel: object | None,
    controller: object,
    health: object,
    log_store: object,
    logger: object,
    *,
    timeout_ms: int = 5_000,
) -> bool:
    runtime_drained = bool(runtime_logs.stop(timeout_ms))
    log_workers_drained = _shutdown_log_panels(log_panels, timeout_ms=timeout_ms)
    if audit_panel is not None:
        audit_panel.shutdown()
    global_workers_drained = bool(controller.shutdown(timeout_ms))
    if global_workers_drained:
        health.close()
    all_drained = runtime_drained and log_workers_drained and global_workers_drained
    if all_drained:
        log_store.close()
    else:
        logger.error("后台任务未在停止时限内结束；为避免关闭后访问，保留相关客户端和日志存储至进程退出")
    return all_drained


def _discover_for_cli(explicit: Path | None) -> ProjectLayout | None:
    if explicit is not None:
        try:
            return ProjectLayout.validate(explicit)
        except (OSError, ValueError):
            return None
    saved: Path | None = None
    try:
        runtime = RuntimePaths.from_environment(os.environ)
        saved = SettingsStore(runtime.settings).load().project_root
    except ValueError:
        pass
    packaged = bool(getattr(sys, "frozen", False))
    anchor = Path(sys.executable) if packaged else Path(__file__)
    return discover_project_root(saved, anchor, packaged)


def _write_json_report(path: Path, payload: dict[str, object]) -> None:
    destination = Path(path).expanduser().resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _resolve_layout(saved: Path | None, application: QApplication) -> ProjectLayout | None:
    packaged = bool(getattr(sys, "frozen", False))
    anchor = Path(sys.executable) if packaged else Path(__file__)
    layout = discover_project_root(saved, anchor, packaged)
    if layout is not None:
        return layout
    selected = QFileDialog.getExistingDirectory(None, "选择 OPC 项目根目录")
    if not selected:
        return None
    try:
        return ProjectLayout.validate(Path(selected))
    except (OSError, ValueError) as exc:
        QMessageBox.critical(None, "项目目录无效", str(exc))
        application.processEvents()
        return None



