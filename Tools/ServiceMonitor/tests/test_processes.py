from __future__ import annotations

import os
import sys
import threading
import time
from io import BytesIO
from pathlib import Path

import pytest

from opc_service_monitor.models import CommandSpec, ServiceId
from opc_service_monitor.processes import (
    OwnedProcess,
    ProcessIdentity,
    SpawnedProcess,
    SubprocessProcessAdapter,
    ownership_matches,
)


def _identity(
    *,
    pid: int = 100,
    created: int = 123_000_000_000,
    executable: str = r"C:\Program Files\PostgreSQL\18\bin\postgres.exe",
    command_line: tuple[str, ...] = ("postgres.exe", "-D", r"D:\OPC\BackendService\.local\integration\data"),
) -> ProcessIdentity:
    return ProcessIdentity(pid, created, executable, command_line)


def test_ownership_requires_pid_creation_executable_command_and_expected_path() -> None:
    snapshot = _identity()
    expected = (r"D:\OPC\BackendService\.local\integration\data",)

    assert ownership_matches(snapshot, _identity(), expected).valid is True
    assert ownership_matches(snapshot, _identity(pid=101), expected).valid is False
    assert ownership_matches(snapshot, _identity(created=124_000_000_000), expected).valid is False
    assert ownership_matches(snapshot, _identity(executable=r"C:\Windows\not-postgres.exe"), expected).valid is False
    assert ownership_matches(snapshot, _identity(command_line=("postgres.exe", "-D", r"D:\other")), expected).valid is False


def test_final_boundary_revalidation_blocks_signal_after_pid_reuse(tmp_path: Path) -> None:
    snapshot = _identity(pid=222)
    reused = _identity(pid=222, created=snapshot.create_time_ns + 1)

    class RecordingAdapter(SubprocessProcessAdapter):
        def __init__(self) -> None:
            super().__init__(inspector=lambda _pid: reused)
            self.signalled = False

        def _signal_graceful(self, _owned: OwnedProcess) -> None:
            self.signalled = True

    command = CommandSpec(sys.executable, ("-c", "pass"), tmp_path)
    owned = OwnedProcess(ServiceId.BACKEND, snapshot, command, expected_command_fragments=())
    adapter = RecordingAdapter()

    assert adapter.request_stop(owned, timeout_s=0.01) is False
    assert adapter.signalled is False


def test_spawn_rejects_shell_command(tmp_path: Path) -> None:
    adapter = SubprocessProcessAdapter()
    command = CommandSpec(sys.executable, ("-c", "pass"), tmp_path, shell=True)

    with pytest.raises(ValueError, match="shell"):
        adapter.spawn(command, lambda _stream, _line: None)


@pytest.mark.skipif(os.name != "nt", reason="Windows process group behavior")
def test_spawn_streams_redacted_output_and_force_stops_owned_tree(tmp_path: Path) -> None:
    fixture = Path(__file__).parent / "fixtures" / "dummy_service.py"
    lines: list[tuple[str, str]] = []
    enough_output = threading.Event()

    def output(stream: str, line: str) -> None:
        lines.append((stream, line))
        if len(lines) >= 5:
            enough_output.set()

    command = CommandSpec(
        executable=sys.executable,
        arguments=(str(fixture), "--spawn-child", "--message", "password=process-secret"),
        cwd=tmp_path,
        environment=(("DUMMY_VISIBLE", "yes"),),
    )
    adapter = SubprocessProcessAdapter()
    spawned = adapter.spawn(command, output)
    owned = spawned.as_owned(ServiceId.BACKEND, expected_command_fragments=(str(fixture),))
    child_pid: int | None = None
    try:
        assert enough_output.wait(5), lines
        flattened = "\n".join(line for _, line in lines)
        assert "process-secret" not in flattened
        assert "password=[REDACTED]" in flattened
        assert f"cwd={tmp_path}" in flattened
        assert "env=yes" in flattened
        child_lines = [line for _, line in lines if line.startswith("child_pid=")]
        child_pid = int(child_lines[0].split("=", 1)[1])

        assert adapter.force_stop(owned, timeout_s=3.0) is True
        assert adapter.inspect(spawned.identity.pid) is None
        assert adapter.inspect(child_pid) is None
    finally:
        if adapter.inspect(spawned.identity.pid) is not None:
            adapter.force_stop(owned, timeout_s=3.0)
        if child_pid is not None and adapter.inspect(child_pid) is not None:
            import psutil

            psutil.Process(child_pid).kill()


def test_listener_lookup_keeps_port_occupancy_separate_from_identity() -> None:
    identity = _identity(pid=333)

    class Address:
        ip = "127.0.0.1"
        port = 8001

    class Connection:
        laddr = Address()
        status = "LISTEN"
        pid = 333

    adapter = SubprocessProcessAdapter(
        inspector=lambda pid: identity if pid == 333 else None,
        connections=lambda: [Connection()],
    )

    occupied = adapter.listener("127.0.0.1", 8001)
    available = adapter.listener("127.0.0.1", 5180)

    assert occupied.occupied is True
    assert occupied.identity == identity
    assert occupied.pid == 333
    assert available.occupied is False
    assert available.identity is None


def test_listener_reports_occupied_when_pid_is_unavailable() -> None:
    class Address:
        ip = "127.0.0.1"
        port = 8001

    class Connection:
        laddr = Address()
        status = "LISTEN"
        pid = None

    adapter = SubprocessProcessAdapter(connections=lambda: [Connection()])

    listener = adapter.listener("127.0.0.1", 8001)

    assert listener.occupied is True
    assert listener.pid is None
    assert listener.identity is None


def test_listener_reports_occupied_when_process_inspection_is_denied() -> None:
    class Address:
        ip = "127.0.0.1"
        port = 8001

    class Connection:
        laddr = Address()
        status = "LISTEN"
        pid = 334

    adapter = SubprocessProcessAdapter(
        inspector=lambda _pid: None,
        connections=lambda: [Connection()],
    )

    listener = adapter.listener("127.0.0.1", 8001)

    assert listener.occupied is True
    assert listener.pid == 334
    assert listener.identity is None


@pytest.mark.parametrize("bound_host", ["0.0.0.0", "::"])
def test_listener_matches_wildcard_bind_for_requested_loopback(bound_host: str) -> None:
    identity = _identity(pid=335)

    class Address:
        ip = bound_host
        port = 8001

    class Connection:
        laddr = Address()
        status = "LISTEN"
        pid = 335

    adapter = SubprocessProcessAdapter(
        inspector=lambda _pid: identity,
        connections=lambda: [Connection()],
    )

    listener = adapter.listener("127.0.0.1", 8001)

    assert listener.occupied is True
    assert listener.identity == identity


def test_listener_ownership_captures_and_persists_verified_descendant(
    tmp_path: Path, monkeypatch
) -> None:
    root = _identity(pid=340, executable="wrapper.exe", command_line=("wrapper.exe",))
    child = _identity(pid=341, executable="service.exe", command_line=("service.exe", "--port", "8001"))
    identities = {root.pid: root, child.pid: child}

    class FakeProcess:
        def __init__(self, pid: int) -> None:
            self.pid = pid

        def children(self, *, recursive: bool):
            assert recursive is True
            return [FakeProcess(child.pid)] if self.pid == root.pid else []

    monkeypatch.setattr("opc_service_monitor.processes.psutil.Process", FakeProcess)
    adapter = SubprocessProcessAdapter(inspector=lambda pid: identities.get(pid))
    owned = OwnedProcess(
        ServiceId.BACKEND,
        root,
        CommandSpec("wrapper.exe", (), tmp_path),
    )

    check = adapter.validate_listener_owned(owned, child)

    assert check.valid is True
    assert owned.descendant_identities == (child,)


def test_validate_owned_refreshes_descendants_while_launcher_is_alive(
    tmp_path: Path, monkeypatch
) -> None:
    root = _identity(pid=342, executable="wrapper.exe", command_line=("wrapper.exe",))
    child = _identity(pid=343, executable="service.exe", command_line=("service.exe", "--port", "8001"))
    identities = {root.pid: root, child.pid: child}

    class FakeProcess:
        def __init__(self, pid: int) -> None:
            self.pid = pid

        def children(self, *, recursive: bool):
            assert recursive is True
            return [FakeProcess(child.pid)] if self.pid == root.pid else []

    monkeypatch.setattr("opc_service_monitor.processes.psutil.Process", FakeProcess)
    adapter = SubprocessProcessAdapter(inspector=lambda pid: identities.get(pid))
    owned = OwnedProcess(ServiceId.BACKEND, root, CommandSpec("wrapper.exe", (), tmp_path))

    check = adapter.validate_owned(owned)

    assert check.valid is True
    assert owned.descendant_identities == (child,)


def test_listener_ownership_recovers_direct_child_after_launcher_exits_before_snapshot(
    tmp_path: Path, monkeypatch
) -> None:
    root = _identity(pid=344, created=100_000_000_000, executable="wrapper.exe", command_line=("wrapper.exe",))
    child = _identity(
        pid=345,
        created=101_000_000_000,
        executable="service.exe",
        command_line=("service.exe", "--port", "8001"),
    )
    identities = {child.pid: child}

    class FakeProcess:
        def __init__(self, pid: int) -> None:
            self.pid = pid

        def ppid(self) -> int:
            assert self.pid == child.pid
            return root.pid

    monkeypatch.setattr("opc_service_monitor.processes.psutil.Process", FakeProcess)
    monkeypatch.setattr("opc_service_monitor.processes.psutil.pid_exists", lambda _pid: False)
    adapter = SubprocessProcessAdapter(inspector=lambda pid: identities.get(pid))
    owned = OwnedProcess(ServiceId.BACKEND, root, CommandSpec("wrapper.exe", (), tmp_path))

    check = adapter.validate_listener_owned(owned, child)

    assert check.valid is True
    assert owned.descendant_identities == (child,)


def test_listener_ownership_rejects_parent_that_exists_but_cannot_be_inspected(
    tmp_path: Path, monkeypatch
) -> None:
    root = _identity(pid=354, created=100_000_000_000, executable="wrapper.exe", command_line=("wrapper.exe",))
    child = _identity(
        pid=355,
        created=101_000_000_000,
        executable="service.exe",
        command_line=("service.exe", "--port", "8001"),
    )
    identities = {child.pid: child}

    class FakeProcess:
        def __init__(self, pid: int) -> None:
            self.pid = pid

        def ppid(self) -> int:
            assert self.pid == child.pid
            return root.pid

    monkeypatch.setattr("opc_service_monitor.processes.psutil.Process", FakeProcess)
    monkeypatch.setattr(
        "opc_service_monitor.processes.psutil.pid_exists",
        lambda pid: pid == root.pid,
    )
    adapter = SubprocessProcessAdapter(inspector=lambda pid: identities.get(pid))
    owned = OwnedProcess(ServiceId.BACKEND, root, CommandSpec("wrapper.exe", (), tmp_path))

    check = adapter.validate_listener_owned(owned, child)

    assert check.valid is False
    assert "不可验证" in check.reason
    assert owned.descendant_identities == ()


def test_listener_ownership_rejects_direct_parent_pid_when_launcher_pid_was_reused(
    tmp_path: Path, monkeypatch
) -> None:
    root = _identity(pid=346, created=100_000_000_000, executable="wrapper.exe", command_line=("wrapper.exe",))
    reused_root = _identity(
        pid=root.pid,
        created=102_000_000_000,
        executable="other-wrapper.exe",
        command_line=("other-wrapper.exe",),
    )
    listener = _identity(
        pid=347,
        created=103_000_000_000,
        executable="competitor.exe",
        command_line=("competitor.exe", "--port", "8001"),
    )
    identities = {root.pid: reused_root, listener.pid: listener}

    class FakeProcess:
        def __init__(self, pid: int) -> None:
            self.pid = pid

        def ppid(self) -> int:
            assert self.pid == listener.pid
            return root.pid

    monkeypatch.setattr("opc_service_monitor.processes.psutil.Process", FakeProcess)
    adapter = SubprocessProcessAdapter(inspector=lambda pid: identities.get(pid))
    owned = OwnedProcess(ServiceId.BACKEND, root, CommandSpec("wrapper.exe", (), tmp_path))

    check = adapter.validate_listener_owned(owned, listener)

    assert check.valid is False
    assert "PID" in check.reason
    assert owned.descendant_identities == ()


def test_listener_ownership_rejects_unrelated_listener_after_launcher_exits(
    tmp_path: Path, monkeypatch
) -> None:
    root = _identity(pid=348, created=100_000_000_000, executable="wrapper.exe", command_line=("wrapper.exe",))
    listener = _identity(
        pid=349,
        created=101_000_000_000,
        executable="competitor.exe",
        command_line=("competitor.exe", "--port", "8001"),
    )
    identities = {listener.pid: listener}

    class FakeProcess:
        def __init__(self, pid: int) -> None:
            self.pid = pid

        def ppid(self) -> int:
            assert self.pid == listener.pid
            return 9999

    monkeypatch.setattr("opc_service_monitor.processes.psutil.Process", FakeProcess)
    adapter = SubprocessProcessAdapter(inspector=lambda pid: identities.get(pid))
    owned = OwnedProcess(ServiceId.BACKEND, root, CommandSpec("wrapper.exe", (), tmp_path))

    check = adapter.validate_listener_owned(owned, listener)

    assert check.valid is False
    assert owned.descendant_identities == ()


def test_listener_ownership_rejects_competing_process_even_when_launcher_is_alive(
    tmp_path: Path, monkeypatch
) -> None:
    root = _identity(pid=350, executable="wrapper.exe", command_line=("wrapper.exe",))
    child = _identity(pid=351, executable="service.exe", command_line=("service.exe", "--port", "8001"))
    competitor = _identity(pid=352, executable="other.exe", command_line=("other.exe", "--port", "8001"))
    identities = {root.pid: root, child.pid: child, competitor.pid: competitor}

    class FakeProcess:
        def __init__(self, pid: int) -> None:
            self.pid = pid

        def children(self, *, recursive: bool):
            assert recursive is True
            return [FakeProcess(child.pid)] if self.pid == root.pid else []

    monkeypatch.setattr("opc_service_monitor.processes.psutil.Process", FakeProcess)
    adapter = SubprocessProcessAdapter(inspector=lambda pid: identities.get(pid))
    owned = OwnedProcess(
        ServiceId.BACKEND,
        root,
        CommandSpec("wrapper.exe", (), tmp_path),
    )

    check = adapter.validate_listener_owned(owned, competitor)

    assert check.valid is False
    assert owned.descendant_identities == (child,)


def test_validate_owned_reports_exact_mismatch_reason(tmp_path: Path) -> None:
    snapshot = _identity(pid=444)
    current = _identity(pid=444, executable=r"C:\Windows\other.exe")
    adapter = SubprocessProcessAdapter(inspector=lambda _pid: current)
    owned = OwnedProcess(
        ServiceId.POSTGRES,
        snapshot,
        CommandSpec("helper.exe", ("start",), tmp_path),
        expected_command_fragments=(r"D:\OPC\BackendService\.local\integration\data",),
    )

    check = adapter.validate_owned(owned)

    assert check.valid is False
    assert "可执行" in check.reason


def test_force_stop_terminates_descendants_before_root(tmp_path: Path, monkeypatch) -> None:
    identities = {
        pid: _identity(pid=pid, command_line=(f"process-{pid}",))
        for pid in (500, 501, 502)
    }
    terminated: list[int] = []

    class FakeProcess:
        def __init__(self, pid: int) -> None:
            self.pid = pid

        def children(self, *, recursive: bool):
            assert recursive is True
            return [FakeProcess(501), FakeProcess(502)]

        def terminate(self) -> None:
            terminated.append(self.pid)
            identities.pop(self.pid, None)

        def kill(self) -> None:
            raise AssertionError("terminate should be enough")

    monkeypatch.setattr("opc_service_monitor.processes.psutil.Process", FakeProcess)
    monkeypatch.setattr(
        "opc_service_monitor.processes.psutil.wait_procs",
        lambda targets, timeout: (list(targets), []),
    )
    adapter = SubprocessProcessAdapter(inspector=lambda pid: identities.get(pid))
    owned = OwnedProcess(
        ServiceId.BACKEND,
        identities[500],
        CommandSpec("service.exe", (), tmp_path),
    )

    assert adapter.force_stop(owned, timeout_s=1.0) is True
    assert terminated == [502, 501, 500]


def test_graceful_stop_tracks_children_and_force_can_finish_after_launcher_exits(
    tmp_path: Path, monkeypatch
) -> None:
    identities = {
        pid: _identity(pid=pid, command_line=(f"process-{pid}",))
        for pid in (600, 601)
    }
    terminated: list[int] = []

    class FakeProcess:
        def __init__(self, pid: int) -> None:
            self.pid = pid

        def children(self, *, recursive: bool):
            assert recursive is True
            return [FakeProcess(601)] if self.pid == 600 else []

        def terminate(self) -> None:
            terminated.append(self.pid)
            identities.pop(self.pid, None)

        def kill(self) -> None:
            raise AssertionError("terminate should be enough")

    class RootExitsFirstAdapter(SubprocessProcessAdapter):
        def _signal_graceful(self, owned: OwnedProcess) -> None:
            identities.pop(owned.identity.pid, None)

    monkeypatch.setattr("opc_service_monitor.processes.psutil.Process", FakeProcess)
    monkeypatch.setattr(
        "opc_service_monitor.processes.psutil.wait_procs",
        lambda targets, timeout: (list(targets), []),
    )
    adapter = RootExitsFirstAdapter(inspector=lambda pid: identities.get(pid))
    owned = OwnedProcess(
        ServiceId.FRONTEND,
        identities[600],
        CommandSpec("npm.cmd", ("run", "dev"), tmp_path),
    )

    assert adapter.request_stop(owned, timeout_s=0.01) is False
    assert [identity.pid for identity in owned.descendant_identities] == [601]
    assert adapter.force_stop(owned, timeout_s=1.0) is True
    assert terminated == [601]


def test_stop_can_clean_persisted_verified_descendant_after_launcher_already_exited(
    tmp_path: Path, monkeypatch
) -> None:
    root = _identity(pid=610, executable="wrapper.exe", command_line=("wrapper.exe",))
    child = _identity(pid=611, executable="service.exe", command_line=("service.exe", "--port", "5180"))
    identities = {child.pid: child}
    terminated: list[int] = []

    class FakeProcess:
        def __init__(self, pid: int) -> None:
            self.pid = pid

        def children(self, *, recursive: bool):
            assert recursive is True
            return []

        def terminate(self) -> None:
            terminated.append(self.pid)
            identities.pop(self.pid, None)

        def kill(self) -> None:
            raise AssertionError("terminate should be enough")

    monkeypatch.setattr("opc_service_monitor.processes.psutil.Process", FakeProcess)
    monkeypatch.setattr(
        "opc_service_monitor.processes.psutil.wait_procs",
        lambda targets, timeout: (list(targets), []),
    )
    adapter = SubprocessProcessAdapter(inspector=lambda pid: identities.get(pid))
    owned = OwnedProcess(
        ServiceId.FRONTEND,
        root,
        CommandSpec("npm.cmd", ("run", "dev"), tmp_path),
        descendant_identities=(child,),
    )

    assert adapter.validate_owned(owned).valid is True
    assert adapter.request_stop(owned, timeout_s=0.01) is True
    assert terminated == [child.pid]


def test_stream_pipe_continues_after_output_callback_raises_and_redacts_error(caplog) -> None:
    delivered: list[str] = []
    attempts = 0

    def output(_stream: str, line: str) -> None:
        nonlocal attempts
        attempts += 1
        if attempts == 1:
            raise RuntimeError("password=callback-secret")
        delivered.append(line)

    with caplog.at_level("ERROR", logger="opc_service_monitor.processes"):
        SubprocessProcessAdapter._stream_pipe(
            BytesIO(b"password=pipe-secret\nsecond line\n"),
            "stdout",
            output,
        )

    assert delivered == ["second line"]
    assert "callback-secret" not in caplog.text
    assert "pipe-secret" not in caplog.text
    assert "[REDACTED]" in caplog.text


def test_request_stop_closes_pipe_and_joins_reader_before_return(tmp_path: Path) -> None:
    identity = _identity(pid=620, executable="wrapper.exe", command_line=("wrapper.exe",))
    identities = {identity.pid: identity}

    class BlockingPipe:
        def __init__(self) -> None:
            self.closed = False
            self._closed = threading.Event()

        def read(self, _size: int) -> bytes:
            self._closed.wait(2)
            return b""

        def close(self) -> None:
            self.closed = True
            self._closed.set()

    pipe = BlockingPipe()

    class FakePopen:
        pid = identity.pid
        stdout = pipe
        stderr = None

        def send_signal(self, _signal: int) -> None:
            identities.pop(identity.pid, None)

        def terminate(self) -> None:
            identities.pop(identity.pid, None)

    adapter = SubprocessProcessAdapter(inspector=lambda pid: identities.get(pid))
    thread = threading.Thread(
        target=adapter._stream_pipe,
        args=(pipe, "stdout", lambda _stream, _line: None),
    )
    thread.start()
    command = CommandSpec("wrapper.exe", (), tmp_path)
    owned = SpawnedProcess(identity, command, FakePopen(), (thread,)).as_owned(ServiceId.BACKEND)

    assert adapter.request_stop(owned, timeout_s=0.1) is True
    assert pipe.closed is True
    assert thread.is_alive() is False


def test_force_stop_closes_pipe_and_joins_reader_before_return(
    tmp_path: Path,
    monkeypatch,
) -> None:
    identity = _identity(pid=621, executable="wrapper.exe", command_line=("wrapper.exe",))
    identities = {identity.pid: identity}

    class BlockingPipe:
        def __init__(self) -> None:
            self.closed = False
            self._closed = threading.Event()

        def read(self, _size: int) -> bytes:
            self._closed.wait(2)
            return b""

        def close(self) -> None:
            self.closed = True
            self._closed.set()

    pipe = BlockingPipe()

    class FakePopen:
        pid = identity.pid
        stdout = pipe
        stderr = None

        def wait(self, timeout: float) -> int:
            assert timeout > 0
            return 0

    class FakeProcess:
        def __init__(self, pid: int) -> None:
            self.pid = pid

        def children(self, *, recursive: bool):
            assert recursive is True
            return []

        def terminate(self) -> None:
            identities.pop(self.pid, None)

        def kill(self) -> None:
            raise AssertionError("terminate should be enough")

    monkeypatch.setattr("opc_service_monitor.processes.psutil.Process", FakeProcess)
    monkeypatch.setattr(
        "opc_service_monitor.processes.psutil.wait_procs",
        lambda targets, timeout: (list(targets), []),
    )
    adapter = SubprocessProcessAdapter(inspector=lambda pid: identities.get(pid))
    thread = threading.Thread(
        target=adapter._stream_pipe,
        args=(pipe, "stdout", lambda _stream, _line: None),
    )
    thread.start()
    command = CommandSpec("wrapper.exe", (), tmp_path)
    owned = SpawnedProcess(identity, command, FakePopen(), (thread,)).as_owned(ServiceId.BACKEND)

    assert adapter.force_stop(owned, timeout_s=0.1) is True
    assert pipe.closed is True
    assert thread.is_alive() is False


def test_output_reader_join_has_a_hard_timeout(tmp_path: Path) -> None:
    identity = _identity(pid=622, executable="wrapper.exe", command_line=("wrapper.exe",))

    class FakePopen:
        pid = identity.pid
        stdout = None
        stderr = None

    class StuckThread:
        def __init__(self) -> None:
            self.timeouts: list[float | None] = []

        def join(self, timeout: float | None = None) -> None:
            self.timeouts.append(timeout)
            if timeout is None:
                raise AssertionError("输出线程不得无限等待")

        def is_alive(self) -> bool:
            return True

    thread = StuckThread()
    command = CommandSpec("wrapper.exe", (), tmp_path)
    owned = SpawnedProcess(identity, command, FakePopen(), (thread,)).as_owned(ServiceId.BACKEND)

    assert SubprocessProcessAdapter._finish_output_threads(owned, timeout_s=0.01) is False
    assert thread.timeouts
    assert all(timeout is not None for timeout in thread.timeouts)


def test_output_pipe_close_has_a_hard_timeout_and_retry_reuses_worker(tmp_path: Path) -> None:
    identity = _identity(pid=623, executable="wrapper.exe", command_line=("wrapper.exe",))
    close_entered = threading.Event()
    release_close = threading.Event()
    close_calls: list[int] = []

    class BlockingClosePipe:
        def close(self) -> None:
            close_calls.append(threading.get_ident())
            close_entered.set()
            release_close.wait(2)

    class FakePopen:
        pid = identity.pid
        stdout = BlockingClosePipe()
        stderr = None

    command = CommandSpec("wrapper.exe", (), tmp_path)
    spawned = SpawnedProcess(identity, command, FakePopen())
    owned = spawned.as_owned(ServiceId.BACKEND)
    try:
        started = time.monotonic()
        assert SubprocessProcessAdapter._finish_output_threads(owned, timeout_s=0.02) is False
        assert time.monotonic() - started < 0.5
        assert close_entered.wait(0.2)
        worker = spawned.output_close_thread
        assert worker is not None and worker.daemon and worker.is_alive()

        started = time.monotonic()
        assert SubprocessProcessAdapter._finish_output_threads(owned, timeout_s=0.02) is False
        assert time.monotonic() - started < 0.5
        assert spawned.output_close_thread is worker
        assert close_calls == [worker.ident]
    finally:
        release_close.set()
    assert SubprocessProcessAdapter._finish_output_threads(owned, timeout_s=0.5) is True
    assert spawned.output_close_thread is worker
    assert len(close_calls) == 1

