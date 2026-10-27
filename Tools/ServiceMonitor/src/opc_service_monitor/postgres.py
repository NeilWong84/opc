from __future__ import annotations

import os
import subprocess
import time
from collections.abc import Callable
from dataclasses import dataclass

from opc_service_monitor.frozen_runtime import sanitized_external_environment
from opc_service_monitor.log_pipeline import decode_log_bytes, make_log_entry, windows_log_encodings
from opc_service_monitor.models import CommandSpec, LogSource, ServiceDefinition, ServiceId
from opc_service_monitor.paths import ProjectLayout
from opc_service_monitor.processes import OutputCallback, OwnedProcess, ProcessAdapter, ProcessIdentity


HelperRunner = Callable[[CommandSpec, float, OutputCallback], int]


@dataclass(frozen=True, slots=True)
class PostgresStatus:
    running: bool
    listener: ProcessIdentity | None
    owned: bool
    external: bool
    summary: str


@dataclass(frozen=True, slots=True)
class PostgresStartResult:
    status: PostgresStatus
    owned: OwnedProcess | None


class PostgresOwnershipError(RuntimeError):
    pass


class PostgresCommandError(RuntimeError):
    pass


class PostgresController:
    def __init__(
        self,
        layout: ProjectLayout,
        definition: ServiceDefinition,
        processes: ProcessAdapter,
        *,
        runner: HelperRunner | None = None,
        output: OutputCallback | None = None,
        clock: Callable[[], float] = time.monotonic,
        waiter: Callable[[float], None] = time.sleep,
    ) -> None:
        if definition.service_id is not ServiceId.POSTGRES:
            raise ValueError("PostgresController 只能使用 PostgreSQL 服务定义")
        self._layout = layout
        self._definition = definition
        self._processes = processes
        self._runner = runner or _run_helper
        self._output = output or (lambda _stream, _line: None)
        self._clock = clock
        self._waiter = waiter
        self._owned: OwnedProcess | None = None

    def status(self) -> PostgresStatus:
        occupancy = self._processes.listener(self._definition.host, self._definition.port)
        if not occupancy.occupied:
            return PostgresStatus(False, None, False, False, "PostgreSQL 未运行")
        listener = occupancy.identity
        if self._owned is not None and listener == self._owned.identity:
            check = self._processes.validate_owned(self._owned)
            if check.valid:
                return PostgresStatus(True, listener, True, False, "PostgreSQL 已运行（本监控器启动）")
        return PostgresStatus(True, listener, False, True, "PostgreSQL 已运行（外部进程，不会停止）")

    def start(self, timeout_s: float) -> PostgresStartResult:
        if timeout_s <= 0:
            raise ValueError("PostgreSQL 启动等待时间必须大于零")
        before = self.status()
        if before.running:
            return PostgresStartResult(before, self._owned if before.owned else None)

        returncode = self._runner(self._definition.start_command, timeout_s, self._safe_output)
        if returncode != 0:
            raise PostgresCommandError("PostgreSQL 启动助手执行失败，请查看 provision.log")

        deadline = self._clock() + timeout_s
        listener: ProcessIdentity | None = None
        occupied = False
        while self._clock() <= deadline:
            occupancy = self._processes.listener(self._definition.host, self._definition.port)
            occupied = occupancy.occupied
            listener = occupancy.identity
            if occupied:
                break
            self._waiter(0.1)
        if not occupied:
            raise PostgresCommandError("PostgreSQL 启动超时，端口 55440 未监听")
        if listener is None:
            raise PostgresOwnershipError("PostgreSQL 端口已监听，但无法读取监听进程身份，拒绝接管")

        data_path = str(self._layout.integration_dir / "data")
        owned = OwnedProcess(
            service_id=ServiceId.POSTGRES,
            identity=listener,
            command=self._definition.start_command,
            expected_command_fragments=(data_path,),
        )
        check = self._processes.validate_owned(owned)
        if not check.valid:
            raise PostgresOwnershipError(f"PostgreSQL 监听进程无法验证所有权: {check.reason}")
        self._owned = owned
        status = PostgresStatus(True, listener, True, False, "PostgreSQL 已就绪（本监控器启动）")
        return PostgresStartResult(status, owned)

    def stop(self, owned: OwnedProcess, timeout_s: float) -> PostgresStatus:
        if timeout_s <= 0:
            raise ValueError("PostgreSQL 停止等待时间必须大于零")
        if owned.service_id is not ServiceId.POSTGRES:
            raise PostgresOwnershipError("拒绝停止：所有权记录不属于 PostgreSQL")
        check = self._processes.validate_owned(owned)
        if not check.valid:
            raise PostgresOwnershipError(f"拒绝停止未验证的 PostgreSQL 进程: {check.reason}")
        command = self._definition.stop_command
        if command is None:
            raise PostgresCommandError("PostgreSQL 停止助手未配置")
        returncode = self._runner(command, timeout_s, self._safe_output)
        if returncode != 0:
            raise PostgresCommandError("PostgreSQL 停止助手执行失败，数据未删除")

        deadline = self._clock() + timeout_s
        while self._clock() <= deadline:
            occupancy = self._processes.listener(self._definition.host, self._definition.port)
            if not occupancy.occupied or occupancy.identity != owned.identity:
                self._owned = None
                return self.status()
            self._waiter(0.1)
        raise PostgresCommandError("PostgreSQL 停止超时，未执行强制删除或按名称终止")

    def _safe_output(self, stream: str, line: str) -> None:
        safe = make_log_entry(source=LogSource.POSTGRES, stream=stream, text=line)
        self._output(stream, safe.message)


def _run_helper(command: CommandSpec, timeout_s: float, output: OutputCallback) -> int:
    if command.shell:
        raise ValueError("PostgreSQL 助手不允许 shell 命令")
    environment = os.environ.copy()
    environment.update(dict(command.environment))
    environment = sanitized_external_environment(environment)
    creation_flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    try:
        completed = subprocess.run(
            list(command.argv()),
            cwd=str(command.cwd),
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            shell=False,
            timeout=timeout_s,
            creationflags=creation_flags,
            check=False,
        )
    except subprocess.TimeoutExpired:
        output("stderr", "PostgreSQL 助手执行超时")
        return 124
    # A helper can combine Python UTF-8 and native pg_ctl messages in one pipe.
    text = "\n".join(
        decode_log_bytes(line, fallback_encodings=windows_log_encodings())
        for line in (completed.stdout or b"").splitlines()
    )
    for line in text.splitlines():
        output("stdout", line)
    return completed.returncode

