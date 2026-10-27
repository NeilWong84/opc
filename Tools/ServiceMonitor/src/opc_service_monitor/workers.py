from __future__ import annotations

import threading
from collections.abc import Callable
from typing import Any

from PySide6.QtCore import QObject, QRunnable, QThreadPool, Signal, Slot

from opc_service_monitor.log_pipeline import redact_log_text
from opc_service_monitor.models import ServiceId
from opc_service_monitor.supervisor import ServiceSupervisor, SupervisorTimeouts


class WorkerSignals(QObject):
    result = Signal(object)
    error = Signal(str)
    finished = Signal()


class TaskWorker(QRunnable):
    def __init__(self, function: Callable[[], Any]) -> None:
        super().__init__()
        self.function: Callable[[], Any] | None = function
        self.signals = WorkerSignals()
        self.setAutoDelete(False)

    def start(self, pool: QThreadPool | None = None) -> None:
        (pool or QThreadPool.globalInstance()).start(self)

    @Slot()
    def run(self) -> None:
        function = self.function
        if function is None:
            self.signals.error.emit("后台任务已释放")
            self.signals.finished.emit()
            return
        try:
            result = function()
        except Exception as exc:
            self.signals.error.emit(redact_log_text(str(exc)) or "后台任务执行失败")
        else:
            self.signals.result.emit(result)
        finally:
            self.function = None
            function = None
            self.signals.finished.emit()


class MonitorController(QObject):
    observation_changed = Signal(object)
    operation_started = Signal(str)
    operation_finished = Signal(object)
    operation_error = Signal(str)
    refresh_finished = Signal(object)

    def __init__(self, supervisor: ServiceSupervisor, pool: QThreadPool | None = None) -> None:
        super().__init__()
        self._supervisor = supervisor
        self._pool = pool or QThreadPool.globalInstance()
        self._busy_lock = threading.Lock()
        self._busy = False
        self._workers: set[TaskWorker] = set()
        setter = getattr(supervisor, "set_state_callback", None)
        if callable(setter):
            setter(self.observation_changed.emit)

    @property
    def busy(self) -> bool:
        with self._busy_lock:
            return self._busy

    @property
    def owned_services(self) -> tuple[ServiceId, ...]:
        return tuple(self._supervisor.owned_services)

    @property
    def timeouts(self) -> SupervisorTimeouts:
        return self._supervisor.timeouts

    def update_timeouts(self, timeouts: SupervisorTimeouts) -> None:
        if self.busy:
            raise RuntimeError("服务操作正在执行，暂时不能修改超时设置")
        self._supervisor.update_timeouts(timeouts)

    def start_all(self) -> bool:
        return self._launch_operation("start_all", self._supervisor.start_all)

    def stop_all(self) -> bool:
        return self._launch_operation("stop_all", self._supervisor.stop_all)

    def start(self, service_id: ServiceId) -> bool:
        return self._launch_operation(f"start:{service_id.value}", lambda: self._supervisor.start(service_id))

    def stop(self, service_id: ServiceId) -> bool:
        return self._launch_operation(f"stop:{service_id.value}", lambda: self._supervisor.stop(service_id))

    def refresh(self) -> bool:
        if not self._claim_busy():
            return False
        worker = TaskWorker(self._supervisor.refresh)
        self._workers.add(worker)
        worker.signals.result.connect(lambda result: self._refresh_success(worker, result))
        worker.signals.error.connect(lambda message: self._worker_error(worker, message))
        worker.signals.finished.connect(lambda: self._complete(worker))
        worker.start(self._pool)
        return True

    def shutdown(self, timeout_ms: int = 3_000) -> bool:
        return self._pool.waitForDone(timeout_ms)

    def _launch_operation(self, name: str, function: Callable[[], Any]) -> bool:
        if not self._claim_busy():
            return False
        self.operation_started.emit(name)
        worker = TaskWorker(function)
        self._workers.add(worker)
        worker.signals.result.connect(lambda result: self._operation_success(worker, result))
        worker.signals.error.connect(lambda message: self._worker_error(worker, message))
        worker.signals.finished.connect(lambda: self._complete(worker))
        worker.start(self._pool)
        return True

    def _claim_busy(self) -> bool:
        with self._busy_lock:
            if self._busy:
                return False
            self._busy = True
            return True

    def _complete(self, worker: TaskWorker) -> None:
        self._workers.discard(worker)
        with self._busy_lock:
            self._busy = False

    def _operation_success(self, worker: TaskWorker, result: object) -> None:
        self._complete(worker)
        self.operation_finished.emit(result)

    def _refresh_success(self, worker: TaskWorker, result: object) -> None:
        self._complete(worker)
        self.refresh_finished.emit(result)

    def _worker_error(self, worker: TaskWorker, message: str) -> None:
        self._complete(worker)
        self.operation_error.emit(message)

