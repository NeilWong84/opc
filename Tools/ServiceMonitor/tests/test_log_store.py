from __future__ import annotations

import sqlite3
import os
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

import opc_service_monitor.log_store as log_store_module
from opc_service_monitor.log_pipeline import make_log_entry
from opc_service_monitor.log_store import LogMatchMode, LogQuery, LogStore
from opc_service_monitor.models import LogEntry, LogLevel, LogSource


def _entry(
    message: str,
    *,
    source: LogSource = LogSource.BACKEND,
    level: LogLevel | None = None,
    occurred_at: datetime | None = None,
) -> LogEntry:
    entry = make_log_entry(
        source=source,
        stream="stdout",
        text=message,
        occurred_at=occurred_at,
    )
    if level is None:
        return entry
    return LogEntry(
        occurred_at=entry.occurred_at,
        source=entry.source,
        level=level,
        stream=entry.stream,
        message=entry.message,
        truncated=entry.truncated,
    )


def test_search_supports_plain_fts_regex_and_case(tmp_path: Path) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    try:
        store.append([_entry("Backend Ready"), _entry("backend waiting"), _entry("frontend ready")])

        plain = store.search(LogQuery(keyword="backend"))
        assert [entry.message for entry in plain.entries] == ["backend waiting", "Backend Ready"]

        case_sensitive = store.search(LogQuery(keyword="Backend", case_sensitive=True))
        assert [entry.message for entry in case_sensitive.entries] == ["Backend Ready"]

        fts = store.search(LogQuery(keyword="frontend ready", match_mode=LogMatchMode.FTS))
        assert [entry.message for entry in fts.entries] == ["frontend ready"]

        regex = store.search(LogQuery(keyword=r"Backend\s+R.*", match_mode=LogMatchMode.REGEX))
        assert [entry.message for entry in regex.entries] == ["Backend Ready"]
    finally:
        store.close()


def test_file_decode_repair_is_exact_scoped_redacted_and_preserves_identity(tmp_path: Path) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    damaged = "\ufffd\ufffd: startup token=private-token"
    safe_old = "\ufffd\ufffd: startup token=[REDACTED]"
    try:
        store.append(
            [
                make_log_entry(source=LogSource.POSTGRES, stream="file", text=damaged, pid=123),
                make_log_entry(source=LogSource.POSTGRES, stream="stdout", text=damaged),
                make_log_entry(source=LogSource.BACKEND, stream="file", text=damaged),
                make_log_entry(source=LogSource.POSTGRES, stream="file", text="healthy"),
            ]
        )
        before = {entry.entry_id: entry for entry in store.search(LogQuery()).entries}
        changed = store.repair_file_messages(
            LogSource.POSTGRES,
            {
                damaged: make_log_entry(
                    source=LogSource.POSTGRES,
                    stream="file",
                    text="日志: ERROR startup token=private-token",
                ),
                "healthy": make_log_entry(source=LogSource.POSTGRES, stream="file", text="changed"),
            },
        )
        assert changed == 1
        after = {entry.entry_id: entry for entry in store.search(LogQuery()).entries}
        assert before.keys() == after.keys()
        for entry_id, entry in after.items():
            previous = before[entry_id]
            if previous.source is LogSource.POSTGRES and previous.stream == "file" and previous.message == safe_old:
                assert entry.message == "日志: ERROR startup token=[REDACTED]"
                assert entry.level is LogLevel.ERROR
                assert entry.pid == previous.pid == 123
                assert entry.occurred_at == previous.occurred_at
            else:
                assert entry == previous
        assert len(store.search(LogQuery(keyword="日志", match_mode=LogMatchMode.FTS)).entries) == 1
        assert store.repair_file_messages(
            LogSource.POSTGRES,
            {safe_old: make_log_entry(source=LogSource.POSTGRES, stream="file", text="still \ufffd")},
        ) == 0
    finally:
        store.close()


def test_search_filters_source_level_and_utc_time(tmp_path: Path) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    base = datetime(2026, 10, 22, 12, 0, tzinfo=UTC)
    try:
        store.append(
            [
                _entry("old", occurred_at=base - timedelta(hours=2)),
                _entry(
                    "database warning",
                    source=LogSource.POSTGRES,
                    level=LogLevel.WARNING,
                    occurred_at=base,
                ),
                _entry("late", occurred_at=base + timedelta(hours=2)),
            ]
        )

        result = store.search(
            LogQuery(
                sources=(LogSource.POSTGRES,),
                levels=(LogLevel.WARNING,),
                started_at=base - timedelta(minutes=1),
                ended_at=base + timedelta(minutes=1),
            )
        )

        assert [entry.message for entry in result.entries] == ["database warning"]
    finally:
        store.close()


def test_invalid_regex_is_a_validation_result(tmp_path: Path) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    try:
        result = store.search(LogQuery(keyword="[", match_mode=LogMatchMode.REGEX))
        assert result.entries == ()
        assert result.validation_error is not None
        assert "正则" in result.validation_error
    finally:
        store.close()


def test_high_risk_regex_is_rejected_before_any_message_evaluation(tmp_path: Path) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    try:
        result = store.search(LogQuery(keyword=r"(a+)+$", match_mode=LogMatchMode.REGEX))

        assert result.entries == ()
        assert result.validation_error is not None
        assert "复杂" in result.validation_error
        assert result.scanned_rows == 0
    finally:
        store.close()


def test_high_risk_regex_is_rejected_before_compilation(monkeypatch) -> None:
    def unexpected_compile(*_args, **_kwargs):
        raise AssertionError("高风险正则不应进入编译器")

    monkeypatch.setattr(log_store_module.safe_regex, "compile", unexpected_compile)

    compiled, validation_error = log_store_module.compile_log_regex(
        r"(a+)+$",
        case_sensitive=False,
    )

    assert compiled is None
    assert validation_error is not None
    assert "复杂" in validation_error


@pytest.mark.parametrize(
    "pattern",
    (
        r"a{999999999}",
        r"a{999999999,}",
        r"a{1,999999999}",
        r"a{,999999999}",
    ),
)
def test_oversized_counted_quantifier_is_rejected_before_compilation(monkeypatch, pattern: str) -> None:
    def unexpected_compile(*_args, **_kwargs):
        raise AssertionError("超大计数量词不应进入编译器")

    monkeypatch.setattr(log_store_module.safe_regex, "compile", unexpected_compile)

    compiled, validation_error = log_store_module.compile_log_regex(pattern, case_sensitive=False)

    assert compiled is None
    assert validation_error is not None
    assert "量词" in validation_error


def test_regex_engine_timeout_is_enforced_inside_one_message(tmp_path: Path, monkeypatch) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    observed_timeouts: list[float] = []

    class TimeoutPattern:
        def search(self, _message: str, *, timeout: float):
            observed_timeouts.append(timeout)
            raise TimeoutError("regex timed out")

    monkeypatch.setattr(log_store_module.safe_regex, "compile", lambda *_args, **_kwargs: TimeoutPattern())
    try:
        store.append([_entry("a" * 1_000)])
        result = store.search(
            LogQuery(
                keyword=r".*a.*b",
                match_mode=LogMatchMode.REGEX,
                timeout_seconds=0.05,
                scan_limit=1,
            )
        )

        assert result.entries == ()
        assert result.timed_out is True
        assert result.scanned_rows == 1
        # Subtracting a large monotonic timestamp can round 50 ms up by a few picoseconds.
        assert observed_timeouts and 0 < observed_timeouts[0] <= 0.05 + 1e-9
    finally:
        store.close()


def test_plain_search_has_an_explicit_newest_candidate_scan_bound(tmp_path: Path) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    try:
        store.append([_entry("only-old-row-matches")])
        store.append([_entry(f"newer-{index}") for index in range(12)])

        result = store.search(LogQuery(keyword="only-old", scan_limit=5))

        assert result.entries == ()
        assert result.scanned_rows == 5
        assert result.scan_limited is True
    finally:
        store.close()


def test_search_stops_accumulating_when_result_text_budget_is_reached(tmp_path: Path) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    try:
        store.append([_entry("12345678"), _entry("abcdefgh"), _entry("ABCDEFGH")])

        result = store.search(LogQuery(limit=3, result_text_limit=10))

        assert [entry.message for entry in result.entries] == ["ABCDEFGH"]
        assert result.result_limited is True
        assert result.scanned_rows == 2
    finally:
        store.close()


def test_search_honors_a_preexisting_cancellation_request(tmp_path: Path) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    cancelled = threading.Event()
    cancelled.set()
    try:
        result = store.search(LogQuery(keyword="anything"), cancel_event=cancelled)

        assert result.entries == ()
        assert result.cancelled is True
        assert result.scanned_rows == 0
    finally:
        store.close()


def test_closed_store_rejects_new_read_work(tmp_path: Path) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    store.close()

    with pytest.raises(RuntimeError, match="已关闭"):
        store.search(LogQuery())


def test_retention_keeps_exact_seven_day_boundary(tmp_path: Path) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    now = datetime(2026, 10, 22, 8, 0, tzinfo=UTC)
    try:
        store.append(
            [
                _entry("expired", occurred_at=now - timedelta(days=7, microseconds=1)),
                _entry("boundary", occurred_at=now - timedelta(days=7)),
                _entry("recent", occurred_at=now),
            ]
        )

        assert store.purge(now, retention_days=7) == 1
        assert {entry.message for entry in store.search(LogQuery()).entries} == {"boundary", "recent"}
    finally:
        store.close()


def test_database_uses_wal_fts_and_never_creates_audit_storage(tmp_path: Path) -> None:
    path = tmp_path / "logs.sqlite3"
    store = LogStore.open(path)
    try:
        store.append([_entry("searchable message")])
        with sqlite3.connect(path) as connection:
            assert connection.execute("PRAGMA journal_mode").fetchone()[0].casefold() == "wal"
            tables = {
                row[0]
                for row in connection.execute("SELECT name FROM sqlite_master WHERE type IN ('table', 'view')")
            }
        assert "logs_fts" in tables
        assert not any("audit" in name.casefold() for name in tables)
    finally:
        store.close()


def test_store_redacts_again_at_persistence_boundary(tmp_path: Path) -> None:
    path = tmp_path / "logs.sqlite3"
    store = LogStore.open(path)
    unsafe = LogEntry(
        occurred_at=datetime.now(UTC),
        source=LogSource.MONITOR,
        level=LogLevel.INFO,
        stream="test",
        message="launch --api-key=must-not-persist X-API-Key: header-must-not-persist",
    )
    try:
        store.append([unsafe])
        result = store.search(LogQuery())
        assert "must-not-persist" not in result.entries[0].message
        assert "header-must-not-persist" not in result.entries[0].message
        with sqlite3.connect(path) as connection:
            raw = connection.execute("SELECT message FROM logs").fetchone()[0]
        assert "must-not-persist" not in raw
        assert "header-must-not-persist" not in raw
        assert raw.count("[REDACTED]") == 2
    finally:
        store.close()


def test_corrupt_database_is_quarantined_and_rebuilt(tmp_path: Path) -> None:
    path = tmp_path / "logs.sqlite3"
    path.write_bytes(b"not a sqlite database")

    store = LogStore.open(path)
    try:
        store.append([_entry("rebuilt")])
        assert [entry.message for entry in store.search(LogQuery()).entries] == ["rebuilt"]
    finally:
        store.close()

    quarantined = list(tmp_path.glob("logs.sqlite3.corrupt-*"))
    assert len(quarantined) == 1
    assert quarantined[0].read_bytes() == b"not a sqlite database"


def test_cursor_round_trip_and_single_writer_concurrency(tmp_path: Path) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    source_file = tmp_path / "postgres.log"
    try:
        assert store.get_cursor(source_file) is None
        store.set_cursor(source_file, file_identity="dev:1", offset=42, size=50)
        cursor = store.get_cursor(source_file)
        assert cursor is not None
        assert cursor.file_identity == "dev:1"
        assert cursor.offset == 42
        assert cursor.size == 50

        def append_one(number: int) -> None:
            store.append([_entry(f"line {number}")])

        with ThreadPoolExecutor(max_workers=8) as executor:
            list(executor.map(append_one, range(80)))

        assert len(store.search(LogQuery(limit=100)).entries) == 80
    finally:
        store.close()


def test_close_releases_database_handle_for_packaged_smoke_cleanup(tmp_path: Path) -> None:
    path = tmp_path / "logs.sqlite3"
    moved = tmp_path / "closed.sqlite3"
    store = LogStore.open(path)
    store.append([_entry("close-me")])

    store.close()
    os.replace(path, moved)

    assert moved.is_file()


def test_close_cannot_enqueue_shutdown_before_an_accepted_write(tmp_path: Path, monkeypatch) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    original_put = store._requests.put
    write_entered = threading.Event()
    release_write = threading.Event()
    close_started = threading.Event()
    order: list[str] = []
    errors: list[Exception] = []

    def controlled_put(item) -> None:
        if item is None:
            order.append("sentinel")
            original_put(item)
            return
        write_entered.set()
        assert release_write.wait(2)
        order.append("request")
        if "sentinel" in order:
            item.error = RuntimeError("writer already stopped")
            item.completed.set()
            return
        original_put(item)

    monkeypatch.setattr(store._requests, "put", controlled_put)

    def append_one() -> None:
        try:
            store.append([_entry("accepted-before-close")])
        except Exception as exc:
            errors.append(exc)

    def close_store() -> None:
        close_started.set()
        store.close()

    writer = threading.Thread(target=append_one)
    closer = threading.Thread(target=close_store)
    writer.start()
    assert write_entered.wait(1)
    closer.start()
    assert close_started.wait(1)
    time.sleep(0.05)
    release_write.set()
    writer.join(2)
    closer.join(2)

    assert not writer.is_alive()
    assert not closer.is_alive()
    assert errors == []
    assert order == ["request", "sentinel"]

