from __future__ import annotations

import threading
import time
from datetime import UTC, datetime, timedelta
from pathlib import Path

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QApplication

import opc_service_monitor.ui.log_panel as log_panel_module
from opc_service_monitor.log_pipeline import make_log_entry
from opc_service_monitor.log_store import LogMatchMode, LogQuery, LogSearchResult, LogStore
from opc_service_monitor.models import LogEntry, LogLevel, LogSource
from opc_service_monitor.ui.log_panel import LogPanel


def _entry(
    message: str,
    *,
    source: LogSource,
    when: datetime,
    level: LogLevel | None = None,
) -> LogEntry:
    entry = make_log_entry(source=source, stream="stdout", text=message, occurred_at=when)
    if level is None:
        return entry
    return LogEntry(when, source, level, "stdout", entry.message)


def test_source_tabs_isolate_entries_and_all_merges(tmp_path: Path, qtbot) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    now = datetime.now(UTC)
    store.append(
        [
            _entry("frontend", source=LogSource.FRONTEND, when=now),
            _entry("backend", source=LogSource.BACKEND, when=now),
            _entry("postgres", source=LogSource.POSTGRES, when=now),
        ]
    )
    all_panel = LogPanel(store)
    frontend_panel = LogPanel(store, fixed_sources=(LogSource.FRONTEND,))
    qtbot.addWidget(all_panel)
    qtbot.addWidget(frontend_panel)
    try:
        all_panel.reload_history()
        frontend_panel.reload_history()

        qtbot.waitUntil(lambda: len(all_panel.visible_entries) == 3)
        qtbot.waitUntil(lambda: len(frontend_panel.visible_entries) == 1)
        assert {entry.message for entry in all_panel.visible_entries} == {"frontend", "backend", "postgres"}
        assert [entry.message for entry in frontend_panel.visible_entries] == ["frontend"]
    finally:
        store.close()


def test_filters_cover_time_level_source_keyword_case_and_regex(tmp_path: Path, qtbot) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    base = datetime(2026, 10, 22, 12, tzinfo=UTC)
    store.append(
        [
            _entry("Backend READY", source=LogSource.BACKEND, when=base, level=LogLevel.INFO),
            _entry("backend warning", source=LogSource.BACKEND, when=base + timedelta(minutes=1), level=LogLevel.WARNING),
            _entry("frontend ready", source=LogSource.FRONTEND, when=base + timedelta(minutes=2)),
        ]
    )
    panel = LogPanel(store)
    qtbot.addWidget(panel)
    try:
        panel.set_query(
            LogQuery(
                keyword="Backend",
                sources=(LogSource.BACKEND,),
                levels=(LogLevel.INFO,),
                started_at=base - timedelta(seconds=1),
                ended_at=base + timedelta(seconds=1),
                case_sensitive=True,
            )
        )
        qtbot.waitUntil(lambda: panel.search_button.isEnabled())
        assert [entry.message for entry in panel.visible_entries] == ["Backend READY"]

        panel.set_query(LogQuery(keyword=r"backend\s+w.*", match_mode=LogMatchMode.REGEX))
        qtbot.waitUntil(lambda: panel.search_button.isEnabled())
        assert [entry.message for entry in panel.visible_entries] == ["backend warning"]

        panel.set_query(LogQuery(keyword="[", match_mode=LogMatchMode.REGEX))
        qtbot.waitUntil(lambda: panel.search_button.isEnabled())
        assert panel.visible_entries == ()
        assert "正则" in panel.validation_label.text()
    finally:
        store.close()


def test_pause_jump_latest_cap_clear_and_copy_do_not_delete_history(tmp_path: Path, qtbot) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    panel = LogPanel(store)
    qtbot.addWidget(panel)
    now = datetime.now(UTC)
    store.append([_entry("persisted", source=LogSource.BACKEND, when=now)])
    try:
        panel.pause_auto_scroll(True)
        assert panel.auto_scroll_paused is True
        panel.append_live(
            [_entry(f"line-{index}", source=LogSource.BACKEND, when=now + timedelta(microseconds=index)) for index in range(5_100)]
        )
        assert len(panel.visible_entries) == 5_000
        assert panel.visible_entries[0].message == "line-100"

        panel.jump_to_latest()
        assert panel.auto_scroll_paused is False
        panel.table.selectRow(panel.table.rowCount() - 1)
        panel.copy_selected()
        assert "line-5099" in QApplication.clipboard().text()

        panel.clear_view()
        assert panel.visible_entries == ()
        assert [entry.message for entry in store.search(LogQuery(keyword="persisted")).entries] == ["persisted"]
    finally:
        store.close()


def test_copy_redacts_api_key_from_direct_live_entry(tmp_path: Path, qtbot) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    panel = LogPanel(store)
    qtbot.addWidget(panel)
    now = datetime.now(UTC)
    unsafe = LogEntry(now, LogSource.BACKEND, LogLevel.INFO, "stdout", "run --api_key copy-secret")
    try:
        panel.append_live(unsafe)
        panel.table.selectRow(0)
        panel.copy_selected()

        copied = QApplication.clipboard().text()
        assert "copy-secret" not in copied
        assert "--api_key [REDACTED]" in copied
    finally:
        store.close()


def test_copy_redacts_prefixed_secret_key_from_direct_live_entry(tmp_path: Path, qtbot) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    panel = LogPanel(store)
    qtbot.addWidget(panel)
    now = datetime.now(UTC)
    unsafe = LogEntry(now, LogSource.BACKEND, LogLevel.INFO, "stdout", "OPENAI_API_KEY=ui-secret")
    try:
        panel.append_live(unsafe)
        panel.table.selectRow(0)
        panel.copy_selected()

        copied = QApplication.clipboard().text()
        assert "ui-secret" not in copied
        assert "OPENAI_API_KEY=[REDACTED]" in copied
    finally:
        store.close()


def test_live_regex_is_compiled_once_and_does_not_use_stdlib_re(tmp_path: Path, qtbot, monkeypatch) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    panel = LogPanel(store)
    qtbot.addWidget(panel)
    now = datetime.now(UTC)
    compile_calls = 0
    real_compile = log_panel_module.compile_log_regex

    def counting_compile(pattern: str, *, case_sensitive: bool):
        nonlocal compile_calls
        compile_calls += 1
        return real_compile(pattern, case_sensitive=case_sensitive)

    monkeypatch.setattr(log_panel_module, "compile_log_regex", counting_compile)
    try:
        panel.set_query(LogQuery(keyword=r"live-\d+", match_mode=LogMatchMode.REGEX))
        qtbot.waitUntil(lambda: panel.search_button.isEnabled())
        panel.append_live(
            [
                _entry("live-1", source=LogSource.BACKEND, when=now),
                _entry("live-2", source=LogSource.BACKEND, when=now),
            ]
        )
        panel.append_live(_entry("live-3", source=LogSource.BACKEND, when=now))

        assert [entry.message for entry in panel.visible_entries] == ["live-1", "live-2", "live-3"]
        assert compile_calls == 1
    finally:
        store.close()


def test_dangerous_and_invalid_live_regex_patterns_do_not_match(tmp_path: Path, qtbot) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    panel = LogPanel(store)
    qtbot.addWidget(panel)
    now = datetime.now(UTC)
    try:
        for keyword in (r"(a+)+$", "["):
            panel.set_query(LogQuery(keyword=keyword, match_mode=LogMatchMode.REGEX))
            qtbot.waitUntil(lambda: panel.search_button.isEnabled())
            panel.append_live(_entry("a" * 10_000 + "!", source=LogSource.BACKEND, when=now))
            assert panel.visible_entries == ()
    finally:
        store.close()


def test_live_regex_timeout_disables_matching_until_query_changes(tmp_path: Path, qtbot, monkeypatch) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    panel = LogPanel(store)
    qtbot.addWidget(panel)
    now = datetime.now(UTC)

    class TimeoutRegex:
        calls = 0

        def matches(self, _text: str, *, timeout_seconds: float) -> bool:
            assert 0 < timeout_seconds <= 0.05
            self.calls += 1
            raise TimeoutError("regex timed out")

    class MatchingRegex:
        def matches(self, text: str, *, timeout_seconds: float) -> bool:
            assert 0 < timeout_seconds <= 0.05
            return text == "recovered-1"

    timeout_regex = TimeoutRegex()

    def compile_for_query(pattern: str, *, case_sensitive: bool):
        assert case_sensitive is False
        if pattern == r"live.*":
            return timeout_regex, None
        return MatchingRegex(), None

    monkeypatch.setattr(
        log_panel_module,
        "compile_log_regex",
        compile_for_query,
    )
    try:
        panel.set_query(LogQuery(keyword=r"live.*", match_mode=LogMatchMode.REGEX))
        qtbot.waitUntil(lambda: panel.search_button.isEnabled())
        panel.append_live(
            [
                _entry("live-1", source=LogSource.BACKEND, when=now),
                _entry("live-2", source=LogSource.BACKEND, when=now),
            ]
        )
        panel.append_live(_entry("live-3", source=LogSource.BACKEND, when=now))

        assert panel.visible_entries == ()
        assert timeout_regex.calls == 1
        assert not panel.validation_label.isHidden()
        assert "实时" in panel.validation_label.text()
        assert "不完整" in panel.validation_label.text()

        panel.set_query(LogQuery(keyword=r"recovered.*", match_mode=LogMatchMode.REGEX))
        qtbot.waitUntil(lambda: panel.search_button.isEnabled())
        panel.append_live(_entry("recovered-1", source=LogSource.BACKEND, when=now))

        assert [entry.message for entry in panel.visible_entries] == ["recovered-1"]
        assert panel.validation_label.isHidden()
    finally:
        store.close()


def test_single_live_entry_appends_rows_without_rebuilding_existing_table(tmp_path: Path, qtbot, monkeypatch) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    panel = LogPanel(store)
    qtbot.addWidget(panel)
    now = datetime.now(UTC)
    try:
        panel.append_live(_entry("first", source=LogSource.BACKEND, when=now))
        monkeypatch.setattr(panel, "_render", lambda: (_ for _ in ()).throw(AssertionError("full rebuild")))

        panel.append_live(_entry("second", source=LogSource.BACKEND, when=now + timedelta(seconds=1)))

        assert [entry.message for entry in panel.visible_entries] == ["first", "second"]
        assert panel.table.rowCount() == 2
        assert panel.table.item(1, 4).text() == "second"
    finally:
        store.close()


def test_history_search_runs_off_the_gui_thread(qtbot) -> None:
    entered = threading.Event()
    release = threading.Event()

    class BlockingStore:
        def search(self, _query, *, cancel_event=None):
            entered.set()
            assert release.wait(2)
            return LogSearchResult(())

    panel = LogPanel(BlockingStore())  # type: ignore[arg-type]
    qtbot.addWidget(panel)
    started = time.monotonic()
    try:
        panel.reload_history()
        assert time.monotonic() - started < 0.2
        assert entered.wait(1)
    finally:
        release.set()
        qtbot.waitUntil(lambda: panel.search_button.isEnabled())


def test_pending_live_rows_are_capped_while_search_is_running(qtbot) -> None:
    entered = threading.Event()
    release = threading.Event()

    class BlockingStore:
        def search(self, _query, *, cancel_event=None):
            entered.set()
            assert release.wait(3)
            return LogSearchResult(())

    panel = LogPanel(BlockingStore())  # type: ignore[arg-type]
    qtbot.addWidget(panel)
    now = datetime.now(UTC)
    try:
        panel.reload_history()
        assert entered.wait(1)
        panel.append_live(
            [_entry(f"pending-{index}", source=LogSource.BACKEND, when=now) for index in range(5_250)]
        )

        assert panel.pending_live_count == 5_000
        release.set()
        qtbot.waitUntil(lambda: panel.search_button.isEnabled())
        assert len(panel.visible_entries) == 5_000
        assert panel.visible_entries[0].message == "pending-250"
    finally:
        release.set()
        panel.shutdown()


def test_shutdown_cancels_and_drains_search_before_store_can_close(qtbot) -> None:
    entered = threading.Event()
    finished = threading.Event()

    class CancellableStore:
        def __init__(self) -> None:
            self.closed = False

        def search(self, _query, *, cancel_event=None):
            entered.set()
            assert cancel_event is not None
            assert cancel_event.wait(2)
            assert not self.closed
            finished.set()
            return LogSearchResult((), cancelled=True)

        def close(self) -> None:
            assert finished.is_set()
            self.closed = True

    store = CancellableStore()
    panel = LogPanel(store)  # type: ignore[arg-type]
    qtbot.addWidget(panel)
    panel.reload_history()
    assert entered.wait(1)

    assert panel.shutdown(timeout_ms=2_000) is True
    store.close()

    assert store.closed is True


def test_cancelled_export_does_not_publish_a_partial_file(tmp_path: Path, qtbot) -> None:
    now = datetime.now(UTC)

    class StoreIgnoringCancellation:
        def search(self, _query, *, cancel_event=None):
            return LogSearchResult((_entry("row", source=LogSource.BACKEND, when=now),))

    panel = LogPanel(StoreIgnoringCancellation())  # type: ignore[arg-type]
    qtbot.addWidget(panel)
    destination = tmp_path / "cancelled.csv"
    cancelled = threading.Event()
    cancelled.set()

    count, message = panel._write_export(destination, cancelled)

    assert count == 0
    assert message is not None and "取消" in message
    assert not destination.exists()


def test_scan_bound_is_disclosed_without_discarding_matches(qtbot) -> None:
    now = datetime.now(UTC)

    class BoundedStore:
        def search(self, _query, *, cancel_event=None):
            return LogSearchResult(
                (_entry("matched", source=LogSource.BACKEND, when=now),),
                scanned_rows=100,
                scan_limited=True,
            )

    panel = LogPanel(BoundedStore())  # type: ignore[arg-type]
    qtbot.addWidget(panel)
    try:
        panel.reload_history()
        qtbot.waitUntil(lambda: panel.search_button.isEnabled())

        assert [entry.message for entry in panel.visible_entries] == ["matched"]
        assert not panel.validation_label.isHidden()
        assert "扫描上限" in panel.validation_label.text()
    finally:
        panel.shutdown()


def test_result_text_bound_is_disclosed_for_history_and_export(tmp_path: Path, qtbot) -> None:
    now = datetime.now(UTC)

    class ResultBoundedStore:
        def search(self, _query, *, cancel_event=None):
            return LogSearchResult(
                (_entry("matched", source=LogSource.BACKEND, when=now),),
                scanned_rows=2,
                result_limited=True,
            )

    panel = LogPanel(ResultBoundedStore())  # type: ignore[arg-type]
    qtbot.addWidget(panel)
    destination = tmp_path / "bounded.csv"
    try:
        panel.reload_history()
        qtbot.waitUntil(lambda: panel.search_button.isEnabled())

        assert [entry.message for entry in panel.visible_entries] == ["matched"]
        assert "内存上限" in panel.validation_label.text()

        count, warning = panel._write_export(destination)
        assert count == 1
        assert warning is not None and "内存上限" in warning
        assert destination.is_file()
    finally:
        panel.shutdown()


def test_export_uses_current_filter_and_redacts_again(tmp_path: Path, qtbot) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    now = datetime.now(UTC)
    unsafe = LogEntry(now, LogSource.BACKEND, LogLevel.INFO, "stdout", "X-API-Key: export-secret")
    store.append([unsafe, _entry("other", source=LogSource.FRONTEND, when=now)])
    panel = LogPanel(store, fixed_sources=(LogSource.BACKEND,))
    qtbot.addWidget(panel)
    destination = tmp_path / "export.csv"
    try:
        panel.export_filtered(destination)
        exported = destination.read_text(encoding="utf-8-sig")
        assert "export-secret" not in exported
        assert "[REDACTED]" in exported
        assert "other" not in exported
    finally:
        store.close()


def test_widget_controls_drive_regex_and_case_query(tmp_path: Path, qtbot) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    panel = LogPanel(store)
    qtbot.addWidget(panel)
    now = datetime.now(UTC)
    store.append([_entry("CaseSensitive", source=LogSource.BACKEND, when=now)])
    try:
        panel.keyword_edit.setText("casesensitive")
        panel.case_checkbox.setChecked(True)
        qtbot.mouseClick(panel.search_button, Qt.LeftButton)
        qtbot.waitUntil(lambda: panel.search_button.isEnabled())
        assert panel.visible_entries == ()
        panel.case_checkbox.setChecked(False)
        qtbot.mouseClick(panel.search_button, Qt.LeftButton)
        qtbot.waitUntil(lambda: panel.search_button.isEnabled())
        assert len(panel.visible_entries) == 1
    finally:
        store.close()

