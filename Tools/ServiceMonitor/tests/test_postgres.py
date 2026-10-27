from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import pytest

from opc_service_monitor.catalog import build_catalog
from opc_service_monitor.models import CommandSpec, ServiceId
from opc_service_monitor.paths import ProjectLayout
from opc_service_monitor.postgres import PostgresController, PostgresOwnershipError
from opc_service_monitor.processes import OwnedProcess, OwnershipCheck, PortOccupancy, ProcessIdentity


def _postgres_identity(layout: ProjectLayout, pid: int = 900) -> ProcessIdentity:
    data = layout.integration_dir / "data"
    return ProcessIdentity(
        pid=pid,
        create_time_ns=123_000_000_000,
        executable=r"C:\Program Files\PostgreSQL\18\bin\postgres.exe",
        command_line=("postgres.exe", "-D", str(data)),
    )


@dataclass
class FakeProcessAdapter:
    current: ProcessIdentity | None = None
    occupied: bool = False
    listener_pid: int | None = None
    valid: bool = True
    listener_calls: int = 0
    validate_calls: int = 0

    def listener(self, host: str, port: int) -> PortOccupancy:
        assert (host, port) == ("127.0.0.1", 55440)
        self.listener_calls += 1
        is_occupied = self.occupied or self.current is not None
        pid = self.current.pid if self.current is not None else self.listener_pid
        return PortOccupancy(is_occupied, self.current, pid, "127.0.0.1" if is_occupied else None)

    def validate_owned(self, owned: OwnedProcess) -> OwnershipCheck:
        self.validate_calls += 1
        if not self.valid or self.current != owned.identity:
            return OwnershipCheck(False, "所有权不匹配", self.current)
        return OwnershipCheck(True, "所有权已验证", self.current)


class RecordingRunner:
    def __init__(self, callback: Callable[[CommandSpec], None] | None = None, returncode: int = 0) -> None:
        self.commands: list[CommandSpec] = []
        self.callback = callback
        self.returncode = returncode

    def __call__(self, command: CommandSpec, timeout_s: float, output) -> int:
        assert timeout_s > 0
        self.commands.append(command)
        output("stdout", "password=helper-secret")
        if self.callback is not None:
            self.callback(command)
        return self.returncode


def test_status_never_invokes_start_helper(opc_root: Path) -> None:
    layout = ProjectLayout.validate(opc_root)
    adapter = FakeProcessAdapter()
    runner = RecordingRunner()
    controller = PostgresController(layout, build_catalog(layout)[ServiceId.POSTGRES], adapter, runner=runner)

    status = controller.status()

    assert status.running is False
    assert runner.commands == []
    assert adapter.listener_calls == 1


def test_existing_listener_is_external_and_start_does_not_run_helper(opc_root: Path) -> None:
    layout = ProjectLayout.validate(opc_root)
    adapter = FakeProcessAdapter(current=_postgres_identity(layout))
    runner = RecordingRunner()
    controller = PostgresController(layout, build_catalog(layout)[ServiceId.POSTGRES], adapter, runner=runner)

    result = controller.start(timeout_s=5)

    assert result.status.running is True
    assert result.status.external is True
    assert result.owned is None
    assert runner.commands == []


@pytest.mark.parametrize("listener_pid", [None, 901], ids=["pid-missing", "inspection-denied"])
def test_uninspectable_listener_is_external_and_blocks_start_helper(
    opc_root: Path,
    listener_pid: int | None,
) -> None:
    layout = ProjectLayout.validate(opc_root)
    adapter = FakeProcessAdapter(occupied=True, listener_pid=listener_pid)
    runner = RecordingRunner()
    controller = PostgresController(layout, build_catalog(layout)[ServiceId.POSTGRES], adapter, runner=runner)

    result = controller.start(timeout_s=5)

    assert result.status.running is True
    assert result.status.external is True
    assert result.status.listener is None
    assert result.owned is None
    assert runner.commands == []


def test_start_calls_fixed_helper_then_claims_verified_runtime_listener(opc_root: Path) -> None:
    layout = ProjectLayout.validate(opc_root)
    adapter = FakeProcessAdapter()

    def on_run(_command: CommandSpec) -> None:
        adapter.current = _postgres_identity(layout)

    runner = RecordingRunner(on_run)
    output: list[str] = []
    controller = PostgresController(
        layout,
        build_catalog(layout)[ServiceId.POSTGRES],
        adapter,
        runner=runner,
        output=lambda _stream, line: output.append(line),
    )

    result = controller.start(timeout_s=5)

    assert len(runner.commands) == 1
    assert runner.commands[0].arguments[-1] == "start"
    assert result.owned is not None
    assert result.status.owned is True
    assert str(layout.integration_dir / "data") in result.owned.expected_command_fragments
    assert "helper-secret" not in "\n".join(output)
    assert "[REDACTED]" in "\n".join(output)


def test_unverified_ownership_blocks_stop_helper(opc_root: Path) -> None:
    layout = ProjectLayout.validate(opc_root)
    identity = _postgres_identity(layout)
    adapter = FakeProcessAdapter(current=identity, valid=False)
    runner = RecordingRunner()
    controller = PostgresController(layout, build_catalog(layout)[ServiceId.POSTGRES], adapter, runner=runner)
    owned = OwnedProcess(
        ServiceId.POSTGRES,
        identity,
        build_catalog(layout)[ServiceId.POSTGRES].start_command,
        expected_command_fragments=(str(layout.integration_dir / "data"),),
    )

    with pytest.raises(PostgresOwnershipError, match="拒绝停止"):
        controller.stop(owned, timeout_s=5)

    assert runner.commands == []


def test_verified_stop_uses_existing_helper_and_retains_data(opc_root: Path) -> None:
    layout = ProjectLayout.validate(opc_root)
    data = layout.integration_dir / "data"
    data.mkdir(parents=True, exist_ok=True)
    sentinel = data / "retained.txt"
    sentinel.write_text("keep", encoding="utf-8")
    identity = _postgres_identity(layout)
    adapter = FakeProcessAdapter(current=identity)

    def on_run(command: CommandSpec) -> None:
        if command.arguments[-1] == "stop":
            adapter.current = None

    runner = RecordingRunner(on_run)
    definition = build_catalog(layout)[ServiceId.POSTGRES]
    controller = PostgresController(layout, definition, adapter, runner=runner)
    owned = OwnedProcess(
        ServiceId.POSTGRES,
        identity,
        definition.start_command,
        expected_command_fragments=(str(data),),
    )

    status = controller.stop(owned, timeout_s=5)

    assert status.running is False
    assert runner.commands == [definition.stop_command]
    assert sentinel.read_text(encoding="utf-8") == "keep"

