from __future__ import annotations

import csv
import os
import threading
from dataclasses import replace
from datetime import UTC, datetime
from pathlib import Path

from PySide6.QtCore import QDateTime, QThreadPool, Qt
from PySide6.QtWidgets import (
    QApplication,
    QCheckBox,
    QDateTimeEdit,
    QFileDialog,
    QHBoxLayout,
    QLabel,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from opc_service_monitor.log_pipeline import make_log_entry, redact_log_text
from opc_service_monitor.log_store import (
    LogMatchMode,
    LogQuery,
    LogSearchResult,
    LogStore,
    SafeLogRegex,
    compile_log_regex,
)
from opc_service_monitor.models import LogEntry, LogLevel, LogSource
from opc_service_monitor.ui.components import (
    ConsoleButton as QPushButton,
    ConsoleComboBox as QComboBox,
    ConsoleLineEdit as QLineEdit,
    ConsoleTable as QTableWidget,
)
from opc_service_monitor.ui.log_detail_dialog import LogDetailDialog
from opc_service_monitor.workers import TaskWorker


MAX_VISIBLE_ROWS = 5_000
LIVE_REGEX_TIMEOUT_SECONDS = 0.01
LIVE_REGEX_TIMEOUT_WARNING = "实时正则匹配达到时间上限，实时结果可能不完整；修改查询后可恢复"
_SOURCE_LABELS = {
    LogSource.MONITOR: "监控器",
    LogSource.FRONTEND: "前端",
    LogSource.BACKEND: "后端",
    LogSource.POSTGRES: "PostgreSQL",
}
_LEVEL_LABELS = {
    LogLevel.DEBUG: "DEBUG",
    LogLevel.INFO: "INFO",
    LogLevel.WARNING: "WARNING",
    LogLevel.ERROR: "ERROR",
    LogLevel.CRITICAL: "CRITICAL",
    LogLevel.UNKNOWN: "UNKNOWN",
}


class LogPanel(QWidget):
    def __init__(
        self,
        store: LogStore,
        *,
        fixed_sources: tuple[LogSource, ...] = (),
        parent=None,
    ) -> None:
        super().__init__(parent)
        self._store = store
        self._fixed_sources = fixed_sources
        self._query = LogQuery(sources=fixed_sources)
        self._visible: list[LogEntry] = []
        self._auto_scroll_paused = False
        self._search_generation = 0
        self._active_searches: set[int] = set()
        self._pending_live: dict[int, list[LogEntry]] = {}
        self._workers: set[TaskWorker] = set()
        self._search_cancellations: dict[int, threading.Event] = {}
        self._export_cancellations: set[threading.Event] = set()
        self._pool = QThreadPool(self)
        self._pool.setMaxThreadCount(2)
        self._shutting_down = False
        self._live_regex_key: tuple[str, bool] | None = None
        self._live_regex: SafeLogRegex | None = None
        self._live_regex_timed_out = False
        self._detail_dialog: LogDetailDialog | None = None

        filters = QHBoxLayout()
        filters.setSpacing(10)
        self.keyword_edit = QLineEdit()
        self.keyword_edit.setPlaceholderText("检索日志关键词…")
        self.source_combo = QComboBox()
        self.source_combo.setMinimumWidth(134)
        self.source_combo.addItem("全部来源", None)
        for source, label in _SOURCE_LABELS.items():
            self.source_combo.addItem(label, source)
        self.level_combo = QComboBox()
        self.level_combo.setMinimumWidth(126)
        self.level_combo.addItem("全部级别", None)
        for level, label in _LEVEL_LABELS.items():
            self.level_combo.addItem(label, level)
        self.case_checkbox = QCheckBox("区分大小写")
        self.regex_checkbox = QCheckBox("正则")
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
        self.search_button = QPushButton("检索", icon="search", variant="primary")
        self.search_button.clicked.connect(self._query_from_controls)
        filters.addWidget(self.keyword_edit, 1)
        for widget in (
            self.source_combo,
            self.level_combo,
            self.search_button,
        ):
            filters.addWidget(widget)

        time_filters = QHBoxLayout()
        time_filters.setSpacing(10)
        for widget in (
            self.start_checkbox,
            self.start_edit,
            self.end_checkbox,
            self.end_edit,
        ):
            time_filters.addWidget(widget)
        time_filters.addStretch(1)
        time_filters.addWidget(self.case_checkbox)
        time_filters.addWidget(self.regex_checkbox)

        if fixed_sources:
            self.source_combo.setEnabled(False)
            if len(fixed_sources) == 1:
                index = self.source_combo.findData(fixed_sources[0])
                self.source_combo.setCurrentIndex(index)

        self.validation_label = QLabel("")
        self.validation_label.setObjectName("logValidation")
        self.validation_label.setProperty("tone", "danger")
        self.validation_label.setWordWrap(True)
        self.validation_label.hide()

        self.table = QTableWidget(0, 5)
        self.table.setObjectName("logTable")
        self.table.setMinimumHeight(114)
        self.table.setHorizontalHeaderLabels(("时间 (UTC)", "来源", "级别", "stream", "消息"))
        self.table.setSelectionBehavior(QTableWidget.SelectRows)
        self.table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.table.setWordWrap(False)
        self.table.horizontalHeader().setStretchLastSection(True)
        self.table.verticalHeader().setDefaultSectionSize(30)
        self.table.verticalHeader().hide()
        for column, width in enumerate((198, 100, 100, 90)):
            self.table.setColumnWidth(column, width)
        self.table.setToolTip("点击日志行查看详情，也可按 Enter 打开")
        self.table.itemClicked.connect(self._show_log_details)
        self.table.itemActivated.connect(self._show_log_details)

        actions = QHBoxLayout()
        actions.setSpacing(10)
        self.pause_button = QPushButton("暂停滚动", icon="pause")
        self.pause_button.setCheckable(True)
        self.pause_button.toggled.connect(self.pause_auto_scroll)
        self.latest_button = QPushButton("跳到最新", icon="latest")
        self.latest_button.clicked.connect(self.jump_to_latest)
        self.copy_button = QPushButton("复制选中", icon="copy")
        self.copy_button.clicked.connect(self.copy_selected)
        self.clear_button = QPushButton("清空视图", icon="clear")
        self.clear_button.clicked.connect(self.clear_view)
        self.export_button = QPushButton("导出筛选结果", icon="download")
        self.export_button.clicked.connect(self._choose_export)
        for button in (
            self.pause_button,
            self.latest_button,
            self.copy_button,
            self.clear_button,
            self.export_button,
        ):
            actions.addWidget(button)
        actions.addStretch(1)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(14, 10, 14, 10)
        layout.setSpacing(8)
        layout.addLayout(filters)
        layout.addLayout(time_filters)
        layout.addWidget(self.validation_label)
        layout.addWidget(self.table, 1)
        layout.addLayout(actions)

    @property
    def visible_entries(self) -> tuple[LogEntry, ...]:
        return tuple(self._visible)

    @property
    def auto_scroll_paused(self) -> bool:
        return self._auto_scroll_paused

    @property
    def pending_live_count(self) -> int:
        return sum(len(entries) for entries in self._pending_live.values())

    def set_query(self, query: LogQuery) -> None:
        if self._fixed_sources:
            query = replace(query, sources=self._fixed_sources)
        self._query = query
        self._live_regex_key = None
        self._live_regex = None
        self._live_regex_timed_out = False
        self.keyword_edit.setText(query.keyword)
        self.case_checkbox.setChecked(query.case_sensitive)
        self.regex_checkbox.setChecked(query.match_mode is LogMatchMode.REGEX)
        self.reload_history()

    def reload_history(self) -> None:
        if self._shutting_down:
            return
        for cancellation in self._search_cancellations.values():
            cancellation.set()
        self._search_generation += 1
        generation = self._search_generation
        query = self._query
        self._active_searches.add(generation)
        self._pending_live[generation] = []
        cancellation = threading.Event()
        self._search_cancellations[generation] = cancellation
        self.search_button.setEnabled(False)
        worker = TaskWorker(lambda: self._store.search(query, cancel_event=cancellation))
        self._workers.add(worker)
        worker.signals.result.connect(lambda result: self._search_completed(worker, generation, result))
        worker.signals.error.connect(lambda message: self._search_failed(worker, generation, message))
        worker.signals.finished.connect(lambda: self._discard_worker(worker))
        worker.start(self._pool)

    def _search_completed(self, worker: TaskWorker, generation: int, result: LogSearchResult) -> None:
        self._discard_worker(worker)
        self._active_searches.discard(generation)
        self._search_cancellations.pop(generation, None)
        pending = self._pending_live.pop(generation, [])
        if self._shutting_down or generation != self._search_generation or result.cancelled:
            return
        self.search_button.setEnabled(True)
        if result.validation_error:
            self.validation_label.setText(result.validation_error)
            self.validation_label.show()
            self._visible = []
        else:
            warnings: list[str] = []
            if result.timed_out:
                warnings.append("日志检索达到时间上限，当前仅显示已扫描到的匹配记录")
            elif result.scan_limited:
                warnings.append("日志检索达到扫描上限，当前仅显示最近候选记录中的匹配结果")
            elif result.result_limited:
                warnings.append("日志检索达到内存上限，当前仅显示已收集的匹配记录")
            if self._live_regex_timed_out:
                warnings.append(LIVE_REGEX_TIMEOUT_WARNING)
            if warnings:
                self.validation_label.setText("；".join(warnings))
                self.validation_label.show()
            else:
                self.validation_label.hide()
            self._visible = list(reversed(result.entries[-MAX_VISIBLE_ROWS:]))
            fingerprints = {_entry_fingerprint(entry) for entry in self._visible}
            for entry in pending:
                fingerprint = _entry_fingerprint(entry)
                if fingerprint not in fingerprints:
                    self._visible.append(entry)
                    fingerprints.add(fingerprint)
            if len(self._visible) > MAX_VISIBLE_ROWS:
                self._visible = self._visible[-MAX_VISIBLE_ROWS:]
        self._render()

    def _search_failed(self, worker: TaskWorker, generation: int, message: str) -> None:
        self._discard_worker(worker)
        self._active_searches.discard(generation)
        self._search_cancellations.pop(generation, None)
        self._pending_live.pop(generation, None)
        if generation != self._search_generation:
            return
        self.search_button.setEnabled(True)
        self.validation_label.setText(message)
        self.validation_label.show()

    def _discard_worker(self, worker: TaskWorker) -> None:
        self._workers.discard(worker)

    def append_live(self, entries: LogEntry | list[LogEntry] | tuple[LogEntry, ...]) -> None:
        incoming = (entries,) if isinstance(entries, LogEntry) else tuple(entries)
        matched: list[LogEntry] = []
        live_regex = self._live_regex_for_query(self._query)
        for entry in incoming:
            safe = _safe_entry(entry)
            try:
                is_match = _matches_query(safe, self._query, self._fixed_sources, live_regex=live_regex)
            except TimeoutError:
                self._live_regex_timed_out = True
                self.validation_label.setText(LIVE_REGEX_TIMEOUT_WARNING)
                self.validation_label.show()
                live_regex = None
                is_match = False
            if is_match:
                matched.append(safe)
        if not matched:
            return
        if self._search_generation in self._active_searches:
            pending = self._pending_live[self._search_generation]
            pending.extend(matched)
            if len(pending) > MAX_VISIBLE_ROWS:
                del pending[: len(pending) - MAX_VISIBLE_ROWS]

        self.table.setUpdatesEnabled(False)
        for entry in matched:
            self._visible.append(entry)
            row = self.table.rowCount()
            self.table.insertRow(row)
            self._populate_row(row, entry)
        excess = max(0, len(self._visible) - MAX_VISIBLE_ROWS)
        if excess:
            del self._visible[:excess]
            for _ in range(excess):
                self.table.removeRow(0)
        self.table.setUpdatesEnabled(True)
        if not self._auto_scroll_paused:
            self.table.scrollToBottom()

    def _live_regex_for_query(self, query: LogQuery) -> SafeLogRegex | None:
        if not query.keyword or query.match_mode is not LogMatchMode.REGEX:
            return None
        key = (query.keyword, query.case_sensitive)
        if self._live_regex_key != key:
            self._live_regex_key = key
            self._live_regex, _validation_error = compile_log_regex(
                query.keyword,
                case_sensitive=query.case_sensitive,
            )
            self._live_regex_timed_out = False
        if self._live_regex_timed_out:
            return None
        return self._live_regex

    def pause_auto_scroll(self, paused: bool) -> None:
        self._auto_scroll_paused = paused
        if self.pause_button.isChecked() != paused:
            self.pause_button.setChecked(paused)

    def jump_to_latest(self) -> None:
        self.pause_auto_scroll(False)
        self.table.scrollToBottom()

    def clear_view(self) -> None:
        self._visible.clear()
        self._render()

    def copy_selected(self) -> None:
        rows = sorted({index.row() for index in self.table.selectedIndexes()})
        lines: list[str] = []
        for row in rows:
            values = [self.table.item(row, column).text() for column in range(self.table.columnCount())]
            lines.append("\t".join(values))
        QApplication.clipboard().setText("\n".join(lines))

    def _show_log_details(self, item: QTableWidgetItem) -> None:
        if self._shutting_down:
            return
        entry = item.data(Qt.UserRole + 1)
        if not isinstance(entry, LogEntry):
            return
        if self._detail_dialog is not None:
            self._detail_dialog.raise_()
            self._detail_dialog.activateWindow()
            return
        dialog = LogDetailDialog(entry, source_label=_SOURCE_LABELS[entry.source], parent=self)
        self._detail_dialog = dialog
        dialog.finished.connect(lambda _result: self._forget_log_details(dialog))
        dialog.open()

    def _forget_log_details(self, dialog: LogDetailDialog) -> None:
        if self._detail_dialog is dialog:
            self._detail_dialog = None

    def export_filtered(self, path: Path) -> int:
        count, validation_error = self._write_export(path)
        if validation_error:
            self.validation_label.setText(validation_error)
            self.validation_label.show()
        return count

    def _write_export(
        self,
        path: Path,
        cancellation: threading.Event | None = None,
    ) -> tuple[int, str | None]:
        if cancellation is not None and cancellation.is_set():
            return 0, "日志导出已取消"
        result = self._store.search(replace(self._query, limit=50_000), cancel_event=cancellation)
        if result.validation_error:
            return 0, result.validation_error
        if result.cancelled:
            return 0, "日志导出已取消"
        if result.timed_out:
            return 0, "日志导出超过时间上限，已取消"
        destination = Path(path)
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_name(f".{destination.name}.{threading.get_ident()}.tmp")
        try:
            with temporary.open("w", encoding="utf-8-sig", newline="") as handle:
                writer = csv.writer(handle)
                writer.writerow(("occurred_at_utc", "source", "level", "stream", "message"))
                for entry in reversed(result.entries):
                    if cancellation is not None and cancellation.is_set():
                        return 0, "日志导出已取消"
                    writer.writerow(
                        (
                            entry.occurred_at.astimezone(UTC).isoformat(),
                            entry.source.value,
                            entry.level.value,
                            entry.stream,
                            redact_log_text(entry.message),
                        )
                    )
            if cancellation is not None and cancellation.is_set():
                return 0, "日志导出已取消"
            os.replace(temporary, destination)
        finally:
            temporary.unlink(missing_ok=True)
        if result.result_limited:
            warning = "日志导出达到内存上限，仅包含已收集的匹配记录"
        elif result.scan_limited:
            warning = "日志数量较多，导出仅包含扫描上限内的匹配记录"
        else:
            warning = None
        return len(result.entries), warning

    def _query_from_controls(self) -> None:
        source = self.source_combo.currentData()
        level = self.level_combo.currentData()
        sources = self._fixed_sources or ((source,) if isinstance(source, LogSource) else ())
        levels = (level,) if isinstance(level, LogLevel) else ()
        started_at = self.start_edit.dateTime().toPython().astimezone() if self.start_checkbox.isChecked() else None
        ended_at = self.end_edit.dateTime().toPython().astimezone() if self.end_checkbox.isChecked() else None
        self.set_query(
            LogQuery(
                keyword=self.keyword_edit.text(),
                sources=sources,
                levels=levels,
                started_at=started_at,
                ended_at=ended_at,
                case_sensitive=self.case_checkbox.isChecked(),
                match_mode=LogMatchMode.REGEX if self.regex_checkbox.isChecked() else LogMatchMode.PLAIN,
            )
        )

    def _choose_export(self) -> None:
        selected, _filter = QFileDialog.getSaveFileName(self, "导出当前日志", "opc-runtime-logs.csv", "CSV (*.csv)")
        if not selected:
            return
        self._start_export(Path(selected))

    def _start_export(self, path: Path) -> bool:
        if self._shutting_down:
            return False
        self.export_button.setEnabled(False)
        cancellation = threading.Event()
        self._export_cancellations.add(cancellation)
        worker = TaskWorker(lambda: self._write_export(path, cancellation))
        self._workers.add(worker)
        worker.signals.result.connect(lambda outcome: self._export_completed(outcome))
        worker.signals.error.connect(self._export_failed)
        worker.signals.finished.connect(lambda: self._export_finished(worker, cancellation))
        worker.start(self._pool)
        return True

    def _export_finished(self, worker: TaskWorker, cancellation: threading.Event) -> None:
        self._discard_worker(worker)
        self._export_cancellations.discard(cancellation)

    def _export_failed(self, message: str) -> None:
        self.export_button.setEnabled(True)
        self.validation_label.setText(message)
        self.validation_label.show()

    def _export_completed(self, outcome: tuple[int, str | None]) -> None:
        _count, validation_error = outcome
        self.export_button.setEnabled(True)
        if validation_error:
            self.validation_label.setText(validation_error)
            self.validation_label.show()

    def shutdown(self, timeout_ms: int = 5_000) -> bool:
        if timeout_ms < 0:
            raise ValueError("停止等待时间不能为负数")
        self._shutting_down = True
        if self._detail_dialog is not None:
            self._detail_dialog.close()
        for cancellation in self._search_cancellations.values():
            cancellation.set()
        for cancellation in self._export_cancellations:
            cancellation.set()
        return self._pool.waitForDone(timeout_ms)

    def _render(self) -> None:
        self.table.setUpdatesEnabled(False)
        self.table.setRowCount(len(self._visible))
        for row, entry in enumerate(self._visible):
            self._populate_row(row, entry)
        self.table.setUpdatesEnabled(True)
        if not self._auto_scroll_paused:
            self.table.scrollToBottom()

    def _populate_row(self, row: int, entry: LogEntry) -> None:
        values = (
            entry.occurred_at.astimezone(UTC).isoformat(timespec="milliseconds").replace("T", " ").removesuffix("+00:00"),
            _SOURCE_LABELS[entry.source],
            _LEVEL_LABELS[entry.level],
            entry.stream,
            entry.message,
        )
        for column, value in enumerate(values):
            item = QTableWidgetItem(value)
            item.setData(Qt.UserRole, entry.entry_id)
            item.setData(Qt.UserRole + 1, entry)
            self.table.setItem(row, column, item)


def _safe_entry(entry: LogEntry) -> LogEntry:
    safe = make_log_entry(
        source=entry.source,
        stream=entry.stream,
        text=entry.message,
        occurred_at=entry.occurred_at,
        pid=entry.pid,
    )
    return replace(safe, level=entry.level, entry_id=entry.entry_id, truncated=entry.truncated or safe.truncated)


def _entry_fingerprint(entry: LogEntry) -> tuple[object, ...]:
    return (
        entry.occurred_at,
        entry.source,
        entry.level,
        entry.stream,
        entry.message,
        entry.pid,
    )


def _matches_query(
    entry: LogEntry,
    query: LogQuery,
    fixed_sources: tuple[LogSource, ...],
    *,
    live_regex: SafeLogRegex | None = None,
) -> bool:
    sources = fixed_sources or query.sources
    if sources and entry.source not in sources:
        return False
    if query.levels and entry.level not in query.levels:
        return False
    timestamp = entry.occurred_at.astimezone(UTC)
    if query.started_at is not None and timestamp < _utc(query.started_at):
        return False
    if query.ended_at is not None and timestamp > _utc(query.ended_at):
        return False
    if not query.keyword:
        return True
    if query.match_mode is LogMatchMode.REGEX:
        return live_regex is not None and live_regex.matches(
            entry.message,
            timeout_seconds=LIVE_REGEX_TIMEOUT_SECONDS,
        )
    message = entry.message if query.case_sensitive else entry.message.casefold()
    keyword = query.keyword if query.case_sensitive else query.keyword.casefold()
    return keyword in message


def _utc(value: datetime) -> datetime:
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)

