from __future__ import annotations

import threading
import time
from collections.abc import Callable
from dataclasses import dataclass, replace
from datetime import UTC, datetime

from opc_service_monitor.health import HealthProbe
from opc_service_monitor.log_pipeline import redact_log_text
from opc_service_monitor.models import HealthResult, ServiceDefinition, ServiceId, ServiceState
from opc_service_monitor.postgres import PostgresController
from opc_service_monitor.processes import OwnedProcess, ProcessAdapter


@dataclass(frozen=True, slots=True)
class SupervisorTimeouts:
    postgres: float = 30
    backend: float = 30
    frontend: float = 30

    def __post_init__(self) -> None:
        for value in (self.postgres, self.backend, self.frontend):
            if not 5 <= value <= 120:
                raise ValueError("服务启动/停止超时必须在 5 到 120 秒之间")

    def for_service(self, service_id: ServiceId) -> float:
        return {
            ServiceId.POSTGRES: self.postgres,
            ServiceId.BACKEND: self.backend,
            ServiceId.FRONTEND: self.frontend,
        }[service_id]


class CancelToken:
    def __init__(self) -> None:
        self._event = threading.Event()

    @property
    def cancelled(self) -> bool:
        return self._event.is_set()

    def cancel(self) -> None:
        self._event.set()


@dataclass(frozen=True, slots=True)
class ServiceObservation:
    service_id: ServiceId
    state: ServiceState
    process_running: bool
    port_open: bool
    live: bool | None
    ready: bool | None
    owned: bool
    external: bool
    pid: int | None
    checked_at: datetime
    summary: str
    last_error: str | None = None
    listener_identified: bool = False


@dataclass(frozen=True, slots=True)
class OperationStep:
    service_id: ServiceId
    action: str
    success: bool
    message: str
    observation: ServiceObservation


@dataclass(frozen=True, slots=True)
class OperationReport:
    action: str
    steps: tuple[OperationStep, ...]
    cancelled: bool = False

    @property
    def success(self) -> bool:
        return bool(self.steps) and not self.cancelled and all(step.success for step in self.steps)


class OperationBusyError(RuntimeError):
    pass


StateCallback = Callable[[ServiceObservation], None]
SupervisorLogCallback = Callable[[ServiceId, str, str], None]


class ServiceSupervisor:
    START_ORDER = (ServiceId.POSTGRES, ServiceId.BACKEND, ServiceId.FRONTEND)
    STOP_ORDER = tuple(reversed(START_ORDER))

    def __init__(
        self,
        catalog: dict[ServiceId, ServiceDefinition],
        processes: ProcessAdapter,
        postgres: PostgresController,
        health: HealthProbe,
        *,
        timeouts: SupervisorTimeouts | None = None,
        state_callback: StateCallback | None = None,
        log_callback: SupervisorLogCallback | None = None,
        clock: Callable[[], float] = time.monotonic,
        waiter: Callable[[float], None] = time.sleep,
    ) -> None:
        if set(catalog) != set(self.START_ORDER):
            raise ValueError("服务目录必须且只能包含 PostgreSQL、BackendService 和 FrontendAdmin")
        self._catalog = catalog
        self._processes = processes
        self._postgres = postgres
        self._health = health
        self._timeouts = timeouts or SupervisorTimeouts()
        self._state_callback = state_callback or (lambda _observation: None)
        self._log_callback = log_callback or (lambda _service, _stream, _line: None)
        self._clock = clock
        self._waiter = waiter
        self._operation_lock = threading.Lock()
        self._owned: dict[ServiceId, OwnedProcess] = {}
        self._observations: dict[ServiceId, ServiceObservation] = {}

    @property
    def owned_services(self) -> tuple[ServiceId, ...]:
        return tuple(service_id for service_id in self.START_ORDER if service_id in self._owned)

    @property
    def operation_active(self) -> bool:
        return self._operation_lock.locked()

    @property
    def timeouts(self) -> SupervisorTimeouts:
        return self._timeouts

    def update_timeouts(self, timeouts: SupervisorTimeouts) -> None:
        with self._exclusive_operation():
            self._timeouts = timeouts

    def set_state_callback(self, callback: StateCallback) -> None:
        self._state_callback = callback

    def set_log_callback(self, callback: SupervisorLogCallback) -> None:
        self._log_callback = callback

    def start(self, service_id: ServiceId, cancel_token: CancelToken | None = None) -> OperationReport:
        with self._exclusive_operation():
            step, cancelled = self._start_one(service_id, cancel_token or CancelToken())
            return OperationReport(f"start:{service_id.value}", (step,), cancelled)

    def start_all(self, cancel_token: CancelToken | None = None) -> OperationReport:
        token = cancel_token or CancelToken()
        with self._exclusive_operation():
            steps: list[OperationStep] = []
            cancelled = False
            for service_id in self.START_ORDER:
                step, cancelled = self._start_one(service_id, token)
                steps.append(step)
                if not step.success or cancelled:
                    break
            return OperationReport("start_all", tuple(steps), cancelled)

    def stop(self, service_id: ServiceId, cancel_token: CancelToken | None = None) -> OperationReport:
        with self._exclusive_operation():
            step, cancelled = self._stop_one(service_id, cancel_token or CancelToken())
            return OperationReport(f"stop:{service_id.value}", (step,), cancelled)

    def stop_all(self, cancel_token: CancelToken | None = None) -> OperationReport:
        token = cancel_token or CancelToken()
        with self._exclusive_operation():
            steps: list[OperationStep] = []
            cancelled = False
            for service_id in self.STOP_ORDER:
                step, cancelled = self._stop_one(service_id, token, preserve_external=True)
                steps.append(step)
                if not step.success or cancelled:
                    break
            return OperationReport("stop_all", tuple(steps), cancelled)

    def refresh(self) -> dict[ServiceId, ServiceObservation]:
        with self._exclusive_operation():
            return {service_id: self._observe(service_id) for service_id in self.START_ORDER}

    def current_observations(self) -> dict[ServiceId, ServiceObservation]:
        return dict(self._observations)

    def _start_one(self, service_id: ServiceId, token: CancelToken) -> tuple[OperationStep, bool]:
        initial = self._observe(service_id)
        if initial.external:
            success = initial.listener_identified and _is_usable(service_id, initial)
            if not initial.listener_identified:
                message = "端口已被占用但监听进程身份不可验证，拒绝启动"
            else:
                message = "检测到外部实例，保持只读观察" if success else "端口被外部实例占用且服务未就绪"
            return OperationStep(service_id, "start", success, message, initial), False
        if initial.owned and _is_usable(service_id, initial):
            return OperationStep(service_id, "start", True, "服务已经就绪", initial), False

        self._emit(
            replace(
                initial,
                state=ServiceState.STARTING,
                summary="正在启动",
                last_error=None,
            )
        )
        timeout = self._timeouts.for_service(service_id)
        try:
            if service_id is ServiceId.POSTGRES:
                result = self._postgres.start(timeout)
                if result.owned is not None:
                    self._owned[service_id] = result.owned
                observation = self._observe(service_id)
                success = result.status.running
                if token.cancelled:
                    return OperationStep(service_id, "start", False, "已取消等待并刷新实际状态", observation), True
                return OperationStep(service_id, "start", success, result.status.summary, observation), False

            definition = self._catalog[service_id]
            occupancy = self._processes.listener(definition.host, definition.port)
            if occupancy.occupied:
                observation = self._observe(service_id)
                return (
                    OperationStep(
                        service_id,
                        "start",
                        observation.listener_identified and _is_usable(service_id, observation),
                        "端口已由外部实例占用",
                        observation,
                    ),
                    False,
                )
            spawned = self._processes.spawn(
                definition.start_command,
                lambda stream, line: self._log_callback(service_id, stream, line),
            )
            owned = spawned.as_owned(
                service_id,
                expected_command_fragments=_expected_fragments(service_id, definition),
            )
            self._owned[service_id] = owned
            deadline = self._clock() + timeout
            while self._clock() <= deadline:
                observation = self._observe(service_id)
                if token.cancelled:
                    return OperationStep(service_id, "start", False, "已取消等待并刷新实际状态", observation), True
                if observation.owned and _is_usable(service_id, observation):
                    return OperationStep(service_id, "start", True, "服务已就绪", observation), False
                if observation.external:
                    failed = self._failed(observation, "服务端口被非本会话进程占用，拒绝认领")
                    return OperationStep(service_id, "start", False, failed.last_error or "启动失败", failed), False
                if not observation.process_running:
                    failed = self._failed(observation, "服务进程在就绪前退出")
                    return OperationStep(service_id, "start", False, failed.last_error or "启动失败", failed), False
                self._waiter(0.1)
            observation = self._observe(service_id)
            failed = self._failed(observation, f"启动超时（{timeout:g} 秒）")
            return OperationStep(service_id, "start", False, failed.last_error or "启动超时", failed), False
        except Exception as exc:
            observation = self._observe(service_id)
            message = redact_log_text(str(exc)) or "启动失败"
            failed = self._failed(observation, message)
            return OperationStep(service_id, "start", False, message, failed), False

    def _stop_one(
        self,
        service_id: ServiceId,
        token: CancelToken,
        *,
        preserve_external: bool = False,
    ) -> tuple[OperationStep, bool]:
        initial = self._observe(service_id)
        if token.cancelled:
            return OperationStep(service_id, "stop", False, "已取消并刷新实际状态", initial), True
        owned = self._owned.get(service_id)
        if initial.external and owned is None:
            if preserve_external:
                return OperationStep(service_id, "stop", True, "已跳过外部实例，保持运行（只读保护）", initial), False
            return OperationStep(service_id, "stop", False, "外部实例不会被本监控器停止", initial), False
        if owned is None:
            success = not initial.process_running and not initial.port_open
            message = "服务已经停止" if success else "没有可验证的本会话所有权，拒绝停止"
            return OperationStep(service_id, "stop", success, message, initial), False

        self._emit(replace(initial, state=ServiceState.STOPPING, summary="正在停止", last_error=None))
        timeout = self._timeouts.for_service(service_id)
        try:
            if service_id is ServiceId.POSTGRES:
                status = self._postgres.stop(owned, timeout)
                self._owned.pop(service_id, None)
                observation = self._observe(service_id)
                return OperationStep(service_id, "stop", not status.running, status.summary, observation), False

            ownership = self._processes.validate_owned(owned)
            if not ownership.valid:
                failed = self._failed(initial, f"所有权验证失败，拒绝停止: {ownership.reason}")
                return OperationStep(service_id, "stop", False, failed.last_error or "拒绝停止", failed), False
            graceful_timeout = min(5.0, timeout / 2)
            stopped = self._processes.request_stop(owned, graceful_timeout)
            if not stopped:
                stopped = self._processes.force_stop(owned, max(0.1, timeout - graceful_timeout))
            if not stopped:
                failed = self._failed(self._observe(service_id), "服务未能在限定时间内停止")
                return OperationStep(service_id, "stop", False, failed.last_error or "停止失败", failed), False
            self._owned.pop(service_id, None)
            observation = self._observe(service_id)
            if observation.port_open:
                failed = self._failed(observation, "进程树停止后服务端口仍在监听，已按外部实例保护")
                return OperationStep(service_id, "stop", False, failed.last_error or "停止不完整", failed), False
            return OperationStep(service_id, "stop", True, "服务已停止", observation), False
        except Exception as exc:
            observation = self._observe(service_id)
            message = redact_log_text(str(exc)) or "停止失败"
            failed = self._failed(observation, message)
            return OperationStep(service_id, "stop", False, message, failed), False

    def _observe(self, service_id: ServiceId) -> ServiceObservation:
        now = datetime.now(UTC)
        if service_id is ServiceId.POSTGRES:
            status = self._postgres.status()
            tracked = self._owned.get(service_id)
            if tracked is not None and not status.owned and not self._processes.validate_owned(tracked).valid:
                self._owned.pop(service_id, None)
            state = ServiceState.STOPPED
            if status.external:
                state = ServiceState.EXTERNAL
            elif status.running:
                state = ServiceState.READY
            observation = ServiceObservation(
                service_id=service_id,
                state=state,
                process_running=status.running,
                port_open=status.running,
                live=None,
                ready=status.running,
                owned=status.owned,
                external=status.external,
                pid=status.listener.pid if status.listener is not None else None,
                checked_at=now,
                summary=status.summary,
                listener_identified=status.listener is not None,
            )
            return self._emit(observation)

        definition = self._catalog[service_id]
        occupancy = self._processes.listener(definition.host, definition.port)
        listener = occupancy.identity
        port_open = occupancy.occupied
        owned = self._owned.get(service_id)
        tracked_running = False
        is_owned = False
        tracked_pid: int | None = None
        if owned is not None:
            ownership = self._processes.validate_owned(owned)
            tracked_running = ownership.valid
            tracked_pid = ownership.current.pid if ownership.current is not None else None
            if listener is not None:
                is_owned = self._processes.validate_listener_owned(owned, listener).valid
                if is_owned:
                    tracked_running = True
                    tracked_pid = listener.pid
            if not tracked_running and not is_owned:
                self._owned.pop(service_id, None)

        health: HealthResult | None = None
        if port_open:
            health = self._health.probe_backend() if service_id is ServiceId.BACKEND else self._health.probe_frontend()
        external = port_open and not is_owned
        live = health.live if health is not None else None
        ready = health.ready if health is not None else False
        if external:
            state = ServiceState.EXTERNAL
        elif is_owned and ready:
            state = ServiceState.READY
        elif is_owned or tracked_running or port_open:
            state = ServiceState.RUNNING_NOT_READY
        else:
            state = ServiceState.STOPPED
        observation = ServiceObservation(
            service_id=service_id,
            state=state,
            process_running=tracked_running or port_open,
            port_open=port_open,
            live=live,
            ready=ready,
            # A verified session process remains stoppable before binding, or after
            # losing its listener. An occupied foreign port never gains ownership.
            owned=is_owned or (tracked_running and not external),
            external=external,
            pid=(
                listener.pid
                if listener is not None
                else occupancy.pid
                if port_open
                else tracked_pid
                if tracked_running
                else None
            ),
            checked_at=now,
            summary=health.summary if health is not None else "端口未监听",
            listener_identified=listener is not None,
        )
        return self._emit(observation)

    def _failed(self, observation: ServiceObservation, message: str) -> ServiceObservation:
        failed = replace(
            observation,
            state=ServiceState.FAILED,
            summary=message,
            last_error=message,
        )
        return self._emit(failed)

    def _emit(self, observation: ServiceObservation) -> ServiceObservation:
        self._observations[observation.service_id] = observation
        self._state_callback(observation)
        return observation

    def _exclusive_operation(self):
        return _OperationGuard(self._operation_lock)


class _OperationGuard:
    def __init__(self, lock: threading.Lock) -> None:
        self._lock = lock

    def __enter__(self) -> None:
        if not self._lock.acquire(blocking=False):
            raise OperationBusyError("已有服务操作正在执行")

    def __exit__(self, *_args: object) -> None:
        self._lock.release()


def _is_usable(service_id: ServiceId, observation: ServiceObservation) -> bool:
    if service_id is ServiceId.POSTGRES:
        return observation.port_open
    return bool(observation.ready)


def _expected_fragments(service_id: ServiceId, definition: ServiceDefinition) -> tuple[str, ...]:
    if service_id is ServiceId.BACKEND:
        return tuple(argument for argument in definition.start_command.arguments if argument.casefold().endswith("start.ps1"))
    if service_id is ServiceId.FRONTEND:
        return (str(definition.port),)
    return ()

