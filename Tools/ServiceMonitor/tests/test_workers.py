from __future__ import annotations

import threading

from PySide6.QtCore import QThread

from opc_service_monitor.supervisor import OperationReport
from opc_service_monitor.workers import MonitorController, TaskWorker


def test_task_worker_returns_on_qt_thread(qtbot) -> None:
    worker = TaskWorker(lambda: "done")
    result: list[tuple[object, QThread]] = []
    worker.signals.result.connect(lambda value: result.append((value, QThread.currentThread())))

    with qtbot.waitSignal(worker.signals.finished, timeout=3000):
        worker.start()

    assert result == [("done", QThread.currentThread())]
    assert worker.function is None


class BlockingSupervisor:
    def __init__(self) -> None:
        self.entered = threading.Event()
        self.release = threading.Event()
        self.start_calls = 0
        self.refresh_calls = 0
        self._state_callback = lambda _observation: None
        self.owned_services = ()

    def set_state_callback(self, callback) -> None:
        self._state_callback = callback

    def start_all(self) -> OperationReport:
        self.start_calls += 1
        self.entered.set()
        assert self.release.wait(3)
        return OperationReport("start_all", ())

    def refresh(self):
        self.refresh_calls += 1
        self.entered.set()
        assert self.release.wait(3)
        return {}


def test_controller_rejects_rapid_duplicate_operations(qtbot) -> None:
    supervisor = BlockingSupervisor()
    controller = MonitorController(supervisor)

    assert controller.start_all() is True
    assert supervisor.entered.wait(2)
    assert controller.start_all() is False
    assert supervisor.start_calls == 1

    supervisor.release.set()
    with qtbot.waitSignal(controller.operation_finished, timeout=3000):
        pass
    assert controller.busy is False


def test_controller_refresh_is_single_flight(qtbot) -> None:
    supervisor = BlockingSupervisor()
    controller = MonitorController(supervisor)

    assert controller.refresh() is True
    assert supervisor.entered.wait(2)
    assert controller.refresh() is False
    assert supervisor.refresh_calls == 1

    supervisor.release.set()
    with qtbot.waitSignal(controller.refresh_finished, timeout=3000):
        pass


class FailingSupervisor(BlockingSupervisor):
    def start_all(self) -> OperationReport:
        raise RuntimeError("password=worker-secret")


def test_controller_redacts_worker_errors(qtbot) -> None:
    controller = MonitorController(FailingSupervisor())

    with qtbot.waitSignal(controller.operation_error, timeout=3000) as signal:
        assert controller.start_all() is True

    message = signal.args[0]
    assert "worker-secret" not in message
    assert "[REDACTED]" in message

