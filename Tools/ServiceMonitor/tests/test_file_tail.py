from __future__ import annotations

import os
from pathlib import Path

import pytest

import opc_service_monitor.file_tail as file_tail_module
from opc_service_monitor.file_tail import AllowedFileTailer, INITIAL_IMPORT_BYTES
from opc_service_monitor.log_pipeline import make_log_entry
from opc_service_monitor.log_store import LogMatchMode, LogQuery, LogStore
from opc_service_monitor.models import LogSource


def test_rejects_file_outside_exact_allowlist(tmp_path: Path) -> None:
    allowed = tmp_path / "postgres.log"
    outside = tmp_path / "other.log"
    store = LogStore.open(tmp_path / "logs.sqlite3")
    try:
        with pytest.raises(ValueError, match="白名单"):
            AllowedFileTailer(outside, allowed_paths=(allowed,), store=store)
    finally:
        store.close()


def test_first_observation_reads_only_final_two_mib_on_line_boundary(tmp_path: Path) -> None:
    log_path = tmp_path / "postgres.log"
    log_path.write_bytes(b"x" * (INITIAL_IMPORT_BYTES + 100) + b"\nkept-one\nkept-two\n")
    store = LogStore.open(tmp_path / "logs.sqlite3")
    tailer = AllowedFileTailer(log_path, allowed_paths=(log_path,), store=store)
    try:
        entries = tailer.poll()

        assert [entry.message for entry in entries] == ["kept-one", "kept-two"]
        assert tailer.last_bytes_read <= INITIAL_IMPORT_BYTES
        assert all(entry.source is LogSource.POSTGRES for entry in entries)
        assert [entry.message for entry in store.search(LogQuery()).entries] == ["kept-two", "kept-one"]
    finally:
        store.close()


def test_resume_uses_persisted_cursor_without_duplicates(tmp_path: Path) -> None:
    log_path = tmp_path / "postgres.log"
    log_path.write_text("first\n", encoding="utf-8")
    database = tmp_path / "logs.sqlite3"
    store = LogStore.open(database)
    try:
        first = AllowedFileTailer(log_path, allowed_paths=(log_path,), store=store)
        assert [entry.message for entry in first.poll()] == ["first"]
        assert first.poll() == []
        with log_path.open("ab") as handle:
            handle.write("second\n".encode())

        resumed = AllowedFileTailer(log_path, allowed_paths=(log_path,), store=store)
        assert [entry.message for entry in resumed.poll()] == ["second"]
        assert [entry.message for entry in store.search(LogQuery()).entries] == ["second", "first"]
    finally:
        store.close()


def test_resumed_growth_is_drained_in_bounded_complete_line_chunks(tmp_path: Path) -> None:
    log_path = tmp_path / "postgres.log"
    log_path.write_bytes(b"seed\n")
    store = LogStore.open(tmp_path / "logs.sqlite3")
    tailer = AllowedFileTailer(log_path, allowed_paths=(log_path,), store=store, initial_bytes=64)
    try:
        assert [entry.message for entry in tailer.poll()] == ["seed"]
        expected = [f"line-{index:03d}" for index in range(40)]
        with log_path.open("ab") as handle:
            handle.write(("\n".join(expected) + "\n").encode())

        observed: list[str] = []
        for _ in range(20):
            observed.extend(entry.message for entry in tailer.poll())
            assert tailer.last_bytes_read <= 64
            if len(observed) == len(expected):
                break

        assert observed == expected
        assert tailer.poll() == []
        cursor = store.get_cursor(log_path)
        assert cursor is not None
        assert cursor.offset == log_path.stat().st_size
    finally:
        store.close()


def test_poll_limits_complete_lines_and_restart_resumes_at_exact_cursor(tmp_path: Path) -> None:
    log_path = tmp_path / "postgres.log"
    expected = [f"line-{index}" for index in range(8)]
    log_path.write_bytes(("\n".join(expected) + "\n").encode())
    store = LogStore.open(tmp_path / "logs.sqlite3")
    try:
        tailer = AllowedFileTailer(
            log_path,
            allowed_paths=(log_path,),
            store=store,
            initial_bytes=1_024,
            max_complete_lines=3,
        )

        assert [entry.message for entry in tailer.poll()] == expected[:3]
        cursor = store.get_cursor(log_path)
        assert cursor is not None
        assert cursor.offset == len("\n".join(expected[:3]).encode()) + 1

        resumed = AllowedFileTailer(
            log_path,
            allowed_paths=(log_path,),
            store=store,
            initial_bytes=1_024,
            max_complete_lines=3,
        )
        assert [entry.message for entry in resumed.poll()] == expected[3:6]
        assert [entry.message for entry in resumed.poll()] == expected[6:]
        assert resumed.poll() == []
        cursor = store.get_cursor(log_path)
        assert cursor is not None
        assert cursor.offset == log_path.stat().st_size
    finally:
        store.close()


def test_unterminated_tail_is_held_until_a_newline_arrives(tmp_path: Path) -> None:
    log_path = tmp_path / "postgres.log"
    log_path.write_bytes(b"partial")
    store = LogStore.open(tmp_path / "logs.sqlite3")
    tailer = AllowedFileTailer(log_path, allowed_paths=(log_path,), store=store)
    try:
        assert tailer.poll() == []
        with log_path.open("ab") as handle:
            handle.write(b"-done\nnext")
        assert [entry.message for entry in tailer.poll()] == ["partial-done"]
        with log_path.open("ab") as handle:
            handle.write(b"-done\n")
        assert [entry.message for entry in tailer.poll()] == ["next-done"]
        assert [entry.message for entry in store.search(LogQuery()).entries] == ["next-done", "partial-done"]
    finally:
        store.close()


def test_overlong_unterminated_line_is_discarded_across_restart_until_newline(tmp_path: Path) -> None:
    log_path = tmp_path / "postgres.log"
    log_path.write_bytes(b"seed\n")
    store = LogStore.open(tmp_path / "logs.sqlite3")
    try:
        tailer = AllowedFileTailer(log_path, allowed_paths=(log_path,), store=store, initial_bytes=32)
        assert [entry.message for entry in tailer.poll()] == ["seed"]
        with log_path.open("ab") as handle:
            handle.write(b"sensitive-payload=" + b"x" * 80 + b"\nafter-long-line\n")

        first_chunk = tailer.poll()
        assert len(first_chunk) == 1
        assert first_chunk[0].truncated is True
        assert "sensitive-payload" not in first_chunk[0].message
        assert tailer.last_bytes_read <= 32

        resumed = AllowedFileTailer(log_path, allowed_paths=(log_path,), store=store, initial_bytes=32)
        observed: list[str] = []
        for _ in range(10):
            observed.extend(entry.message for entry in resumed.poll())
            assert resumed.last_bytes_read <= 32
            if "after-long-line" in observed:
                break

        assert observed == ["after-long-line"]
        cursor = store.get_cursor(log_path)
        assert cursor is not None
        assert cursor.offset == log_path.stat().st_size
        assert cursor.discard_until_newline is False
    finally:
        store.close()


def test_truncation_restarts_at_beginning_of_same_file(tmp_path: Path) -> None:
    log_path = tmp_path / "postgres.log"
    log_path.write_text("old-one\nold-two\n", encoding="utf-8")
    store = LogStore.open(tmp_path / "logs.sqlite3")
    tailer = AllowedFileTailer(log_path, allowed_paths=(log_path,), store=store)
    try:
        assert len(tailer.poll()) == 2
        log_path.write_text("new-after-truncate\n", encoding="utf-8")

        assert [entry.message for entry in tailer.poll()] == ["new-after-truncate"]
    finally:
        store.close()


def test_rotation_restarts_when_file_identity_changes(tmp_path: Path) -> None:
    log_path = tmp_path / "provision.log"
    rotated = tmp_path / "provision.log.1"
    log_path.write_text("before-rotation\n", encoding="utf-8")
    store = LogStore.open(tmp_path / "logs.sqlite3")
    tailer = AllowedFileTailer(log_path, allowed_paths=(log_path,), store=store)
    try:
        assert [entry.message for entry in tailer.poll()] == ["before-rotation"]
        os.replace(log_path, rotated)
        log_path.write_text("after-rotation\n", encoding="utf-8")

        assert [entry.message for entry in tailer.poll()] == ["after-rotation"]
    finally:
        store.close()


def test_mixed_utf8_and_windows_lines_resume_with_split_legacy_characters(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(file_tail_module, "windows_log_encodings", lambda: ("gb18030",))
    log_path = tmp_path / "postgres.log"
    log_path.write_bytes("日志: 已启动\n".encode("gb18030") + "日语: 起動しました\n".encode("utf-8"))
    store = LogStore.open(tmp_path / "logs.sqlite3")
    try:
        tailer = AllowedFileTailer(log_path, allowed_paths=(log_path,), store=store)
        assert [entry.message for entry in tailer.poll()] == ["日志: 已启动", "日语: 起動しました"]
        suffix = "日志: 等待连接\n".encode("gb18030")
        with log_path.open("ab") as handle:
            handle.write(suffix[:1])
        assert tailer.poll() == []
        resumed = AllowedFileTailer(log_path, allowed_paths=(log_path,), store=store)
        with log_path.open("ab") as handle:
            handle.write(suffix[1:])
        assert [entry.message for entry in resumed.poll()] == ["日志: 等待连接"]
        assert len(store.search(LogQuery()).entries) == 3
        assert resumed.poll() == []
    finally:
        store.close()


def test_legacy_index_repairs_at_eof_without_replay_and_preserves_record_metadata(tmp_path: Path, monkeypatch) -> None:
    log_path = tmp_path / "postgres.log"
    log_path.write_bytes("日志: 服务已启动 password=local-secret\nhealthy\n".encode("gb18030"))
    store = LogStore.open(tmp_path / "logs.sqlite3")
    try:
        monkeypatch.setattr(file_tail_module, "windows_log_encodings", lambda: ())
        legacy = AllowedFileTailer(log_path, allowed_paths=(log_path,), store=store)
        original = legacy.poll()
        old_message = original[0].message
        assert "\ufffd" in old_message
        store.append(
            [
                make_log_entry(source=LogSource.BACKEND, stream="stderr", text=old_message),
                make_log_entry(source=LogSource.POSTGRES, stream="stdout", text=old_message),
                make_log_entry(source=LogSource.POSTGRES, stream="file", text="不可恢复 \ufffd"),
            ]
        )
        before = {entry.entry_id: entry for entry in store.search(LogQuery()).entries}
        cursor_before = store.get_cursor(log_path)
        monkeypatch.setattr(file_tail_module, "windows_log_encodings", lambda: ("gb18030",))
        upgraded = AllowedFileTailer(log_path, allowed_paths=(log_path,), store=store)

        assert upgraded.repair_legacy_entries() == 1
        assert upgraded.last_repair_bytes_read <= INITIAL_IMPORT_BYTES
        assert upgraded.repair_legacy_entries() == 0
        assert store.get_cursor(log_path) == cursor_before
        assert upgraded.poll() == []
        after = {entry.entry_id: entry for entry in store.search(LogQuery()).entries}
        assert after.keys() == before.keys()
        for entry_id, entry in after.items():
            assert entry.occurred_at == before[entry_id].occurred_at
            if entry.source is LogSource.POSTGRES and entry.stream == "file" and entry.message.startswith("日志"):
                assert entry.message == "日志: 服务已启动 password=[REDACTED]"
            else:
                assert entry == before[entry_id]
        result = store.search(LogQuery(keyword="日志", match_mode=LogMatchMode.FTS))
        assert len(result.entries) == 1
        assert result.entries[0].message == "日志: 服务已启动 password=[REDACTED]"
    finally:
        store.close()


@pytest.mark.parametrize("other_raw", (b"\x82@", "\ufffd@".encode("utf-8")))
def test_legacy_repair_skips_ambiguous_replacement_messages(tmp_path: Path, monkeypatch, other_raw: bytes) -> None:
    monkeypatch.setattr(file_tail_module, "windows_log_encodings", lambda: ("gb18030",))
    log_path = tmp_path / "postgres.log"
    log_path.write_bytes(b"\x81@\n" + other_raw + b"\n")
    previous = b"\x81@".decode("utf-8", errors="replace")
    assert previous == other_raw.decode("utf-8", errors="replace")
    store = LogStore.open(tmp_path / "logs.sqlite3")
    try:
        store.append([make_log_entry(source=LogSource.POSTGRES, stream="file", text=previous)])
        tailer = AllowedFileTailer(log_path, allowed_paths=(log_path,), store=store)
        assert tailer.repair_legacy_entries() == 0
        assert store.search(LogQuery()).entries[0].message == previous
    finally:
        store.close()


def test_legacy_repair_retries_after_allowed_file_was_temporarily_missing(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(file_tail_module, "windows_log_encodings", lambda: ("gb18030",))
    log_path = tmp_path / "postgres.log"
    raw = "日志: 服务就绪".encode("gb18030")
    previous = raw.decode("utf-8", errors="replace")
    store = LogStore.open(tmp_path / "logs.sqlite3")
    try:
        store.append([make_log_entry(source=LogSource.POSTGRES, stream="file", text=previous)])
        tailer = AllowedFileTailer(log_path, allowed_paths=(log_path,), store=store)
        assert tailer.repair_legacy_entries() == 0
        log_path.write_bytes(raw + b"\n")
        assert tailer.repair_legacy_entries() == 1
        assert store.search(LogQuery()).entries[0].message == "日志: 服务就绪"
    finally:
        store.close()


def test_legacy_repair_obeys_tail_window_and_complete_line_limit(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(file_tail_module, "windows_log_encodings", lambda: ("gb18030",))
    lines = [f"日志: {index}".encode("gb18030") for index in range(8)]
    log_path = tmp_path / "postgres.log"
    log_path.write_bytes(b"\n".join(lines) + b"\n" + "日志: 未完成".encode("gb18030"))
    store = LogStore.open(tmp_path / "logs.sqlite3")
    try:
        for raw in (*lines, "日志: 未完成".encode("gb18030")):
            store.append(
                [make_log_entry(source=LogSource.POSTGRES, stream="file", text=raw.decode("utf-8", errors="replace"))]
            )
        tailer = AllowedFileTailer(
            log_path,
            allowed_paths=(log_path,),
            store=store,
            initial_bytes=40,
            max_complete_lines=2,
        )
        assert tailer.repair_legacy_entries() == 2
        assert tailer.last_repair_bytes_read == 40
        entries = store.search(LogQuery()).entries
        corrected = [entry for entry in entries if "\ufffd" not in entry.message]
        assert len(corrected) == 2
        assert all(entry.message != "日志: 未完成" for entry in corrected)
        assert "\ufffd" in next(entry.message for entry in entries if entry.message.endswith("0"))
    finally:
        store.close()

