from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass

from opc_service_monitor.models import ServiceId, ServiceState
from opc_service_monitor.supervisor import ServiceObservation


@dataclass(frozen=True, slots=True)
class ServiceActions:
    can_start: bool
    can_stop: bool
    power_on: bool | None
    reason: str
    transition: str | None = None


def service_actions(observation: ServiceObservation | None, *, busy: bool = False) -> ServiceActions:
    """Derive controls from process evidence and ownership, never readiness alone."""
    if observation is None:
        return ServiceActions(False, False, None, "等待状态检查，暂不能操作")
    if observation.state in {ServiceState.STARTING, ServiceState.STOPPING}:
        starting = observation.state is ServiceState.STARTING
        return ServiceActions(False, False, None, "服务操作执行中，请稍候", "starting" if starting else "stopping")

    running = observation.process_running or observation.port_open
    if observation.external or observation.state is ServiceState.EXTERNAL:
        power_on = True if observation.process_running else None if observation.port_open else False
        actions = ServiceActions(False, False, power_on, "外部实例只读保护，不能由本监控器启停")
    elif running:
        actions = ServiceActions(
            False, observation.owned, True,
            "服务已启动，可停止本会话自有进程" if observation.owned else "服务正在运行，但未确认本会话所有权，禁止启停",
        )
    else:
        actions = ServiceActions(True, False, False, "服务已停止，可以启动")
    if busy:
        return ServiceActions(False, False, actions.power_on, "服务操作执行中，请稍候")
    return actions


def aggregate_actions(
    observations: Mapping[ServiceId, ServiceObservation], *, busy: bool = False,
) -> ServiceActions:
    """Aggregate eligible actions without granting authority over external services."""
    actions = [service_actions(observations.get(service_id)) for service_id in ServiceId]
    powers = {action.power_on for action in actions}
    power_on = next(iter(powers)) if len(powers) == 1 else None
    transition = next((action.transition for action in actions if action.transition), None)
    if busy or transition:
        return ServiceActions(False, False, power_on, "服务操作执行中，请稍候", transition)
    can_start = all(service_id in observations for service_id in ServiceId) and any(action.can_start for action in actions)
    can_stop = any(action.can_stop for action in actions)
    if can_start and can_stop:
        reason = "服务部分运行：启动缺少的服务，或停止本会话自有服务；外部实例不受影响"
    elif can_start:
        reason = "启动尚未运行的服务；外部实例只读保护"
    elif can_stop:
        reason = "停止本会话自有服务；外部实例保持运行"
    elif power_on is True:
        reason = "服务均已启动；外部实例只读保护，无可停止的本会话进程"
    else:
        reason = "等待状态检查，或没有可安全启停的服务"
    return ServiceActions(can_start, can_stop, power_on, reason)
