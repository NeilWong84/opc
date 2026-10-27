from __future__ import annotations

import threading
import time
from datetime import UTC, datetime
from pathlib import Path

from opc_service_monitor.log_pipeline import make_log_entry
from opc_service_monitor.log_store import LogQuery, LogStore
from opc_service_monitor.models import LogSource, ServiceId
from opc_service_monitor.runtime_logs import RuntimeLogCoordinator


def test_service_output_is_redacted_stored_and_emitted(tmp_path: Path, qtbot) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    coordinator = RuntimeLogCoordinator(store)
    received = []
    coordinator.entry_received.connect(received.append)
    try:
        coordinator.record_service(ServiceId.BACKEND, "stderr", "password=runtime-secret")
        qtbot.waitUntil(lambda: len(received) == 1)

        assert len(received[0]) == 1
        assert received[0][0].source is LogSource.BACKEND
        assert "runtime-secret" not in received[0][0].message
        stored = store.search(LogQuery()).entries
        assert len(stored) == 1
        assert "runtime-secret" not in stored[0].message
    finally:
        coordinator.stop()
        store.close()


def test_postgres_file_poll_is_single_flight_and_emits_results(tmp_path: Path, qtbot) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    entered = threading.Event()
    release = threading.Event()
    entry = make_log_entry(
        source=LogSource.POSTGRES,
        stream="file",
        text="postgres ready",
        occurred_at=datetime.now(UTC),
    )

    class BlockingTailer:
        calls = 0

        def poll(self):
            self.calls += 1
            entered.set()
            assert release.wait(3)
            return [entry]

    tailer = BlockingTailer()
    coordinator = RuntimeLogCoordinator(store, tailers=(tailer,))
    received = []
    reentrant_results: list[bool] = []
    coordinator.entry_received.connect(received.append)

    def start_one_reentrant_poll() -> None:
        if not reentrant_results:
            reentrant_results.append(coordinator.poll_files())

    coordinator.poll_finished.connect(start_one_reentrant_poll)
    try:
        assert coordinator.poll_files() is True
        assert entered.wait(2)
        assert coordinator.poll_files() is False
        release.set()
        with qtbot.waitSignal(coordinator.poll_finished, timeout=3000):
            pass
        assert reentrant_results == [True]
        qtbot.waitUntil(lambda: tailer.calls == 2 and len(received) == 2)
        assert received == [(entry,), (entry,)]
    finally:
        coordinator.stop()
        store.close()


def test_runtime_maintenance_purges_records_older_than_seven_days(qtbot) -> None:
    class RecordingStore:
        def __init__(self) -> None:
            self.calls: list[tuple[datetime, int]] = []

        def purge(self, now_utc: datetime, retention_days: int = 7) -> int:
            self.calls.append((now_utc, retention_days))
            return 4

    store = RecordingStore()
    coordinator = RuntimeLogCoordinator(store)  # type: ignore[arg-type]
    results: list[int] = []
    coordinator.maintenance_finished.connect(results.append)
    try:
        assert coordinator.run_maintenance() is True
        with qtbot.waitSignal(coordinator.maintenance_finished, timeout=3000):
            pass
        assert results == [4]
        assert len(store.calls) == 1
        assert store.calls[0][1] == 7
        assert store.calls[0][0].tzinfo is UTC
    finally:
        coordinator.stop()


def test_runtime_ingestion_is_bounded_nonblocking_batched_and_secret_safe(qtbot) -> None:
    entered = threading.Event()
    release = threading.Event()

    class SlowStore:
        def __init__(self) -> None:
            self.batches: list[tuple] = []

        def append(self, entries):
            entered.set()
            assert release.wait(3)
            self.batches.append(tuple(entries))
            return len(entries)

    store = SlowStore()
    coordinator = RuntimeLogCoordinator(
        store,  # type: ignore[arg-type]
        ingestion_queue_size=3,
        ingestion_batch_size=3,
    )
    errors: list[str] = []
    coordinator.ingestion_error.connect(errors.append)
    try:
        coordinator.record_service(ServiceId.BACKEND, "stdout", "first password=first-secret")
        assert entered.wait(1)

        started = time.monotonic()
        for index in range(10):
            coordinator.record_service(ServiceId.BACKEND, "stdout", f"burst-{index} token=secret-{index}")
        assert time.monotonic() - started < 0.2
        assert coordinator.dropped_count >= 1
        qtbot.waitUntil(lambda: bool(errors))
        qtbot.wait(20)
        assert len(errors) == 1
        assert all("secret" not in message for message in errors)

        release.set()
        assert coordinator.stop(timeout_ms=3_000) is True
        persisted = [entry for batch in store.batches for entry in batch]
        assert len(store.batches) >= 2
        assert any(len(batch) > 1 for batch in store.batches)
        assert len(persisted) == coordinator.accepted_count
        assert all("secret" not in entry.message for entry in persisted)
    finally:
        release.set()
        coordinator.stop()


def test_runtime_stop_drains_all_accepted_entries_before_store_close() -> None:
    class RecordingStore:
        def __init__(self) -> None:
            self.entries = []
            self.closed = False

        def append(self, entries):
            assert not self.closed
            self.entries.extend(entries)
            return len(entries)

        def close(self) -> None:
            self.closed = True

    store = RecordingStore()
    coordinator = RuntimeLogCoordinator(store, ingestion_queue_size=32)  # type: ignore[arg-type]
    for index in range(20):
        coordinator.record_service(ServiceId.FRONTEND, "stdout", f"line-{index}")

    assert coordinator.stop(timeout_ms=3_000) is True
    store.close()

    assert len(store.entries) == 20
    assert coordinator.persisted_count == 20


def test_runtime_store_failure_is_reported_without_secret_and_counted_as_dropped(qtbot) -> None:
    class FailingStore:
        def append(self, _entries):
            raise RuntimeError("password=storage-secret")

    coordinator = RuntimeLogCoordinator(FailingStore())  # type: ignore[arg-type]
    errors: list[str] = []
    coordinator.ingestion_error.connect(errors.append)
    try:
        coordinator.record_service(ServiceId.BACKEND, "stdout", "normal line")
        qtbot.waitUntil(lambda: bool(errors))

        assert "storage-secret" not in errors[0]
        assert "[REDACTED]" in errors[0]
        assert coordinator.dropped_count == 1
        assert coordinator.persisted_count == 0
    finally:
        coordinator.stop()


def test_live_ui_queue_is_bounded_single_flight_and_does_not_drop_history(tmp_path: Path, qtbot) -> None:
    store = LogStore.open(tmp_path / "logs.sqlite3")
    coordinator = RuntimeLogCoordinator(
        store,
        ingestion_queue_size=128,
        ingestion_batch_size=128,
        live_queue_size=3,
    )
    batches: list[tuple] = []
    overflow_notices: list[int] = []
    ingestion_errors: list[str] = []
    coordinator.entry_received.connect(batches.append)
    coordinator.live_overflow.connect(overflow_notices.append)
    coordinator.ingestion_error.connect(ingestion_errors.append)
    try:
        for index in range(50):
            coordinator.record_service(ServiceId.FRONTEND, "stdout", f"line-{index}")

        deadline = time.monotonic() + 3
        while coordinator.persisted_count != 50 and time.monotonic() < deadline:
            time.sleep(0.01)
        assert coordinator.persisted_count == 50

        qtbot.waitUntil(lambda: len(batches) == 1)
        assert [[entry.message for entry in batch] for batch in batches] == [
            ["line-47", "line-48", "line-49"]
        ]
        assert overflow_notices == [47]
        assert coordinator.live_dropped_count == 47
        assert ingestion_errors == []
        assert len(store.search(LogQuery(limit=100)).entries) == 50
    finally:
        coordinator.stop()
        store.close()


def test_stopped_runtime_coordinator_rejects_new_background_store_work() -> None:
    class RecordingStore:
        def __init__(self) -> None:
            self.purge_calls = 0

        def purge(self, *_args, **_kwargs):
            self.purge_calls += 1
            return 0

    class RecordingTailer:
        def __init__(self) -> None:
            self.poll_calls = 0

        def poll(self):
            self.poll_calls += 1
            return []

    store = RecordingStore()
    tailer = RecordingTailer()
    coordinator = RuntimeLogCoordinator(store, tailers=(tailer,))  # type: ignore[arg-type]

    assert coordinator.stop() is True
    assert coordinator.poll_files() is False
    assert coordinator.run_maintenance() is False
    assert tailer.poll_calls == 0
    assert store.purge_calls == 0

