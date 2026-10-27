from __future__ import annotations

from dataclasses import replace
from datetime import UTC

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QApplication, QDialog, QGridLayout, QHBoxLayout, QLabel, QPlainTextEdit, QVBoxLayout

from opc_service_monitor.log_pipeline import make_log_entry, redact_log_text
from opc_service_monitor.models import LogEntry
from opc_service_monitor.ui.components import ConsoleButton


class LogDetailDialog(QDialog):
    """Read-only snapshot of the captured log, independent of table updates."""

    def __init__(self, entry: LogEntry, *, source_label: str, parent=None) -> None:
        super().__init__(parent)
        safe = make_log_entry(
            source=entry.source, stream=entry.stream, text=entry.message,
            occurred_at=entry.occurred_at, pid=entry.pid,
        )
        self.entry = replace(entry, message=safe.message, truncated=entry.truncated or safe.truncated)
        self.setWindowTitle("日志详情")
        self.setObjectName("logDetailDialog")
        self.setAttribute(Qt.WA_DeleteOnClose)
        self.setWindowModality(Qt.WindowModal)
        self.resize(860, 560)
        self.setMinimumSize(600, 380)

        heading = QLabel("日志详情")
        heading.setObjectName("sectionTitle")
        self._fields = (
            ("采集时间 (UTC)", self.entry.occurred_at.astimezone(UTC).isoformat(timespec="milliseconds")),
            ("来源", source_label),
            ("级别", self.entry.level.value.upper()),
            ("输出流", self.entry.stream),
            ("进程 PID", str(self.entry.pid) if self.entry.pid is not None else "未记录"),
            ("日志 ID", str(self.entry.entry_id) if self.entry.entry_id is not None else "实时记录"),
        )
        metadata = QGridLayout()
        metadata.setHorizontalSpacing(14)
        metadata.setVerticalSpacing(7)
        for index, (caption, value) in enumerate(self._fields):
            row, group = divmod(index, 2)
            label = QLabel(caption)
            label.setProperty("tone", "muted")
            content = QLabel(value)
            content.setTextFormat(Qt.PlainText)
            content.setTextInteractionFlags(Qt.TextSelectableByMouse | Qt.TextSelectableByKeyboard)
            content.setWordWrap(True)
            metadata.addWidget(label, row, group * 2)
            metadata.addWidget(content, row, group * 2 + 1)
        metadata.setColumnStretch(1, 2)
        metadata.setColumnStretch(3, 1)

        self.truncation_label = QLabel("此条日志在采集时达到长度上限，详情展示已保存的内容。")
        self.truncation_label.setProperty("tone", "warning")
        self.truncation_label.setWordWrap(True)
        self.truncation_label.setVisible(self.entry.truncated)

        self.message_edit = QPlainTextEdit()
        self.message_edit.setObjectName("logDetailMessage")
        self.message_edit.setAccessibleName("完整日志消息")
        self.message_edit.setReadOnly(True)
        self.message_edit.setPlainText(self.entry.message)
        self.message_edit.setLineWrapMode(QPlainTextEdit.WidgetWidth)

        self.copy_message_button = ConsoleButton("复制消息", icon="copy")
        self.copy_all_button = ConsoleButton("复制全部", icon="copy")
        self.close_button = ConsoleButton("关闭", variant="primary")
        self.copy_message_button.clicked.connect(self.copy_message)
        self.copy_all_button.clicked.connect(self.copy_all)
        self.close_button.clicked.connect(self.accept)
        actions = QHBoxLayout()
        for button in (self.copy_message_button, self.copy_all_button):
            button.setAutoDefault(False)
            actions.addWidget(button)
        actions.addStretch(1)
        self.close_button.setAutoDefault(False)
        actions.addWidget(self.close_button)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(20, 18, 20, 18)
        layout.setSpacing(12)
        layout.addWidget(heading)
        layout.addLayout(metadata)
        layout.addWidget(self.truncation_label)
        layout.addWidget(QLabel("完整消息"))
        layout.addWidget(self.message_edit, 1)
        layout.addLayout(actions)

    def copy_message(self) -> None:
        QApplication.clipboard().setText(redact_log_text(self.entry.message))

    def copy_all(self) -> None:
        metadata = "\n".join(f"{caption}：{value}" for caption, value in self._fields)
        note = "\n采集时已截断" if self.entry.truncated else ""
        QApplication.clipboard().setText(redact_log_text(f"{metadata}{note}\n\n{self.entry.message}"))
