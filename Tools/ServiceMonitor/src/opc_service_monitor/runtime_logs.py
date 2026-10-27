from __future__ import annotations

import queue
import threading
import time
from collections import deque
from collections.abc import Iterable
from datetime import UTC, datetime

from PySide6.QtCore import QObject, QThreadPool, QTimer, Qt, Signal

from opc_service_monitor.log_pipeline import make_log_entry, redact_log_text
from opc_service_monitor.log_store import LogStore
from opc_service_monitor.models import LogEntry, LogSource, ServiceId
from opc_service_monitor.workers import TaskWorker


_SERVICE_SOURCES = {
    ServiceId.POSTGRES: LogSource.POSTGRES,
    ServiceId.BACKEND: LogSource.BACKEND,
    ServiceId.FRONTEND: LogSource.FRONTEND,
}


class RuntimeLogCoordinator(QObject):
    entry_received = Signal(object)
    live_overflow = Signal(int)
    _live_ready = Signal()
    _ingestion_notice_ready = Signal()
    ingestion_error = Signal(str)
    poll_error = Signal(str)
    poll_finished = Signal()
    maintenance_finished = Signal(int)

    def __init__(
        self,
        store: LogStore,
        *,
        tailers: Iterable[object] = (),
        ingestion_queue_size: int = 4_096,
        ingestion_batch_size: int = 128,
        live_queue_size: int = 512,
        parent=None,
    ) -> None:
        super().__init__(parent)
        if ingestion_queue_size < 1:
            raise ValueError("运行日志队列容量必须大于零")
        if ingestion_batch_size < 1:
            raise ValueError("运行日志批量大小必须大于零")
        if live_queue_size < 1:
            raise ValueError("实时日志显示队列容量必须大于零")
        ingestion_batch_size = min(ingestion_batch_size, ingestion_queue_size)
        self._store = store
        self._tailers = tuple(tailers)
        self._lifecycle_lock = threading.Lock()
        self._stopped = False
        self._poll_lock = threading.Lock()
        self._polling = False
        self._maintenance_lock = threading.Lock()
        self._maintenance_running = False
        self._workers: set[TaskWorker] = set()
        self._pool = QThreadPool(self)
        self._pool.setMaxThreadCount(2)
        self._ingestion_queue: queue.Queue[LogEntry] = queue.Queue(maxsize=ingestion_queue_size)
        self._ingestion_batch_size = ingestion_batch_size
        self._ingestion_stop = threading.Event()
        self._ingestion_lock = threading.Lock()
        self._accepting = True
        self._accepted_count = 0
        self._persisted_count = 0
        self._dropped_count = 0
        self._ingestion_notice_lock = threading.Lock()
        self._ingestion_notice_count = 0
        self._ingestion_notice_message: str | None = None
        self._ingestion_notice_pending = False
        self._live_lock = threading.Lock()
        self._live_queue: deque[LogEntry] = deque()
        self._live_queue_size = live_queue_size
        self._live_notification_pending = False
        self._live_dropped_count = 0
        self._live_dropped_since_notice = 0
        self._live_ready.connect(self._flush_live_entries, Qt.ConnectionType.QueuedConnection)
        self._ingestion_notice_ready.connect(
            self._flush_ingestion_notice,
            Qt.ConnectionType.QueuedConnection,
        )
        self._ingestion_thread = threading.Thread(
            target=self._ingestion_loop,
            name="opc-runtime-log-ingestion",
            daemon=True,
        )
        self._ingestion_thread.start()
        self._timer = QTimer(self)
        self._timer.timeout.connect(self.poll_files)
        self._maintenance_timer = QTimer(self)
        self._maintenance_timer.setInterval(60 * 60 * 1_000)
        self._maintenance_timer.timeout.connect(self.run_maintenance)

    def start(self, interval_ms: int = 1_000) -> None:
        if interval_ms < 100:
            raise ValueError("日志文件轮询间隔不能小于 100 毫秒")
        with self._lifecycle_lock:
            if self._stopped:
                raise RuntimeError("运行日志协调器已停止")
            self._timer.start(interval_ms)
            self._maintenance_timer.start()
        self.poll_files()

    @property
    def accepted_count(self) -> int:
        with self._ingestion_lock:
            return self._accepted_count

    @property
    def persisted_count(self) -> int:
        with self._ingestion_lock:
            return self._persisted_count

    @property
    def dropped_count(self) -> int:
        with self._ingestion_lock:
            return self._dropped_count

    @property
    def live_dropped_count(self) -> int:
        with self._live_lock:
            return self._live_dropped_count

    def stop(self, timeout_ms: int = 5_000) -> bool:
        if timeout_ms < 0:
            raise ValueError("停止等待时间不能为负数")
        deadline = time.monotonic() + timeout_ms / 1_000
        with self._lifecycle_lock:
            self._stopped = True
            self._timer.stop()
            self._maintenance_timer.stop()
        with self._ingestion_lock:
            self._accepting = False
        pool_drained = self._pool.waitForDone(max(0, int((deadline - time.monotonic()) * 1_000)))
        self._ingestion_stop.set()
        self._ingestion_thread.join(timeout=max(0.0, deadline - time.monotonic()))
        return pool_drained and not self._ingestion_thread.is_alive()

    def run_maintenance(self) -> bool:
        with self._lifecycle_lock:
            if self._stopped:
                return False
            with self._maintenance_lock:
                if self._maintenance_running:
                    return False
                self._maintenance_running = True
            worker = TaskWorker(lambda: self._store.purge(datetime.now(UTC), retention_days=7))
            self._workers.add(worker)

            def completed(count: int) -> None:
                self._complete_maintenance(worker)
                self.maintenance_finished.emit(count)

            def failed(message: str) -> None:
                self._complete_maintenance(worker)
                self.poll_error.emit(message)

            worker.signals.result.connect(completed)
            worker.signals.error.connect(failed)
            worker.signals.finished.connect(lambda: self._complete_maintenance(worker))
            worker.start(self._pool)
        return True

    def record_service(self, service_id: ServiceId, stream: str, line: str) -> LogEntry:
        return self.record(_SERVICE_SOURCES[service_id], stream, line)

    def record(self, source: LogSource, stream: str, line: str) -> LogEntry:
        entry = make_log_entry(source=source, stream=stream, text=line)
        queue_overflow = False
        with self._ingestion_lock:
            if not self._accepting:
                self._dropped_count += 1
            else:
                try:
                    self._ingestion_queue.put_nowait(entry)
                except queue.Full:
                    self._dropped_count += 1
                    queue_overflow = True
                else:
                    self._accepted_count += 1
        if queue_overflow:
            self._queue_ingestion_notice("运行日志队列已满", 1)
        return entry

    def poll_files(self) -> bool:
        with self._lifecycle_lock:
            if self._stopped:
                return False
            with self._poll_lock:
                if self._polling or not self._tailers:
                    return False
                self._polling = True

            def poll_all() -> list[LogEntry]:
                entries: list[LogEntry] = []
                for tailer in self._tailers:
                    entries.extend(tailer.poll())
                return entries

            worker = TaskWorker(poll_all)
            self._workers.add(worker)

            def received(entries: list[LogEntry]) -> None:
                self._complete(worker)
                self._queue_live_entries(entries)
                self.poll_finished.emit()

            def failed(message: str) -> None:
                self._complete(worker)
                self.poll_error.emit(message)

            worker.signals.result.connect(received)
            worker.signals.error.connect(failed)
            worker.signals.finished.connect(lambda: self._complete(worker))
            worker.start(self._pool)
        return True

    def _ingestion_loop(self) -> None:
        while True:
            if self._ingestion_stop.is_set() and self._ingestion_queue.empty():
                return
            try:
                first = self._ingestion_queue.get(timeout=0.05)
            except queue.Empty:
                continue
            batch = [first]
            while len(batch) < self._ingestion_batch_size:
                try:
                    batch.append(self._ingestion_queue.get_nowait())
                except queue.Empty:
                    break
            try:
                persisted = self._store.append(batch)
            except Exception as exc:
                with self._ingestion_lock:
                    self._dropped_count += len(batch)
                message = redact_log_text(str(exc)) or "运行日志写入失败"
                self._queue_ingestion_notice(f"运行日志写入失败: {message}", len(batch))
            else:
                with self._ingestion_lock:
                    self._persisted_count += int(persisted)
                self._queue_live_entries(batch)
            finally:
                for _entry in batch:
                    self._ingestion_queue.task_done()

    def _queue_live_entries(self, entries: Iterable[LogEntry]) -> None:
        notify = False
        with self._live_lock:
            for entry in entries:
                if len(self._live_queue) >= self._live_queue_size:
                    self._live_queue.popleft()
                    self._live_dropped_count += 1
                    self._live_dropped_since_notice += 1
                self._live_queue.append(entry)
            if self._live_queue and not self._live_notification_pending:
                self._live_notification_pending = True
                notify = True
        if notify:
            self._live_ready.emit()

    def _flush_live_entries(self) -> None:
        with self._live_lock:
            entries = tuple(self._live_queue)
            self._live_queue.clear()
            dropped = self._live_dropped_since_notice
            self._live_dropped_since_notice = 0
            self._live_notification_pending = False
        if entries:
            self.entry_received.emit(entries)
        if dropped:
            self.live_overflow.emit(dropped)

    def _queue_ingestion_notice(self, message: str, count: int) -> None:
        notify = False
        safe_message = redact_log_text(message) or "运行日志处理失败"
        with self._ingestion_notice_lock:
            self._ingestion_notice_count += max(1, count)
            if self._ingestion_notice_message is None:
                self._ingestion_notice_message = safe_message
            elif self._ingestion_notice_message != safe_message:
                self._ingestion_notice_message = "运行日志缓冲或写入失败"
            if not self._ingestion_notice_pending:
                self._ingestion_notice_pending = True
                notify = True
        if notify:
            self._ingestion_notice_ready.emit()

    def _flush_ingestion_notice(self) -> None:
        with self._ingestion_notice_lock:
            count = self._ingestion_notice_count
            message = self._ingestion_notice_message or "运行日志处理失败"
            self._ingestion_notice_count = 0
            self._ingestion_notice_message = None
            self._ingestion_notice_pending = False
        if count:
            self.ingestion_error.emit(f"{message}，已丢弃 {count} 条日志")

    def _complete(self, worker: TaskWorker) -> None:
        self._workers.discard(worker)
        with self._poll_lock:
            self._polling = False

    def _complete_maintenance(self, worker: TaskWorker) -> None:
        self._workers.discard(worker)
        with self._maintenance_lock:
            self._maintenance_running = False

