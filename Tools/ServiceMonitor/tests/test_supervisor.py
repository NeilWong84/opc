from __future__ import annotations

import threading
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

import pytest

from opc_service_monitor.catalog import build_catalog
from opc_service_monitor.models import HealthResult, ServiceId, ServiceState
from opc_service_monitor.paths import ProjectLayout
from opc_service_monitor.postgres import PostgresStartResult, PostgresStatus
from opc_service_monitor.processes import OwnedProcess, OwnershipCheck, PortOccupancy, ProcessIdentity
from opc_service_monitor.supervisor import (
    CancelToken,
    OperationBusyError,
    ServiceSupervisor,
    SupervisorTimeouts,
)


def _health(*, live: bool | None = None, ready: bool | None = None, port: bool | None = None) -> HealthResult:
    return HealthResult(
        checked_at=datetime.now(UTC),
        reachable=bool(port or live or ready),
        port_open=port,
        live=live,
        ready=ready,
        summary="test",
    )


class FakeHealth:
    def __init__(self) -> None:
        self.backend = _health(live=True, ready=True)
        self.frontend = _health(ready=True)

    def probe_backend(self) -> HealthResult:
        return self.backend

    def probe_frontend(self) -> HealthResult:
        return self.frontend


class FakeSpawned:
    def __init__(self, identity: ProcessIdentity, command) -> None:
        self.identity = identity
        self.command = command

    def as_owned(self, service_id: ServiceId, *, expected_command_fragments=()) -> OwnedProcess:
        return OwnedProcess(service_id, self.identity, self.command, tuple(expected_command_fragments))


class FakeProcesses:
    def __init__(self, catalog, order: list[str]) -> None:
        self.catalog = catalog
        self.order = order
        self.listeners: dict[int, ProcessIdentity | None] = {}
        self.listener_pids: dict[int, int | None] = {}
        self.identities: dict[int, ProcessIdentity] = {}
        self.descendant_on_spawn: dict[ServiceId, ProcessIdentity] = {}
        self.competitor_on_spawn: dict[ServiceId, ProcessIdentity] = {}
        self.exit_wrapper_on_spawn: set[ServiceId] = set()
        self.stop_attempts: list[ServiceId] = []
        self.fail_stop_for: ServiceId | None = None
        self.leave_listener_on_stop_for: ServiceId | None = None
        self._pid = 1000

    def _service_for_command(self, command) -> ServiceId:
        for service_id, definition in self.catalog.items():
            if definition.start_command == command:
                return service_id
        raise AssertionError(command)

    def listener(self, host: str, port: int) -> PortOccupancy:
        assert host == "127.0.0.1"
        if port not in self.listeners:
            return PortOccupancy(False)
        identity = self.listeners[port]
        pid = identity.pid if identity is not None else self.listener_pids.get(port)
        return PortOccupancy(True, identity, pid, host)

    def spawn(self, command, _output) -> FakeSpawned:
        service_id = self._service_for_command(command)
        self.order.append(service_id.value)
        self._pid += 1
        identity = ProcessIdentity(
            self._pid,
            self._pid * 1_000_000_000,
            command.executable,
            (command.executable, *command.arguments),
        )
        self.identities[identity.pid] = identity
        listener = self.competitor_on_spawn.get(service_id)
        if listener is None:
            listener = self.descendant_on_spawn.get(service_id, identity)
        self.listeners[self.catalog[service_id].port] = listener
        self.listener_pids[self.catalog[service_id].port] = listener.pid
        if listener != identity and service_id in self.descendant_on_spawn:
            self.identities[listener.pid] = listener
        if service_id in self.exit_wrapper_on_spawn:
            self.identities.pop(identity.pid, None)
        return FakeSpawned(identity, command)

    def inspect(self, pid: int) -> ProcessIdentity | None:
        return self.identities.get(pid) or next(
            (item for item in self.listeners.values() if item is not None and item.pid == pid),
            None,
        )

    def validate_owned(self, owned: OwnedProcess) -> OwnershipCheck:
        current = self.inspect(owned.identity.pid)
        if current == owned.identity:
            return OwnershipCheck(True, "ok", current)
        for descendant in owned.descendant_identities:
            current = self.inspect(descendant.pid)
            if current == descendant:
                return OwnershipCheck(True, "descendant", current)
        return OwnershipCheck(False, "mismatch", current)

    def validate_listener_owned(
        self,
        owned: OwnedProcess,
        listener: ProcessIdentity,
    ) -> OwnershipCheck:
        if listener == owned.identity and self.inspect(listener.pid) == listener:
            return OwnershipCheck(True, "root", listener)
        descendant = self.descendant_on_spawn.get(owned.service_id)
        if descendant == listener and self.inspect(listener.pid) == listener:
            owned.descendant_identities = (descendant,)
            return OwnershipCheck(True, "descendant", listener)
        return OwnershipCheck(False, "competing listener", listener)

    def request_stop(self, owned: OwnedProcess, timeout_s: float) -> bool:
        assert timeout_s >= 0
        self.stop_attempts.append(owned.service_id)
        self.order.append(f"stop:{owned.service_id.value}")
        if self.fail_stop_for is owned.service_id:
            return False
        tracked = {owned.identity, *owned.descendant_identities}
        for identity in tracked:
            self.identities.pop(identity.pid, None)
        port = self.catalog[owned.service_id].port
        if self.leave_listener_on_stop_for is not owned.service_id and self.listeners.get(port) in tracked:
            self.listeners.pop(port, None)
            self.listener_pids.pop(port, None)
        return True

    def force_stop(self, owned: OwnedProcess, timeout_s: float) -> bool:
        assert timeout_s > 0
        if self.fail_stop_for is owned.service_id:
            return False
        tracked = {owned.identity, *owned.descendant_identities}
        for identity in tracked:
            self.identities.pop(identity.pid, None)
        port = self.catalog[owned.service_id].port
        if self.listeners.get(port) in tracked:
            self.listeners.pop(port, None)
            self.listener_pids.pop(port, None)
        return True


class FakePostgres:
    def __init__(self, definition, order: list[str]) -> None:
        self.definition = definition
        self.order = order
        self.running = False
        self.external = False
        self.owned: OwnedProcess | None = None
        self.fail_start = False
        self.fail_stop = False
        self.start_entered: threading.Event | None = None
        self.start_release: threading.Event | None = None

    def status(self) -> PostgresStatus:
        listener = self.owned.identity if self.owned is not None and self.running else None
        return PostgresStatus(
            self.running,
            listener,
            self.owned is not None and self.running,
            self.external,
            "test",
        )

    def start(self, timeout_s: float) -> PostgresStartResult:
        assert 5 <= timeout_s <= 120
        self.order.append(ServiceId.POSTGRES.value)
        if self.start_entered is not None:
            self.start_entered.set()
        if self.start_release is not None:
            assert self.start_release.wait(3)
        if self.fail_start:
            raise RuntimeError("pg failed")
        identity = ProcessIdentity(900, 900_000_000_000, "postgres.exe", ("postgres.exe", "-D", "data"))
        self.owned = OwnedProcess(ServiceId.POSTGRES, identity, self.definition.start_command, ("data",))
        self.running = True
        return PostgresStartResult(self.status(), self.owned)

    def stop(self, owned: OwnedProcess, timeout_s: float) -> PostgresStatus:
        assert owned == self.owned
        assert 5 <= timeout_s <= 120
        self.order.append("stop:postgresql")
        if self.fail_stop:
            raise RuntimeError("pg stop failed")
        self.running = False
        self.owned = None
        return self.status()


@dataclass
class FakeClock:
    current: float = 0.0

    def __call__(self) -> float:
        return self.current

    def wait(self, seconds: float) -> None:
        self.current += seconds


def _supervisor(opc_root: Path):
    layout = ProjectLayout.validate(opc_root)
    catalog = build_catalog(layout)
    order: list[str] = []
    processes = FakeProcesses(catalog, order)
    postgres = FakePostgres(catalog[ServiceId.POSTGRES], order)
    health = FakeHealth()
    clock = FakeClock()
    supervisor = ServiceSupervisor(
        catalog,
        processes,
        postgres,
        health,
        clock=clock,
        waiter=clock.wait,
    )
    return supervisor, processes, postgres, health, order


def test_timeout_defaults_and_bounds() -> None:
    assert SupervisorTimeouts().for_service(ServiceId.POSTGRES) == 30
    assert SupervisorTimeouts().for_service(ServiceId.BACKEND) == 30
    assert SupervisorTimeouts().for_service(ServiceId.FRONTEND) == 30
    SupervisorTimeouts(postgres=5, backend=120, frontend=30)
    with pytest.raises(ValueError, match="5.*120"):
        SupervisorTimeouts(backend=4)
    with pytest.raises(ValueError, match="5.*120"):
        SupervisorTimeouts(frontend=121)


def test_start_all_uses_dependency_order_and_real_readiness(opc_root: Path) -> None:
    supervisor, _processes, _postgres, _health_client, order = _supervisor(opc_root)

    report = supervisor.start_all()

    assert report.success is True
    assert order == ["postgresql", "backend", "frontend"]
    assert [step.service_id for step in report.steps] == [
        ServiceId.POSTGRES,
        ServiceId.BACKEND,
        ServiceId.FRONTEND,
    ]
    assert all(step.observation.state is ServiceState.READY for step in report.steps)


def test_start_failure_stops_later_steps_without_rollback(opc_root: Path) -> None:
    supervisor, processes, postgres, health, order = _supervisor(opc_root)
    health.backend = _health(live=True, ready=False)

    report = supervisor.start_all()

    assert report.success is False
    assert order == ["postgresql", "backend"]
    assert postgres.running is True
    assert ServiceId.BACKEND in supervisor.owned_services
    assert processes.stop_attempts == []
    assert report.steps[-1].observation.state is ServiceState.FAILED


def test_stop_all_uses_reverse_order(opc_root: Path) -> None:
    supervisor, _processes, _postgres, _health, order = _supervisor(opc_root)
    assert supervisor.start_all().success
    order.clear()

    report = supervisor.stop_all()

    assert report.success is True
    assert order == ["stop:frontend", "stop:backend", "stop:postgresql"]
    assert supervisor.owned_services == ()


def test_stop_all_preserves_external_postgres_and_stops_owned_application_services(opc_root: Path) -> None:
    supervisor, processes, postgres, _health, order = _supervisor(opc_root)
    postgres.running = True
    postgres.external = True
    assert supervisor.start(ServiceId.BACKEND).success
    assert supervisor.start(ServiceId.FRONTEND).success
    order.clear()

    report = supervisor.stop_all()

    assert report.success is True
    assert order == ["stop:frontend", "stop:backend"]
    assert processes.stop_attempts == [ServiceId.FRONTEND, ServiceId.BACKEND]
    assert postgres.running is True
    assert postgres.external is True
    assert postgres.owned is None
    assert supervisor.owned_services == ()
    assert report.steps[-1].service_id is ServiceId.POSTGRES
    assert report.steps[-1].observation.state is ServiceState.EXTERNAL
    assert "跳过" in report.steps[-1].message
    assert "保持运行" in report.steps[-1].message


def test_stop_all_skips_external_frontend_without_blocking_owned_dependencies(opc_root: Path) -> None:
    supervisor, processes, postgres, _health, order = _supervisor(opc_root)
    frontend = processes.catalog[ServiceId.FRONTEND]
    external = ProcessIdentity(2999, 2_999_000_000_000, "external.exe", ("external.exe",))
    processes.listeners[frontend.port] = external
    assert supervisor.start_all().success
    order.clear()

    report = supervisor.stop_all()

    assert report.success is True
    assert order == ["stop:backend", "stop:postgresql"]
    assert processes.stop_attempts == [ServiceId.BACKEND]
    assert processes.listeners[frontend.port] == external
    assert postgres.running is False
    assert supervisor.owned_services == ()
    assert report.steps[0].observation.external is True
    assert "保持运行" in report.steps[0].message


@pytest.mark.parametrize("service_id", tuple(ServiceId))
def test_single_stop_still_refuses_external_service(opc_root: Path, service_id: ServiceId) -> None:
    supervisor, processes, postgres, _health, order = _supervisor(opc_root)
    if service_id is ServiceId.POSTGRES:
        postgres.running = True
        postgres.external = True
    else:
        definition = processes.catalog[service_id]
        processes.listeners[definition.port] = ProcessIdentity(
            2998, 2_998_000_000_000, "external.exe", ("external.exe",)
        )

    report = supervisor.stop(service_id)

    assert report.success is False
    assert report.steps[0].observation.external is True
    assert "不会" in report.steps[0].message
    assert processes.stop_attempts == []
    assert order == []


def test_stop_all_cleans_owned_wrapper_but_still_fails_for_competing_external_listener(opc_root: Path) -> None:
    supervisor, processes, postgres, _health, order = _supervisor(opc_root)
    frontend = processes.catalog[ServiceId.FRONTEND]
    competitor = ProcessIdentity(2997, 2_997_000_000_000, "other.exe", ("other.exe", "--port", "5180"))
    processes.competitor_on_spawn[ServiceId.FRONTEND] = competitor
    assert supervisor.start_all().success is False
    assert ServiceId.FRONTEND in supervisor.owned_services
    order.clear()

    report = supervisor.stop_all()

    assert report.success is False
    assert order == ["stop:frontend"]
    assert processes.stop_attempts == [ServiceId.FRONTEND]
    assert processes.listeners[frontend.port] == competitor
    assert ServiceId.FRONTEND not in supervisor.owned_services
    assert ServiceId.BACKEND in supervisor.owned_services
    assert postgres.running is True
    assert "端口" in report.steps[0].message


def test_failed_stop_prevents_dependency_shutdown(opc_root: Path) -> None:
    supervisor, processes, postgres, _health, order = _supervisor(opc_root)
    assert supervisor.start_all().success
    order.clear()
    processes.fail_stop_for = ServiceId.FRONTEND

    report = supervisor.stop_all()

    assert report.success is False
    assert order == ["stop:frontend"]
    assert postgres.running is True
    assert ServiceId.BACKEND in supervisor.owned_services


def test_stop_does_not_report_success_while_service_port_is_still_listening(opc_root: Path) -> None:
    supervisor, processes, _postgres, _health, _order = _supervisor(opc_root)
    assert supervisor.start_all().success is True
    processes.leave_listener_on_stop_for = ServiceId.FRONTEND

    report = supervisor.stop(ServiceId.FRONTEND)

    assert report.success is False
    assert report.steps[0].observation.port_open is True
    assert "端口" in report.steps[0].message


def test_external_listener_is_observed_but_never_stopped(opc_root: Path) -> None:
    supervisor, processes, _postgres, _health, _order = _supervisor(opc_root)
    backend = processes.catalog[ServiceId.BACKEND]
    processes.listeners[backend.port] = ProcessIdentity(
        777,
        777_000_000_000,
        "external.exe",
        ("external.exe",),
    )

    observations = supervisor.refresh()
    report = supervisor.stop(ServiceId.BACKEND)

    assert observations[ServiceId.BACKEND].state is ServiceState.EXTERNAL
    assert report.success is False
    assert processes.stop_attempts == []


@pytest.mark.parametrize("service_id", [ServiceId.BACKEND, ServiceId.FRONTEND])
def test_owned_process_without_listener_remains_stoppable(opc_root: Path, service_id: ServiceId) -> None:
    supervisor, processes, _postgres, _health, _order = _supervisor(opc_root)
    assert supervisor.start(service_id).success
    definition = processes.catalog[service_id]
    owned_pid = processes.listeners.pop(definition.port).pid
    processes.listener_pids.pop(definition.port)

    observation = supervisor.refresh()[service_id]

    assert observation.state is ServiceState.RUNNING_NOT_READY
    assert observation.process_running is True
    assert observation.port_open is False
    assert observation.owned is True
    assert observation.external is False
    assert observation.pid == owned_pid
    assert observation.ready is False

    report = supervisor.stop(service_id)

    assert report.success is True
    assert processes.stop_attempts == [service_id]
    assert processes.inspect(owned_pid) is None
    assert service_id not in supervisor.owned_services


@pytest.mark.parametrize("service_id", [ServiceId.BACKEND, ServiceId.FRONTEND])
def test_owned_process_does_not_claim_replacement_external_listener(opc_root: Path, service_id: ServiceId) -> None:
    supervisor, processes, _postgres, _health, _order = _supervisor(opc_root)
    assert supervisor.start(service_id).success
    definition = processes.catalog[service_id]
    owned_pid = processes.listeners[definition.port].pid
    competitor = ProcessIdentity(2996, 2_996_000_000_000, "other.exe", ("other.exe",))
    processes.listeners[definition.port] = competitor

    observation = supervisor.refresh()[service_id]

    assert processes.inspect(owned_pid) is not None
    assert observation.state is ServiceState.EXTERNAL
    assert observation.process_running is True
    assert observation.port_open is True
    assert observation.owned is False
    assert observation.external is True
    assert observation.pid == competitor.pid

    report = supervisor.stop(service_id)

    assert report.success is False
    assert processes.inspect(owned_pid) is None
    assert processes.listeners[definition.port] == competitor
    assert service_id not in supervisor.owned_services


@pytest.mark.parametrize("listener_pid", [None, 778], ids=["pid-missing", "inspection-denied"])
def test_uninspectable_occupied_port_blocks_start_without_spawning(
    opc_root: Path,
    listener_pid: int | None,
) -> None:
    supervisor, processes, _postgres, _health, order = _supervisor(opc_root)
    backend = processes.catalog[ServiceId.BACKEND]
    processes.listeners[backend.port] = None
    processes.listener_pids[backend.port] = listener_pid

    report = supervisor.start(ServiceId.BACKEND)

    assert report.success is False
    assert report.steps[0].observation.external is True
    assert report.steps[0].observation.owned is False
    assert ServiceId.BACKEND.value not in order


def test_competing_listener_after_spawn_is_not_claimed_or_stopped(opc_root: Path) -> None:
    supervisor, processes, _postgres, _health, _order = _supervisor(opc_root)
    competitor = ProcessIdentity(
        1777,
        1_777_000_000_000,
        "other.exe",
        ("other.exe", "--port", "8001"),
    )
    processes.competitor_on_spawn[ServiceId.BACKEND] = competitor

    start_report = supervisor.start(ServiceId.BACKEND)

    assert start_report.success is False
    assert start_report.steps[0].observation.external is True
    assert start_report.steps[0].observation.owned is False
    assert ServiceId.BACKEND in supervisor.owned_services

    stop_report = supervisor.stop(ServiceId.BACKEND)

    assert stop_report.success is False
    assert processes.stop_attempts == [ServiceId.BACKEND]
    assert processes.listeners[processes.catalog[ServiceId.BACKEND].port] == competitor
    assert ServiceId.BACKEND not in supervisor.owned_services


def test_stop_cleans_verified_descendant_after_wrapper_exits(opc_root: Path) -> None:
    supervisor, processes, _postgres, _health, _order = _supervisor(opc_root)
    descendant = ProcessIdentity(
        1888,
        1_888_000_000_000,
        "backend.exe",
        ("backend.exe", "--port", "8001"),
    )
    processes.descendant_on_spawn[ServiceId.BACKEND] = descendant
    assert supervisor.start(ServiceId.BACKEND).success is True
    wrapper_pid = next(pid for pid in processes.identities if pid != descendant.pid)
    processes.identities.pop(wrapper_pid)

    report = supervisor.stop(ServiceId.BACKEND)

    assert report.success is True
    assert processes.inspect(descendant.pid) is None
    assert ServiceId.BACKEND not in supervisor.owned_services


def test_start_retains_ownership_when_listener_is_verified_after_wrapper_early_exit(
    opc_root: Path,
) -> None:
    supervisor, processes, _postgres, _health, _order = _supervisor(opc_root)
    descendant = ProcessIdentity(
        1889,
        1_889_000_000_000,
        "backend.exe",
        ("backend.exe", "--port", "8001"),
    )
    processes.descendant_on_spawn[ServiceId.BACKEND] = descendant
    processes.exit_wrapper_on_spawn.add(ServiceId.BACKEND)

    report = supervisor.start(ServiceId.BACKEND)

    assert report.success is True
    assert report.steps[0].observation.owned is True
    assert ServiceId.BACKEND in supervisor.owned_services


def test_duplicate_lifecycle_operation_is_rejected(opc_root: Path) -> None:
    supervisor, _processes, postgres, _health, _order = _supervisor(opc_root)
    postgres.start_entered = threading.Event()
    postgres.start_release = threading.Event()
    result: list[object] = []

    worker = threading.Thread(target=lambda: result.append(supervisor.start_all()))
    worker.start()
    assert postgres.start_entered.wait(2)
    try:
        with pytest.raises(OperationBusyError):
            supervisor.stop_all()
    finally:
        postgres.start_release.set()
        worker.join(3)
    assert len(result) == 1


def test_cancellation_ends_wait_then_refreshes_actual_state(opc_root: Path) -> None:
    supervisor, processes, _postgres, health, _order = _supervisor(opc_root)
    health.backend = _health(live=True, ready=False)
    token = CancelToken()
    token.cancel()

    report = supervisor.start(ServiceId.BACKEND, cancel_token=token)

    assert report.cancelled is True
    assert processes.stop_attempts == []
    assert report.steps[-1].observation.process_running is True
    assert report.steps[-1].observation.state is ServiceState.RUNNING_NOT_READY


def test_observation_keeps_process_live_and_ready_evidence_separate(opc_root: Path) -> None:
    supervisor, _processes, _postgres, health, _order = _supervisor(opc_root)
    health.backend = _health(live=True, ready=False)

    report = supervisor.start(ServiceId.BACKEND, cancel_token=CancelToken())
    observation = report.steps[-1].observation

    assert observation.process_running is True
    assert observation.port_open is True
    assert observation.live is True
    assert observation.ready is False


def test_startup_timeouts_can_be_updated_while_idle(opc_root: Path) -> None:
    supervisor, _processes, _postgres, _health, _order = _supervisor(opc_root)
    updated = SupervisorTimeouts(postgres=45, backend=50, frontend=55)

    supervisor.update_timeouts(updated)

    assert supervisor.timeouts == updated

