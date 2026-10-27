from __future__ import annotations

from collections.abc import Callable, Iterable
from dataclasses import replace

from PySide6.QtCore import QTimer, QUrl
from PySide6.QtGui import QCloseEvent, QDesktopServices
from PySide6.QtWidgets import (
    QApplication,
    QDialog,
    QFrame,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QMessageBox,
    QVBoxLayout,
    QWidget,
)

from opc_service_monitor.log_pipeline import redact_log_text
from opc_service_monitor.models import LogEntry, LogSource, ServiceDefinition, ServiceId
from opc_service_monitor.paths import ProjectLayout
from opc_service_monitor.settings import MonitorSettings, SettingsStore
from opc_service_monitor.supervisor import OperationReport, ServiceObservation, SupervisorTimeouts
from opc_service_monitor.ui.audit_panel import AuditPanel
from opc_service_monitor.ui.log_panel import LogPanel
from opc_service_monitor.ui.power_control import PowerControl
from opc_service_monitor.ui.service_actions import aggregate_actions, service_actions
from opc_service_monitor.ui.service_card import ServiceCard
from opc_service_monitor.ui.settings_dialog import SettingsDialog
from opc_service_monitor.ui.components import BrandMark, ConsoleButton, ConsoleSurface, ConsoleTabs, ThemeSwitch
from opc_service_monitor.ui.theme import apply_theme


ADMIN_URL = "http://127.0.0.1:5180/#/dashboard"
SWAGGER_URL = "http://127.0.0.1:8001/docs"


class MainWindow(QMainWindow):
    def __init__(
        self,
        controller,
        catalog: dict[ServiceId, ServiceDefinition],
        *,
        log_store=None,
        audit_client=None,
        audit_task_runner=None,
        project_layout: ProjectLayout | None = None,
        settings_store: SettingsStore | None = None,
        settings: MonitorSettings | None = None,
        url_opener: Callable[[str], bool] | None = None,
        confirm_close: Callable[[], bool] | None = None,
        parent=None,
    ) -> None:
        super().__init__(parent)
        self.controller = controller
        self.catalog = catalog
        self._url_opener = url_opener or (lambda url: QDesktopServices.openUrl(QUrl(url)))
        self._confirm_close = confirm_close or self._default_confirm_close
        self._project_layout = project_layout
        self._settings_store = settings_store
        self._settings = settings or (settings_store.load() if settings_store else MonitorSettings())
        self.current_theme = self._settings.theme
        self._observations: dict[ServiceId, ServiceObservation] = {}
        self._operation_active = False
        apply_theme(QApplication.instance(), self.current_theme)
        self._allow_close = False
        self._close_after_stop = False
        self.log_panels: dict[str, LogPanel] = {}
        self.audit_panel: AuditPanel | None = None
        self.setWindowTitle("OPC 后台服务监控器")
        self.resize(1280, 860)
        self.setMinimumSize(1024, 740)

        root = ConsoleSurface()
        root.setObjectName("consoleRoot")
        outer = QVBoxLayout(root)
        outer.setContentsMargins(18, 18, 18, 18)
        outer.setSpacing(8)

        header = QFrame()
        header.setObjectName("consoleHeader")
        header_row = QHBoxLayout(header)
        header_row.setContentsMargins(16, 8, 16, 8)
        header_row.setSpacing(16)
        header_row.addWidget(BrandMark())
        heading = QVBoxLayout()
        heading.setSpacing(1)
        eyebrow = QLabel("OPC  /  SERVICE CONTROL")
        eyebrow.setObjectName("eyebrow")
        title = QLabel("后台服务控制台")
        title.setObjectName("appTitle")
        subtitle = QLabel("本机服务编排  /  运行日志检索  /  业务审计")
        subtitle.setObjectName("subtitle")
        for label in (eyebrow, title, subtitle):
            heading.addWidget(label)
        header_row.addLayout(heading, 1)
        scope = QLabel("LOCAL ONLY")
        scope.setObjectName("scopeBadge")
        scope.setFixedHeight(26)
        header_row.addWidget(scope)
        self.theme_switch = ThemeSwitch()
        self.theme_switch.set_theme(self.current_theme)
        self.theme_switch.theme_selected.connect(self.set_theme)
        header_row.addWidget(self.theme_switch)
        outer.addWidget(header)

        toolbar = QHBoxLayout()
        self.power_control = PowerControl("全部启动", "全部停止")
        self.start_all_button = self.power_control.start_button
        self.start_all_button.setObjectName("startAllButton")
        self.stop_all_button = self.power_control.stop_button
        self.stop_all_button.setObjectName("stopAllButton")
        self.refresh_button = _button("刷新状态", "refreshButton", "refresh")
        self.open_admin_button = _button("打开管理后台", "openAdminButton", "external")
        self.open_swagger_button = _button("打开 Swagger", "openSwaggerButton", "code")
        self.settings_button = _button("设置", "settingsButton", "settings")
        toolbar.addWidget(self.power_control)
        for button in (
            self.refresh_button,
            self.open_admin_button,
            self.open_swagger_button,
            self.settings_button,
        ):
            toolbar.addWidget(button)
        toolbar.addStretch(1)
        outer.addLayout(toolbar)

        self.error_banner = QLabel("")
        self.error_banner.setObjectName("errorBanner")
        self.error_banner.setWordWrap(True)
        self.error_banner.hide()
        outer.addWidget(self.error_banner)

        section = QHBoxLayout()
        service_heading = QLabel("服务节点")
        service_heading.setObjectName("sectionTitle")
        section.addWidget(service_heading)
        section.addStretch(1)
        self.summary_label = QLabel("3 个本机目标 · 等待状态检查")
        self.summary_label.setProperty("tone", "muted")
        section.addWidget(self.summary_label)
        outer.addLayout(section)

        cards_layout = QHBoxLayout()
        self.cards: dict[ServiceId, ServiceCard] = {}
        for service_id in (ServiceId.POSTGRES, ServiceId.BACKEND, ServiceId.FRONTEND):
            card = ServiceCard(catalog[service_id])
            card.start_requested.connect(self._start_service)
            card.stop_requested.connect(self._stop_service)
            cards_layout.addWidget(card)
            self.cards[service_id] = card
            cards_layout.setStretch(cards_layout.count() - 1, 1)
        outer.addLayout(cards_layout)

        self.tabs = ConsoleTabs()
        self.tabs.setObjectName("logTabs")
        if log_store is None:
            for title in ("全部日志", "前端", "后端", "PostgreSQL"):
                placeholder = QWidget()
                placeholder_layout = QVBoxLayout(placeholder)
                placeholder_layout.addWidget(QLabel(f"{title}工作区"))
                placeholder_layout.addStretch(1)
                self.tabs.addTab(placeholder, title)
        else:
            self.log_panels = {
                "all": LogPanel(log_store),
                "frontend": LogPanel(log_store, fixed_sources=(LogSource.FRONTEND,)),
                "backend": LogPanel(log_store, fixed_sources=(LogSource.BACKEND,)),
                "postgres": LogPanel(log_store, fixed_sources=(LogSource.POSTGRES,)),
            }
            for key, title in (
                ("all", "全部日志"),
                ("frontend", "前端"),
                ("backend", "后端"),
                ("postgres", "PostgreSQL"),
            ):
                self.tabs.addTab(self.log_panels[key], title)
                self.log_panels[key].reload_history()
        if audit_client is None:
            audit_placeholder = QWidget()
            audit_layout = QVBoxLayout(audit_placeholder)
            audit_layout.addWidget(QLabel("业务审计工作区"))
            audit_layout.addStretch(1)
            self.tabs.addTab(audit_placeholder, "业务审计")
        else:
            self.audit_panel = AuditPanel(audit_client, task_runner=audit_task_runner)
            self.tabs.addTab(self.audit_panel, "业务审计")
        outer.addWidget(self.tabs, 1)
        self.tabs.refresh_theme()
        self.setCentralWidget(root)
        self.statusBar().showMessage("仅管理本机会话自有进程；外部实例只读保护")
        footer = QLabel("SQLITE / FTS5   ·   保留 7 天   ·   UTC 日志")
        footer.setProperty("tone", "muted")
        self.statusBar().addPermanentWidget(footer)

        self.start_all_button.clicked.connect(self._start_all)
        self.stop_all_button.clicked.connect(self._stop_all)
        self.refresh_button.clicked.connect(self._request_refresh)
        self.open_admin_button.clicked.connect(lambda: self._url_opener(ADMIN_URL))
        self.open_swagger_button.clicked.connect(lambda: self._url_opener(SWAGGER_URL))
        self.settings_button.clicked.connect(self._show_settings)
        self.controller.observation_changed.connect(self._apply_observation)
        self.controller.operation_started.connect(self._operation_started)
        self.controller.operation_finished.connect(self._operation_finished)
        self.controller.operation_error.connect(self._operation_error)
        self.controller.refresh_finished.connect(self._refresh_finished)
        self._set_busy(False)

        self.refresh_timer = QTimer(self)
        self.refresh_timer.setInterval(2_000)
        self.refresh_timer.timeout.connect(self._request_refresh)
        self.refresh_timer.start()
        QTimer.singleShot(0, self._request_refresh)

    def set_theme(self, mode: str, *, persist: bool = True) -> None:
        if mode not in {"dark", "light"}:
            raise ValueError("不支持的界面主题")
        try:
            apply_theme(QApplication.instance(), mode)
        except (OSError, RuntimeError, ValueError) as exc:
            self.theme_switch.set_theme(self.current_theme)
            self._show_error(f"主题切换失败：{exc}")
            return
        self.current_theme = mode
        self.theme_switch.set_theme(mode)
        self._settings = replace(self._settings, theme=mode)
        if persist and self._settings_store is not None:
            try:
                self._settings_store.save(self._settings)
            except (OSError, ValueError) as exc:
                self._show_error(f"主题已切换，但偏好保存失败：{exc}")
                return
        self.statusBar().showMessage(f"已切换为{'暗黑' if mode == 'dark' else '明亮'}模式", 3_000)

    def append_log_entry(self, entries: Iterable[LogEntry]) -> None:
        if not self.log_panels:
            return
        routed: dict[str, list[LogEntry]] = {
            "all": [],
            "frontend": [],
            "backend": [],
            "postgres": [],
        }
        target_for_source = {
            LogSource.FRONTEND: "frontend",
            LogSource.BACKEND: "backend",
            LogSource.POSTGRES: "postgres",
        }
        for entry in entries:
            routed["all"].append(entry)
            target = target_for_source.get(entry.source)
            if target is not None:
                routed[target].append(entry)
        for target, batch in routed.items():
            if batch:
                self.log_panels[target].append_live(tuple(batch))

    def _request_refresh(self) -> None:
        self.controller.refresh()

    def _start_all(self) -> None:
        if aggregate_actions(self._observations, busy=self._operation_active).can_start and self._dependencies_ready(None):
            self._dispatch_operation(self.controller.start_all)

    def _stop_all(self) -> None:
        if aggregate_actions(self._observations, busy=self._operation_active).can_stop:
            self._dispatch_operation(self.controller.stop_all)

    def _start_service(self, service_id: ServiceId) -> None:
        actions = service_actions(self._observations.get(service_id), busy=self._operation_active)
        if actions.can_start and self._dependencies_ready(service_id):
            self._dispatch_operation(lambda: self.controller.start(service_id))

    def _stop_service(self, service_id: ServiceId) -> None:
        if service_actions(self._observations.get(service_id), busy=self._operation_active).can_stop:
            self._dispatch_operation(lambda: self.controller.stop(service_id))

    def _dispatch_operation(self, operation: Callable[[], bool]) -> None:
        # Lock immediately, including controllers whose signals arrive on a later event-loop turn.
        self._set_busy(True)
        if not operation():
            self._set_busy(False)
            self.statusBar().showMessage("正在检查服务状态，请稍后重试", 3_000)

    def _dependencies_ready(self, service_id: ServiceId | None) -> bool:
        if self._project_layout is None:
            return True
        from opc_service_monitor.dependencies import check_dependencies

        required = {
            None: {"backend_python", "backend_start", "postgres_helper", "postgres_18", "npm", "frontend_dependencies"},
            ServiceId.POSTGRES: {"backend_python", "postgres_helper", "postgres_18"},
            ServiceId.BACKEND: {"backend_python", "backend_start"},
            ServiceId.FRONTEND: {"npm", "frontend_dependencies"},
        }[service_id]
        missing = [result for result in check_dependencies(self._project_layout) if result.key in required and not result.ok]
        if not missing:
            return True
        details = "；".join(f"{result.name}：{result.message}" for result in missing)
        self._show_error(f"依赖检查未通过：{details}")
        return False

    def _apply_observation(self, observation: ServiceObservation) -> None:
        card = self.cards.get(observation.service_id)
        if card is not None:
            card.set_observation(observation)
            self._observations[observation.service_id] = observation
            ready = sum(bool(item.ready) for item in self._observations.values())
            external = sum(item.external for item in self._observations.values())
            self.summary_label.setText(f"就绪 {ready} / 3   ·   外部实例 {external}   ·   每 2 秒检查")
            self._sync_power_control()

    def _operation_started(self, name: str) -> None:
        self.error_banner.hide()
        self.statusBar().showMessage(f"正在执行：{name}")
        self._set_busy(True)

    def _operation_finished(self, report: OperationReport) -> None:
        for step in report.steps:
            self._apply_observation(step.observation)
        self._set_busy(False)
        if report.success:
            self.statusBar().showMessage("操作完成", 5_000)
        elif report.cancelled:
            self._show_error("操作等待已取消，界面已刷新实际状态")
        else:
            failed = next((step for step in report.steps if not step.success), None)
            self._show_error(failed.message if failed is not None else "操作未完成，请检查服务日志")
        if self._close_after_stop and report.action == "stop_all":
            self._close_after_stop = False
            if report.success and not self.controller.owned_services:
                self._allow_close = True
                self.close()

    def _operation_error(self, message: str) -> None:
        self._close_after_stop = False
        self._set_busy(False)
        self._show_error(message)

    def _refresh_finished(self, observations: object) -> None:
        if isinstance(observations, dict):
            for observation in observations.values():
                if isinstance(observation, ServiceObservation):
                    self._apply_observation(observation)

    def _set_busy(self, busy: bool) -> None:
        self._operation_active = busy
        self._sync_power_control()
        self.refresh_button.setEnabled(not busy)
        self.settings_button.setEnabled(not busy)
        for card in self.cards.values():
            card.set_busy(busy)

    def _sync_power_control(self) -> None:
        self.power_control.set_actions(aggregate_actions(self._observations, busy=self._operation_active))

    def _show_error(self, message: str) -> None:
        safe = redact_log_text(message) or "操作失败，请检查监控器日志"
        self.error_banner.setText(safe)
        self.error_banner.show()
        self.statusBar().showMessage("操作未完成")

    def _show_settings(self) -> None:
        layout = self._project_layout
        if layout is None:
            try:
                layout = ProjectLayout.validate(self.catalog[ServiceId.BACKEND].start_command.cwd.parent)
            except (OSError, ValueError) as exc:
                self._show_error(str(exc))
                return
        timeouts = getattr(self.controller, "timeouts", SupervisorTimeouts())
        dialog = SettingsDialog(layout, timeouts, parent=self)
        if dialog.exec() != QDialog.Accepted:
            return
        try:
            updater = getattr(self.controller, "update_timeouts", None)
            if callable(updater):
                updater(dialog.selected_timeouts)
            updated_settings = replace(
                self._settings,
                project_root=dialog.project_layout.root,
                timeouts=dialog.selected_timeouts,
            )
            if self._settings_store is not None:
                self._settings_store.save(updated_settings)
            self._settings = updated_settings
        except (OSError, RuntimeError, ValueError) as exc:
            self._show_error(str(exc))
            return
        if dialog.project_layout.root != layout.root:
            self.statusBar().showMessage("项目目录已保存，重启监控器后生效", 10_000)
        else:
            self.statusBar().showMessage("设置已保存", 5_000)

    def closeEvent(self, event: QCloseEvent) -> None:  # noqa: N802 - Qt API name
        if self.controller.busy:
            event.ignore()
            self._show_error("服务操作正在执行，请等待完成后再退出")
            return
        if self._allow_close or not self.controller.owned_services:
            if self.audit_panel is not None:
                self.audit_panel.shutdown()
            event.accept()
            return
        if not self._confirm_close():
            event.ignore()
            return
        event.ignore()
        self._close_after_stop = True
        if not self.controller.stop_all():
            self._close_after_stop = False
            self._show_error("已有操作正在执行，暂时不能退出")

    def _default_confirm_close(self) -> bool:
        result = QMessageBox.question(
            self,
            "停止服务并退出",
            "本监控器启动的服务仍在运行。是否按安全顺序停止后退出？",
            QMessageBox.Yes | QMessageBox.Cancel,
            QMessageBox.Cancel,
        )
        return result == QMessageBox.Yes


def _button(text: str, object_name: str, icon: str = "", variant: str = "default") -> ConsoleButton:
    button = ConsoleButton(text, icon=icon, variant=variant)
    button.setObjectName(object_name)
    return button

