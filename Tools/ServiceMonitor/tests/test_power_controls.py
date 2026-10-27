from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path

import pytest
from PySide6.QtCore import QObject, Qt, Signal

from opc_service_monitor.catalog import build_catalog
from opc_service_monitor.models import ServiceId, ServiceState
from opc_service_monitor.paths import ProjectLayout
from opc_service_monitor.supervisor import OperationReport, OperationStep, ServiceObservation
from opc_service_monitor.ui.main_window import MainWindow
from opc_service_monitor.ui.service_actions import aggregate_actions, service_actions


SERVICE_IDS = (ServiceId.POSTGRES, ServiceId.BACKEND, ServiceId.FRONTEND)


def _observed(
    service_id: ServiceId,
    state: ServiceState = ServiceState.STOPPED,
    *,
    running: bool = False,
    owned: bool = False,
    external: bool = False,
    port_open: bool | None = None,
) -> ServiceObservation:
    return ServiceObservation(
        service_id=service_id,
        state=state,
        process_running=running,
        port_open=running if port_open is None else port_open,
        live=running if service_id is ServiceId.BACKEND else None,
        ready=running and state in {ServiceState.READY, ServiceState.EXTERNAL},
        owned=owned,
        external=external,
        pid=42 if running else None,
        checked_at=datetime.now(UTC),
        summary="合成开关状态测试",
        listener_identified=running,
    )


def _stopped() -> dict[ServiceId, ServiceObservation]:
    return {service_id: _observed(service_id) for service_id in SERVICE_IDS}


def _ready_with_external_postgres() -> dict[ServiceId, ServiceObservation]:
    return {
        ServiceId.POSTGRES: _observed(ServiceId.POSTGRES, ServiceState.EXTERNAL, running=True, external=True),
        ServiceId.BACKEND: _observed(ServiceId.BACKEND, ServiceState.READY, running=True, owned=True),
        ServiceId.FRONTEND: _observed(ServiceId.FRONTEND, ServiceState.READY, running=True, owned=True),
    }


@pytest.mark.parametrize(
    ("observation", "can_start", "can_stop", "power_on"),
    [
        (None, False, False, None),
        (_observed(ServiceId.BACKEND), True, False, False),
        (_observed(ServiceId.BACKEND, ServiceState.FAILED), True, False, False),
        (_observed(ServiceId.BACKEND, ServiceState.READY, running=True, owned=True), False, True, True),
        (_observed(ServiceId.BACKEND, ServiceState.RUNNING_NOT_READY, running=True, owned=True), False, True, True),
        (_observed(ServiceId.BACKEND, ServiceState.FAILED, running=True, owned=True), False, True, True),
        (_observed(ServiceId.BACKEND, ServiceState.EXTERNAL, running=True, external=True), False, False, True),
        (_observed(ServiceId.BACKEND, ServiceState.EXTERNAL, port_open=True, external=True), False, False, None),
        (_observed(ServiceId.BACKEND, ServiceState.STARTING, running=True, owned=True), False, False, None),
        (_observed(ServiceId.BACKEND, ServiceState.STOPPING, running=True, owned=True), False, False, None),
    ],
    ids=["unchecked", "stopped", "failed-exited", "ready", "not-ready", "failed-owned-running", "external", "unidentified-listener", "starting", "stopping"],
)
def test_single_service_actions_follow_process_state_and_ownership(
    observation: ServiceObservation | None, can_start: bool, can_stop: bool, power_on: bool | None
) -> None:
    actions = service_actions(observation)
    assert (actions.can_start, actions.can_stop, actions.power_on) == (can_start, can_stop, power_on)
    assert actions.reason


def test_global_actions_only_offer_needed_authorized_operations() -> None:
    observations = _stopped()
    actions = aggregate_actions(observations)
    assert (actions.can_start, actions.can_stop, actions.power_on) == (True, False, False)

    observations = _ready_with_external_postgres()
    actions = aggregate_actions(observations)
    assert (actions.can_start, actions.can_stop, actions.power_on) == (False, True, True)

    observations[ServiceId.FRONTEND] = _observed(ServiceId.FRONTEND)
    actions = aggregate_actions(observations)
    assert (actions.can_start, actions.can_stop, actions.power_on) == (True, True, None)

    observations[ServiceId.BACKEND] = _observed(ServiceId.BACKEND)
    actions = aggregate_actions(observations)
    assert actions.can_start is True
    assert actions.can_stop is False
    assert actions.power_on is None


def test_global_controls_wait_for_all_targets_and_never_stop_external_only() -> None:
    assert not aggregate_actions({}).can_start
    observations = _stopped()
    del observations[ServiceId.FRONTEND]
    assert not aggregate_actions(observations).can_start
    observations[ServiceId.BACKEND] = _observed(ServiceId.BACKEND, ServiceState.READY, running=True, owned=True)
    actions = aggregate_actions(observations)
    assert actions.can_start is False
    assert actions.can_stop is True

    observations = {
        service_id: _observed(service_id, ServiceState.EXTERNAL, running=True, external=True)
        for service_id in SERVICE_IDS
    }
    actions = aggregate_actions(observations)
    assert (actions.can_start, actions.can_stop, actions.power_on) == (False, False, True)


@pytest.mark.parametrize("state", [ServiceState.STARTING, ServiceState.STOPPING])
def test_any_transition_locks_both_global_actions(state: ServiceState) -> None:
    observations = _stopped()
    observations[ServiceId.BACKEND] = _observed(ServiceId.BACKEND, state, running=True, owned=True)
    actions = aggregate_actions(observations)
    assert (actions.can_start, actions.can_stop) == (False, False)


def test_busy_overrides_new_observations_for_single_and_global_actions() -> None:
    observations = _ready_with_external_postgres()
    actions = aggregate_actions(observations, busy=True)
    assert (actions.can_start, actions.can_stop) == (False, False)
    actions = service_actions(observations[ServiceId.BACKEND], busy=True)
    assert (actions.can_start, actions.can_stop) == (False, False)


class PowerController(QObject):
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

    def _begin(self, action: str, service_id: ServiceId | None = None) -> bool:
        if self.busy:
            return False
        self.calls.append((action, service_id) if service_id else action)
        self.busy = True
        self.operation_started.emit(f"{action}:{service_id.value}" if service_id else action)
        return True

    def start_all(self) -> bool:
        return self._begin("start_all")

    def stop_all(self) -> bool:
        return self._begin("stop_all")

    def start(self, service_id: ServiceId) -> bool:
        return self._begin("start", service_id)

    def stop(self, service_id: ServiceId) -> bool:
        return self._begin("stop", service_id)

    def refresh(self) -> bool:
        return not self.busy

    def observe(self, observations: dict[ServiceId, ServiceObservation]) -> None:
        for observation in observations.values():
            self.observation_changed.emit(observation)

    def finish(
        self, action: str, observations: dict[ServiceId, ServiceObservation], *, failed: ServiceId | None = None
    ) -> None:
        self.busy = False
        steps = tuple(
            OperationStep(service_id, "start", service_id is not failed, "状态测试", observation)
            for service_id, observation in observations.items()
        )
        self.operation_finished.emit(OperationReport(action, steps))


@pytest.fixture
def power_window(opc_root: Path, qtbot):
    controller = PowerController()
    window = MainWindow(controller, build_catalog(ProjectLayout.validate(opc_root)))
    qtbot.addWidget(window)
    window.refresh_timer.stop()
    window.show()
    yield window, controller
    controller.busy = False


def _assert_switch(control, enabled: tuple[bool, bool], checked: tuple[bool, bool]) -> None:
    assert control.start_button.isCheckable() and control.stop_button.isCheckable()
    assert (control.start_button.isEnabled(), control.stop_button.isEnabled()) == enabled
    assert (control.start_button.isChecked(), control.stop_button.isChecked()) == checked


def test_initial_unchecked_state_disables_every_switch(power_window) -> None:
    window, controller = power_window
    _assert_switch(window.power_control, (False, False), (False, False))
    for card in window.cards.values():
        _assert_switch(card.power_control, (False, False), (False, False))
        card.start_button.click()
        card.stop_button.click()
    window.start_all_button.click()
    window.stop_all_button.click()
    assert controller.calls == []


def test_all_ready_disables_redundant_start_and_protects_external_service(power_window) -> None:
    window, controller = power_window
    controller.observe(_ready_with_external_postgres())
    _assert_switch(window.power_control, (False, True), (True, False))
    _assert_switch(window.cards[ServiceId.POSTGRES].power_control, (False, False), (True, False))
    for service_id in (ServiceId.BACKEND, ServiceId.FRONTEND):
        _assert_switch(window.cards[service_id].power_control, (False, True), (True, False))
    window.start_all_button.click()
    for card in window.cards.values():
        card.start_button.click()
    window.cards[ServiceId.POSTGRES].stop_button.click()
    assert controller.calls == []


def test_start_click_does_not_select_on_and_refresh_cannot_unlock_busy_switch(power_window, qtbot) -> None:
    window, controller = power_window
    controller.observe(_stopped())
    _assert_switch(window.power_control, (True, False), (False, True))
    qtbot.mouseClick(window.start_all_button, Qt.LeftButton)
    qtbot.mouseClick(window.start_all_button, Qt.LeftButton)
    assert controller.calls == ["start_all"]
    _assert_switch(window.power_control, (False, False), (False, True))

    observations = _ready_with_external_postgres()
    controller.refresh_finished.emit(observations)
    assert not window.start_all_button.isEnabled() and not window.stop_all_button.isEnabled()
    assert all(not card.start_button.isEnabled() and not card.stop_button.isEnabled() for card in window.cards.values())
    controller.finish("start_all", observations)
    _assert_switch(window.power_control, (False, True), (True, False))


def test_partial_failure_restores_actions_from_observations_not_report_success(power_window, qtbot) -> None:
    window, controller = power_window
    controller.observe(_stopped())
    qtbot.mouseClick(window.start_all_button, Qt.LeftButton)
    observations = _ready_with_external_postgres()
    observations[ServiceId.FRONTEND] = _observed(ServiceId.FRONTEND, ServiceState.FAILED)
    controller.finish("start_all", observations, failed=ServiceId.FRONTEND)

    _assert_switch(window.power_control, (True, True), (False, False))
    _assert_switch(window.cards[ServiceId.BACKEND].power_control, (False, True), (True, False))
    _assert_switch(window.cards[ServiceId.FRONTEND].power_control, (True, False), (False, True))
    assert window.error_banner.isVisible()


def test_single_service_click_and_error_keep_observed_state_until_refresh(power_window, qtbot) -> None:
    window, controller = power_window
    controller.observe(_stopped())
    card = window.cards[ServiceId.FRONTEND]
    qtbot.mouseClick(card.start_button, Qt.LeftButton)
    assert controller.calls == [("start", ServiceId.FRONTEND)]
    assert not card.start_button.isChecked() and card.stop_button.isChecked()
    assert not card.start_button.isEnabled() and not card.stop_button.isEnabled()

    controller.observe({ServiceId.FRONTEND: _observed(ServiceId.FRONTEND, ServiceState.FAILED, running=True, owned=True)})
    assert not card.start_button.isEnabled() and not card.stop_button.isEnabled()
    controller.busy = False
    controller.operation_error.emit("合成启动超时")
    _assert_switch(card.power_control, (False, True), (True, False))
    assert not card.start_button.isEnabled()


def test_stop_click_cannot_select_off_before_process_is_observed_stopped(power_window, qtbot) -> None:
    window, controller = power_window
    observations = _ready_with_external_postgres()
    controller.observe(observations)
    card = window.cards[ServiceId.BACKEND]
    qtbot.mouseClick(card.stop_button, Qt.LeftButton)
    assert controller.calls == [("stop", ServiceId.BACKEND)]
    assert card.start_button.isChecked() and not card.stop_button.isChecked()
    observations[ServiceId.BACKEND] = _observed(ServiceId.BACKEND)
    controller.finish("stop:backend", observations)
    _assert_switch(card.power_control, (True, False), (False, True))
    _assert_switch(window.power_control, (True, True), (False, False))
