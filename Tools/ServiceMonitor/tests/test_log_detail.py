from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path

import pytest
from PySide6.QtCore import Qt
from PySide6.QtWidgets import QApplication

import opc_service_monitor.ui.log_panel as log_panel_module
from opc_service_monitor.log_store import LogStore
from opc_service_monitor.models import LogEntry, LogLevel, LogSource
from opc_service_monitor.ui.log_detail_dialog import LogDetailDialog
from opc_service_monitor.ui.log_panel import LogPanel


@pytest.fixture
def detail_panel(tmp_path: Path, qtbot):
    created: list[tuple[LogPanel, LogStore]] = []

    def create(*, fixed_sources: tuple[LogSource, ...] = ()) -> LogPanel:
        store = LogStore.open(tmp_path / f"detail-{len(created)}.sqlite3")
        panel = LogPanel(store, fixed_sources=fixed_sources)
        qtbot.addWidget(panel)
        panel.resize(1200, 560)
        panel.show()
        created.append((panel, store))
        return panel

    yield create

    for panel, store in created:
        panel.shutdown()
        panel.close()
        store.close()


def _entry(message: str, *, source: LogSource = LogSource.POSTGRES, truncated: bool = False) -> LogEntry:
    return LogEntry(
        datetime(2026, 10, 25, 9, 38, tzinfo=UTC), source, LogLevel.INFO, "file", message,
        entry_id=37, pid=1234, truncated=truncated,
    )


def _click_message(panel: LogPanel, qtbot, row: int = 0) -> LogDetailDialog:
    item = panel.table.item(row, 4)
    assert item is not None
    panel.table.scrollToItem(item)
    qtbot.mouseClick(panel.table.viewport(), Qt.LeftButton, pos=panel.table.visualItemRect(item).center())
    qtbot.waitUntil(lambda: panel._detail_dialog is not None and panel._detail_dialog.isVisible())
    return panel._detail_dialog


@pytest.mark.parametrize("fixed_sources,source", [
    ((), LogSource.POSTGRES),
    ((LogSource.FRONTEND,), LogSource.FRONTEND),
    ((LogSource.BACKEND,), LogSource.BACKEND),
    ((LogSource.POSTGRES,), LogSource.POSTGRES),
])
def test_click_message_opens_complete_plaintext_in_each_runtime_tab(detail_panel, qtbot, fixed_sources, source):
    panel = detail_panel(fixed_sources=fixed_sources)
    message = "数据库检查完成：" + "中文详细信息" * 150 + "\n<b>这只是日志原文</b>\n最后一行"
    panel.append_live(_entry(message, source=source))

    dialog = _click_message(panel, qtbot)

    assert dialog.message_edit.isReadOnly()
    assert dialog.message_edit.toPlainText() == message
    assert dialog.entry.source is source
    assert dialog.entry.entry_id == 37
    assert dialog.entry.pid == 1234
    assert dialog.windowModality() == Qt.WindowModal


def test_enter_activates_selected_log_without_duplicate_detail_windows(detail_panel, qtbot):
    panel = detail_panel()
    panel.append_live(_entry("键盘查看详情"))
    panel.table.setCurrentCell(0, 4)
    panel.table.setFocus()

    qtbot.keyClick(panel.table, Qt.Key_Return)

    qtbot.waitUntil(lambda: panel._detail_dialog is not None and panel._detail_dialog.isVisible())
    dialog = panel._detail_dialog
    panel.table.itemActivated.emit(panel.table.item(0, 4))
    assert panel._detail_dialog is dialog
    assert len(panel.findChildren(LogDetailDialog)) == 1
    assert dialog.message_edit.toPlainText() == "键盘查看详情"


def test_open_detail_remains_snapshot_when_rows_roll_over_and_view_is_cleared(detail_panel, qtbot, monkeypatch):
    monkeypatch.setattr(log_panel_module, "MAX_VISIBLE_ROWS", 2)
    panel = detail_panel()
    panel.append_live(_entry("正在查看的原记录"))
    dialog = _click_message(panel, qtbot)

    panel.append_live([_entry("后续记录一"), _entry("后续记录二")])
    assert [entry.message for entry in panel.visible_entries] == ["后续记录一", "后续记录二"]
    panel.clear_view()

    assert dialog.isVisible()
    assert dialog.entry.message == "正在查看的原记录"
    assert dialog.message_edit.toPlainText() == "正在查看的原记录"


def test_detail_display_and_both_copy_actions_redact_direct_unsafe_entry(qtbot):
    unsafe = _entry("Authorization: Bearer detail-token\nOPENAI_API_KEY=detail-key\n正常中文消息")
    dialog = LogDetailDialog(unsafe, source_label="PostgreSQL")
    qtbot.addWidget(dialog)
    dialog.show()

    assert "detail-token" not in dialog.entry.message
    assert "detail-key" not in dialog.message_edit.toPlainText()
    assert "[REDACTED]" in dialog.message_edit.toPlainText()

    for button in (dialog.copy_message_button, dialog.copy_all_button):
        qtbot.mouseClick(button, Qt.LeftButton)
        copied = QApplication.clipboard().text()
        assert "detail-token" not in copied
        assert "detail-key" not in copied
        assert "正常中文消息" in copied
        assert "[REDACTED]" in copied


def test_existing_collection_truncation_is_disclosed_in_detail(detail_panel, qtbot):
    panel = detail_panel()
    panel.append_live(_entry("已保留的日志片段", truncated=True))

    dialog = _click_message(panel, qtbot)

    assert dialog.entry.truncated
    assert dialog.truncation_label.isVisible()
    assert "采集" in dialog.truncation_label.text()
    assert "截断" in dialog.truncation_label.text() or "长度上限" in dialog.truncation_label.text()
    assert dialog.message_edit.toPlainText() == "已保留的日志片段"


def test_escape_allows_reopening_and_shutdown_closes_detail(detail_panel, qtbot):
    panel = detail_panel()
    panel.append_live(_entry("关闭后重新查看"))
    dialog = _click_message(panel, qtbot)

    qtbot.keyClick(dialog, Qt.Key_Escape)
    qtbot.waitUntil(lambda: not dialog.isVisible())
    reopened = _click_message(panel, qtbot)
    assert reopened.message_edit.toPlainText() == "关闭后重新查看"

    assert panel.shutdown()
    qtbot.waitUntil(lambda: not reopened.isVisible())
