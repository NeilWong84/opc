"""Render acceptance screenshots with synthetic data and no network/process access."""
from __future__ import annotations

import argparse
import os
import tempfile
from datetime import UTC, datetime, timedelta
from pathlib import Path

from PySide6.QtCore import QObject, QThreadPool, Signal
from PySide6.QtWidgets import QApplication, QLabel, QScrollArea

from opc_service_monitor.audit import AdminProfile, AdminSession, AuditEvent, AuditPage
from opc_service_monitor.catalog import build_catalog
from opc_service_monitor.dependencies import DependencyCheck
from opc_service_monitor.log_pipeline import make_log_entry
from opc_service_monitor.log_store import LogStore
from opc_service_monitor.models import LogSource, ServiceId, ServiceState
from opc_service_monitor.paths import ProjectLayout
from opc_service_monitor.settings import MonitorSettings
from opc_service_monitor.supervisor import ServiceObservation, SupervisorTimeouts
from opc_service_monitor.ui.main_window import MainWindow
from opc_service_monitor.ui.settings_dialog import SettingsDialog


NOTICE = "UI 验收 · 全部状态与日志均为合成数据 · 未连接或操作真实服务"
WHEN = datetime(2026, 10, 25, 9, 30, tzinfo=UTC)


class PreviewController(QObject):
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
        raise RuntimeError("UI preview never starts services")

    def stop_all(self):
        raise RuntimeError("UI preview never stops services")

    def start(self, _service):
        raise RuntimeError("UI preview never starts services")

    def stop(self, _service):
        raise RuntimeError("UI preview never stops services")


class PreviewAudit:
    session = None

    def login(self, _email, _password):
        self.session = AdminSession("synthetic-memory-only", "bearer", "admin", WHEN)
        return self.session

    def me(self):
        return AdminProfile("ui", "ui@example.invalid", "UI 验收账号", "active", "zh", 1,
                            WHEN, ("administrator",), False, False)

    def list_events(self, **_kwargs):
        return AuditPage(tuple(AuditEvent(
            index, WHEN, "ui-acceptance", "ui-preview", "requests", "UPDATE",
            {"id": index}, ("status",), {"note": "合成审计验收数据"},
        ) for index in range(6, 0, -1)), None)

    def logout(self):
        self.session = None

    def close(self):
        self.session = None


def sync_task(function, success, error):
    try:
        result = function()
    except Exception as exc:
        error(str(exc), exc)
    else:
        success(result)


def preview_layout(root: Path) -> ProjectLayout:
    return ProjectLayout(
        root, root / "BackendService", root / "FrontendAdmin", root / "DB",
        root / "BackendService/scripts/start.ps1", root / "BackendService/scripts/provision-local-integration.py",
        root / "BackendService/.venv/Scripts/python.exe", root / "BackendService/.local/integration",
    )


def capture(widget, path: Path, application: QApplication):
    widget.move(0, 0)
    widget.show()
    application.processEvents()
    application.processEvents()
    widget.repaint()
    pixmap = widget.grab()
    if not pixmap.save(str(path)):
        raise RuntimeError(f"截图保存失败: {path}")
    print(f"{path.name}: logical={widget.width()}x{widget.height()} "
          f"pixels={pixmap.width()}x{pixmap.height()} DPR={pixmap.devicePixelRatio()}")


def power_observations(scenario: str) -> tuple[ServiceObservation, ...]:
    """Acceptance scenarios contain fabricated process evidence only."""
    if scenario == "unknown":
        return ()
    observations = []
    for index, service in enumerate((ServiceId.POSTGRES, ServiceId.BACKEND, ServiceId.FRONTEND)):
        running = scenario == "ready" or (
            scenario in {"mixed", "starting"} and service in {ServiceId.POSTGRES, ServiceId.BACKEND}
        )
        starting = scenario == "starting" and service is ServiceId.BACKEND
        external = running and service is ServiceId.POSTGRES
        state = (
            ServiceState.STARTING if starting else
            ServiceState.EXTERNAL if external else
            ServiceState.READY if running else ServiceState.STOPPED
        )
        observations.append(ServiceObservation(
            service_id=service, state=state, process_running=running, port_open=running and not starting,
            live=running and not starting if service is ServiceId.BACKEND else None,
            ready=running and not starting, owned=running and not external, external=external,
            pid=9100 + index if running else None, checked_at=WHEN,
            summary=f"合成状态：{'启动中' if starting else '外部只读实例' if external else '本会话已就绪' if running else '服务已停止'}",
            listener_identified=running and not starting,
        ))
    return tuple(observations)


def capture_power_controls(application: QApplication, layout: ProjectLayout, store: LogStore, output: Path) -> None:
    for mode in ("dark", "light"):
        for scenario in ("ready", "stopped", "mixed", "starting", "unknown"):
            controller = PreviewController()
            window = MainWindow(
                controller, build_catalog(layout), log_store=store, settings=MonitorSettings(theme=mode),
                url_opener=lambda _url: False,
            )
            window.refresh_timer.stop()
            window.setWindowTitle(f"OPC 开关验收 · {scenario} · 合成状态")
            subtitle = window.findChild(QLabel, "subtitle")
            subtitle.setText(f"UI 验收 · {scenario} 合成状态 / 未连接或操作真实服务")
            subtitle.setWordWrap(True)
            window.show()
            for panel in window.log_panels.values():
                panel._pool.waitForDone(3000)
            application.processEvents()
            for observation in power_observations(scenario):
                controller.observation_changed.emit(observation)
            if scenario == "starting":
                window._operation_started("合成全部启动")
            window.tabs.setCurrentIndex(0)
            sizes = ((1024, 740), (1280, 860)) if scenario == "ready" else ((1024, 740),)
            for width, height in sizes:
                window.setFixedSize(width, height)
                capture(window, output / f"{mode}-{scenario}-{width}x{height}.png", application)
            for panel in window.log_panels.values():
                panel.shutdown()
            window.close()
            window.deleteLater()
            application.processEvents()
    QThreadPool.globalInstance().waitForDone(3000)
    application.processEvents()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--platform", default="offscreen", choices=("offscreen", "windows"))
    parser.add_argument("--power-controls-only", action="store_true", help="仅渲染合成启停开关状态，不操作真实服务")
    args = parser.parse_args()
    os.environ["QT_QPA_PLATFORM"] = args.platform
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    application = QApplication([])
    with tempfile.TemporaryDirectory(prefix="opc-ui-preview-") as temporary:
        root = Path(temporary)
        layout = preview_layout(root / "SYNTHETIC-OPC")
        store = LogStore.open(root / "preview.sqlite3")
        sources = (LogSource.MONITOR, LogSource.POSTGRES, LogSource.BACKEND, LogSource.FRONTEND)
        messages = ("[UI 合成数据] 状态检查周期完成", "[UI 合成数据] PostgreSQL 日志读取成功",
                    "[UI 合成数据] GET /health/ready → 200", "[UI 合成数据] 管理前端资源已就绪")
        store.append([make_log_entry(source=sources[index % 4], stream="stdout", text=messages[index % 4],
                                     occurred_at=WHEN + timedelta(seconds=index)) for index in range(12)])
        if args.power_controls_only:
            capture_power_controls(application, layout, store, output)
            store.close()
            return 0
        controller = PreviewController()
        window = MainWindow(controller, build_catalog(layout), log_store=store, audit_client=PreviewAudit(),
                            audit_task_runner=sync_task, settings=MonitorSettings(), url_opener=lambda _url: False)
        window.refresh_timer.stop()
        subtitle = window.findChild(QLabel, "subtitle")
        subtitle.setText("UI 验收 · 合成数据 / 未连接或操作真实服务")
        subtitle.setWordWrap(True)
        window.show()
        for panel in window.log_panels.values():
            panel._pool.waitForDone(3000)
        application.processEvents()
        for index, service in enumerate((ServiceId.POSTGRES, ServiceId.BACKEND, ServiceId.FRONTEND)):
            controller.observation_changed.emit(ServiceObservation(
                service_id=service, state=ServiceState.EXTERNAL, process_running=True, port_open=True,
                live=True if service is ServiceId.BACKEND else None, ready=True, owned=False,
                external=True, pid=9100 + index, checked_at=WHEN, summary="合成状态：只读健康检查通过",
            ))
        for mode in ("dark", "light"):
            window.set_theme(mode, persist=False)
            for width, height in ((1280, 860), (1024, 740)):
                suffix = f"{width}x{height}.png"
                # Fixed dimensions are preview-only; production windows remain resizable.
                window.setFixedSize(width, height)
                window.tabs.setCurrentIndex(0)
                capture(window, output / f"{mode}-main-{suffix}", application)
                log_table = window.log_panels["all"].table
                assert log_table.viewport().height() >= 2 * log_table.verticalHeader().defaultSectionSize()
                audit = window.audit_panel
                audit._clear_session_ui()
                window.tabs.setCurrentWidget(audit)
                login_scroll = audit.findChild(QScrollArea, "auditLoginScroll")
                login_scroll.verticalScrollBar().setValue(0)
                capture(window, output / f"{mode}-audit-login-{suffix}", application)
                if login_scroll.verticalScrollBar().maximum() > 0:
                    login_scroll.ensureWidgetVisible(audit.login_button, 0, 0)
                    login_scroll.verticalScrollBar().setValue(login_scroll.verticalScrollBar().maximum())
                    capture(window, output / f"{mode}-audit-login-scrolled-{suffix}", application)
                audit.email_edit.setText("ui@example.invalid")
                audit.password_edit.setText("synthetic-only")
                audit.login()
                capture(window, output / f"{mode}-audit-events-{suffix}", application)
                dialog = SettingsDialog(layout, SupervisorTimeouts(), parent=window,
                    dependency_checker=lambda _layout: tuple(DependencyCheck(
                        key, name, True, f"SYNTHETIC-OPC/{name}", "UI 合成检查结果；未检查真实依赖",
                    ) for key, name in (("python", "Python 3.12"), ("node", "Node.js"), ("postgres", "PostgreSQL 18"))))
                notice = QLabel(NOTICE)
                notice.setWordWrap(True)
                notice.setProperty("tone", "muted")
                dialog.layout().insertWidget(0, notice)
                dialog.setFixedSize(width, height)
                capture(dialog, output / f"{mode}-settings-{suffix}", application)
                dialog.close()
                dialog.deleteLater()
                application.processEvents()
        for panel in window.log_panels.values():
            panel.shutdown()
        window.close()
        QThreadPool.globalInstance().waitForDone(3000)
        application.processEvents()
        store.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
