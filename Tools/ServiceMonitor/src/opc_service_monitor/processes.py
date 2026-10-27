from __future__ import annotations

import os
import logging
import signal
import subprocess
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from ipaddress import ip_address
from pathlib import Path
from typing import Protocol

import psutil

from opc_service_monitor.frozen_runtime import sanitized_external_environment
from opc_service_monitor.log_pipeline import IncrementalLineDecoder, make_log_entry, redact_log_text, windows_log_encodings
from opc_service_monitor.models import CommandSpec, LogSource, ServiceId


OutputCallback = Callable[[str, str], None]
_LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class ProcessIdentity:
    pid: int
    create_time_ns: int
    executable: str
    command_line: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class PortOccupancy:
    occupied: bool
    identity: ProcessIdentity | None = None
    pid: int | None = None
    bound_host: str | None = None


@dataclass(frozen=True, slots=True)
class OwnershipCheck:
    valid: bool
    reason: str
    current: ProcessIdentity | None = None


@dataclass(slots=True)
class SpawnedProcess:
    identity: ProcessIdentity
    command: CommandSpec
    process: subprocess.Popen[bytes] = field(repr=False, compare=False)
    output_threads: tuple[threading.Thread, ...] = field(default=(), repr=False, compare=False)
    output_close_thread: threading.Thread | None = field(default=None, init=False, repr=False, compare=False)
    output_close_lock: threading.Lock = field(default_factory=threading.Lock, init=False, repr=False, compare=False)

    def as_owned(
        self,
        service_id: ServiceId,
        *,
        expected_command_fragments: tuple[str, ...] = (),
    ) -> OwnedProcess:
        return OwnedProcess(
            service_id=service_id,
            identity=self.identity,
            command=self.command,
            expected_command_fragments=expected_command_fragments,
            spawned=self,
        )


@dataclass(slots=True)
class OwnedProcess:
    service_id: ServiceId
    identity: ProcessIdentity
    command: CommandSpec
    expected_command_fragments: tuple[str, ...] = ()
    spawned: SpawnedProcess | None = field(default=None, repr=False, compare=False)
    descendant_identities: tuple[ProcessIdentity, ...] = field(default=(), repr=False, compare=False)


class ProcessAdapter(Protocol):
    def listener(self, host: str, port: int) -> PortOccupancy: ...

    def spawn(self, command: CommandSpec, output: OutputCallback) -> SpawnedProcess: ...

    def inspect(self, pid: int) -> ProcessIdentity | None: ...

    def validate_owned(self, owned: OwnedProcess) -> OwnershipCheck: ...

    def validate_listener_owned(
        self,
        owned: OwnedProcess,
        listener: ProcessIdentity,
    ) -> OwnershipCheck: ...

    def request_stop(self, owned: OwnedProcess, timeout_s: float) -> bool: ...

    def force_stop(self, owned: OwnedProcess, timeout_s: float) -> bool: ...


def ownership_matches(
    snapshot: ProcessIdentity,
    current: ProcessIdentity | None,
    expected_command_fragments: tuple[str, ...] = (),
) -> OwnershipCheck:
    if current is None:
        return OwnershipCheck(False, "进程已不存在", None)
    if current.pid != snapshot.pid:
        return OwnershipCheck(False, "PID 不匹配", current)
    if current.create_time_ns != snapshot.create_time_ns:
        return OwnershipCheck(False, "进程创建时间不匹配，PID 可能已复用", current)
    if _normalized_executable(current.executable) != _normalized_executable(snapshot.executable):
        return OwnershipCheck(False, "可执行文件不匹配", current)
    if current.command_line != snapshot.command_line:
        return OwnershipCheck(False, "命令行不匹配", current)
    command_text = " ".join(current.command_line).casefold()
    for fragment in expected_command_fragments:
        if fragment.casefold() not in command_text:
            return OwnershipCheck(False, "命令行缺少预期项目路径", current)
    return OwnershipCheck(True, "进程所有权已验证", current)


class SubprocessProcessAdapter:
    def __init__(
        self,
        *,
        inspector: Callable[[int], ProcessIdentity | None] | None = None,
        connections: Callable[[], list[object]] | None = None,
    ) -> None:
        self._injected_inspector = inspector
        self._connections = connections or (lambda: list(psutil.net_connections(kind="tcp")))

    def listener(self, host: str, port: int) -> PortOccupancy:
        for connection in self._connections():
            if getattr(connection, "status", None) != psutil.CONN_LISTEN:
                continue
            address = getattr(connection, "laddr", None)
            if address is None:
                continue
            address_host = getattr(address, "ip", address[0] if isinstance(address, tuple) else None)
            address_port = getattr(address, "port", address[1] if isinstance(address, tuple) else None)
            if address_port != port or not _listener_host_matches(host, address_host):
                continue
            pid = getattr(connection, "pid", None)
            numeric_pid = int(pid) if pid is not None else None
            identity = self.inspect(numeric_pid) if numeric_pid is not None else None
            return PortOccupancy(True, identity, numeric_pid, str(address_host))
        return PortOccupancy(False)

    def spawn(self, command: CommandSpec, output: OutputCallback) -> SpawnedProcess:
        if command.shell:
            raise ValueError("shell 命令不允许用于服务进程")
        if not isinstance(command.arguments, tuple):
            raise ValueError("命令参数必须为固定元组")
        cwd = Path(command.cwd).resolve()
        if not cwd.is_dir():
            raise ValueError(f"命令工作目录不存在: {cwd}")
        environment = os.environ.copy()
        environment.update(dict(command.environment))
        environment = sanitized_external_environment(environment)
        creation_flags = 0
        if os.name == "nt":
            creation_flags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW
        process = subprocess.Popen(
            list(command.argv()),
            cwd=str(cwd),
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            shell=False,
            creationflags=creation_flags,
            bufsize=0,
        )
        identity = self._wait_for_identity(process.pid)
        if identity is None:
            process.kill()
            raise RuntimeError("服务进程启动后立即退出，无法建立所有权")
        threads: list[threading.Thread] = []
        for stream_name, pipe in (("stdout", process.stdout), ("stderr", process.stderr)):
            if pipe is None:
                continue
            thread = threading.Thread(
                target=self._stream_pipe,
                args=(pipe, stream_name, output),
                name=f"opc-{process.pid}-{stream_name}",
                daemon=True,
            )
            thread.start()
            threads.append(thread)
        return SpawnedProcess(identity, command, process, tuple(threads))

    def inspect(self, pid: int) -> ProcessIdentity | None:
        if self._injected_inspector is not None:
            return self._injected_inspector(pid)
        try:
            process = psutil.Process(pid)
            with process.oneshot():
                if not process.is_running():
                    return None
                return ProcessIdentity(
                    pid=process.pid,
                    create_time_ns=int(process.create_time() * 1_000_000_000),
                    executable=process.exe(),
                    command_line=tuple(process.cmdline()),
                )
        except (psutil.Error, OSError):
            return None

    def validate_owned(self, owned: OwnedProcess) -> OwnershipCheck:
        root = ownership_matches(
            owned.identity,
            self.inspect(owned.identity.pid),
            owned.expected_command_fragments,
        )
        if root.valid:
            owned.descendant_identities = _merge_identities(
                owned.descendant_identities,
                self._capture_descendants(owned.identity.pid),
            )
            return root
        for descendant in owned.descendant_identities:
            current = self.inspect(descendant.pid)
            if ownership_matches(descendant, current).valid:
                return OwnershipCheck(
                    True,
                    "启动包装进程已退出，已验证的会话后代仍在运行",
                    current,
                )
        return root

    def validate_listener_owned(
        self,
        owned: OwnedProcess,
        listener: ProcessIdentity,
    ) -> OwnershipCheck:
        listener_check = ownership_matches(listener, self.inspect(listener.pid))
        if not listener_check.valid:
            return OwnershipCheck(False, f"监听进程身份已变化: {listener_check.reason}", listener_check.current)

        root_check = ownership_matches(
            owned.identity,
            self.inspect(owned.identity.pid),
            owned.expected_command_fragments,
        )
        if root_check.valid:
            owned.descendant_identities = _merge_identities(
                owned.descendant_identities,
                self._capture_descendants(owned.identity.pid),
            )

        candidates = (owned.identity, *owned.descendant_identities)
        for candidate in candidates:
            if candidate != listener:
                continue
            expected = owned.expected_command_fragments if candidate == owned.identity else ()
            return ownership_matches(candidate, self.inspect(candidate.pid), expected)

        recovered = self._recover_listener_descendant(owned, listener, root_check)
        if recovered.valid:
            owned.descendant_identities = _merge_identities(
                owned.descendant_identities,
                (listener,),
            )
        return recovered

    def _recover_listener_descendant(
        self,
        owned: OwnedProcess,
        listener: ProcessIdentity,
        root_check: OwnershipCheck,
    ) -> OwnershipCheck:
        if listener.create_time_ns < owned.identity.create_time_ns:
            return OwnershipCheck(False, "监听进程早于启动包装进程，拒绝认领", listener)
        if root_check.current is not None and not root_check.valid:
            return OwnershipCheck(False, f"启动包装进程 PID 已复用: {root_check.reason}", listener)
        if root_check.current is None and psutil.pid_exists(owned.identity.pid):
            return OwnershipCheck(False, "启动包装进程仍存在但身份不可验证，拒绝认领", listener)

        current = listener
        visited = {listener.pid}
        for _ in range(32):
            try:
                process = psutil.Process(current.pid)
                parent_pid = int(process.ppid())
            except (psutil.Error, OSError, AttributeError, TypeError, ValueError):
                return OwnershipCheck(False, "无法验证监听进程父链", listener)

            current_check = ownership_matches(current, self.inspect(current.pid))
            if not current_check.valid:
                return OwnershipCheck(False, f"父链进程身份已变化: {current_check.reason}", listener)
            if parent_pid == owned.identity.pid:
                latest_root = self.inspect(owned.identity.pid)
                if latest_root is not None:
                    latest_root_check = ownership_matches(
                        owned.identity,
                        latest_root,
                        owned.expected_command_fragments,
                    )
                    if not latest_root_check.valid:
                        return OwnershipCheck(
                            False,
                            f"启动包装进程 PID 已复用: {latest_root_check.reason}",
                            listener,
                        )
                return OwnershipCheck(True, "已通过创建时间与父链验证监听进程归属", listener)
            if parent_pid <= 0 or parent_pid in visited:
                return OwnershipCheck(False, "监听进程父链未指向本次启动包装进程", listener)

            parent = self.inspect(parent_pid)
            if parent is None:
                return OwnershipCheck(False, "监听进程父链身份不可验证", listener)
            if parent.create_time_ns > current.create_time_ns:
                return OwnershipCheck(False, "监听进程父链创建时间无效", listener)
            visited.add(parent_pid)
            current = parent

        return OwnershipCheck(False, "监听进程父链过深，拒绝认领", listener)

    def request_stop(self, owned: OwnedProcess, timeout_s: float) -> bool:
        if timeout_s < 0:
            raise ValueError("停止等待时间不能为负数")
        check = self.validate_owned(owned)
        if not check.valid:
            self._finish_output_threads(owned)
            return False
        root_check = ownership_matches(
            owned.identity,
            self.inspect(owned.identity.pid),
            owned.expected_command_fragments,
        )
        if root_check.valid:
            owned.descendant_identities = _merge_identities(
                owned.descendant_identities,
                self._capture_descendants(owned.identity.pid),
            )
        try:
            if root_check.valid:
                self._signal_graceful(owned)
            else:
                self._signal_verified_descendants(owned)
        except (OSError, psutil.Error, ProcessLookupError):
            pass
        deadline = time.monotonic() + timeout_s
        while time.monotonic() < deadline:
            if self._tracked_tree_stopped(owned):
                break
            time.sleep(0.05)
        stopped = self._tracked_tree_stopped(owned)
        output_finished = self._finish_output_threads(owned)
        return stopped and output_finished

    def force_stop(self, owned: OwnedProcess, timeout_s: float) -> bool:
        if timeout_s <= 0:
            raise ValueError("强制停止等待时间必须大于零")
        root_check = ownership_matches(
            owned.identity,
            self.inspect(owned.identity.pid),
            owned.expected_command_fragments,
        )
        if root_check.valid:
            owned.descendant_identities = _merge_identities(
                owned.descendant_identities,
                self._capture_descendants(owned.identity.pid),
            )

        snapshots = [*reversed(owned.descendant_identities)]
        if root_check.valid:
            snapshots.append(owned.identity)
        targets: list[psutil.Process] = []
        for snapshot in snapshots:
            current = self.inspect(snapshot.pid)
            expected = owned.expected_command_fragments if snapshot.pid == owned.identity.pid else ()
            if not ownership_matches(snapshot, current, expected).valid:
                continue
            try:
                process = psutil.Process(snapshot.pid)
                process.terminate()
                targets.append(process)
            except psutil.Error:
                continue

        wait_slice = max(0.05, timeout_s / 2)
        _, alive = psutil.wait_procs(targets, timeout=wait_slice)
        kill_targets: list[psutil.Process] = []
        for process in alive:
            snapshot = next((item for item in snapshots if item.pid == process.pid), None)
            if snapshot is None or not ownership_matches(snapshot, self.inspect(process.pid)).valid:
                continue
            try:
                process.kill()
                kill_targets.append(process)
            except psutil.Error:
                continue
        if kill_targets:
            psutil.wait_procs(kill_targets, timeout=wait_slice)
        if owned.spawned is not None:
            try:
                owned.spawned.process.wait(timeout=0.2)
            except subprocess.TimeoutExpired:
                pass
        output_finished = self._finish_output_threads(owned)
        return self._tracked_tree_stopped(owned) and output_finished

    def _capture_descendants(self, root_pid: int) -> tuple[ProcessIdentity, ...]:
        try:
            descendants = psutil.Process(root_pid).children(recursive=True)
        except psutil.Error:
            return ()
        snapshots: list[ProcessIdentity] = []
        for process in descendants:
            identity = self.inspect(process.pid)
            if identity is not None:
                snapshots.append(identity)
        return tuple(snapshots)

    def _tracked_tree_stopped(self, owned: OwnedProcess) -> bool:
        snapshots = (owned.identity, *owned.descendant_identities)
        return all(not ownership_matches(snapshot, self.inspect(snapshot.pid)).valid for snapshot in snapshots)

    def _wait_for_identity(self, pid: int) -> ProcessIdentity | None:
        for _ in range(20):
            identity = self.inspect(pid)
            if identity is not None:
                return identity
            time.sleep(0.01)
        return None

    def _signal_graceful(self, owned: OwnedProcess) -> None:
        if owned.spawned is not None and owned.spawned.process.pid == owned.identity.pid:
            if os.name == "nt":
                owned.spawned.process.send_signal(signal.CTRL_BREAK_EVENT)
            else:
                owned.spawned.process.terminate()
            return
        process = psutil.Process(owned.identity.pid)
        if os.name == "nt":
            process.send_signal(signal.CTRL_BREAK_EVENT)
        else:
            process.terminate()

    def _signal_verified_descendants(self, owned: OwnedProcess) -> None:
        for snapshot in reversed(owned.descendant_identities):
            if not ownership_matches(snapshot, self.inspect(snapshot.pid)).valid:
                continue
            psutil.Process(snapshot.pid).terminate()

    @staticmethod
    def _stream_pipe(pipe: object, stream: str, output: OutputCallback) -> None:
        decoder = IncrementalLineDecoder(fallback_encodings=windows_log_encodings())

        def deliver(line: str) -> None:
            safe_line = make_log_entry(source=LogSource.MONITOR, stream=stream, text=line).message
            try:
                output(stream, safe_line)
            except Exception as exc:
                safe_error = redact_log_text(str(exc)) or type(exc).__name__
                _LOGGER.error("运行日志输出回调失败（%s）: %s", stream, safe_error)

        try:
            while True:
                try:
                    chunk = pipe.read(4096)  # type: ignore[attr-defined]
                except (OSError, ValueError):
                    break
                if not chunk:
                    break
                for line in decoder.feed(chunk):
                    deliver(line)
            for line in decoder.flush():
                deliver(line)
        finally:
            try:
                pipe.close()  # type: ignore[attr-defined]
            except (OSError, ValueError):
                pass

    @staticmethod
    def _finish_output_threads(owned: OwnedProcess, timeout_s: float = 1.0) -> bool:
        if timeout_s < 0:
            raise ValueError("输出线程等待时间不能为负数")
        spawned = owned.spawned
        if spawned is None:
            return True
        deadline = time.monotonic() + timeout_s
        # On Windows an anonymous-pipe close can itself wait for a blocking read.
        # Keep that operation off the stop caller so it can reach force_stop.
        # One worker per spawn is reused by graceful/forced/repeated cleanup.
        if not spawned.output_close_lock.acquire(timeout=max(0.0, deadline - time.monotonic())):
            return False
        try:
            pipes = tuple(pipe for pipe in (spawned.process.stdout, spawned.process.stderr) if pipe is not None)
            if spawned.output_close_thread is None and pipes:
                def close_pipes() -> None:
                    for pipe in pipes:
                        try:
                            pipe.close()
                        except (OSError, ValueError):
                            pass

                spawned.output_close_thread = threading.Thread(
                    target=close_pipes,
                    name=f"opc-{spawned.identity.pid}-output-close",
                    daemon=True,
                )
                spawned.output_close_thread.start()
            close_thread = spawned.output_close_thread
        finally:
            spawned.output_close_lock.release()
        threads = (*spawned.output_threads, *((close_thread,) if close_thread is not None else ()))
        for thread in threads:
            if thread is threading.current_thread():
                continue
            thread.join(timeout=max(0.0, deadline - time.monotonic()))
        return all(not thread.is_alive() for thread in threads)


def _normalized_executable(value: str) -> str:
    return os.path.normcase(os.path.normpath(value.strip('"')))


def _listener_host_matches(requested_host: str, bound_host: object) -> bool:
    if bound_host is None:
        return False
    requested_text = requested_host.strip("[]").split("%", 1)[0]
    bound_text = str(bound_host).strip("[]").split("%", 1)[0]
    if requested_text.casefold() == bound_text.casefold():
        return True
    try:
        requested = ip_address(requested_text)
        bound = ip_address(bound_text)
    except ValueError:
        return False
    return requested.is_loopback and bound.is_unspecified


def _merge_identities(
    existing: tuple[ProcessIdentity, ...],
    discovered: tuple[ProcessIdentity, ...],
) -> tuple[ProcessIdentity, ...]:
    merged: dict[tuple[int, int], ProcessIdentity] = {
        (identity.pid, identity.create_time_ns): identity for identity in existing
    }
    for identity in discovered:
        merged[(identity.pid, identity.create_time_ns)] = identity
    return tuple(merged.values())

