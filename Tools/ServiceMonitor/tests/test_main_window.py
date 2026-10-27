from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path

from PySide6.QtCore import QObject, Qt, Signal
from PySide6.QtWidgets import QPushButton, QTabWidget

from opc_service_monitor.catalog import build_catalog
from opc_service_monitor.models import ServiceId, ServiceState
from opc_service_monitor.paths import ProjectLayout
from opc_service_monitor.supervisor import OperationReport, OperationStep, ServiceObservation
from opc_service_monitor.ui.main_window import MainWindow
from opc_service_monitor.ui.service_card import ServiceCard


class FakeController(QObject):
    observation_changed = Signal(object)
    operation_started = Signal(str)
    operation_finished = Signal(object)
    operation_error = Signal(str)
    refresh_finished = Signal(object)

    def __init__(self) -> None:
        super().__init__()
        self.calls: list[object] = []
        self.busy = False
        self.owned_services = ()

    def start_all(self) -> bool:
        if self.busy:
            return False
        self.busy = True
        self.calls.append("start_all")
        self.operation_started.emit("start_all")
        return True

    def stop_all(self) -> bool:
        self.calls.append("stop_all")
        return True

    def start(self, service_id: ServiceId) -> bool:
        self.calls.append(("start", service_id))
        return True

    def stop(self, service_id: ServiceId) -> bool:
        self.calls.append(("stop", service_id))
        return True

    def refresh(self) -> bool:
        self.calls.append("refresh")
        return not self.busy


def _observation(
    service_id: ServiceId,
    state: ServiceState,
    *,
    pid: int | None = None,
    running: bool = False,
    owned: bool = False,
    external: bool = False,
) -> ServiceObservation:
    return ServiceObservation(
        service_id=service_id,
        state=state,
        process_running=running,
        port_open=running,
        live=True if running and service_id is ServiceId.BACKEND else None,
        ready=running,
        owned=owned,
        external=external,
        pid=pid,
        checked_at=datetime.now(UTC),
        summary="健康状态测试",
    )


def _window(opc_root: Path, qtbot):
    controller = FakeController()
    opened: list[str] = []
    window = MainWindow(
        controller,
        build_catalog(ProjectLayout.validate(opc_root)),
        url_opener=lambda url: opened.append(url) or True,
        confirm_close=lambda: False,
    )
    qtbot.addWidget(window)
    window.show()
    return window, controller, opened


def test_main_window_has_three_chinese_service_cards_and_five_tabs(opc_root: Path, qtbot) -> None:
    window, _controller, _opened = _window(opc_root, qtbot)

    cards = window.findChildren(ServiceCard)
    assert len(cards) == 3
    assert {card.title_label.text() for card in cards} == {"PostgreSQL", "后端服务", "后台管理前端"}
    tabs = window.findChild(QTabWidget, "logTabs")
    assert tabs is not None
    assert [tabs.tabText(index) for index in range(tabs.count())] == [
        "全部日志",
        "前端",
        "后端",
        "PostgreSQL",
        "业务审计",
    ]
    assert window.refresh_timer.interval() == 2000


def test_service_card_renders_states_and_reliable_pid_only(opc_root: Path, qtbot) -> None:
    window, controller, _opened = _window(opc_root, qtbot)
    card = window.cards[ServiceId.BACKEND]

    controller.observation_changed.emit(
        _observation(ServiceId.BACKEND, ServiceState.READY, pid=321, running=True, owned=True)
    )
    assert card.status_label.text() == "已就绪"
    assert card.pid_value.text() == "321"

    controller.observation_changed.emit(
        _observation(ServiceId.BACKEND, ServiceState.FAILED, pid=999, running=False, owned=False)
    )
    assert card.status_label.text() == "失败"
    assert card.pid_value.text() == "—"


def test_operation_disables_conflicting_buttons_and_double_click_runs_once(opc_root: Path, qtbot) -> None:
    window, controller, _opened = _window(opc_root, qtbot)
    start_all = window.findChild(QPushButton, "startAllButton")
    assert start_all is not None
    for service_id in ServiceId:
        controller.observation_changed.emit(_observation(service_id, ServiceState.STOPPED))

    qtbot.mouseClick(start_all, Qt.LeftButton)
    qtbot.mouseClick(start_all, Qt.LeftButton)

    assert controller.calls.count("start_all") == 1
    assert start_all.isEnabled() is False
    assert all(not card.start_button.isEnabled() for card in window.cards.values())

    controller.busy = False
    controller.operation_finished.emit(OperationReport("start_all", tuple(
        OperationStep(service_id, "start", True, "服务已启动", _observation(
            service_id, ServiceState.READY, running=True, owned=True,
        )) for service_id in ServiceId
    )))
    assert start_all.isEnabled() is False
    assert window.stop_all_button.isEnabled() is True


def test_external_instance_disables_stop_and_fixed_browser_targets(opc_root: Path, qtbot) -> None:
    window, controller, opened = _window(opc_root, qtbot)
    controller.observation_changed.emit(
        _observation(ServiceId.FRONTEND, ServiceState.EXTERNAL, pid=444, running=True, external=True)
    )
    assert window.cards[ServiceId.FRONTEND].stop_button.isEnabled() is False

    qtbot.mouseClick(window.open_admin_button, Qt.LeftButton)
    qtbot.mouseClick(window.open_swagger_button, Qt.LeftButton)
    assert opened == ["http://127.0.0.1:5180/#/dashboard", "http://127.0.0.1:8001/docs"]


def test_errors_are_actionable_redacted_and_no_mobile_actions_exist(opc_root: Path, qtbot) -> None:
    window, controller, _opened = _window(opc_root, qtbot)

    controller.operation_error.emit("启动失败 password=ui-secret")
    assert "ui-secret" not in window.error_banner.text()
    assert "[REDACTED]" in window.error_banner.text()

    all_text = " ".join(
        widget.text()
        for widget in window.findChildren(QPushButton)
        if hasattr(widget, "text")
    ).casefold()
    assert "flutter" not in all_text
    assert "adb" not in all_text


def test_close_is_blocked_while_lifecycle_operation_is_running(opc_root: Path, qtbot) -> None:
    window, controller, _opened = _window(opc_root, qtbot)
    controller.busy = True

    assert window.close() is False
    assert window.isVisible() is True
    assert "正在执行" in window.error_banner.text()


def test_confirmed_close_waits_for_successful_stop_all(opc_root: Path, qtbot) -> None:
    controller = FakeController()
    controller.owned_services = (ServiceId.BACKEND,)
    window = MainWindow(
        controller,
        build_catalog(ProjectLayout.validate(opc_root)),
        confirm_close=lambda: True,
    )
    qtbot.addWidget(window)
    window.show()

    assert window.close() is False
    assert controller.calls == ["stop_all"]
    assert window.isVisible() is True

    observation = _observation(ServiceId.BACKEND, ServiceState.STOPPED)
    controller.owned_services = ()
    controller.operation_finished.emit(
        OperationReport(
            "stop_all",
            (OperationStep(ServiceId.BACKEND, "stop", True, "服务已停止", observation),),
        )
    )
    qtbot.waitUntil(lambda: not window.isVisible())

