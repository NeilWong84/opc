from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from pathlib import Path


class ServiceId(StrEnum):
    POSTGRES = "postgresql"
    BACKEND = "backend"
    FRONTEND = "frontend"


class ServiceState(StrEnum):
    STOPPED = "stopped"
    STARTING = "starting"
    RUNNING_NOT_READY = "running_not_ready"
    READY = "ready"
    EXTERNAL = "external"
    STOPPING = "stopping"
    FAILED = "failed"


class LogSource(StrEnum):
    MONITOR = "monitor"
    POSTGRES = "postgresql"
    BACKEND = "backend"
    FRONTEND = "frontend"


class LogLevel(StrEnum):
    DEBUG = "debug"
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"
    CRITICAL = "critical"
    UNKNOWN = "unknown"


@dataclass(frozen=True, slots=True)
class CommandSpec:
    executable: str
    arguments: tuple[str, ...]
    cwd: Path
    environment: tuple[tuple[str, str], ...] = ()
    shell: bool = False

    def argv(self) -> tuple[str, ...]:
        return (self.executable, *self.arguments)


@dataclass(frozen=True, slots=True)
class ServiceDefinition:
    service_id: ServiceId
    display_name: str
    host: str
    port: int
    start_command: CommandSpec
    stop_command: CommandSpec | None = None
    health_urls: tuple[str, ...] = ()
    dependencies: tuple[ServiceId, ...] = ()
    log_files: tuple[Path, ...] = ()


@dataclass(frozen=True, slots=True)
class LogEntry:
    occurred_at: datetime
    source: LogSource
    level: LogLevel
    stream: str
    message: str
    truncated: bool = False
    entry_id: int | None = None
    pid: int | None = None


@dataclass(frozen=True, slots=True)
class HealthResult:
    checked_at: datetime
    reachable: bool
    port_open: bool | None = None
    live: bool | None = None
    ready: bool | None = None
    status_code: int | None = None
    error_code: str | None = None
    summary: str = ""

