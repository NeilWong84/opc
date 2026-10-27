from __future__ import annotations

import json
from collections.abc import Callable
from datetime import UTC
from typing import Any

from PySide6.QtCore import QDateTime, Qt
from PySide6.QtWidgets import (
    QCheckBox,
    QDateTimeEdit,
    QFormLayout,
    QHBoxLayout,
    QLabel,
    QLayout,
    QScrollArea,
    QStackedWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from opc_service_monitor.audit import AdminProfile, AuditClient, AuditClientError, AuditEvent, AuditPage
from opc_service_monitor.ui.components import (
    ConsoleButton as QPushButton,
    ConsoleLineEdit as QLineEdit,
    ConsoleTable as QTableWidget,
)
from opc_service_monitor.workers import TaskWorker


TaskRunner = Callable[[Callable[[], Any], Callable[[Any], None], Callable[[str, Exception], None]], None]


class AuditPanel(QWidget):
    def __init__(
        self,
        client: AuditClient,
        *,
        task_runner: TaskRunner | None = None,
        parent=None,
    ) -> None:
        super().__init__(parent)
        self._client = client
        self._task_runner = task_runner or self._run_qt_task
        self._workers: set[TaskWorker] = set()
        self._page: AuditPage | None = None
        self._visible: tuple[AuditEvent, ...] = ()
        self._logged_in = False
        self._exhausted = False
        self._shutdown = False

        self.error_label = QLabel("")
        self.error_label.setObjectName("auditError")
        self.error_label.setProperty("tone", "danger")
        self.error_label.setWordWrap(True)
        self.error_label.hide()

        self.stack = QStackedWidget()
        login_page = QWidget()
        login_layout = QVBoxLayout(login_page)
        login_layout.setSizeConstraint(QLayout.SetMinimumSize)
        login_card = QWidget()
        login_card.setObjectName("auditLoginCard")
        login_card.setMinimumWidth(440)
        login_card.setMaximumWidth(520)
        card_layout = QVBoxLayout(login_card)
        card_layout.setContentsMargins(28, 24, 28, 28)
        card_layout.setSpacing(16)
        card_layout.setSizeConstraint(QLayout.SetMinimumSize)
        title = QLabel("业务审计 · 安全访问")
        title.setObjectName("sectionTitle")
        card_layout.addWidget(title)
        intro = QLabel("使用后台管理员账号手动登录。密码与 Token 不保存到本地。")
        intro.setWordWrap(True)
        intro.setProperty("tone", "muted")
        card_layout.addWidget(intro)
        form = QFormLayout()
        form.setSpacing(12)
        self.email_edit = QLineEdit()
        self.email_edit.setPlaceholderText("管理员邮箱")
        self.password_edit = QLineEdit()
        self.password_edit.setEchoMode(QLineEdit.Password)
        self.password_edit.setPlaceholderText("管理员密码")
        form.addRow("邮箱", self.email_edit)
        form.addRow("密码", self.password_edit)
        card_layout.addLayout(form)
        self.login_button = QPushButton("登录并读取业务审计", icon="lock", variant="primary")
        self.login_button.clicked.connect(self.login)
        card_layout.addWidget(self.login_button)
        security_note = QLabel("审计数据仅在当前会话查看，不写入日志索引或导出文件。")
        security_note.setWordWrap(True)
        security_note.setProperty("tone", "muted")
        card_layout.addWidget(security_note)
        login_layout.addStretch(1)
        login_layout.addWidget(login_card, 0, Qt.AlignHCenter)
        login_layout.addStretch(1)

        events_page = QWidget()
        events_layout = QVBoxLayout(events_page)
        events_layout.setContentsMargins(0, 0, 0, 0)
        events_layout.setSpacing(12)
        session_row = QHBoxLayout()
        self.profile_label = QLabel("")
        self.refresh_button = QPushButton("刷新", icon="refresh")
        self.refresh_button.clicked.connect(self.refresh_events)
        self.load_more_button = QPushButton("加载更多", icon="latest")
        self.load_more_button.clicked.connect(self.load_more)
        self.logout_button = QPushButton("退出登录", icon="logout")
        self.logout_button.clicked.connect(self.logout)
        session_row.addWidget(self.profile_label)
        session_row.addStretch(1)
        session_row.addWidget(self.refresh_button)
        session_row.addWidget(self.load_more_button)
        session_row.addWidget(self.logout_button)
        events_layout.addLayout(session_row)

        filter_row = QHBoxLayout()
        filter_row.setSpacing(10)
        self.actor_filter = QLineEdit()
        self.actor_filter.setPlaceholderText("操作者")
        self.table_filter = QLineEdit()
        self.table_filter.setPlaceholderText("对象/表")
        self.operation_filter = QLineEdit()
        self.operation_filter.setPlaceholderText("操作")
        self.keyword_filter = QLineEdit()
        self.keyword_filter.setPlaceholderText("关键词")
        self.start_checkbox = QCheckBox("起始")
        self.start_edit = QDateTimeEdit(QDateTime.currentDateTime().addDays(-1))
        self.start_edit.setDisplayFormat("yyyy-MM-dd HH:mm:ss")
        self.start_edit.setMinimumWidth(210)
        self.start_edit.setEnabled(False)
        self.end_checkbox = QCheckBox("结束")
        self.end_edit = QDateTimeEdit(QDateTime.currentDateTime())
        self.end_edit.setDisplayFormat("yyyy-MM-dd HH:mm:ss")
        self.end_edit.setMinimumWidth(210)
        self.end_edit.setEnabled(False)
        self.start_checkbox.toggled.connect(self.start_edit.setEnabled)
        self.end_checkbox.toggled.connect(self.end_edit.setEnabled)
        filter_button = QPushButton("筛选已加载", icon="search", variant="primary")
        filter_button.clicked.connect(self.apply_filters)
        for widget in (
            self.actor_filter,
            self.table_filter,
            self.operation_filter,
            self.keyword_filter,
        ):
            filter_row.addWidget(widget, 1)
        filter_row.addWidget(filter_button)
        events_layout.addLayout(filter_row)
        time_filter_row = QHBoxLayout()
        time_filter_row.setSpacing(10)
        for widget in (
            self.start_checkbox,
            self.start_edit,
            self.end_checkbox,
            self.end_edit,
        ):
            time_filter_row.addWidget(widget)
        time_filter_row.addStretch(1)
        events_layout.addLayout(time_filter_row)

        self.table = QTableWidget(0, 7)
        self.table.setObjectName("auditTable")
        self.table.setHorizontalHeaderLabels(("ID", "时间 (UTC)", "操作者", "对象", "操作", "变更字段", "详情"))
        self.table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.table.setWordWrap(False)
        self.table.horizontalHeader().setStretchLastSection(True)
        self.table.verticalHeader().setDefaultSectionSize(36)
        self.table.verticalHeader().hide()
        for column, width in enumerate((80, 198, 140, 130, 90, 160)):
            self.table.setColumnWidth(column, width)
        events_layout.addWidget(self.table, 1)

        login_scroll = QScrollArea()
        login_scroll.setObjectName("auditLoginScroll")
        login_scroll.setWidgetResizable(True)
        login_scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        login_scroll.setWidget(login_page)
        self.stack.addWidget(login_scroll)
        self.stack.addWidget(events_page)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(18, 18, 18, 16)
        layout.setSpacing(12)
        layout.addWidget(self.error_label)
        layout.addWidget(self.stack, 1)

    @property
    def is_logged_in(self) -> bool:
        return self._logged_in

    @property
    def loaded_events(self) -> tuple[AuditEvent, ...]:
        return self._page.items if self._page is not None else ()

    @property
    def visible_events(self) -> tuple[AuditEvent, ...]:
        return self._visible

    def login(self) -> None:
        if self._shutdown:
            return
        email = self.email_edit.text().strip()
        password = self.password_edit.text()
        self.password_edit.clear()
        if not email or not password:
            self._show_error("请输入管理员邮箱和密码")
            return
        self._set_busy(True)

        def perform() -> AdminProfile:
            self._client.login(email, password)
            return self._client.me()

        def success(profile: AdminProfile) -> None:
            self._logged_in = True
            self.stack.setCurrentIndex(1)
            self.profile_label.setText(f"{profile.display_name}（{profile.email}）")
            self._set_busy(False)
            self.error_label.hide()
            self.refresh_events()

        self._task_runner(perform, success, self._handle_error)

    def refresh_events(self) -> None:
        if self._shutdown or not self._logged_in:
            return
        self._set_busy(True)

        def success(page: AuditPage) -> None:
            self._page = page
            self._exhausted = not bool(page.items)
            self._set_busy(False)
            self.error_label.hide()
            self.apply_filters()

        self._task_runner(lambda: self._client.list_events(limit=50), success, self._handle_error)

    def load_more(self) -> None:
        if (
            self._shutdown
            or not self._logged_in
            or self._page is None
            or self._page.next_before_id is None
            or self._exhausted
        ):
            self.load_more_button.setEnabled(False)
            return
        before_id = self._page.next_before_id
        self._set_busy(True)

        def success(page: AuditPage) -> None:
            if not page.items:
                self._exhausted = True
            else:
                self._page = self._page.merged_with(page) if self._page is not None else page
            self._set_busy(False)
            self.error_label.hide()
            self.apply_filters()

        self._task_runner(lambda: self._client.list_events(limit=50, before_id=before_id), success, self._handle_error)

    def logout(self) -> None:
        if self._shutdown:
            return
        self._clear_session_ui()
        self._set_busy(True)
        self._task_runner(self._client.logout, lambda _result: self._set_busy(False), self._handle_error)

    def set_filters(
        self,
        *,
        actor: str = "",
        table: str = "",
        operation: str = "",
        keyword: str = "",
    ) -> None:
        self.actor_filter.setText(actor)
        self.table_filter.setText(table)
        self.operation_filter.setText(operation)
        self.keyword_filter.setText(keyword)
        self.apply_filters()

    def apply_filters(self) -> None:
        events = self.loaded_events
        actor = self.actor_filter.text().strip().casefold()
        table = self.table_filter.text().strip().casefold()
        operation = self.operation_filter.text().strip().casefold()
        keyword = self.keyword_filter.text().strip().casefold()
        started_at = self.start_edit.dateTime().toPython().astimezone(UTC) if self.start_checkbox.isChecked() else None
        ended_at = self.end_edit.dateTime().toPython().astimezone(UTC) if self.end_checkbox.isChecked() else None
        visible: list[AuditEvent] = []
        for event in events:
            if started_at is not None and event.occurred_at < started_at:
                continue
            if ended_at is not None and event.occurred_at > ended_at:
                continue
            if actor and actor not in (event.application_actor_id or "").casefold():
                continue
            if table and table not in event.table_name.casefold():
                continue
            if operation and operation not in event.operation.casefold():
                continue
            searchable = " ".join(
                (
                    str(event.id),
                    event.application_actor_id or "",
                    event.correlation_id or "",
                    event.table_name,
                    event.operation,
                    json.dumps(event.entity_key, ensure_ascii=False, sort_keys=True),
                    " ".join(event.changed_fields),
                    json.dumps(event.details, ensure_ascii=False, sort_keys=True),
                )
            ).casefold()
            if keyword and keyword not in searchable:
                continue
            visible.append(event)
        self._visible = tuple(visible)
        self._render()
        self.load_more_button.setEnabled(
            self._logged_in
            and not self._exhausted
            and self._page is not None
            and self._page.next_before_id is not None
        )

    def shutdown(self) -> None:
        if self._shutdown:
            return
        self._shutdown = True
        self._clear_session_ui()
        self._set_busy(True)

        def dispose() -> None:
            try:
                if getattr(self._client, "session", None) is not None:
                    self._client.logout()
            except Exception:
                pass
            finally:
                self._client.close()

        worker = TaskWorker(dispose)
        self._workers.add(worker)
        worker.signals.finished.connect(lambda: self._workers.discard(worker))
        worker.start()

    def _handle_error(self, message: str, error: Exception) -> None:
        self._set_busy(False)
        if isinstance(error, AuditClientError) and error.relogin_required:
            self._clear_session_ui()
            self._show_error(f"{message}，请重新登录")
            return
        self._show_error(message)

    def _clear_session_ui(self) -> None:
        self._logged_in = False
        self._page = None
        self._visible = ()
        self._exhausted = False
        self.password_edit.clear()
        self.stack.setCurrentIndex(0)
        self.table.setRowCount(0)
        self.load_more_button.setEnabled(False)

    def _show_error(self, message: str) -> None:
        self.error_label.setText(message)
        self.error_label.show()

    def _set_busy(self, busy: bool) -> None:
        self.login_button.setEnabled(not busy)
        self.refresh_button.setEnabled(not busy and self._logged_in)
        self.load_more_button.setEnabled(not busy and self._logged_in and not self._exhausted)
        self.logout_button.setEnabled(not busy and self._logged_in)

    def _render(self) -> None:
        self.table.setRowCount(len(self._visible))
        for row, event in enumerate(self._visible):
            values = (
                str(event.id),
                event.occurred_at.astimezone(UTC).strftime("%Y-%m-%d %H:%M:%S"),
                event.application_actor_id or "—",
                event.table_name,
                event.operation,
                ", ".join(event.changed_fields),
                json.dumps(event.details, ensure_ascii=False, sort_keys=True),
            )
            for column, value in enumerate(values):
                self.table.setItem(row, column, QTableWidgetItem(value))

    def _run_qt_task(
        self,
        function: Callable[[], Any],
        success: Callable[[Any], None],
        error: Callable[[str, Exception], None],
    ) -> None:
        def protected() -> tuple[bool, Any]:
            try:
                return True, function()
            except Exception as exc:
                return False, exc

        worker = TaskWorker(protected)
        self._workers.add(worker)

        def completed(outcome: tuple[bool, Any]) -> None:
            if self._shutdown:
                return
            ok, value = outcome
            if ok:
                success(value)
            else:
                error(str(value), value)

        worker.signals.result.connect(completed)
        worker.signals.finished.connect(lambda: self._workers.discard(worker))
        worker.start()

